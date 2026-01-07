import Foundation
import Combine
import SwiftData
import AppKit

// MARK: - LLM Settings
/// Settings for LLM API calls, persisted via UserDefaults
final class LLMSettings: ObservableObject {
    static let shared = LLMSettings()
    
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
    
    private init() {
        // Load from UserDefaults with defaults
        self.temperature = UserDefaults.standard.object(forKey: "llm_temperature") as? Double ?? 1.0
        self.maxTokens = UserDefaults.standard.object(forKey: "llm_maxTokens") as? Int ?? 4096
        self.maxMessageCount = UserDefaults.standard.object(forKey: "llm_maxMessageCount") as? Int ?? 20
        self.systemPrompt = UserDefaults.standard.string(forKey: "llm_systemPrompt") ?? "You are a helpful assistant."
        self.useSystemPrompt = UserDefaults.standard.object(forKey: "llm_useSystemPrompt") as? Bool ?? true
    }
    
    func reset() {
        temperature = 1.0
        maxTokens = 4096
        maxMessageCount = 20
        systemPrompt = "You are a helpful assistant."
        useSystemPrompt = true
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var composerText: String = ""
    @Published var isSending: Bool = false
    @Published var lastErrorMessage: String?
    @Published var imageErrorMessage: String?  // Error message for image operations
    @Published var alwaysAttachAppContext: Bool = true
    @Published var streamingMessageID: UUID?  // Track the message being streamed
    @Published var mentionedApps: [RunningApp] = []  // Apps mentioned with @
    @Published var mentionedAppContexts: [String: AppContextSnapshot] = [:] // Cached captured content by bundleIdentifier
    @Published var showMentionPicker: Bool = false  // Show @ mention picker
    @Published var mentionSearchText: String = ""  // Filter text for mention picker
    @Published var pendingImages: [PendingImage] = []  // Images being composed
    var activeThreadID: UUID?

    // MARK: - Pending Image Model

    /// Temporary image data before sending
    struct PendingImage: Identifiable, Equatable {
        let id: UUID
        let data: Data
        let fileName: String
        let mimeType: String
        let thumbnail: NSImage?

        static func == (lhs: PendingImage, rhs: PendingImage) -> Bool {
            lhs.id == rhs.id
        }
    }

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
        mentionedAppContexts.removeValue(forKey: app.bundleIdentifier)
    }
    
    /// Clear all mentions
    func clearMentions() {
        mentionedApps.removeAll()
        mentionedAppContexts.removeAll()
    }
    
    /// Update cached context for a mentioned app
    func updateMentionContext(for bundleIdentifier: String, snapshot: AppContextSnapshot?) {
        if let snapshot = snapshot {
            mentionedAppContexts[bundleIdentifier] = snapshot
        } else {
            mentionedAppContexts.removeValue(forKey: bundleIdentifier)
        }
    }
    
    /// Get cached context for a mentioned app
    func getMentionContext(for bundleIdentifier: String) -> AppContextSnapshot? {
        return mentionedAppContexts[bundleIdentifier]
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

    // MARK: - Image Attachment Methods

    /// Add image from pasteboard (Cmd+V)
    func addImageFromPasteboard() {
        let pasteboard = NSPasteboard.general

        // Check for image types
        let imageTypes = [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff]
        guard let type = pasteboard.availableType(from: imageTypes) else { return }

        guard let data = pasteboard.data(forType: type) else { return }

        // Convert to PNG if needed
        if let nsImage = NSImage(data: data) {
            if let pngData = nsImage.pngData() {
                addPendingImage(data: pngData, fileName: "pasted-image.png", mimeType: "image/png")
            }
        }
    }

    /// Add images from file URLs (file picker or drag-drop)
    func addImagesFromURLs(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let mimeType = getMimeType(for: url)
                addPendingImage(data: data, fileName: fileName, mimeType: mimeType)
            } catch {
                imageErrorMessage = "Failed to load image: \(error.localizedDescription)"
            }
        }
    }

    /// Add a pending image (internal)
    func addPendingImage(data: Data, fileName: String, mimeType: String) {
        // Validate with ImageStorageService
        do {
            guard let nsImage = NSImage(data: data) else {
                imageErrorMessage = "Invalid image format"
                return
            }

            // Check file size (20MB limit)
            let fileSizeBytes = data.count
            guard fileSizeBytes <= 20 * 1024 * 1024 else {
                imageErrorMessage = "Image exceeds 20MB limit"
                return
            }

            // Create thumbnail
            let thumbnail = nsImage.resized(to: NSSize(width: 120, height: 120))

            let pending = PendingImage(
                id: UUID(),
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                thumbnail: thumbnail
            )

            pendingImages.append(pending)
        }
    }

    /// Remove a pending image
    func removePendingImage(_ image: PendingImage) {
        pendingImages.removeAll { $0.id == image.id }
    }

    /// Clear all pending images
    func clearPendingImages() {
        pendingImages.removeAll()
    }

    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        default: return "image/jpeg"
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
        // Allow sending if there's text OR images
        guard !trimmed.isEmpty || !pendingImages.isEmpty else { return }

        isSending = true
        lastErrorMessage = nil

        // Capture state before clearing - including cached contexts!
        let appsToCapture = mentionedApps
        let cachedContexts = mentionedAppContexts
        let imagesToSend = pendingImages

        composerText = ""
        mentionedApps = []
        mentionedAppContexts = [:]
        pendingImages = []

        do {
            let provider = try ensureDefaultProvider(in: context)
            let thread = try ensureThread(in: context)

            // Create user message with attachments
            let userMessage = ChatMessage(role: .user, content: trimmed, thread: thread)
            context.insert(userMessage)

            // Save images to disk and create attachments
            for pendingImage in imagesToSend {
                let result = try ImageStorageService.shared.saveImage(
                    data: pendingImage.data,
                    originalFileName: pendingImage.fileName
                )

                let attachment = ImageAttachment(
                    fileName: result.fileName,
                    filePath: result.filePath,
                    mimeType: result.mimeType,
                    fileSize: result.fileSize,
                    width: result.dimensions?.width,
                    height: result.dimensions?.height,
                    message: userMessage
                )
                context.insert(attachment)
            }

            try context.save()

            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: appsToCapture, cachedContexts: cachedContexts, in: context)

            // Auto-generate thread title from first user message if still "New Chat"
            if thread.title == "New Chat" {
                let titleText = !trimmed.isEmpty ? trimmed : "Image conversation"
                thread.title = generateThreadTitle(from: titleText)
                try context.save()
            }
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        
        isSending = false
    }
    
    /// Delete a specific message
    func deleteMessage(_ message: ChatMessage, in context: ModelContext) {
        context.delete(message)
        try? context.save()
    }
    
    private func sendAssistantResponse(for thread: ChatThread, provider: LLMProvider, mentionedApps: [RunningApp] = [], cachedContexts: [String: AppContextSnapshot] = [:], in context: ModelContext) async throws {
        let settings = LLMSettings.shared
        let history = thread.messages.sorted(by: { $0.createdAt < $1.createdAt })

        // Build message history with image support
        var requestMessages: [OpenAIChatMessage] = []
        
        // Build combined system prompt
        var systemPromptParts: [String] = []
        
        // Add user system prompt if enabled
        if settings.useSystemPrompt && !settings.systemPrompt.isEmpty {
            systemPromptParts.append(settings.systemPrompt)
        }
        
        // Add MCP tools to system prompt if enabled
        let toolRegistry = MCPToolRegistry.shared
        if toolRegistry.isMCPEnabled {
            // Fetch MCP servers from context
            let descriptor = FetchDescriptor<MCPServer>()
            let mcpServers = (try? context.fetch(descriptor)) ?? []
            
            // Get tools system prompt (will use cache if available)
            let toolsPrompt = await toolRegistry.getToolsSystemPrompt(servers: mcpServers)
            if !toolsPrompt.isEmpty {
                systemPromptParts.append(toolsPrompt)
            }
        }
        
        // Combine all system prompt parts
        if !systemPromptParts.isEmpty {
            requestMessages.append(OpenAIChatMessage(role: "system", content: systemPromptParts.joined(separator: "\n\n")))
        }

        // Limit message history based on maxMessageCount setting
        let limitedHistory: [ChatMessage]
        if settings.maxMessageCount > 0 && history.count > settings.maxMessageCount {
            limitedHistory = Array(history.suffix(settings.maxMessageCount))
        } else {
            limitedHistory = history
        }

        for msg in limitedHistory {
            if msg.attachments.isEmpty {
                // Text-only message (backward compatible)
                requestMessages.append(OpenAIChatMessage(role: msg.roleRawValue, content: msg.content))
            } else {
                // Multimodal message with images
                var contentParts: [OpenAIChatMessageContent] = []

                // Add text part if not empty
                if !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contentParts.append(.text(msg.content))
                }

                // Add image parts
                for attachment in msg.attachments {
                    do {
                        let imageData = try ImageStorageService.shared.loadImage(filePath: attachment.filePath)
                        let dataURL = OpenAICompatibleClient.encodeImageToDataURL(
                            data: imageData,
                            mimeType: attachment.mimeType
                        )
                        contentParts.append(.imageUrl(url: dataURL, detail: "auto"))
                    } catch {
                        print("Failed to load attachment \(attachment.fileName): \(error)")
                    }
                }

                requestMessages.append(OpenAIChatMessage(role: msg.roleRawValue, contentParts: contentParts))
            }
        }

        // Add context from @ mentioned apps - use CACHED contexts first
        for app in mentionedApps {
            // First try to use cached context from MentionChipView
            var snapshot: AppContextSnapshot?
            if let cached = cachedContexts[app.bundleIdentifier] {
                print("[ChatViewModel] Using MentionChip cached context for \(app.appName)")
                snapshot = cached
            } else if let globalCached = ContentCacheService.shared.getCachedSnapshot(for: app.bundleIdentifier) {
                // Try global cache from floating panel
                print("[ChatViewModel] Using FloatingPanel cached context for \(app.appName)")
                snapshot = globalCached
            } else {
                // Fall back to capturing (shouldn't happen normally)
                print("[ChatViewModel] No cached context for \(app.appName), capturing now...")
                snapshot = await accessibilityService.captureContextWithActivation(for: app.bundleIdentifier, promptIfNeeded: true)
            }
            
            if let snapshot = snapshot {
                let rule = try permissionsStore.ensureRule(
                    for: snapshot.bundleIdentifier,
                    displayName: snapshot.appName,
                    in: context
                )
                
                if rule.allowContext {
                    let contextText = formatAppContext(snapshot, isMentioned: true)
                    if !contextText.isEmpty {
                        print("[ChatViewModel] Adding context for \(app.appName): \(contextText.prefix(100))...")
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
            messages: requestMessages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )
        
        for try await chunk in stream {
            assistantMessage.content += chunk
        }
        
        try context.save()
        
        // Check for tool calls and execute them (MCP tool loop)
        if toolRegistry.isMCPEnabled {
            let mcpServers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
            try await executeToolCallsIfNeeded(
                assistantMessage: assistantMessage,
                thread: thread,
                provider: provider,
                mcpServers: mcpServers,
                requestMessages: requestMessages,
                settings: settings,
                in: context
            )
        }
    }
    
    // MARK: - MCP Tool Execution
    
    /// Execute tool calls from assistant response and continue conversation
    private func executeToolCallsIfNeeded(
        assistantMessage: ChatMessage,
        thread: ChatThread,
        provider: LLMProvider,
        mcpServers: [MCPServer],
        requestMessages: [OpenAIChatMessage],
        settings: LLMSettings,
        in context: ModelContext,
        depth: Int = 0
    ) async throws {
        // Limit recursion depth to prevent infinite loops
        let maxToolIterations = 5
        guard depth < maxToolIterations else {
            print("[MCP] Max tool iterations reached (\(maxToolIterations))")
            return
        }
        
        let toolRegistry = MCPToolRegistry.shared
        let toolCalls = MCPToolRegistry.parseToolCalls(from: assistantMessage.content)
        
        guard !toolCalls.isEmpty else {
            return // No tool calls to process
        }
        
        print("[MCP] Found \(toolCalls.count) tool call(s) in response")
        
        // Execute each tool call and collect results
        var toolResults: [(name: String, result: String)] = []
        
        for (name, arguments) in toolCalls {
            print("[MCP] Executing tool: \(name)")
            do {
                let result = try await toolRegistry.callTool(name: name, arguments: arguments, servers: mcpServers)
                toolResults.append((name: name, result: result))
                print("[MCP] Tool \(name) returned: \(result.prefix(200))...")
            } catch {
                let errorResult = "Error executing tool '\(name)': \(error.localizedDescription)"
                toolResults.append((name: name, result: errorResult))
                print("[MCP] Tool \(name) failed: \(error)")
            }
        }
        
        // Format tool results as a system message
        let toolResultsContent = formatToolResults(toolResults)
        
        // Build updated message history including the tool results
        var updatedMessages = requestMessages
        
        // Add the assistant's response (with tool calls)
        updatedMessages.append(OpenAIChatMessage(role: "assistant", content: assistantMessage.content))
        
        // Add tool results as a system message
        updatedMessages.append(OpenAIChatMessage(role: "system", content: toolResultsContent))
        
        // Create a new assistant message for the follow-up response
        let followUpMessage = ChatMessage(role: .assistant, content: "", thread: thread)
        context.insert(followUpMessage)
        try context.save()
        
        // Update streaming message ID
        streamingMessageID = followUpMessage.id
        
        // Stream the follow-up response
        let stream = client.createChatCompletionStream(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            model: provider.selectedModel,
            messages: updatedMessages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )
        
        for try await chunk in stream {
            followUpMessage.content += chunk
        }
        
        try context.save()
        
        // Recursively check for more tool calls
        try await executeToolCallsIfNeeded(
            assistantMessage: followUpMessage,
            thread: thread,
            provider: provider,
            mcpServers: mcpServers,
            requestMessages: updatedMessages,
            settings: settings,
            in: context,
            depth: depth + 1
        )
    }
    
    /// Format tool results for injection into conversation
    private func formatToolResults(_ results: [(name: String, result: String)]) -> String {
        var lines: [String] = ["Tool execution results:"]
        
        for (name, result) in results {
            lines.append("")
            lines.append("<tool_result name=\"\(name)\">")
            lines.append(result)
            lines.append("</tool_result>")
        }
        
        lines.append("")
        lines.append("Please continue your response based on the tool results above. If you need to call more tools, use the <tool_call> format. Otherwise, provide your final answer to the user.")
        
        return lines.joined(separator: "\n")
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
