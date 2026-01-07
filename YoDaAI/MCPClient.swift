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
    case sseEndpointNotReceived
    case sseParseError(String)
    case sseResponseTimeout
    
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
        case .sseEndpointNotReceived:
            return "SSE endpoint URL not received from server"
        case .sseParseError(let detail):
            return "SSE parse error: \(detail)"
        case .sseResponseTimeout:
            return "Timeout waiting for SSE response"
        }
    }
}

// MARK: - SSE Response Handler

/// Handles SSE stream and collects responses
private class SSEResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Int: Data] = [:]
    private var continuations: [Int: CheckedContinuation<Data, Error>] = [:]
    
    func addContinuation(for id: Int, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if response already arrived
        if let data = responses.removeValue(forKey: id) {
            continuation.resume(returning: data)
        } else {
            continuations[id] = continuation
        }
    }
    
    func handleResponse(id: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: data)
        } else {
            // Store for later retrieval
            responses[id] = data
        }
    }
    
    func cancelAll(with error: Error) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
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
    
    /// SSE-specific: the POST endpoint URL received from SSE connection
    private var ssePostEndpoint: URL?
    
    /// SSE-specific: response collector for async responses
    private var sseResponseCollector: SSEResponseCollector?
    
    /// SSE-specific: active SSE listening task
    private var sseListenTask: Task<Void, Never>?
    
    /// SSE-specific: the base URL for the SSE connection
    private var sseBaseURL: URL?
    
    /// Request timeout in seconds
    private let timeout: TimeInterval = 30
    
    init(server: MCPServer) {
        self.server = server
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        sseListenTask?.cancel()
    }
    
    // MARK: - Request ID Management
    
    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }
    
    // MARK: - Initialize
    
    /// Initialize the MCP connection
    func initialize() async throws -> MCPInitializeResult {
        // For SSE transport, we need to connect to SSE first
        if server.transport == .sse {
            try await connectSSE()
        }
        
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
    
    // MARK: - SSE Connection
    
    /// Connect to SSE endpoint, get the POST endpoint URL, and start listening for responses
    private func connectSSE() async throws {
        guard let url = server.endpointURL else {
            throw MCPClientError.invalidURL
        }
        
        self.sseBaseURL = url
        print("[MCPClient] Connecting to SSE endpoint: \(url)")
        
        // Create response collector
        let collector = SSEResponseCollector()
        self.sseResponseCollector = collector
        
        // Use a dedicated session with longer timeout for SSE
        let sseConfig = URLSessionConfiguration.default
        sseConfig.timeoutIntervalForRequest = 300 // 5 minutes for SSE
        sseConfig.timeoutIntervalForResource = 600
        let sseSession = URLSession(configuration: sseConfig)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Add custom headers
        for (key, value) in server.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Connect and get the endpoint
        let (bytes, response) = try await sseSession.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse
        }
        
        print("[MCPClient] SSE connection status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.httpError(statusCode: httpResponse.statusCode, message: "Failed to connect to SSE endpoint")
        }
        
        // Create async stream iterator
        var iterator = bytes.lines.makeAsyncIterator()
        
        // First, find the endpoint event
        var currentEvent: String?
        var foundEndpoint = false
        
        while !foundEndpoint {
            guard let line = try await iterator.next() else {
                throw MCPClientError.sseEndpointNotReceived
            }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            print("[MCPClient] SSE line: '\(trimmed)'")
            
            if trimmed.hasPrefix("event:") {
                currentEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                print("[MCPClient] SSE event type: \(currentEvent ?? "nil")")
            } else if trimmed.hasPrefix("data:") {
                let data = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                print("[MCPClient] SSE data: \(data)")
                
                if currentEvent == "endpoint" && !data.isEmpty {
                    // Build full URL
                    let endpointURL: URL?
                    if data.hasPrefix("http://") || data.hasPrefix("https://") {
                        endpointURL = URL(string: data)
                    } else {
                        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                        if let pathURL = URL(string: data, relativeTo: url) {
                            components?.path = pathURL.path
                            components?.query = pathURL.query
                        }
                        endpointURL = components?.url
                    }
                    
                    if let finalURL = endpointURL {
                        self.ssePostEndpoint = finalURL
                        print("[MCPClient] SSE endpoint received: \(finalURL)")
                        foundEndpoint = true
                    }
                }
            }
        }
        
        // Start background task to listen for responses
        sseListenTask = Task { [weak collector] in
            do {
                var msgEvent: String?
                var msgData: String?
                
                while let line = try await iterator.next() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    
                    if trimmed.isEmpty {
                        // End of event - process if we have message data
                        if msgEvent == "message", let dataStr = msgData {
                            print("[MCPClient] SSE message received: \(dataStr.prefix(200))")
                            
                            // Parse JSON-RPC response to get ID
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let id = json["id"] as? Int {
                                collector?.handleResponse(id: id, data: data)
                            }
                        }
                        msgEvent = nil
                        msgData = nil
                    } else if trimmed.hasPrefix("event:") {
                        msgEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("data:") {
                        msgData = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    }
                }
            } catch {
                print("[MCPClient] SSE listen error: \(error)")
                collector?.cancelAll(with: error)
            }
        }
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
    
    /// Get the URL to send requests to (different for SSE vs HTTP transport)
    private func getRequestURL() throws -> URL {
        if server.transport == .sse {
            guard let sseEndpoint = ssePostEndpoint else {
                throw MCPClientError.sseEndpointNotReceived
            }
            return sseEndpoint
        } else {
            guard let url = server.endpointURL else {
                throw MCPClientError.invalidURL
            }
            return url
        }
    }
    
    /// Send a JSON-RPC request and wait for response
    private func sendRequest<T: Decodable>(method: String, params: [String: AnyCodable]?) async throws -> T {
        let url = try getRequestURL()
        let reqId = nextRequestId()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // Set headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        
        // Add custom headers from server config
        for (key, value) in server.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Build JSON-RPC request
        let jsonRPCRequest = JSONRPCRequest(
            id: reqId,
            method: method,
            params: params
        )
        
        let encoder = JSONEncoder()
        let requestBody = try encoder.encode(jsonRPCRequest)
        request.httpBody = requestBody
        
        // Debug: log request
        if let requestStr = String(data: requestBody, encoding: .utf8) {
            print("[MCPClient] Sending request to \(url): \(method) (id: \(reqId))")
            print("[MCPClient] Request body: \(requestStr)")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPClientError.invalidResponse
            }
            
            print("[MCPClient] Response status: \(httpResponse.statusCode)")
            
            // For SSE transport with 202 Accepted, wait for response on SSE stream
            if server.transport == .sse && httpResponse.statusCode == 202 {
                print("[MCPClient] Waiting for SSE response for request \(reqId)...")
                
                guard let collector = sseResponseCollector else {
                    throw MCPClientError.sseParseError("SSE collector not initialized")
                }
                
                // Wait for response with timeout
                let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
                    group.addTask {
                        try await withCheckedThrowingContinuation { continuation in
                            collector.addContinuation(for: reqId, continuation: continuation)
                        }
                    }
                    
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                        throw MCPClientError.sseResponseTimeout
                    }
                    
                    guard let result = try await group.next() else {
                        throw MCPClientError.sseResponseTimeout
                    }
                    group.cancelAll()
                    return result
                }
                
                return try parseJSONRPCResponse(from: responseData)
            }
            
            // Log response body for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[MCPClient] Response body: \(responseStr.prefix(1000))")
            }
            
            // Check HTTP status
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                throw MCPClientError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            // If empty response, error
            if data.isEmpty {
                throw MCPClientError.invalidResponse
            }
            
            return try parseJSONRPCResponse(from: data)
            
        } catch let error as MCPClientError {
            throw error
        } catch let error as DecodingError {
            print("[MCPClient] Decoding error: \(error)")
            throw MCPClientError.decodingError(error)
        } catch {
            throw MCPClientError.connectionFailed(error)
        }
    }
    
    /// Parse JSON-RPC response from data
    private func parseJSONRPCResponse<T: Decodable>(from data: Data) throws -> T {
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
    }
    
    /// Send a JSON-RPC notification (no response expected)
    private func sendNotification(method: String, params: [String: AnyCodable]?) async throws {
        let url = try getRequestURL()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // Set headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add custom headers from server config
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
