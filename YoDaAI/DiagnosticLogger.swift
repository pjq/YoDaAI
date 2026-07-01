import Foundation
import os.log

// MARK: - Log Level

enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var prefix: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "💀"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Diagnostic Logger

/// Lightweight file-based diagnostic logger for post-mortem crash/ANR analysis.
/// Writes to a ring-buffer log file in Application Support.
/// Enable via Settings > General > "Debug Logging".
final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    private let queue = DispatchQueue(label: "me.pjq.YoDaAI.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let maxFileSize: UInt64 = 512 * 1024  // 512KB — auto-rotates
    private let logFileURL: URL
    private let osLog = OSLog(subsystem: "me.pjq.YoDaAI", category: "diagnostics")

    /// Master switch — controlled by LLMSettings.enableDiagnosticLogging
    var isEnabled: Bool = false {
        didSet {
            if isEnabled && fileHandle == nil {
                openLogFile()
            } else if !isEnabled {
                closeLogFile()
            }
        }
    }

    /// Minimum severity to write (default: .info when enabled)
    var minimumLevel: LogLevel = .info

    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private init() {
        // Store logs in Application Support alongside the SwiftData store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("me.pjq.YoDaAI")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        logFileURL = appDir.appendingPathComponent("diagnostics.log")
    }

    // MARK: - Public API

    /// Log a message with category and severity
    func log(_ message: String, level: LogLevel = .info, category: String = "General") {
        guard isEnabled, level >= minimumLevel else { return }

        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(level.prefix) [\(category)] \(message)\n"

        // Also route to os_log for Console.app when attached
        os_log("%{public}@", log: osLog, type: level.osLogType, "[\(category)] \(message)")

        queue.async { [self] in
            write(line, flush: level >= .error)
        }
    }

    /// Measure a synchronous operation and log its elapsed time
    @discardableResult
    func measure<T>(_ label: String, category: String = "Perf", warnThresholdMs: Double = 2000, block: () throws -> T) rethrows -> T {
        guard isEnabled else { return try block() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let level: LogLevel = elapsed > warnThresholdMs ? .warning : .info
        let suffix = elapsed > warnThresholdMs ? " — SLOW" : ""
        log("\(label) took \(Int(elapsed))ms\(suffix)", level: level, category: category)
        return result
    }

    /// Measure an async operation and log its elapsed time
    @discardableResult
    func measureAsync<T>(_ label: String, category: String = "Perf", warnThresholdMs: Double = 2000, block: () async throws -> T) async rethrows -> T {
        guard isEnabled else { return try await block() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let level: LogLevel = elapsed > warnThresholdMs ? .warning : .info
        let suffix = elapsed > warnThresholdMs ? " — SLOW" : ""
        log("\(label) took \(Int(elapsed))ms\(suffix)", level: level, category: category)
        return result
    }

    /// Get the log file URL (for "Open Log File" button in Settings)
    var logFileLocation: URL { logFileURL }

    /// Get recent log content (last N lines) for display
    func recentLogs(lines: Int = 100) -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return "(No logs yet)"
        }
        let allLines = content.components(separatedBy: "\n")
        let recent = allLines.suffix(lines)
        return recent.joined(separator: "\n")
    }

    // MARK: - Private

    private func openLogFile() {
        queue.async { [self] in
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile()

            // Write session header
            let header = "\n--- Session started at \(dateFormatter.string(from: Date())) ---\n"
            write(header, flush: true)
        }
    }

    private func closeLogFile() {
        queue.async { [self] in
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }

    private func write(_ text: String, flush: Bool) {
        guard let data = text.data(using: .utf8) else { return }

        // Auto-rotate if file is too large
        if let handle = fileHandle {
            let currentSize = handle.offsetInFile
            if currentSize > maxFileSize {
                rotateLog()
            }
        }

        fileHandle?.write(data)
        if flush {
            fileHandle?.synchronizeFile()
        }
    }

    private func rotateLog() {
        // Keep the last half of the file
        fileHandle?.closeFile()

        if let data = try? Data(contentsOf: logFileURL) {
            let keepFrom = data.count / 2
            let kept = data.suffix(from: keepFrom)

            // Find the first newline in the kept portion to start at a clean line
            if let newlineIndex = kept.firstIndex(of: UInt8(ascii: "\n")) {
                let cleanData = kept.suffix(from: kept.index(after: newlineIndex))
                let header = "--- Log rotated (kept last \(cleanData.count) bytes) ---\n".data(using: .utf8) ?? Data()
                try? (header + cleanData).write(to: logFileURL)
            } else {
                try? kept.write(to: logFileURL)
            }
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }
}
