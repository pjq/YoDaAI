//
//  PiConfigStore.swift
//  YoDaAI
//
//  Reads and writes the pi agent's shared configuration under ~/.pi/agent/:
//   - settings.json  (defaults, thinking, compaction) — MERGE-edited: only the
//     keys YoDaAI owns are changed; every unknown key is preserved.
//   - models.json    (custom providers + models) — full CRUD over `providers`.
//   - auth.json      (API keys) — read-only awareness (which providers have keys).
//
//  Safety: this config is SHARED with the user's terminal pi and Claude Code.
//  Every write makes a single `.bak`, serializes to a temp file, validates it
//  round-trips as JSON, then atomically replaces the original. Secret values are
//  never surfaced or logged.
//

import Foundation
import Combine

@MainActor
final class PiConfigStore: ObservableObject {

    static let shared = PiConfigStore()

    /// Supported provider API kinds (pi models.json `api` field).
    enum ProviderAPI: String, CaseIterable, Identifiable, Codable {
        case openaiCompletions = "openai-completions"
        case openaiResponses = "openai-responses"
        case anthropicMessages = "anthropic-messages"
        case googleGenerativeAI = "google-generative-ai"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .openaiCompletions: return "OpenAI Completions"
            case .openaiResponses: return "OpenAI Responses"
            case .anthropicMessages: return "Anthropic Messages"
            case .googleGenerativeAI: return "Google Generative AI"
            }
        }
    }

    // MARK: - Model types (editor-facing)

    struct CustomModel: Identifiable, Equatable {
        let id = UUID()
        var modelId: String            // the pi `id`
        var name: String               // optional display name
        var reasoning: Bool
        var contextWindow: Int?
        var maxTokens: Int?
    }

    struct CustomProvider: Identifiable, Equatable {
        let id = UUID()
        var key: String                // the providers map key, e.g. "sapaicore"
        var name: String               // optional display name
        var baseUrl: String
        var api: ProviderAPI
        var apiKey: String             // config-value syntax allowed ($ENV, !cmd)
        var models: [CustomModel]
    }

    // MARK: - Published state

    @Published var defaultProvider: String = ""
    @Published var defaultModel: String = ""
    @Published var defaultThinkingLevel: PiThinkingLevel = .medium
    @Published var hideThinkingBlock: Bool = false
    @Published var compactionEnabled: Bool = true
    @Published var providers: [CustomProvider] = []
    /// Provider keys present in auth.json (never the values).
    @Published private(set) var authProviderKeys: [String] = []
    @Published private(set) var lastError: String?

    // MARK: - Paths

    private var agentDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent", isDirectory: true)
    }
    private var settingsURL: URL { agentDir.appendingPathComponent("settings.json") }
    private var modelsURL: URL { agentDir.appendingPathComponent("models.json") }
    private var authURL: URL { agentDir.appendingPathComponent("auth.json") }

    /// Raw settings.json contents, kept so writes preserve unknown keys.
    private var rawSettings: [String: JSONValue] = [:]

    private init() { load() }

    // MARK: - Load

    func load() {
        lastError = nil
        loadSettings()
        loadModels()
        loadAuth()
    }

    private func decodeObject(at url: URL) -> [String: JSONValue]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let obj) = value else { return nil }
        return obj
    }

    private func loadSettings() {
        let obj = decodeObject(at: settingsURL) ?? [:]
        rawSettings = obj
        defaultProvider = obj["defaultProvider"]?.stringValue ?? ""
        defaultModel = obj["defaultModel"]?.stringValue ?? ""
        defaultThinkingLevel = (obj["defaultThinkingLevel"]?.stringValue)
            .flatMap { PiThinkingLevel(rawValue: $0) } ?? .medium
        hideThinkingBlock = obj["hideThinkingBlock"]?.boolValue ?? false
        compactionEnabled = obj["compaction"]?["enabled"]?.boolValue ?? true
    }

    private func loadModels() {
        guard let root = decodeObject(at: modelsURL),
              case .object(let provMap)? = root["providers"] else {
            providers = []
            return
        }
        var result: [CustomProvider] = []
        for (key, pv) in provMap {
            guard case .object = pv else { continue }
            let apiRaw = pv["api"]?.stringValue ?? ProviderAPI.openaiCompletions.rawValue
            let models: [CustomModel] = (pv["models"]?.arrayValue ?? []).compactMap { m in
                guard let mid = m["id"]?.stringValue else { return nil }
                return CustomModel(
                    modelId: mid,
                    name: m["name"]?.stringValue ?? "",
                    reasoning: m["reasoning"]?.boolValue ?? false,
                    contextWindow: m["contextWindow"]?.intValue,
                    maxTokens: m["maxTokens"]?.intValue)
            }
            result.append(CustomProvider(
                key: key,
                name: pv["name"]?.stringValue ?? "",
                baseUrl: pv["baseUrl"]?.stringValue ?? "",
                api: ProviderAPI(rawValue: apiRaw) ?? .openaiCompletions,
                apiKey: pv["apiKey"]?.stringValue ?? "",
                models: models))
        }
        providers = result.sorted { $0.key < $1.key }
    }

    private func loadAuth() {
        authProviderKeys = (decodeObject(at: authURL) ?? [:]).keys.sorted()
    }

    // MARK: - Save

    /// Merge-edit settings.json: mutate only the keys YoDaAI owns, preserve the rest.
    func saveSettings() {
        var obj = rawSettings
        obj["defaultProvider"] = .string(defaultProvider)
        obj["defaultModel"] = .string(defaultModel)
        obj["defaultThinkingLevel"] = .string(defaultThinkingLevel.rawValue)
        obj["hideThinkingBlock"] = .bool(hideThinkingBlock)
        // compaction is a nested object; preserve its other keys.
        var compaction: [String: JSONValue]
        if case .object(let existing)? = obj["compaction"] { compaction = existing } else { compaction = [:] }
        compaction["enabled"] = .bool(compactionEnabled)
        obj["compaction"] = .object(compaction)

        rawSettings = obj
        write(.object(obj), to: settingsURL)
    }

    /// Rewrite models.json from the editor state. Preserves any top-level keys
    /// other than `providers` that were present in the file.
    func saveModels() {
        var root = decodeObject(at: modelsURL) ?? [:]
        var provMap: [String: JSONValue] = [:]
        for p in providers {
            guard !p.key.isEmpty else { continue }
            var pv: [String: JSONValue] = [:]
            if !p.name.isEmpty { pv["name"] = .string(p.name) }
            pv["baseUrl"] = .string(p.baseUrl)
            pv["api"] = .string(p.api.rawValue)
            if !p.apiKey.isEmpty { pv["apiKey"] = .string(p.apiKey) }
            pv["models"] = .array(p.models.map { m in
                var mo: [String: JSONValue] = ["id": .string(m.modelId)]
                if !m.name.isEmpty { mo["name"] = .string(m.name) }
                if m.reasoning { mo["reasoning"] = .bool(true) }
                if let cw = m.contextWindow { mo["contextWindow"] = .number(Double(cw)) }
                if let mt = m.maxTokens { mo["maxTokens"] = .number(Double(mt)) }
                return .object(mo)
            })
            provMap[p.key] = .object(pv)
        }
        root["providers"] = .object(provMap)
        write(.object(root), to: modelsURL)
    }

    // MARK: - CRUD helpers

    func addProvider() {
        providers.append(CustomProvider(key: "", name: "", baseUrl: "",
                                        api: .openaiCompletions, apiKey: "", models: []))
    }
    func removeProvider(_ provider: CustomProvider) {
        providers.removeAll { $0.id == provider.id }
    }

    // MARK: - Atomic, validated write

    private func write(_ value: JSONValue, to url: URL) {
        lastError = nil
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            // Validate round-trip before touching the real file.
            _ = try JSONSerialization.jsonObject(with: data)
            // Single rolling backup of the existing file.
            if fm.fileExists(atPath: url.path) {
                let bak = url.appendingPathExtension("bak")
                try? fm.removeItem(at: bak)
                try? fm.copyItem(at: url, to: bak)
            }
            // Atomic write (temp + replace).
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } catch {
            lastError = error.localizedDescription
            DiagnosticLogger.shared.log("PiConfigStore write failed for \(url.lastPathComponent): \(error.localizedDescription)", level: .error, category: "Pi")
        }
    }
}
