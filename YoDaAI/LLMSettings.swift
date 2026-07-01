import Foundation
import Combine
import AppKit

// MARK: - Appearance Mode
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - LLM Settings
/// Settings for LLM API calls and app preferences, persisted via UserDefaults
final class LLMSettings: ObservableObject {
    static let shared = LLMSettings()

    // MARK: LLM Parameters

    @Published var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "llm_temperature") }
    }

    @Published var maxTokens: Int {
        didSet { UserDefaults.standard.set(maxTokens, forKey: "llm_maxTokens") }
    }

    @Published var maxMessageCount: Int {
        didSet { UserDefaults.standard.set(maxMessageCount, forKey: "llm_maxMessageCount") }
    }

    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "llm_systemPrompt") }
    }

    @Published var useSystemPrompt: Bool {
        didSet { UserDefaults.standard.set(useSystemPrompt, forKey: "llm_useSystemPrompt") }
    }

    // MARK: App Context

    @Published var alwaysAttachAppContext: Bool {
        didSet { UserDefaults.standard.set(alwaysAttachAppContext, forKey: "llm_alwaysAttachAppContext") }
    }

    // MARK: Appearance

    @Published var enableMarkdown: Bool {
        didSet { UserDefaults.standard.set(enableMarkdown, forKey: "llm_enableMarkdown") }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "app_appearanceMode")
            NSApp?.appearance = appearanceMode.nsAppearance
        }
    }

    @Published var showTimestamps: Bool {
        didSet { UserDefaults.standard.set(showTimestamps, forKey: "app_showTimestamps") }
    }

    // MARK: Diagnostics

    @Published var enableDiagnosticLogging: Bool {
        didSet {
            UserDefaults.standard.set(enableDiagnosticLogging, forKey: "app_enableDiagnosticLogging")
            DiagnosticLogger.shared.isEnabled = enableDiagnosticLogging
        }
    }

    // MARK: Init

    private init() {
        let ud = UserDefaults.standard
        self.temperature = ud.object(forKey: "llm_temperature") as? Double ?? 1.0
        self.maxTokens = ud.object(forKey: "llm_maxTokens") as? Int ?? 0
        self.maxMessageCount = ud.object(forKey: "llm_maxMessageCount") as? Int ?? 20
        self.systemPrompt = ud.string(forKey: "llm_systemPrompt") ?? "You are a helpful assistant."
        self.useSystemPrompt = ud.object(forKey: "llm_useSystemPrompt") as? Bool ?? true
        self.alwaysAttachAppContext = ud.object(forKey: "llm_alwaysAttachAppContext") as? Bool ?? true
        self.enableMarkdown = ud.object(forKey: "llm_enableMarkdown") as? Bool ?? true
        self.appearanceMode = AppearanceMode(rawValue: ud.integer(forKey: "app_appearanceMode")) ?? .system
        self.showTimestamps = ud.object(forKey: "app_showTimestamps") as? Bool ?? false
        self.enableDiagnosticLogging = ud.object(forKey: "app_enableDiagnosticLogging") as? Bool ?? false

        // Activate logger if previously enabled
        if self.enableDiagnosticLogging {
            DiagnosticLogger.shared.isEnabled = true
        }
    }

    func reset() {
        temperature = 1.0
        maxTokens = 0
        maxMessageCount = 20
        systemPrompt = "You are a helpful assistant."
        useSystemPrompt = true
        alwaysAttachAppContext = true
        enableMarkdown = true
        showTimestamps = false
    }

    func applyAppearance() {
        NSApp?.appearance = appearanceMode.nsAppearance
    }
}
