//
//  MCPClient.swift
//  YoDaAI
//
//  MCP client wrapper using the official MCP Swift SDK.
//  Handles connection, initialization, and tool operations.
//

import Foundation
import MCP

// MARK: - MCP Client Errors

enum MCPClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case mcpError(String)
    case connectionFailed(Error)
    case notInitialized
    case timeout
    case serverNotAvailable
    case transportNotSupported
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid MCP server URL"
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .httpError(let code, let message):
            if let msg = message {
                return "HTTP \(code): \(msg)"
            }
            return "HTTP error \(code)"
        case .decodingError(let error):
            return "Failed to decode MCP response: \(error.localizedDescription)"
        case .mcpError(let message):
            return "MCP Error: \(message)"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .notInitialized:
            return "MCP client not initialized. Call initialize() first."
        case .timeout:
            return "MCP request timed out"
        case .serverNotAvailable:
            return "MCP server is not available"
        case .transportNotSupported:
            return "Transport type not supported"
        }
    }
}

// MARK: - MCP Client Wrapper

/// Wrapper around the official MCP SDK Client for YoDaAI integration
actor MCPClientWrapper {
    private let server: MCPServer
    private var client: Client?
    private var transport: HTTPClientTransport?
    private var isInitialized: Bool = false
    private var serverCapabilitiesResult: Server.Capabilities?
    private var serverInfoResult: Server.Info?
    
    init(server: MCPServer) {
        self.server = server
    }
    
    // MARK: - Initialize
    
    /// Initialize the MCP connection
    func initialize() async throws -> MCPInitializeResult {
        guard let url = server.endpointURL else {
            throw MCPClientError.invalidURL
        }
        
        print("[MCPClient] Connecting to MCP server: \(url)")
        
        // Create the MCP client
        let mcpClient = Client(
            name: "YoDaAI",
            version: "1.0.0",
            configuration: .default
        )
        
        // Create transport with request modifier for custom headers
        let httpTransport = HTTPClientTransport(
            endpoint: url,
            streaming: true,
            requestModifier: { [server] request in
                var modifiedRequest = request
                for (key, value) in server.buildHeaders() {
                    modifiedRequest.addValue(value, forHTTPHeaderField: key)
                }
                return modifiedRequest
            }
        )
        
        self.transport = httpTransport
        self.client = mcpClient
        
        // Connect to the server
        do {
            let result = try await mcpClient.connect(transport: httpTransport)
            
            self.serverCapabilitiesResult = result.capabilities
            self.serverInfoResult = result.serverInfo
            self.isInitialized = true
            
            print("[MCPClient] Connected to server: \(result.serverInfo.name)")
            
            return MCPInitializeResult(
                protocolVersion: result.protocolVersion,
                capabilities: mapCapabilities(result.capabilities),
                serverInfo: MCPServerInfo(
                    name: result.serverInfo.name,
                    version: result.serverInfo.version
                )
            )
        } catch {
            print("[MCPClient] Connection failed: \(error)")
            throw MCPClientError.connectionFailed(error)
        }
    }
    
    // MARK: - Tools
    
    /// List available tools from the server
    func listTools() async throws -> [MCPTool] {
        guard isInitialized, let client = client else {
            throw MCPClientError.notInitialized
        }
        
        do {
            let (tools, _) = try await client.listTools()
            
            return tools.map { tool in
                MCPTool(
                    name: tool.name,
                    description: tool.description,
                    inputSchema: mapInputSchema(tool.inputSchema)
                )
            }
        } catch {
            print("[MCPClient] listTools error: \(error)")
            throw MCPClientError.mcpError(error.localizedDescription)
        }
    }
    
    /// Call a tool on the server
    func callTool(name: String, arguments: [String: Any]? = nil) async throws -> MCPToolCallResult {
        guard isInitialized, let client = client else {
            throw MCPClientError.notInitialized
        }
        
        do {
            // Convert arguments to MCP Value type
            let mcpArguments: [String: Value]?
            if let args = arguments {
                mcpArguments = args.mapValues { anyToValue($0) }
            } else {
                mcpArguments = nil
            }
            
            let (content, isError) = try await client.callTool(
                name: name,
                arguments: mcpArguments
            )
            
            // Convert content to our format
            let resultContent = content.map { item -> MCPToolResultContent in
                switch item {
                case .text(let text):
                    return MCPToolResultContent(type: "text", text: text, mimeType: nil, data: nil)
                case .image(let imageData, let mimeType, _):
                    // imageData is already a String (base64 encoded) in the SDK
                    return MCPToolResultContent(type: "image", text: nil, mimeType: mimeType, data: imageData)
                case .audio(let audioData, let mimeType):
                    return MCPToolResultContent(type: "audio", text: nil, mimeType: mimeType, data: audioData)
                case .resource(let uri, let mimeType, let text):
                    return MCPToolResultContent(type: "resource", text: text ?? uri, mimeType: mimeType, data: nil)
                }
            }
            
            return MCPToolCallResult(content: resultContent, isError: isError)
        } catch {
            print("[MCPClient] callTool error: \(error)")
            throw MCPClientError.mcpError(error.localizedDescription)
        }
    }
    
    // MARK: - Connection Testing
    
    /// Test if the server is reachable and responds to initialize
    func testConnection() async throws -> (serverName: String?, serverVersion: String?) {
        let result = try await initialize()
        return (result.serverInfo?.name, result.serverInfo?.version)
    }
    
    /// Disconnect from the server
    func disconnect() async {
        if let transport = transport {
            await transport.disconnect()
        }
        client = nil
        transport = nil
        isInitialized = false
    }
    
    // MARK: - Private Helpers
    
    /// Convert Any to MCP Value
    private func anyToValue(_ any: Any) -> Value {
        switch any {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { anyToValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { anyToValue($0) })
        case is NSNull:
            return .null
        default:
            return .string(String(describing: any))
        }
    }
    
    /// Map SDK capabilities to our format
    private func mapCapabilities(_ capabilities: Server.Capabilities) -> MCPServerCapabilities? {
        return MCPServerCapabilities(
            tools: capabilities.tools != nil ? MCPToolsCapability(listChanged: capabilities.tools?.listChanged) : nil,
            resources: capabilities.resources != nil ? MCPResourcesCapability(subscribe: capabilities.resources?.subscribe, listChanged: capabilities.resources?.listChanged) : nil,
            prompts: capabilities.prompts != nil ? MCPPromptsCapability(listChanged: capabilities.prompts?.listChanged) : nil
        )
    }
    
    /// Map SDK input schema to our format
    private func mapInputSchema(_ schema: Value) -> MCPToolInputSchema? {
        // The SDK uses Value type for schema
        // We need to extract the relevant fields
        var properties: [String: MCPToolProperty]? = nil
        var required: [String]? = nil
        
        // Access schema as a dictionary
        if case .object(let schemaDict) = schema {
            if let propsValue = schemaDict["properties"], case .object(let propsDict) = propsValue {
                var props: [String: MCPToolProperty] = [:]
                for (key, value) in propsDict {
                    if case .object(let propDict) = value {
                        let type = propDict["type"].flatMap { v -> String? in
                            if case .string(let s) = v { return s }
                            return nil
                        }
                        let description = propDict["description"].flatMap { v -> String? in
                            if case .string(let s) = v { return s }
                            return nil
                        }
                        let enumValues = propDict["enum"].flatMap { v -> [String]? in
                            if case .array(let arr) = v {
                                return arr.compactMap { item in
                                    if case .string(let s) = item { return s }
                                    return nil
                                }
                            }
                            return nil
                        }
                        props[key] = MCPToolProperty(
                            type: type,
                            description: description,
                            enum: enumValues,
                            items: nil,
                            default: nil
                        )
                    }
                }
                properties = props.isEmpty ? nil : props
            }
            
            // Extract required
            if let reqValue = schemaDict["required"], case .array(let reqArr) = reqValue {
                required = reqArr.compactMap { v -> String? in
                    if case .string(let s) = v { return s }
                    return nil
                }
            }
        }
        
        return MCPToolInputSchema(
            type: "object",
            properties: properties,
            required: required,
            additionalProperties: nil
        )
    }
}

// MARK: - Legacy MCPClient Alias

/// Alias for backward compatibility
typealias MCPClient = MCPClientWrapper

// MARK: - MCPClient Factory

extension MCPClientWrapper {
    /// Create a client from an MCPServer model
    nonisolated static func from(_ server: MCPServer) -> MCPClientWrapper {
        MCPClientWrapper(server: server)
    }
}

// MARK: - Tool Result Text Extraction

extension MCPToolCallResult {
    /// Extract text content from tool result
    var textContent: String? {
        guard let content = content else { return nil }
        
        return content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: "\n")
    }
    
    /// Check if this result represents an error
    var hasError: Bool {
        isError == true
    }
}
