//
//  MCPTypes.swift
//  YoDaAI
//
//  MCP (Model Context Protocol) type definitions for JSON-RPC communication.
//

import Foundation

// MARK: - MCP Transport Type

/// Transport protocol for MCP server communication
enum MCPTransport: String, Codable, CaseIterable, Identifiable {
    case httpStreamable = "http_streamable"
    case sse = "sse"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .httpStreamable: return "HTTP Streamable"
        case .sse: return "Server-Sent Events (SSE)"
        }
    }
    
    var description: String {
        switch self {
        case .httpStreamable: return "Default transport using HTTP POST with optional streaming"
        case .sse: return "Server-Sent Events transport for streaming responses"
        }
    }
}

// MARK: - JSON-RPC Types

/// JSON-RPC 2.0 request
struct JSONRPCRequest: Encodable, Sendable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
    
    init(id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response
struct JSONRPCResponse<T: Decodable>: Decodable, Sendable where T: Sendable {
    let jsonrpc: String
    let id: Int?
    let result: T?
    let error: JSONRPCError?
}

/// JSON-RPC 2.0 error
struct JSONRPCError: Decodable, Error, LocalizedError, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?
    
    var errorDescription: String? {
        "MCP Error [\(code)]: \(message)"
    }
}

// MARK: - MCP Initialize Types

/// MCP client info sent during initialization
struct MCPClientInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// MCP protocol capabilities
struct MCPCapabilities: Codable, Sendable {
    // Client capabilities - currently empty but extensible
    init() {}
}

/// MCP initialize request params
struct MCPInitializeParams: Encodable, Sendable {
    let protocolVersion: String
    let capabilities: MCPCapabilities
    let clientInfo: MCPClientInfo
    
    static func `default`() -> MCPInitializeParams {
        MCPInitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: MCPCapabilities(),
            clientInfo: MCPClientInfo(name: "YoDaAI", version: "1.0.0")
        )
    }
}

/// MCP server info received during initialization
struct MCPServerInfo: Decodable, Sendable {
    let name: String?
    let version: String?
}

/// MCP server capabilities
struct MCPServerCapabilities: Decodable, Sendable {
    let tools: MCPToolsCapability?
    let resources: MCPResourcesCapability?
    let prompts: MCPPromptsCapability?
}

struct MCPToolsCapability: Decodable, Sendable {
    let listChanged: Bool?
}

struct MCPResourcesCapability: Decodable, Sendable {
    let subscribe: Bool?
    let listChanged: Bool?
}

struct MCPPromptsCapability: Decodable, Sendable {
    let listChanged: Bool?
}

/// MCP initialize response result
struct MCPInitializeResult: Decodable, Sendable {
    let protocolVersion: String
    let capabilities: MCPServerCapabilities?
    let serverInfo: MCPServerInfo?
}

// MARK: - MCP Tool Types

/// MCP tool definition
struct MCPTool: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let description: String?
    let inputSchema: MCPToolInputSchema?
    
    var id: String { name }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.name == rhs.name
    }
}

/// JSON Schema for tool input parameters
struct MCPToolInputSchema: Codable, Sendable {
    let type: String?
    let properties: [String: MCPToolProperty]?
    let required: [String]?
    let additionalProperties: Bool?
}

/// Individual tool property definition
struct MCPToolProperty: Codable, Sendable {
    let type: String?
    let description: String?
    let `enum`: [String]?
    let items: MCPToolPropertyItems?
    let `default`: AnyCodable?
}

/// For array items
struct MCPToolPropertyItems: Codable, Sendable {
    let type: String?
}

/// MCP tools/list response
struct MCPToolsListResult: Decodable, Sendable {
    let tools: [MCPTool]
    let nextCursor: String?
}

// MARK: - MCP Tool Call Types

/// MCP tools/call request params
struct MCPToolCallParams: Encodable, Sendable {
    let name: String
    let arguments: [String: AnyCodable]?
}

/// MCP tool call result content item
struct MCPToolResultContent: Decodable, Sendable {
    let type: String
    let text: String?
    let mimeType: String?
    let data: String?  // Base64 encoded for non-text
}

/// MCP tools/call response
struct MCPToolCallResult: Decodable, Sendable {
    let content: [MCPToolResultContent]?
    let isError: Bool?
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic JSON values
struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        // Use string description for hashing since Any isn't Hashable
        hasher.combine(String(describing: value))
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - Tool Prompt Formatting

extension MCPTool {
    /// Format this tool as a prompt description for embedding in system prompt
    func formatForPrompt() -> String {
        var lines: [String] = []
        lines.append("## \(name)")
        
        if let description = description, !description.isEmpty {
            lines.append("Description: \(description)")
        }
        
        if let schema = inputSchema, let properties = schema.properties, !properties.isEmpty {
            lines.append("Parameters:")
            for (propName, prop) in properties.sorted(by: { $0.key < $1.key }) {
                let typeStr = prop.type ?? "any"
                let required = schema.required?.contains(propName) == true ? " (required)" : ""
                var line = "- \(propName) (\(typeStr))\(required)"
                if let desc = prop.description, !desc.isEmpty {
                    line += ": \(desc)"
                }
                if let enumValues = prop.enum, !enumValues.isEmpty {
                    line += " [options: \(enumValues.joined(separator: ", "))]"
                }
                lines.append(line)
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

extension Array where Element == MCPTool {
    /// Format all tools as a system prompt block
    func formatForSystemPrompt() -> String {
        guard !isEmpty else { return "" }
        
        var lines: [String] = []
        lines.append("You have access to the following tools from connected MCP servers:")
        lines.append("")
        
        for tool in self {
            lines.append(tool.formatForPrompt())
            lines.append("")
        }
        
        lines.append("To use a tool, respond with a tool call in this exact format:")
        lines.append("<tool_call>")
        lines.append("{\"name\": \"tool_name\", \"arguments\": {\"param1\": \"value1\"}}")
        lines.append("</tool_call>")
        lines.append("")
        lines.append("You may use multiple tool calls in a single response if needed.")
        lines.append("After receiving tool results, incorporate them into your response to the user.")
        
        return lines.joined(separator: "\n")
    }
}
