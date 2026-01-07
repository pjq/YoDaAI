//
//  LegacySSETransport.swift
//  YoDaAI
//
//  Custom transport for legacy MCP SSE servers (like AMAP).
//  The legacy SSE transport protocol:
//  1. Client opens a GET SSE connection to the endpoint
//  2. Server sends an "endpoint" event with the POST URL for messages
//  3. Client sends JSON-RPC messages via POST to that URL
//  4. Server responds via SSE stream
//

import Foundation
import MCP
import Logging

/// Legacy SSE Transport for MCP servers using the old SSE protocol
public actor LegacySSETransport: Transport {
    public let endpoint: URL
    private let session: URLSession
    public nonisolated let logger: Logger
    
    private var messageEndpoint: URL?
    private var sseTask: Task<Void, Never>?
    private var isConnected = false
    
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    
    private var endpointContinuation: CheckedContinuation<URL, Error>?
    
    private let requestModifier: (URLRequest) -> URLRequest
    private let connectionTimeout: TimeInterval
    
    /// Creates a new legacy SSE transport
    /// - Parameters:
    ///   - endpoint: The SSE endpoint URL
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - configuration: Optional URLSession configuration
    ///   - requestModifier: Closure to modify requests (e.g., add auth headers)
    ///   - logger: Optional logger
    public init(
        endpoint: URL,
        timeout: TimeInterval = 60,
        configuration: URLSessionConfiguration? = nil,
        requestModifier: @escaping (URLRequest) -> URLRequest = { $0 },
        logger: Logger? = nil
    ) {
        self.endpoint = endpoint
        self.connectionTimeout = timeout
        
        // Configure session for long-lived SSE connections
        let config = configuration ?? {
            let c = URLSessionConfiguration.default
            // Use the provided timeout for initial connection
            c.timeoutIntervalForRequest = timeout
            // Resource timeout should be longer for SSE streams
            c.timeoutIntervalForResource = max(timeout * 10, 3600)  // At least 1 hour
            // Allow SSE to work properly
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return c
        }()
        
        self.session = URLSession(configuration: config)
        self.requestModifier = requestModifier
        
        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
        
        self.logger = logger ?? Logger(
            label: "mcp.transport.legacysse",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )
    }
    
    /// Connect to the SSE stream and wait for the endpoint event
    public func connect() async throws {
        guard !isConnected else { return }
        
        print("[LegacySSE] Connecting to SSE endpoint: \(endpoint) (timeout: \(Int(connectionTimeout))s)")
        
        // Start SSE connection task
        sseTask = Task {
            await startSSEConnection()
        }
        
        // Wait for the endpoint event with configurable timeout
        do {
            messageEndpoint = try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        Task { await self.setEndpointContinuation(continuation) }
                    }
                }
                
                group.addTask { [connectionTimeout] in
                    try await Task.sleep(for: .seconds(connectionTimeout))
                    throw MCPError.internalError("Timeout waiting for endpoint event after \(Int(connectionTimeout))s")
                }
                
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                throw MCPError.internalError("No endpoint received")
            }
            
            isConnected = true
            print("[LegacySSE] Connected, message endpoint: \(messageEndpoint?.absoluteString ?? "nil")")
        } catch {
            sseTask?.cancel()
            throw error
        }
    }
    
    private func setEndpointContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        self.endpointContinuation = continuation
    }
    
    /// Disconnect from the transport
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        
        sseTask?.cancel()
        sseTask = nil
        session.invalidateAndCancel()
        messageContinuation.finish()
        
        print("[LegacySSE] Disconnected")
    }
    
    /// Send data via HTTP POST to the message endpoint
    public func send(_ data: Data) async throws {
        guard isConnected, let messageEndpoint = messageEndpoint else {
            throw MCPError.internalError("Transport not connected or no message endpoint")
        }
        
        var request = URLRequest(url: messageEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        
        // Apply request modifier (for auth headers)
        request = requestModifier(request)
        
        if let requestStr = String(data: data, encoding: .utf8) {
            print("[LegacySSE] Sending: \(requestStr.prefix(200))")
        }
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid HTTP response")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw MCPError.internalError("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }
        
        // If we got a direct response, yield it
        if !responseData.isEmpty {
            if let responseStr = String(data: responseData, encoding: .utf8) {
                print("[LegacySSE] Response: \(responseStr.prefix(200))")
            }
            messageContinuation.yield(responseData)
        }
    }
    
    /// Receive messages from the SSE stream
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }
    
    // MARK: - Private Methods
    
    private func startSSEConnection() async {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // Use longer timeout for SSE - the stream should stay open
        request.timeoutInterval = max(connectionTimeout * 10, 3600)
        
        // Apply request modifier
        request = requestModifier(request)
        
        do {
            let (stream, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                endpointContinuation?.resume(throwing: MCPError.internalError("Invalid HTTP response"))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                endpointContinuation?.resume(throwing: MCPError.internalError("HTTP \(httpResponse.statusCode)"))
                return
            }
            
            print("[LegacySSE] SSE connection established")
            
            // Parse SSE events manually
            var eventType: String?
            var eventData: String = ""
            
            for try await line in stream.lines {
                if Task.isCancelled { break }
                
                // Empty line = end of event
                if line.isEmpty {
                    if let type = eventType, !eventData.isEmpty {
                        await handleSSEEvent(type: type, data: eventData)
                    }
                    eventType = nil
                    eventData = ""
                    continue
                }
                
                if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if !eventData.isEmpty {
                        eventData += "\n"
                    }
                    eventData += data
                } else if line.hasPrefix(":") {
                    // Comment, ignore
                    continue
                }
            }
        } catch {
            if !Task.isCancelled {
                print("[LegacySSE] SSE connection error: \(error)")
                endpointContinuation?.resume(throwing: error)
            }
        }
    }
    
    private func handleSSEEvent(type: String, data: String) async {
        print("[LegacySSE] Event: \(type), data: \(data.prefix(100))")
        
        switch type {
        case "endpoint":
            // The endpoint event contains the URL for POST requests
            // It may be a relative path or absolute URL
            if let endpointURL = resolveEndpointURL(data) {
                endpointContinuation?.resume(returning: endpointURL)
                endpointContinuation = nil
            } else {
                endpointContinuation?.resume(throwing: MCPError.internalError("Invalid endpoint URL: \(data)"))
                endpointContinuation = nil
            }
            
        case "message":
            // JSON-RPC message from server
            if let messageData = data.data(using: .utf8) {
                messageContinuation.yield(messageData)
            }
            
        default:
            // Other event types - try to parse as JSON-RPC
            if let messageData = data.data(using: .utf8) {
                messageContinuation.yield(messageData)
            }
        }
    }
    
    private func resolveEndpointURL(_ path: String) -> URL? {
        // If it's already an absolute URL, use it directly
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        
        // Otherwise, resolve relative to the base endpoint
        // Extract base URL from endpoint (e.g., https://mcp.amap.com from https://mcp.amap.com/sse)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)
        
        if path.hasPrefix("/") {
            // Absolute path - just replace the path
            components?.path = path
        } else {
            // Relative path - append to existing
            let basePath = (components?.path ?? "").components(separatedBy: "/").dropLast().joined(separator: "/")
            components?.path = basePath + "/" + path
        }
        
        // Preserve query string from original endpoint if new path doesn't have one
        if let existingQuery = endpoint.query, components?.queryItems == nil {
            components?.query = existingQuery
        }
        
        return components?.url
    }
}
