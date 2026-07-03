//
//  PiChatEngine.swift
//  YoDaAI
//
//  Drives a chat turn through the pi agent (RPC) and mirrors pi's event stream
//  into a SwiftData ChatMessage + the existing tool-execution UI state. This is
//  the pi-backed counterpart to ChatViewModel.sendAssistantResponse's OpenAI
//  path, activated by LLMSettings.usePiAgent.
//
//  pi owns the tool loop, MCP, and skills. We do NOT parse <tool_call> XML or
//  re-inject tool results — we just render the events pi emits.
//

import Foundation
import SwiftData

/// Callbacks the engine uses to push streamed state back to the ViewModel
/// (which is @MainActor and owns the @Published properties + ModelContext).
@MainActor
struct PiChatCallbacks {
    /// Append streamed assistant text to the live message.
    let appendText: (String) -> Void
    /// Replace the collapsed thinking buffer.
    let appendThinking: (String) -> Void
    /// Update the tool-execution card state.
    let setToolState: (ToolExecutionState?) -> Void
    /// Persist current state (fire-and-forget save).
    let save: () -> Void
    /// A dialog/approval request from an extension; return the reply to send back.
    let handleUIRequest: (PiExtensionUIRequest) async -> PiExtensionUIResponse?
}

@MainActor
final class PiChatEngine {

    /// One bridge per working directory, cached so we reuse the pi process
    /// across turns in the same project.
    private var bridges: [String: PiAgentBridge] = [:]

    static let shared = PiChatEngine()
    private init() {}

    enum PiChatError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case .unavailable(let m): return m }
        }
    }

    /// Get (or lazily launch) a bridge for a working directory.
    private func bridge(for workingDirectory: URL,
                        provider: LLMProvider) async throws -> PiAgentBridge {
        let key = workingDirectory.path
        if let existing = bridges[key] { return existing }

        guard let resolved = PiExecutable.resolve() else {
            throw PiChatError.unavailable(
                "pi agent not found. Build it (../pi: npm run build) or bundle the binary.")
        }

        var config = PiLaunchConfig(
            executableURL: resolved.executable,
            interpreterURL: resolved.interpreter,
            workingDirectory: workingDirectory)
        // Route pi at the same provider/model the user configured, when the
        // provider name maps to a pi provider. Left nil => pi uses its own default
        // (e.g. the SAP AI Core proxy already configured in ~/.pi).
        config.noSession = false

        // Load skills from ~/.claude/skills, ~/.agents/skills, and the project's
        // .claude/skills (the last requires project trust in RPC mode).
        let skills = PiSkillsConfig.skillPaths(for: workingDirectory)
        config.skillPaths = skills.paths
        config.approveProjectTrust = skills.needsApprove

        let bridge = PiAgentBridge(config: config)
        try await bridge.start()
        bridges[key] = bridge
        return bridge
    }

    /// Tear down all bridges (e.g. on app quit or project removal).
    func shutdownAll() async {
        for (_, b) in bridges { await b.stop() }
        bridges.removeAll()
    }

    func shutdown(workingDirectory: URL) async {
        if let b = bridges.removeValue(forKey: workingDirectory.path) { await b.stop() }
    }

    /// Run one prompt turn. Streams events into `callbacks` until agent_end.
    /// `workingDirectory` scopes the pi process to a project; defaults to home.
    func generate(prompt: String,
                  images: [PiImageContent],
                  workingDirectory: URL,
                  provider: LLMProvider,
                  callbacks: PiChatCallbacks) async throws {
        let bridge = try await bridge(for: workingDirectory, provider: provider)
        let events = await bridge.events()

        // Accept the prompt. pi returns a response ack, then streams events.
        try await bridge.send(.prompt(prompt, images: images.isEmpty ? nil : images))

        var textBatch = ""
        var lastFlush = Date()

        func flush(force: Bool) {
            let now = Date()
            if !textBatch.isEmpty && (force || now.timeIntervalSince(lastFlush) > 0.05 || textBatch.count > 500) {
                let batch = textBatch
                textBatch = ""
                lastFlush = now
                callbacks.appendText(batch)
            }
        }

        for await event in events {
            try Task.checkCancellation()
            switch event {
            case .messageUpdate(_, let delta):
                switch delta {
                case .textDelta(_, let d):
                    textBatch += d
                    flush(force: false)
                case .thinkingDelta(_, let d):
                    callbacks.appendThinking(d)
                default:
                    break
                }

            case .toolExecutionStart(_, let toolName, let args):
                flush(force: true)
                let query = args?["command"]?.stringValue
                    ?? args?["query"]?.stringValue
                    ?? args?["path"]?.stringValue
                callbacks.setToolState(.executing(current: 1, total: 1, toolName: toolName, query: query))

            case .toolExecutionEnd(_, let toolName, let result, let isError):
                let preview = Self.previewText(from: result)
                if isError {
                    callbacks.setToolState(.failed(error: preview))
                } else {
                    callbacks.setToolState(.completed(results: [
                        ToolExecutionResult(toolName: toolName, query: nil,
                                            resultPreview: String(preview.prefix(200)),
                                            fullResult: preview, success: true)
                    ]))
                }

            case .extensionUIRequest(let req):
                if req.isDialog {
                    if let reply = await callbacks.handleUIRequest(req) {
                        try? await bridge.reply(reply)
                    } else {
                        try? await bridge.reply(.cancel(id: req.id))
                    }
                }
                // fire-and-forget requests (notify/setStatus/…) are ignored for now.

            case .agentEnd:
                flush(force: true)
                callbacks.setToolState(nil)
                callbacks.save()
                return

            case .response(_, let command, let success, let error, _):
                if !success, command == "prompt", let error {
                    throw PiChatError.unavailable(error)
                }

            default:
                break
            }
        }
        // Stream ended without agent_end (process died): flush what we have.
        flush(force: true)
        callbacks.save()
    }

    // MARK: - Command / skill discovery

    /// A command pi discovered (extension, prompt template, or skill).
    struct DiscoveredCommand: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let description: String
        let source: String   // "extension" | "prompt" | "skill"
        let path: String?
    }

    /// Query pi for the commands/skills available in a working directory. Uses
    /// the live per-project bridge if one exists, otherwise a short-lived one.
    func discoverCommands(workingDirectory: URL, provider: LLMProvider) async -> [DiscoveredCommand] {
        let bridge: PiAgentBridge
        let isTemporary: Bool
        if let existing = bridges[workingDirectory.path] {
            bridge = existing
            isTemporary = false
        } else {
            guard let resolved = PiExecutable.resolve() else { return [] }
            var config = PiLaunchConfig(
                executableURL: resolved.executable,
                interpreterURL: resolved.interpreter,
                workingDirectory: workingDirectory)
            config.noSession = true
            let skills = PiSkillsConfig.skillPaths(for: workingDirectory)
            config.skillPaths = skills.paths
            config.approveProjectTrust = skills.needsApprove
            bridge = PiAgentBridge(config: config)
            do { try await bridge.start() } catch { return [] }
            isTemporary = true
        }
        defer { if isTemporary { Task { await bridge.stop() } } }

        guard let response = try? await bridge.request({ id in .getCommands(id: id) }),
              case .response(_, _, let success, _, let data) = response, success,
              let commands = data?["commands"]?.arrayValue else {
            return []
        }
        return commands.map { cmd in
            DiscoveredCommand(
                name: cmd["name"]?.stringValue ?? "",
                description: cmd["description"]?.stringValue ?? "",
                source: cmd["source"]?.stringValue ?? "",
                path: cmd["sourceInfo"]?["path"]?.stringValue ?? cmd["path"]?.stringValue)
        }
    }

    /// Extract a text preview from a tool result content array.
    private static func previewText(from result: JSONValue?) -> String {
        guard let content = result?["content"]?.arrayValue else {
            return result?.stringValue ?? ""
        }
        return content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }
}
