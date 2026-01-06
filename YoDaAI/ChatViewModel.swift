import Foundation
import Combine
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var composerText: String = ""
    @Published var isSending: Bool = false
    @Published var lastErrorMessage: String?
    @Published var alwaysAttachAppContext: Bool = true
    @Published var streamingMessageID: UUID?  // Track the message being streamed
    @Published var mentionedApps: [RunningApp] = []  // Apps mentioned with @
    @Published var showMentionPicker: Bool = false  // Show @ mention picker
    @Published var mentionSearchText: String = ""  // Filter text for mention picker
    var activeThreadID: UUID?

    private let client: OpenAICompatibleClient
    let accessibilityService: AccessibilityService
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
    
    // MARK: - @ Mention Support
    
    /// Get list of running apps for @ mention picker
    func getRunningApps() -> [RunningApp] {
        accessibilityService.listRunningApps()
    }
    
    /// Get filtered running apps based on search text
    func getFilteredRunningApps() -> [RunningApp] {
        let apps = getRunningApps()
        guard !mentionSearchText.isEmpty else { return apps }
        return apps.filter { $0.appName.localizedCaseInsensitiveContains(mentionSearchText) }
    }
    
    /// Add an app to the mentioned apps list
    func addMention(_ app: RunningApp) {
        guard !mentionedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        mentionedApps.append(app)
        mentionSearchText = ""
        showMentionPicker = false
    }
    
    /// Remove an app from the mentioned apps list
    func removeMention(_ app: RunningApp) {
        mentionedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
    }
    
    /// Clear all mentions
    func clearMentions() {
        mentionedApps.removeAll()
    }
    
    /// Check if user typed @ and should show picker
    func checkForMentionTrigger() {
        // Check if user typed @ at the end or after a space
        let text = composerText
        if text.hasSuffix("@") || text.hasSuffix(" @") {
            showMentionPicker = true
            mentionSearchText = ""
        }
    }


    func ensureDefaultProvider(in context: ModelContext) throws -> LLMProvider {
        let descriptor = FetchDescriptor<LLMProvider>(sortBy: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
        let providers = try context.fetch(descriptor)
        if let existingDefault = providers.first(where: { $0.isDefault }) {
            return existingDefault
        }

        if let first = providers.first {
            first.isDefault = true
            first.updatedAt = Date()
            try context.save()
            return first
        }

        let created = LLMProvider()
        context.insert(created)
        try context.save()
        return created
    }

    func ensureThread(in context: ModelContext) throws -> ChatThread {
        // Use the active thread if set
        if let activeID = activeThreadID {
            let descriptor = FetchDescriptor<ChatThread>(predicate: #Predicate { $0.id == activeID })
            if let thread = try context.fetch(descriptor).first {
                return thread
            }
        }

        // Fallback to most recent thread
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
        
        // Capture mentioned apps before clearing
        let appsToCapture = mentionedApps
        
        composerText = ""
        mentionedApps = []

        do {
            let provider = try ensureDefaultProvider(in: context)
            let thread = try ensureThread(in: context)

            let userMessage = ChatMessage(role: .user, content: trimmed, thread: thread)
            context.insert(userMessage)
            try context.save()

            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: appsToCapture, in: context)
            
            // Auto-generate thread title from first user message if still "New Chat"
            if thread.title == "New Chat" {
                thread.title = generateThreadTitle(from: trimmed)
                try context.save()
            }
        } catch {
            lastErrorMessage = String(describing: error)
        }

        isSending = false
    }
    
    /// Retry: delete the last assistant message and regenerate
    func retryLastResponse(in context: ModelContext) async {
        isSending = true
        lastErrorMessage = nil
        
        do {
            let provider = try ensureDefaultProvider(in: context)
            let thread = try ensureThread(in: context)
            
            // Find and delete the last assistant message
            let sortedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
            if let lastAssistant = sortedMessages.last(where: { $0.role == .assistant }) {
                context.delete(lastAssistant)
                try context.save()
            }
            
            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: [], in: context)
        } catch {
            lastErrorMessage = String(describing: error)
        }
        
        isSending = false
    }
    
    /// Retry from a specific message: delete all messages after it and regenerate
    func retryFrom(message: ChatMessage, in context: ModelContext) async {
        guard let thread = message.thread else { return }
        
        isSending = true
        lastErrorMessage = nil
        
        do {
            let provider = try ensureDefaultProvider(in: context)
            
            // Delete all messages after this one
            let sortedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
            var shouldDelete = false
            for msg in sortedMessages {
                if shouldDelete {
                    context.delete(msg)
                } else if msg.id == message.id {
                    shouldDelete = true
                    // If it's a user message, keep it; if assistant, delete it too
                    if message.role == .assistant {
                        context.delete(msg)
                    }
                }
            }
            try context.save()
            
            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: [], in: context)
        } catch {
            lastErrorMessage = String(describing: error)
        }
        
        isSending = false
    }
    
    /// Delete a specific message
    func deleteMessage(_ message: ChatMessage, in context: ModelContext) {
        context.delete(message)
        try? context.save()
    }
    
    private func sendAssistantResponse(for thread: ChatThread, provider: LLMProvider, mentionedApps: [RunningApp] = [], in context: ModelContext) async throws {
        let history = thread.messages.sorted(by: { $0.createdAt < $1.createdAt })
        var requestMessages = history.map { OpenAIChatMessage(role: $0.roleRawValue, content: $0.content) }

        // Add context from @ mentioned apps
        for app in mentionedApps {
            if let snapshot = accessibilityService.captureContext(for: app.bundleIdentifier, promptIfNeeded: true) {
                let rule = try permissionsStore.ensureRule(
                    for: snapshot.bundleIdentifier,
                    displayName: snapshot.appName,
                    in: context
                )
                
                if rule.allowContext {
                    let contextText = formatAppContext(snapshot, isMentioned: true)
                    if !contextText.isEmpty {
                        requestMessages.append(OpenAIChatMessage(role: "system", content: contextText))
                    }
                }
            }
        }

        // Also add frontmost app context if enabled (and not already mentioned)
        if alwaysAttachAppContext {
            let snapshot = accessibilityService.captureFrontmostContext(promptIfNeeded: true)

            if let snapshot {
                // Skip if this app was already mentioned
                let alreadyMentioned = mentionedApps.contains { $0.bundleIdentifier == snapshot.bundleIdentifier }
                
                if !alreadyMentioned {
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
        }

        // Create empty assistant message for streaming
        let assistantMessage = ChatMessage(role: .assistant, content: "", thread: thread)
        context.insert(assistantMessage)
        try context.save()
        
        // Track the streaming message
        streamingMessageID = assistantMessage.id
        
        defer {
            streamingMessageID = nil
        }
        
        // Stream the response
        let stream = client.createChatCompletionStream(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            model: provider.selectedModel,
            messages: requestMessages
        )
        
        for try await chunk in stream {
            assistantMessage.content += chunk
        }
        
        try context.save()
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

    private func generateThreadTitle(from message: String) -> String {
        // Take the first line or up to 40 characters
        let firstLine = message.components(separatedBy: .newlines).first ?? message
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count <= 40 {
            return trimmed
        }
        
        // Truncate at word boundary if possible
        let prefix = String(trimmed.prefix(40))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    private func formatAppContext(_ snapshot: AppContextSnapshot?, isMentioned: Bool = false) -> String {
        guard let snapshot else { return "" }

        var lines: [String] = []
        if isMentioned {
            lines.append("YoDaAI @mentioned app context:")
        } else {
            lines.append("YoDaAI app context (frontmost macOS app):")
        }
        lines.append("- App: \(snapshot.appName) (\(snapshot.bundleIdentifier))")

        if let title = snapshot.windowTitle, !title.isEmpty {
            lines.append("- Window: \(title)")
        }

        if let role = snapshot.focusedRole {
            lines.append("- Focused role: \(role)")
        }

        if snapshot.focusedIsSecure {
            lines.append("- Content: (redacted: secure field)")
        } else if let preview = snapshot.focusedValuePreview, !preview.isEmpty {
            lines.append("- Content: \(preview)")
        }

        lines.append("Instruction: Use this context only to answer the user's request, and do not invent UI details.")
        return lines.joined(separator: "\n")
    }
}
