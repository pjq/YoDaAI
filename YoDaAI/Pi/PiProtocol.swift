//
//  PiProtocol.swift
//  YoDaAI
//
//  Swift Codable model of the pi agent's RPC protocol (JSONL over stdin/stdout).
//  Ported from ../pi/packages/coding-agent/src/modes/rpc/rpc-types.ts and
//  ../pi/packages/coding-agent/docs/rpc.md.
//
//  Design notes:
//  - Commands (Swift -> pi) are encoded to a single JSON object + "\n".
//  - Events/responses (pi -> Swift) are decoded from one JSON object per "\n".
//  - Deep pi types (Model, AgentMessage, SessionStats) are kept as opaque
//    JSONValue payloads: we don't need to fully mirror pi's type tree, just the
//    fields the UI reads. This keeps the Swift port small and resilient to pi
//    adding fields.
//

import Foundation

// Everything in this file is protocol wire-modeling with no UI state, so it is
// `nonisolated` — the PiAgentBridge actor encodes/decodes these off the main
// actor. (The project defaults types to @MainActor isolation.)

// MARK: - JSONValue (opaque payload holder)

/// A minimal JSON value type so we can carry arbitrary pi payloads (model
/// objects, messages, stats) without porting every nested type. Read fields
/// on demand via subscript / typed accessors.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // Convenience accessors
    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

// MARK: - Image content (for prompt/steer/follow_up)

nonisolated struct PiImageContent: Codable, Sendable {
    let type: String   // "image"
    let data: String   // base64
    let mimeType: String

    init(base64 data: String, mimeType: String) {
        self.type = "image"
        self.data = data
        self.mimeType = mimeType
    }
}

// MARK: - Commands (Swift -> pi)

/// Streaming behavior when the agent is already running (prompt only).
nonisolated enum PiStreamingBehavior: String, Codable, Sendable {
    case steer
    case followUp
}

nonisolated enum PiThinkingLevel: String, Codable, Sendable {
    case off, minimal, low, medium, high, xhigh
}

/// A command to send to pi. Encodes to a flat JSON object matching RpcCommand.
/// We build these via factory methods so callers can't produce invalid shapes.
nonisolated struct PiCommand: Encodable, Sendable {
    let id: String?
    let type: String
    // Optional fields depending on `type`. Only non-nil ones are encoded.
    var message: String?
    var images: [PiImageContent]?
    var streamingBehavior: PiStreamingBehavior?
    var provider: String?
    var modelId: String?
    var level: PiThinkingLevel?
    var mode: String?
    var enabled: Bool?
    var command: String?          // for bash
    var excludeFromContext: Bool?
    var customInstructions: String?
    var outputPath: String?
    var sessionPath: String?
    var parentSession: String?
    var entryId: String?
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, message, images, streamingBehavior, provider, modelId,
             level, mode, enabled, command, excludeFromContext, customInstructions,
             outputPath, sessionPath, parentSession, entryId, name
    }

    private init(type: String, id: String? = nil) {
        self.type = type
        self.id = id
    }

    // Factories
    static func prompt(_ message: String, id: String? = nil,
                       images: [PiImageContent]? = nil,
                       streamingBehavior: PiStreamingBehavior? = nil) -> PiCommand {
        var c = PiCommand(type: "prompt", id: id)
        c.message = message; c.images = images; c.streamingBehavior = streamingBehavior
        return c
    }
    static func steer(_ message: String, id: String? = nil, images: [PiImageContent]? = nil) -> PiCommand {
        var c = PiCommand(type: "steer", id: id); c.message = message; c.images = images; return c
    }
    static func followUp(_ message: String, id: String? = nil, images: [PiImageContent]? = nil) -> PiCommand {
        var c = PiCommand(type: "follow_up", id: id); c.message = message; c.images = images; return c
    }
    static func abort(id: String? = nil) -> PiCommand { PiCommand(type: "abort", id: id) }
    static func newSession(parentSession: String? = nil, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "new_session", id: id); c.parentSession = parentSession; return c
    }
    static func getState(id: String? = nil) -> PiCommand { PiCommand(type: "get_state", id: id) }
    static func getMessages(id: String? = nil) -> PiCommand { PiCommand(type: "get_messages", id: id) }
    static func getCommands(id: String? = nil) -> PiCommand { PiCommand(type: "get_commands", id: id) }
    static func getSessionStats(id: String? = nil) -> PiCommand { PiCommand(type: "get_session_stats", id: id) }
    static func getAvailableModels(id: String? = nil) -> PiCommand { PiCommand(type: "get_available_models", id: id) }
    static func getLastAssistantText(id: String? = nil) -> PiCommand { PiCommand(type: "get_last_assistant_text", id: id) }
    static func setModel(provider: String, modelId: String, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "set_model", id: id); c.provider = provider; c.modelId = modelId; return c
    }
    static func setThinkingLevel(_ level: PiThinkingLevel, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "set_thinking_level", id: id); c.level = level; return c
    }
    static func switchSession(_ sessionPath: String, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "switch_session", id: id); c.sessionPath = sessionPath; return c
    }
    static func setSessionName(_ name: String, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "set_session_name", id: id); c.name = name; return c
    }
    static func compact(customInstructions: String? = nil, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "compact", id: id); c.customInstructions = customInstructions; return c
    }
    static func bash(_ command: String, excludeFromContext: Bool? = nil, id: String? = nil) -> PiCommand {
        var c = PiCommand(type: "bash", id: id); c.command = command; c.excludeFromContext = excludeFromContext; return c
    }
}

// MARK: - Extension UI response (Swift -> pi)

/// Reply to an `extension_ui_request`. `id` must match the request.
nonisolated struct PiExtensionUIResponse: Encodable, Sendable {
    let type = "extension_ui_response"
    let id: String
    var value: String?
    var confirmed: Bool?
    var cancelled: Bool?

    static func value(_ v: String, id: String) -> PiExtensionUIResponse {
        var r = PiExtensionUIResponse(id: id); r.value = v; return r
    }
    static func confirm(_ ok: Bool, id: String) -> PiExtensionUIResponse {
        var r = PiExtensionUIResponse(id: id); r.confirmed = ok; return r
    }
    static func cancel(id: String) -> PiExtensionUIResponse {
        var r = PiExtensionUIResponse(id: id); r.cancelled = true; return r
    }

    private init(id: String) { self.id = id }
}

// MARK: - Inbound messages (pi -> Swift)

/// Assistant streaming delta types carried inside a `message_update` event's
/// `assistantMessageEvent`. Mirrors rpc.md's delta table.
nonisolated enum PiDelta: Sendable {
    case start
    case textStart(contentIndex: Int)
    case textDelta(contentIndex: Int, delta: String)
    case textEnd(contentIndex: Int, content: String)
    case thinkingStart(contentIndex: Int)
    case thinkingDelta(contentIndex: Int, delta: String)
    case thinkingEnd(contentIndex: Int)
    case toolCallStart(contentIndex: Int)
    case toolCallDelta(contentIndex: Int)
    case toolCallEnd(contentIndex: Int, toolCall: JSONValue?)
    case done(reason: String?)
    case error(reason: String?)
    case other(type: String)

    init(from j: JSONValue) {
        let type = j["type"]?.stringValue ?? "unknown"
        let idx = j["contentIndex"]?.intValue ?? 0
        switch type {
        case "start": self = .start
        case "text_start": self = .textStart(contentIndex: idx)
        case "text_delta": self = .textDelta(contentIndex: idx, delta: j["delta"]?.stringValue ?? "")
        case "text_end": self = .textEnd(contentIndex: idx, content: j["content"]?.stringValue ?? "")
        case "thinking_start": self = .thinkingStart(contentIndex: idx)
        case "thinking_delta": self = .thinkingDelta(contentIndex: idx, delta: j["delta"]?.stringValue ?? "")
        case "thinking_end": self = .thinkingEnd(contentIndex: idx)
        case "toolcall_start": self = .toolCallStart(contentIndex: idx)
        case "toolcall_delta": self = .toolCallDelta(contentIndex: idx)
        case "toolcall_end": self = .toolCallEnd(contentIndex: idx, toolCall: j["toolCall"])
        case "done": self = .done(reason: j["reason"]?.stringValue)
        case "error": self = .error(reason: j["reason"]?.stringValue)
        default: self = .other(type: type)
        }
    }
}

/// An extension UI request from pi (dialog or fire-and-forget).
nonisolated struct PiExtensionUIRequest: Sendable {
    let id: String
    let method: String   // select | confirm | input | editor | notify | setStatus | setWidget | setTitle | set_editor_text
    let raw: JSONValue   // full object so callers can read method-specific fields

    var title: String? { raw["title"]?.stringValue }
    var message: String? { raw["message"]?.stringValue }
    var placeholder: String? { raw["placeholder"]?.stringValue }
    var prefill: String? { raw["prefill"]?.stringValue }
    var options: [String]? { raw["options"]?.arrayValue?.compactMap { $0.stringValue } }
    var notifyType: String? { raw["notifyType"]?.stringValue }
    var timeout: Int? { raw["timeout"]?.intValue }
    var text: String? { raw["text"]?.stringValue }

    /// Dialog methods block awaiting a response; fire-and-forget ones don't.
    var isDialog: Bool { ["select", "confirm", "input", "editor"].contains(method) }
}

/// Everything pi can emit on stdout, normalized into one enum. `response` and
/// the fine-grained lifecycle events are separated so the bridge can route
/// responses by `id` and stream events to consumers.
nonisolated enum PiInbound: Sendable {
    case response(id: String?, command: String, success: Bool, error: String?, data: JSONValue?)
    case agentStart
    case agentEnd(messages: JSONValue?)
    case turnStart
    case turnEnd(message: JSONValue?, toolResults: JSONValue?)
    case messageStart(message: JSONValue?)
    case messageEnd(message: JSONValue?)
    case messageUpdate(message: JSONValue?, delta: PiDelta)
    case toolExecutionStart(toolCallId: String, toolName: String, args: JSONValue?)
    case toolExecutionUpdate(toolCallId: String, toolName: String, partialResult: JSONValue?)
    case toolExecutionEnd(toolCallId: String, toolName: String, result: JSONValue?, isError: Bool)
    case queueUpdate(steering: [String], followUp: [String])
    case compactionStart(reason: String?)
    case compactionEnd(reason: String?, aborted: Bool, errorMessage: String?)
    case autoRetryStart(attempt: Int, maxAttempts: Int, delayMs: Int, errorMessage: String?)
    case autoRetryEnd(success: Bool, attempt: Int, finalError: String?)
    case extensionError(extensionPath: String?, event: String?, error: String?)
    case extensionUIRequest(PiExtensionUIRequest)
    case unknown(type: String, raw: JSONValue)

    /// Decode one parsed JSON line into a PiInbound. Returns nil only if the
    /// line has no `type` string at all.
    init?(json j: JSONValue) {
        guard let type = j["type"]?.stringValue else { return nil }
        switch type {
        case "response":
            self = .response(
                id: j["id"]?.stringValue,
                command: j["command"]?.stringValue ?? "",
                success: j["success"]?.boolValue ?? false,
                error: j["error"]?.stringValue,
                data: j["data"])
        case "agent_start": self = .agentStart
        case "agent_end": self = .agentEnd(messages: j["messages"])
        case "turn_start": self = .turnStart
        case "turn_end": self = .turnEnd(message: j["message"], toolResults: j["toolResults"])
        case "message_start": self = .messageStart(message: j["message"])
        case "message_end": self = .messageEnd(message: j["message"])
        case "message_update":
            let deltaJSON = j["assistantMessageEvent"] ?? .null
            self = .messageUpdate(message: j["message"], delta: PiDelta(from: deltaJSON))
        case "tool_execution_start":
            self = .toolExecutionStart(
                toolCallId: j["toolCallId"]?.stringValue ?? "",
                toolName: j["toolName"]?.stringValue ?? "",
                args: j["args"])
        case "tool_execution_update":
            self = .toolExecutionUpdate(
                toolCallId: j["toolCallId"]?.stringValue ?? "",
                toolName: j["toolName"]?.stringValue ?? "",
                partialResult: j["partialResult"])
        case "tool_execution_end":
            self = .toolExecutionEnd(
                toolCallId: j["toolCallId"]?.stringValue ?? "",
                toolName: j["toolName"]?.stringValue ?? "",
                result: j["result"],
                isError: j["isError"]?.boolValue ?? false)
        case "queue_update":
            self = .queueUpdate(
                steering: j["steering"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                followUp: j["followUp"]?.arrayValue?.compactMap { $0.stringValue } ?? [])
        case "compaction_start": self = .compactionStart(reason: j["reason"]?.stringValue)
        case "compaction_end":
            self = .compactionEnd(reason: j["reason"]?.stringValue,
                                  aborted: j["aborted"]?.boolValue ?? false,
                                  errorMessage: j["errorMessage"]?.stringValue)
        case "auto_retry_start":
            self = .autoRetryStart(attempt: j["attempt"]?.intValue ?? 0,
                                   maxAttempts: j["maxAttempts"]?.intValue ?? 0,
                                   delayMs: j["delayMs"]?.intValue ?? 0,
                                   errorMessage: j["errorMessage"]?.stringValue)
        case "auto_retry_end":
            self = .autoRetryEnd(success: j["success"]?.boolValue ?? false,
                                 attempt: j["attempt"]?.intValue ?? 0,
                                 finalError: j["finalError"]?.stringValue)
        case "extension_error":
            self = .extensionError(extensionPath: j["extensionPath"]?.stringValue,
                                   event: j["event"]?.stringValue,
                                   error: j["error"]?.stringValue)
        case "extension_ui_request":
            self = .extensionUIRequest(PiExtensionUIRequest(
                id: j["id"]?.stringValue ?? "",
                method: j["method"]?.stringValue ?? "",
                raw: j))
        default:
            self = .unknown(type: type, raw: j)
        }
    }
}
