//
//  PiExecutable.swift
//  YoDaAI
//
//  Locates the pi agent executable at runtime. Two modes:
//   - Bundled (release): a self-contained `pi` binary embedded in the .app at
//     Contents/Resources/pi/pi (built via `bun build --compile`).
//   - Development: fall back to running the repo's `node dist/cli.js`, so we can
//     iterate without rebuilding the binary on every change.
//

import Foundation

enum PiExecutable {

    /// Resolve how to launch pi. Returns (executableURL, interpreterURL?).
    /// interpreterURL is non-nil only in the dev/node fallback.
    static func resolve() -> (executable: URL, interpreter: URL?)? {
        // 1) Bundled single binary.
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("pi/pi")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return (bundled, nil)
            }
        }

        // 2) Dev fallback: node + the built cli.js in the sibling pi repo.
        //    Path is relative to the YoDaAI workspace; adjust if your layout differs.
        let devCLI = URL(fileURLWithPath:
            "/Users/I329817/SAPDevelop/workspace/pi/packages/coding-agent/dist/cli.js")
        if FileManager.default.fileExists(atPath: devCLI.path),
           let node = findNode() {
            return (devCLI, node)
        }

        // 3) pi on PATH (developer installed it globally).
        if let onPath = which("pi") {
            return (onPath, nil)
        }

        return nil
    }

    /// Find a node interpreter without relying on the sandboxed PATH.
    private static func findNode() -> URL? {
        which("node")
    }

    /// GUI apps launched from Finder/Xcode do NOT inherit the user's shell
    /// environment, so exports in ~/.zshrc (e.g. OPENAI_API_KEY that pi's config
    /// references as "$OPENAI_API_KEY") are missing. Capture the login shell's
    /// environment once and cache it, so the spawned pi sees the same env the
    /// user gets in a terminal.
    static let loginShellEnvironment: [String: String] = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        // -l login, -i interactive so ~/.zshrc (not just ~/.zprofile) is sourced;
        // print a NUL-delimited env so values with newlines survive.
        proc.arguments = ["-lic", "/usr/bin/env -0"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [:] }
            var env: [String: String] = [:]
            for entry in text.split(separator: "\0") {
                if let eq = entry.firstIndex(of: "=") {
                    let key = String(entry[..<eq])
                    let value = String(entry[entry.index(after: eq)...])
                    env[key] = value
                }
            }
            return env
        } catch {
            return [:]
        }
    }()

    /// Minimal `which`: probe common locations and $PATH.
    private static func which(_ name: String) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        }
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }
}
