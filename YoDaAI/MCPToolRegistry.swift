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
        
        isLoading = true
        lastError = nil
        
        let enabledServers = servers.filter { $0.isEnabled && $0.hasValidEndpoint }
        
        var allTools: [MCPToolWithServer] = []
        
        for server in enabledServers {
            do {
                // Update status
                serverStatus[server.endpoint] = .connecting
                
                // Get or create client
                let client = getOrCreateClient(for: server)
                
                // Initialize if needed
                let initResult = try await client.initialize()
                
                // Update status with server info
                serverStatus[server.endpoint] = .connected(
                    serverName: initResult.serverInfo?.name,
                    serverVersion: initResult.serverInfo?.version
                )
                
                // Fetch tools
                let tools = try await client.listTools()
                
                // Wrap with server info
                for tool in tools {
                    allTools.append(MCPToolWithServer(
                        tool: tool,
                        serverName: server.name,
                        serverEndpoint: server.endpoint
                    ))
                }
                
                print("[MCPToolRegistry] Fetched \(tools.count) tools from \(server.name)")
                
            } catch {
                print("[MCPToolRegistry] Error fetching tools from \(server.name): \(error)")
                serverStatus[server.endpoint] = .error(error.localizedDescription)
                
                // Remove failed client
                clients.removeValue(forKey: server.endpoint)
            }
        }
        
        self.tools = allTools
        self.lastFetchTime = Date()
        self.isLoading = false
        
        print("[MCPToolRegistry] Total tools available: \(allTools.count)")
    }
    
    /// Get cached tools or refresh if needed
    func getToolsForPrompt(servers: [MCPServer]) async -> [MCPTool] {
        guard isMCPEnabled else { return [] }
        
        // Check cache validity
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheExpirationSeconds,
           !tools.isEmpty {
            return tools.map { $0.tool }
        }
        
        // Refresh
        await refreshTools(servers: servers)
        
        return tools.map { $0.tool }
    }
    
    /// Get the system prompt addition for available tools
    func getToolsSystemPrompt(servers: [MCPServer]) async -> String {
        let toolList = await getToolsForPrompt(servers: servers)
        return toolList.formatForSystemPrompt()
    }
    
    // MARK: - Tool Calling
    
    /// Call a tool by name
    func callTool(name: String, arguments: [String: Any]?, servers: [MCPServer]) async throws -> String {
        // Find which server has this tool
        guard let toolWithServer = tools.first(where: { $0.tool.name == name }) else {
            throw MCPClientError.serverNotAvailable
        }
        
        guard let client = clients[toolWithServer.serverEndpoint] else {
            throw MCPClientError.notInitialized
        }
        
        let result = try await client.callTool(name: name, arguments: arguments)
        
        if result.hasError {
            return "Tool error: \(result.textContent ?? "Unknown error")"
        }
        
        return result.textContent ?? ""
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
    /// Regex pattern to match tool calls in assistant responses
    static let toolCallPattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
    
    /// Parse tool calls from assistant message
    static func parseToolCalls(from text: String) -> [(name: String, arguments: [String: Any]?)] {
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
    
    /// Check if text contains tool calls
    static func containsToolCalls(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: toolCallPattern, options: []) else {
            return false
        }
        
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
