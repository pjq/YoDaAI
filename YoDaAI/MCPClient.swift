//
//  MCPClient.swift
//  YoDaAI
//
//  Network client for MCP (Model Context Protocol) servers.
//  Supports HTTP Streamable and SSE transports.
//

import Foundation

// MARK: - MCP Client Errors

enum MCPClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case jsonRPCError(JSONRPCError)
    case connectionFailed(Error)
    case notInitialized
    case timeout
    case serverNotAvailable
    
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
        case .jsonRPCError(let error):
            return error.errorDescription
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .notInitialized:
            return "MCP client not initialized. Call initialize() first."
        case .timeout:
            return "MCP request timed out"
        case .serverNotAvailable:
            return "MCP server is not available"
        }
    }
}

// MARK: - MCP Client

/// Client for communicating with MCP servers
actor MCPClient {
    private let server: MCPServer
    private let session: URLSession
    private var isInitialized: Bool = false
    private var serverCapabilities: MCPServerCapabilities?
    private var serverInfo: MCPServerInfo?
    private var requestId: Int = 0
    
    /// Request timeout in seconds
    private let timeout: TimeInterval = 30
    
    init(server: MCPServer) {
        self.server = server
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Request ID Management
    
    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }
    
    // MARK: - Initialize
    
    /// Initialize the MCP connection
    func initialize() async throws -> MCPInitializeResult {
        let params = MCPInitializeParams.default()
        
        let result: MCPInitializeResult = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": AnyCodable(params.protocolVersion),
                "capabilities": AnyCodable([:]),
                "clientInfo": AnyCodable([
                    "name": params.clientInfo.name,
                    "version": params.clientInfo.version
                ])
            ]
        )
        
        self.serverCapabilities = result.capabilities
        self.serverInfo = result.serverInfo
        self.isInitialized = true
        
        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: nil)
        
        return result
    }
    
    // MARK: - Tools
    
    /// List available tools from the server
    func listTools() async throws -> [MCPTool] {
        guard isInitialized else {
            throw MCPClientError.notInitialized
        }
        
        let result: MCPToolsListResult = try await sendRequest(
            method: "tools/list",
            params: nil
        )
        
        return result.tools
    }
    
    /// Call a tool on the server
    func callTool(name: String, arguments: [String: Any]? = nil) async throws -> MCPToolCallResult {
        guard isInitialized else {
            throw MCPClientError.notInitialized
        }
        
        var params: [String: AnyCodable] = [
            "name": AnyCodable(name)
        ]
        
        if let arguments = arguments {
            params["arguments"] = AnyCodable(arguments)
        }
        
        let result: MCPToolCallResult = try await sendRequest(
            method: "tools/call",
            params: params
        )
        
        return result
    }
    
    // MARK: - Connection Testing
    
    /// Test if the server is reachable and responds to initialize
    func testConnection() async throws -> (serverName: String?, serverVersion: String?) {
        let result = try await initialize()
        return (result.serverInfo?.name, result.serverInfo?.version)
    }
    
    // MARK: - Private Methods
    
    /// Send a JSON-RPC request and wait for response
    private func sendRequest<T: Decodable>(method: String, params: [String: AnyCodable]?) async throws -> T {
        guard let url = server.endpointURL else {
            throw MCPClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // Set headers
        for (key, value) in server.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Build JSON-RPC request
        let jsonRPCRequest = JSONRPCRequest(
            id: nextRequestId(),
            method: method,
            params: params
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(jsonRPCRequest)
        
        print("[MCPClient] Sending request to \(url): \(method)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPClientError.invalidResponse
            }
            
            print("[MCPClient] Response status: \(httpResponse.statusCode)")
            
            // Check HTTP status
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                throw MCPClientError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            // Parse JSON-RPC response
            let decoder = JSONDecoder()
            let jsonRPCResponse = try decoder.decode(JSONRPCResponse<T>.self, from: data)
            
            // Check for JSON-RPC error
            if let error = jsonRPCResponse.error {
                throw MCPClientError.jsonRPCError(error)
            }
            
            guard let result = jsonRPCResponse.result else {
                throw MCPClientError.invalidResponse
            }
            
            return result
        } catch let error as MCPClientError {
            throw error
        } catch let error as DecodingError {
            throw MCPClientError.decodingError(error)
        } catch {
            throw MCPClientError.connectionFailed(error)
        }
    }
    
    /// Send a JSON-RPC notification (no response expected)
    private func sendNotification(method: String, params: [String: AnyCodable]?) async throws {
        guard let url = server.endpointURL else {
            throw MCPClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // Set headers
        for (key, value) in server.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Notification has no id field
        struct JSONRPCNotification: Encodable {
            let jsonrpc: String = "2.0"
            let method: String
            let params: [String: AnyCodable]?
        }
        
        let notification = JSONRPCNotification(method: method, params: params)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(notification)
        
        print("[MCPClient] Sending notification: \(method)")
        
        // Fire and forget - don't wait for response
        _ = try? await session.data(for: request)
    }
}

// MARK: - MCPClient Factory

extension MCPClient {
    /// Create a client from an MCPServer model
    static func from(_ server: MCPServer) -> MCPClient {
        MCPClient(server: server)
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
