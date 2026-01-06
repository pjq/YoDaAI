import Foundation
import Combine
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var composerText: String = ""
    @Published var isSending: Bool = false
    @Published var lastErrorMessage: String?
    @Published var alwaysAttachAppContext: Bool = true

    private let client: OpenAICompatibleClient
    private let accessibilityService: AccessibilityService
    private let permissionsStore: AppPermissionsStore

    init(
        client: OpenAICompatibleClient = OpenAICompatibleClient(),
        accessibilityService: AccessibilityService,
        permissionsStore: AppPermissionsStore
    ) {
        self.client = client
        self.accessibilityService = accessibilityService
        self.permissionsStore = permissionsStore
    }

    func ensureSettings(in context: ModelContext) throws -> ProviderSettings {
        let descriptor = FetchDescriptor<ProviderSettings>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let created = ProviderSettings()
        context.insert(created)
        try context.save()
        return created
    }

    func ensureThread(in context: ModelContext) throws -> ChatThread {
        let descriptor = FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\ChatThread.createdAt, order: .reverse)])
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let created = ChatThread(title: "New Chat")
        context.insert(created)
        try context.save()
        return created
    }

    func send(in context: ModelContext) async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        lastErrorMessage = nil
        composerText = ""

        do {
            let settings = try ensureSettings(in: context)
            let thread = try ensureThread(in: context)

            let userMessage = ChatMessage(role: .user, content: trimmed, thread: thread)
            context.insert(userMessage)
            try context.save()

            let history = thread.messages.sorted(by: { $0.createdAt < $1.createdAt })
            var requestMessages = history.map { OpenAIChatMessage(role: $0.roleRawValue, content: $0.content) }

            if alwaysAttachAppContext {
                let snapshot = accessibilityService.captureFrontmostContext(promptIfNeeded: true)

                if let snapshot {
                    let rule = try permissionsStore.ensureRule(
                        for: snapshot.bundleIdentifier,
                        displayName: snapshot.appName,
                        in: context
                    )

                    if rule.allowContext {
                        let contextText = formatAppContext(snapshot)
                        if !contextText.isEmpty {
                            requestMessages.append(OpenAIChatMessage(role: "system", content: contextText))
                        }
                    }
                }
            }

            let assistantText = try await client.createChatCompletion(
                baseURL: settings.baseURL,
                apiKey: settings.apiKey,
                model: settings.model,
                messages: requestMessages
            )

            let assistantMessage = ChatMessage(role: .assistant, content: assistantText, thread: thread)
            context.insert(assistantMessage)
            settings.updatedAt = Date()
            try context.save()
        } catch {
            lastErrorMessage = String(describing: error)
        }

        isSending = false
    }

    func insertLastAssistantMessageIntoFocusedApp(in context: ModelContext) {
        guard let latest = try? latestAssistantMessage(in: context) else { return }

        if let snapshot = accessibilityService.captureFrontmostContext(promptIfNeeded: true) {
            if let rule = try? permissionsStore.ensureRule(
                for: snapshot.bundleIdentifier,
                displayName: snapshot.appName,
                in: context
            ), rule.allowInsert {
                _ = accessibilityService.insertTextIntoFocusedElement(latest, promptIfNeeded: true)
            }
            return
        }

        _ = accessibilityService.insertTextIntoFocusedElement(latest, promptIfNeeded: true)
    }

    private func latestAssistantMessage(in context: ModelContext) throws -> String? {
        let descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\ChatMessage.createdAt, order: .reverse)])
        for message in try context.fetch(descriptor) {
            if message.role == .assistant {
                return message.content
            }
        }
        return nil
    }

    private func formatAppContext(_ snapshot: AppContextSnapshot?) -> String {
        guard let snapshot else { return "" }

        var lines: [String] = []
        lines.append("YouDaAI app context (frontmost macOS app):")
        lines.append("- App: \(snapshot.appName) (\(snapshot.bundleIdentifier))")

        if let title = snapshot.windowTitle, !title.isEmpty {
            lines.append("- Window: \(title)")
        }

        if let role = snapshot.focusedRole {
            lines.append("- Focused role: \(role)")
        }

        if snapshot.focusedIsSecure {
            lines.append("- Focused value preview: (redacted: secure field)")
        } else if let preview = snapshot.focusedValuePreview, !preview.isEmpty {
            lines.append("- Focused value preview: \(preview)")
        }

        lines.append("Instruction: Use this context only to answer the user's request, and do not invent UI details.")
        return lines.joined(separator: "\n")
    }
}
