//
//  MCPToolRegistry.swift
//  YoDaAI
//
//  Central service for managing MCP tools from configured servers.
//  Handles fetching, caching, and providing tools for system prompt injection.
//

import Foundation
import SwiftData
import Combine

// MARK: - Tool with Server Info

/// A tool along with the server it came from
struct MCPToolWithServer: Identifiable, Hashable {
    let tool: MCPTool
    let serverName: String
    let serverEndpoint: String
    
    var id: String { "\(serverEndpoint):\(tool.name)" }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MCPToolWithServer, rhs: MCPToolWithServer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - MCP Tool Registry

/// Central registry for MCP tools from all configured servers
@MainActor
final class MCPToolRegistry: ObservableObject {
    static let shared = MCPToolRegistry()
    
    /// All available tools from enabled servers
    @Published private(set) var tools: [MCPToolWithServer] = []
    
    /// Whether tools are currently being fetched
    @Published private(set) var isLoading: Bool = false
    
    /// Last error message
    @Published var lastError: String?
    
    /// Per-server connection status
    @Published private(set) var serverStatus: [String: ServerConnectionStatus] = [:]
    
    /// MCP enabled state (persisted)
    @Published var isMCPEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMCPEnabled, forKey: "mcp_enabled")
        }
    }
    
    /// Active client connections
    private var clients: [String: MCPClient] = [:]
    
    /// Cache expiration (5 minutes)
    private let cacheExpirationSeconds: TimeInterval = 300
    private var lastFetchTime: Date?
    
    private init() {
        self.isMCPEnabled = UserDefaults.standard.object(forKey: "mcp_enabled") as? Bool ?? false
    }
    
    // MARK: - Server Status
    
    enum ServerConnectionStatus: Equatable {
        case unknown
        case connecting
        case connected(serverName: String?, serverVersion: String?)
        case error(String)
        
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }
    
    // MARK: - Tool Fetching
    
    /// Refresh tools from all enabled MCP servers
    func refreshTools(servers: [MCPServer]) async {
        guard isMCPEnabled else {
            tools = []
            clients.removeAll()
            serverStatus.removeAll()
            return
        }
        
        // Prevent concurrent refreshes
        guard !isLoading else {
            print("[MCPToolRegistry] Refresh already in progress, skipping...")
            return
        }
        
        isLoading = true
        lastError = nil
        
        let enabledServers = servers.filter { $0.isEnabled && $0.hasValidEndpoint }
        
        print("[MCPToolRegistry] Starting refresh with \(enabledServers.count) enabled servers: \(enabledServers.map { $0.name })")
        
        // Clear existing tools before refresh
        tools = []
        
        // Process servers in PARALLEL so slow servers don't block fast ones
        await withTaskGroup(of: (MCPServer, Result<[MCPToolWithServer], Error>).self) { group in
            for server in enabledServers {
                group.addTask { [self] in
                    do {
                        // Update status (must be done on MainActor)
                        await MainActor.run {
                            self.serverStatus[server.endpoint] = .connecting
                        }
                        
                        // Get or create client
                        let client = await self.getOrCreateClient(for: server)
                        
                        // Initialize if needed
                        let initResult = try await client.initialize()
                        
                        // Update status with server info
                        await MainActor.run {
                            self.serverStatus[server.endpoint] = .connected(
                                serverName: initResult.serverInfo?.name,
                                serverVersion: initResult.serverInfo?.version
                            )
                        }
                        
                        // Fetch tools
                        let serverTools = try await client.listTools()
                        
                        // Wrap with server info
                        let wrappedTools = serverTools.map { tool in
                            MCPToolWithServer(
                                tool: tool,
                                serverName: server.name,
                                serverEndpoint: server.endpoint
                            )
                        }
                        
                        print("[MCPToolRegistry] Fetched \(serverTools.count) tools from \(server.name)")
                        
                        return (server, .success(wrappedTools))
                        
                    } catch {
                        print("[MCPToolRegistry] Error fetching tools from \(server.name): \(error)")
                        
                        await MainActor.run {
                            self.serverStatus[server.endpoint] = .error(error.localizedDescription)
                            self.clients.removeValue(forKey: server.endpoint)
                        }
                        
                        return (server, .failure(error))
                    }
                }
            }
            
            // Collect results as they complete and update UI incrementally
            for await (server, result) in group {
                if case .success(let wrappedTools) = result {
                    self.tools.append(contentsOf: wrappedTools)
                    print("[MCPToolRegistry] Added tools from \(server.name), total now: \(self.tools.count)")
                }
            }
        }
        
        self.lastFetchTime = Date()
        self.isLoading = false
        
        print("[MCPToolRegistry] Refresh complete. Total tools available: \(self.tools.count)")
    }
    
    /// Get cached tools or refresh if needed
    func getToolsForPrompt(servers: [MCPServer]) async -> [MCPTool] {
        guard isMCPEnabled else { return [] }
        
        // Check cache validity - if cache is still valid, use it
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheExpirationSeconds,
           !tools.isEmpty {
            return tools.map { $0.tool }
        }
        
        // If no cache but tools are being loaded, just return what we have
        // Don't block waiting for slow servers
        if isLoading {
            return tools.map { $0.tool }
        }
        
        // If no tools and not loading, trigger a background refresh but don't wait
        if tools.isEmpty {
            Task {
                await refreshTools(servers: servers)
            }
        }
        
        // Return whatever tools we currently have (may be empty on first call)
        return tools.map { $0.tool }
    }
    
    /// Get the system prompt addition for available tools (includes server name prefix)
    func getToolsSystemPrompt(servers: [MCPServer]) async -> String {
        guard isMCPEnabled else { return "" }
        
        // If tools are empty and not loading, trigger background refresh
        if tools.isEmpty && !isLoading {
            Task {
                await refreshTools(servers: servers)
            }
        }
        
        // Format tools with server name prefix
        return formatToolsForSystemPrompt()
    }
    
    /// Format tools for system prompt with server name prefix
    private func formatToolsForSystemPrompt() -> String {
        guard !tools.isEmpty else { return "" }
        
        var lines: [String] = []
        lines.append("You have access to the following tools from connected MCP servers:")
        lines.append("")
        
        // Group tools by server for better organization
        let toolsByServer = Dictionary(grouping: tools) { $0.serverName }
        
        for (serverName, serverTools) in toolsByServer.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(serverName) Tools:")
            lines.append("")
            
            for toolWithServer in serverTools {
                let tool = toolWithServer.tool
                // Add server name prefix to tool name for clarity
                let prefixedName = "\(serverName).\(tool.name)"
                
                lines.append("### \(prefixedName)")
                if let description = tool.description {
                    lines.append(description)
                }
                
                // Format parameters using the proper struct
                if let inputSchema = tool.inputSchema,
                   let properties = inputSchema.properties {
                    let required = inputSchema.required ?? []
                    
                    if !properties.isEmpty {
                        lines.append("Parameters:")
                        for (paramName, paramInfo) in properties.sorted(by: { $0.key < $1.key }) {
                            let paramType = paramInfo.type ?? "any"
                            let paramDesc = paramInfo.description ?? ""
                            let isRequired = required.contains(paramName)
                            let reqMarker = isRequired ? " (required)" : " (optional)"
                            lines.append("  - \(paramName): \(paramType)\(reqMarker) - \(paramDesc)")
                        }
                    }
                }
                lines.append("")
            }
        }
        
        lines.append("## How to Call Tools")
        lines.append("")
        lines.append("When you need to use a tool, you MUST use this EXACT format with JSON inside <tool_call> tags:")
        lines.append("")
        lines.append("```")
        lines.append("<tool_call>")
        lines.append("{\"name\": \"ServerName.tool_name\", \"arguments\": {\"param1\": \"value1\", \"param2\": \"value2\"}}")
        lines.append("</tool_call>")
        lines.append("```")
        lines.append("")
        lines.append("Example for SplunkQuery tool:")
        lines.append("```")
        lines.append("<tool_call>")
        lines.append("{\"name\": \"SplunkQuery.get_splunk_query_context_tool\", \"arguments\": {\"query_description\": \"find active users\"}}")
        lines.append("</tool_call>")
        lines.append("```")
        lines.append("")
        lines.append("CRITICAL RULES:")
        lines.append("1. Use EXACTLY <tool_call> and </tool_call> tags (not <execute>, <invoke>, or any other format)")
        lines.append("2. The content MUST be valid JSON with \"name\" and \"arguments\" fields")
        lines.append("3. Always include the server prefix in the tool name (e.g., \"SplunkQuery.tool_name\")")
        lines.append("4. After I execute the tool, I will provide the results, then you should continue your response")
        lines.append("5. Do NOT hallucinate or make up tool results - wait for actual results")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Tool Calling
    
    /// Call a tool by name (supports both "ServerName.tool_name" and plain "tool_name" formats)
    func callTool(name: String, arguments: [String: Any]?, servers: [MCPServer]) async throws -> String {
        // Parse the tool name - it may be prefixed with "ServerName."
        let (serverNameHint, actualToolName) = parseToolName(name)
        
        // Find which server has this tool
        let toolWithServer: MCPToolWithServer?
        
        if let serverName = serverNameHint {
            // If server name is specified, look for the tool in that specific server
            toolWithServer = tools.first(where: { 
                $0.serverName == serverName && $0.tool.name == actualToolName 
            })
        } else {
            // Otherwise, search all servers for the tool
            toolWithServer = tools.first(where: { $0.tool.name == actualToolName })
        }
        
        guard let foundTool = toolWithServer else {
            throw MCPClientError.serverNotAvailable
        }
        
        guard let client = clients[foundTool.serverEndpoint] else {
            throw MCPClientError.notInitialized
        }
        
        // Call the tool using the actual (non-prefixed) name
        let result = try await client.callTool(name: actualToolName, arguments: arguments)
        
        if result.hasError {
            return "Tool error: \(result.textContent ?? "Unknown error")"
        }
        
        return result.textContent ?? ""
    }
    
    /// Parse a tool name that may be prefixed with "ServerName."
    /// Returns (serverName, toolName) where serverName is nil if no prefix
    private func parseToolName(_ fullName: String) -> (serverName: String?, toolName: String) {
        // Check if the name contains a dot (server prefix)
        if let dotIndex = fullName.firstIndex(of: ".") {
            let serverName = String(fullName[..<dotIndex])
            let toolName = String(fullName[fullName.index(after: dotIndex)...])
            return (serverName, toolName)
        }
        return (nil, fullName)
    }
    
    // MARK: - Connection Testing
    
    /// Test connection to a specific server
    func testConnection(server: MCPServer) async throws -> (serverName: String?, serverVersion: String?) {
        serverStatus[server.endpoint] = .connecting
        
        do {
            let client = MCPClient(server: server)
            let result = try await client.testConnection()
            
            serverStatus[server.endpoint] = .connected(
                serverName: result.serverName,
                serverVersion: result.serverVersion
            )
            
            return result
        } catch {
            serverStatus[server.endpoint] = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func getOrCreateClient(for server: MCPServer) -> MCPClient {
        if let existing = clients[server.endpoint] {
            return existing
        }
        
        let client = MCPClient(server: server)
        clients[server.endpoint] = client
        return client
    }
    
    /// Clear all cached data
    func clearCache() {
        tools = []
        clients.removeAll()
        serverStatus.removeAll()
        lastFetchTime = nil
    }
    
    /// Remove client for a specific server (e.g., when server is deleted)
    func removeClient(for endpoint: String) {
        clients.removeValue(forKey: endpoint)
        serverStatus.removeValue(forKey: endpoint)
        tools.removeAll { $0.serverEndpoint == endpoint }
    }
}

// MARK: - Tool Call Parsing

extension MCPToolRegistry {
    /// Regex pattern to match tool calls in JSON format: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
    static let toolCallPattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
    
    /// Alternative XML format: <execute><invoke name="..."><parameter name="...">value</parameter></invoke></execute>
    static let alternativeXMLPattern = #"<(?:execute|tool)>\s*<invoke\s+name="([^"]+)">([\s\S]*?)</invoke>\s*</(?:execute|tool)>"#
    
    /// Parameter pattern for alternative XML format
    static let parameterPattern = #"<parameter\s+name="([^"]+)">([^<]*)</parameter>"#
    
    /// Parse tool calls from assistant message (supports multiple formats)
    static func parseToolCalls(from text: String) -> [(name: String, arguments: [String: Any]?)] {
        var results: [(name: String, arguments: [String: Any]?)] = []
        
        // Try JSON format first: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
        results.append(contentsOf: parseJSONToolCalls(from: text))
        
        // If no JSON format found, try alternative XML format
        if results.isEmpty {
            results.append(contentsOf: parseXMLToolCalls(from: text))
        }
        
        return results
    }
    
    /// Parse JSON format tool calls
    private static func parseJSONToolCalls(from text: String) -> [(name: String, arguments: [String: Any]?)] {
        guard let regex = try? NSRegularExpression(pattern: toolCallPattern, options: []) else {
            return []
        }
        
        var results: [(name: String, arguments: [String: Any]?)] = []
        let range = NSRange(text.startIndex..., in: text)
        
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let jsonRange = Range(match.range(at: 1), in: text) else {
                return
            }
            
            let jsonString = String(text[jsonRange])
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else {
                return
            }
            
            let arguments = json["arguments"] as? [String: Any]
            results.append((name: name, arguments: arguments))
        }
        
        return results
    }
    
    /// Parse alternative XML format tool calls: <execute><invoke name="...">...</invoke></execute>
    private static func parseXMLToolCalls(from text: String) -> [(name: String, arguments: [String: Any]?)] {
        guard let invokeRegex = try? NSRegularExpression(pattern: alternativeXMLPattern, options: []),
              let paramRegex = try? NSRegularExpression(pattern: parameterPattern, options: []) else {
            return []
        }
        
        var results: [(name: String, arguments: [String: Any]?)] = []
        let range = NSRange(text.startIndex..., in: text)
        
        invokeRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let paramsRange = Range(match.range(at: 2), in: text) else {
                return
            }
            
            let toolName = String(text[nameRange])
            let paramsText = String(text[paramsRange])
            
            // Parse parameters
            var arguments: [String: Any] = [:]
            let paramsNSRange = NSRange(paramsText.startIndex..., in: paramsText)
            
            paramRegex.enumerateMatches(in: paramsText, options: [], range: paramsNSRange) { paramMatch, _, _ in
                guard let paramMatch = paramMatch,
                      let paramNameRange = Range(paramMatch.range(at: 1), in: paramsText),
                      let paramValueRange = Range(paramMatch.range(at: 2), in: paramsText) else {
                    return
                }
                
                let paramName = String(paramsText[paramNameRange])
                let paramValue = String(paramsText[paramValueRange])
                arguments[paramName] = paramValue
            }
            
            print("[MCP] Parsed XML tool call: \(toolName) with arguments: \(arguments)")
            results.append((name: toolName, arguments: arguments.isEmpty ? nil : arguments))
        }
        
        return results
    }
    
    /// Check if text contains tool calls (any format)
    static func containsToolCalls(_ text: String) -> Bool {
        // Check JSON format
        if let regex = try? NSRegularExpression(pattern: toolCallPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        
        // Check XML format
        if let regex = try? NSRegularExpression(pattern: alternativeXMLPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        
        return false
    }
}
