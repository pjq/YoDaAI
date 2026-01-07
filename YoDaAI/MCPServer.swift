//
//  MCPServer.swift
//  YoDaAI
//
//  SwiftData model for MCP server configuration.
//

import Foundation
import SwiftData

/// MCP Server configuration model for SwiftData persistence
@Model
final class MCPServer {
    /// Unique identifier
    var id: UUID = UUID()
    
    /// Human-readable name for this server
    var name: String = "New MCP Server"
    
    /// Server endpoint URL (e.g., "https://mcp.example.com/mcp")
    var endpoint: String = ""
    
    /// Transport protocol to use
    var transportRawValue: String = MCPTransport.httpStreamable.rawValue
    
    /// Whether this server is enabled
    var isEnabled: Bool = true
    
    /// Optional API key for authentication
    var apiKey: String = ""
    
    /// Additional headers as JSON string (for custom auth)
    var customHeadersJSON: String = "{}"
    
    /// When this server was created
    var createdAt: Date = Date()
    
    /// When this server was last modified
    var updatedAt: Date = Date()
    
    /// Computed transport property
    var transport: MCPTransport {
        get { MCPTransport(rawValue: transportRawValue) ?? .httpStreamable }
        set { transportRawValue = newValue.rawValue }
    }
    
    /// Parse custom headers from JSON
    var customHeaders: [String: String] {
        get {
            guard let data = customHeadersJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                customHeadersJSON = str
            }
        }
    }
    
    init() {}
    
    init(name: String, endpoint: String, transport: MCPTransport = .httpStreamable, apiKey: String = "") {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.transportRawValue = transport.rawValue
        self.apiKey = apiKey
        self.isEnabled = true
        self.customHeadersJSON = "{}"
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Convenience Extensions

extension MCPServer {
    /// Check if this server has a valid endpoint URL
    var hasValidEndpoint: Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    /// Get full URL for the endpoint
    var endpointURL: URL? {
        URL(string: endpoint)
    }
    
    /// Build HTTP headers for requests to this server
    func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        // Add API key if present
        if !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        
        // Merge custom headers (overrides defaults)
        for (key, value) in customHeaders {
            headers[key] = value
        }
        
        return headers
    }
}
