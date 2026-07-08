//
//  PiAgentBridge.swift
//  YoDaAI
//
//  Spawns and drives a `pi --mode rpc` child process. Speaks pi's strict JSONL
//  protocol over stdin/stdout: commands are written as one JSON object + "\n";
//  events/responses are read as one JSON object per "\n".
//
//  Critical protocol rules (from ../pi/packages/coding-agent/docs/rpc.md and the
//  M0 smoke test):
//   - stdin MUST stay open for the process lifetime — pi exits on stdin EOF.
//   - Frame stdout on "\n" ONLY. Strip a trailing "\r". Do NOT split on
//     U+2028/U+2029 (they are valid inside JSON strings).
//   - Responses carry an optional `id`; events never do. We correlate
//     request/response by id via continuations, and broadcast events to a stream.
//

import Foundation

/// Errors surfaced by the bridge.
enum PiBridgeError: LocalizedError {
    case executableNotFound
    case processNotRunning
    case processTerminated(code: Int32)
    case commandFailed(command: String, error: String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "The pi agent executable could not be located."
        case .processNotRunning: return "The pi agent process is not running."
        case .processTerminated(let code): return "The pi agent process exited (code \(code))."
        case .commandFailed(let cmd, let err): return "pi command '\(cmd)' failed: \(err)"
        case .encodingFailed: return "Failed to encode a command for pi."
        }
    }
}

/// Configuration for launching a pi process.
nonisolated struct PiLaunchConfig: Sendable {
    /// Absolute path to the pi executable (bundled binary or `node cli.js`).
    var executableURL: URL
    /// If executableURL is a node script, the interpreter to run it with.
    var interpreterURL: URL?
    /// Working directory for the agent (a project directory).
    var workingDirectory: URL
    /// Session directory (pi persists .jsonl sessions here). nil => pi default.
    var sessionDir: URL?
    /// Disable session persistence entirely.
    var noSession: Bool = false
    /// Optional provider/model overrides.
    var provider: String?
    var model: String?
    var sessionName: String?
    /// Extra skill file/directory paths to load (pi `--skill`, repeatable, additive).
    var skillPaths: [String] = []
    /// Trust project-local files (`.pi`, project `.claude/skills`) for this run
    /// (pi `--approve`). Needed to load per-project skills in RPC mode.
    var approveProjectTrust: Bool = false
    /// Extra environment variables merged over the process environment.
    var extraEnvironment: [String: String] = [:]

    func buildArguments() -> [String] {
        var args: [String] = []
        // When running via interpreter, the script path is the first argument.
        if interpreterURL != nil { args.append(executableURL.path) }
        args.append(contentsOf: ["--mode", "rpc"])
        if noSession { args.append("--no-session") }
        if let sessionDir { args.append(contentsOf: ["--session-dir", sessionDir.path]) }
        if let provider { args.append(contentsOf: ["--provider", provider]) }
        if let model { args.append(contentsOf: ["--model", model]) }
        if let sessionName { args.append(contentsOf: ["--name", sessionName]) }
        if approveProjectTrust { args.append("--approve") }
        for skill in skillPaths { args.append(contentsOf: ["--skill", skill]) }
        return args
    }
}

/// A single running pi RPC session. One bridge == one child process == (in our
/// design) one project. Thread-safe via actor isolation.
actor PiAgentBridge {

    // MARK: State

    private let config: PiLaunchConfig
    private var process: Process?
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    /// Buffer for partial stdout lines (LF framing).
    private var stdoutBuffer = Data()

    /// Pending id-correlated command responses.
    private var pending: [String: CheckedContinuation<PiInbound, Error>] = [:]

    /// Continuation for the CURRENT turn's event stream. Each turn gets a fresh
    /// stream (an AsyncStream supports only one consumer), so the bridge routes
    /// events to whichever turn is active and finishes it on agent_end.
    private var eventContinuation: AsyncStream<PiInbound>.Continuation?
    /// Captured stderr text for diagnostics.
    private(set) var stderrText: String = ""

    private var isRunning = false
    private var autoID = 0

    // MARK: Lifecycle

    init(config: PiLaunchConfig) {
        self.config = config
    }

    /// Begin a turn: returns a fresh single-consumer event stream and registers it
    /// as the active turn. Any previous turn's continuation is finished first so we
    /// never leave two live consumers (which would hang). The bridge finishes this
    /// stream when the turn ends (agent_end handled by the caller, or on stop).
    func beginTurn() -> AsyncStream<PiInbound> {
        eventContinuation?.finish()
        return AsyncStream<PiInbound> { continuation in
            self.eventContinuation = continuation
        }
    }

    /// End the current turn's event stream (call after agent_end so the caller's
    /// `for await` loop terminates cleanly and the next turn starts fresh).
    func endTurn() {
        eventContinuation?.finish()
        eventContinuation = nil
    }

    /// Launch the pi process. Idempotent-safe: throws if already running.
    func start() throws {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: config.executableURL.path) else {
            throw PiBridgeError.executableNotFound
        }

        let proc = Process()
        if let interpreter = config.interpreterURL {
            proc.executableURL = interpreter
            proc.arguments = config.buildArguments()
        } else {
            proc.executableURL = config.executableURL
            proc.arguments = config.buildArguments()
        }
        proc.currentDirectoryURL = config.workingDirectory

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.extraEnvironment { env[k] = v }
        proc.environment = env

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // stdout: LF-framed JSONL reader.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { await self?.ingestStdout(chunk) }
        }
        // stderr: capture for diagnostics only (never triggers events).
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) else { return }
            Task { await self?.appendStderr(s) }
        }

        proc.terminationHandler = { [weak self] p in
            Task { await self?.handleTermination(code: p.terminationStatus) }
        }

        try proc.run()
        self.process = proc
        self.isRunning = true
    }

    /// Stop the process. Closes stdin (triggers pi shutdown), then terminates.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        try? stdinPipe.fileHandleForWriting.close()
        process?.terminate()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        eventContinuation?.finish()
        // Fail any outstanding correlated requests.
        for (_, cont) in pending { cont.resume(throwing: PiBridgeError.processNotRunning) }
        pending.removeAll()
    }

    // MARK: Sending

    /// Fire-and-forget: write a command, don't wait for its response.
    func send(_ command: PiCommand) throws {
        try writeLine(command)
    }

    /// Send an extension-UI reply (id must match the request).
    func reply(_ response: PiExtensionUIResponse) throws {
        try writeLine(response)
    }

    /// Send a command and await its id-correlated `response`. Assigns an id if
    /// the command doesn't already have one. Use for request/response commands
    /// (get_state, set_model, …) — NOT for `prompt`, whose real output is the
    /// async event stream (the response only acks acceptance).
    func request(_ make: (String) -> PiCommand) async throws -> PiInbound {
        let id = nextID()
        let command = make(id)
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            do { try writeLine(command) }
            catch { pending[id] = nil; cont.resume(throwing: error) }
        }
    }

    private func nextID() -> String {
        autoID += 1
        return "yoda-\(autoID)"
    }

    private func writeLine<T: Encodable>(_ value: T) throws {
        guard isRunning else { throw PiBridgeError.processNotRunning }
        let encoder = JSONEncoder()
        // pi expects compact JSON; key order doesn't matter.
        guard var data = try? encoder.encode(value) else { throw PiBridgeError.encodingFailed }
        data.append(0x0A) // "\n"
        stdinPipe.fileHandleForWriting.write(data)
    }

    // MARK: Receiving (LF framing)

    private func ingestStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        // Split on 0x0A only.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            var lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            // Advance buffer past the newline.
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            // Strip a trailing \r if present.
            if lineData.last == 0x0D { lineData.removeLast() }
            if lineData.isEmpty { continue }
            dispatch(lineData)
        }
    }

    private func dispatch(_ lineData: Data) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: lineData),
              let inbound = PiInbound(json: json) else {
            // Not valid JSON / no type — ignore (could be a stray log line).
            return
        }
        if case .response(let id?, _, _, _, _) = inbound, let cont = pending[id] {
            pending[id] = nil
            cont.resume(returning: inbound)
            return
        }
        // Everything else (events, un-correlated responses) goes to the stream.
        eventContinuation?.yield(inbound)
    }

    private func appendStderr(_ s: String) {
        stderrText += s
        if stderrText.count > 64_000 { stderrText = String(stderrText.suffix(48_000)) }
    }

    private func handleTermination(code: Int32) {
        guard isRunning else { return }
        isRunning = false
        if code != 0 {
            let tail = String(stderrText.suffix(500))
            DiagnosticLogger.shared.log("pi process exited (code \(code)). stderr tail: \(tail)", level: .error, category: "Pi")
        }
        eventContinuation?.finish()
        for (_, cont) in pending { cont.resume(throwing: PiBridgeError.processTerminated(code: code)) }
        pending.removeAll()
    }
}
