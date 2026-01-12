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
    @Published var isSending: Bool = false {
        didSet {
            // Sync with AppState for menu commands
            AppState.shared.isSending = isSending
        }
    }
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

    // MCP Tool execution state tracking
    @Published var toolExecutionState: ToolExecutionState? = nil
    @Published var toolExecutionMessageID: UUID? = nil  // Message ID that has active tool execution

    // Task tracking for cancellation
    private var currentTask: Task<Void, Never>?

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

    /// Stop the current generation/API call
    func stopGenerating() {
        currentTask?.cancel()
        currentTask = nil
        isSending = false
        streamingMessageID = nil  // Clear streaming indicator
    }
    
    /// Start sending with Task tracking for cancellation
    func startSending(in context: ModelContext) {
        currentTask = Task {
            await send(in: context)
        }
    }

    func send(in context: ModelContext) async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capture state before clearing - including cached contexts!
        let appsToCapture = mentionedApps
        let cachedContexts = mentionedAppContexts
        let imagesToSend = pendingImages

        // Allow sending if there's text OR images OR @ mentions
        guard !trimmed.isEmpty || !imagesToSend.isEmpty || !appsToCapture.isEmpty else { return }

        isSending = true
        lastErrorMessage = nil

        composerText = ""
        mentionedApps = []
        mentionedAppContexts = [:]
        pendingImages = []

        defer {
            isSending = false
            currentTask = nil
            streamingMessageID = nil
        }

        do {
            // Check for cancellation early
            try Task.checkCancellation()

            let provider = try ensureDefaultProvider(in: context)
            let thread = try ensureThread(in: context)

            // STEP 1: Create separate user messages for each @ mentioned app
            for app in appsToCapture {
                // Get cached context
                var snapshot: AppContextSnapshot?
                if let cached = cachedContexts[app.bundleIdentifier] {
                    snapshot = cached
                } else if let globalCached = ContentCacheService.shared.getCachedSnapshot(for: app.bundleIdentifier) {
                    snapshot = globalCached
                } else {
                    snapshot = await accessibilityService.captureContextWithActivation(for: app.bundleIdentifier, promptIfNeeded: true)
                }

                if let snapshot = snapshot {
                    // Format context as message content
                    let contextText = formatAppContext(snapshot, isMentioned: true)

                    // Create user message for this @ mention
                    let contextMessage = ChatMessage(role: .user, content: contextText, thread: thread)
                    context.insert(contextMessage)

                    // Attach app context metadata
                    let appContext = AppContextAttachment(
                        bundleIdentifier: snapshot.bundleIdentifier,
                        appName: snapshot.appName,
                        windowTitle: snapshot.windowTitle,
                        focusedContent: snapshot.focusedValuePreview,
                        focusedRole: snapshot.focusedRole,
                        isSecureField: snapshot.focusedIsSecure,
                        message: contextMessage
                    )
                    context.insert(appContext)
                }
            }

            // STEP 2: Create user message with text/images (if user typed anything)
            if !trimmed.isEmpty || !imagesToSend.isEmpty {
                let userMessage = ChatMessage(role: .user, content: trimmed, thread: thread)
                context.insert(userMessage)

                // Save images to disk and create attachments
                // Note: saveImage is synchronous I/O - consider making it async in future
                for pendingImage in imagesToSend {
                    try Task.checkCancellation()

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
            }

            try context.save()

            // STEP 3: Generate AI response (no need to pass mentions - they're now in message history)
            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: [], cachedContexts: [:], in: context)

            // Auto-generate thread title from first user message if still "New Chat"
            if thread.title == "New Chat" {
                let titleText = !trimmed.isEmpty ? trimmed : "Image conversation"
                thread.title = generateThreadTitle(from: titleText)
                try context.save()
            }
        } catch is CancellationError {
            // User cancelled - this is expected, don't show error
            print("[ChatViewModel] Generation cancelled by user")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// Retry: delete the last assistant message and regenerate
    func retryLastResponse(in context: ModelContext) async {
        isSending = true
        lastErrorMessage = nil

        defer {
            isSending = false
            currentTask = nil
            streamingMessageID = nil
        }

        do {
            try Task.checkCancellation()
            
            let provider = try ensureDefaultProvider(in: context)
            let thread = try ensureThread(in: context)
            
            // Find and delete the last assistant message
            let sortedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
            if let lastAssistant = sortedMessages.last(where: { $0.role == .assistant }) {
                context.delete(lastAssistant)
                try context.save()
            }
            
            try await sendAssistantResponse(for: thread, provider: provider, mentionedApps: [], in: context)
        } catch is CancellationError {
            print("[ChatViewModel] Retry cancelled by user")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// Retry from a specific message: delete all messages after it and regenerate
    func retryFrom(message: ChatMessage, in context: ModelContext) async {
        guard let thread = message.thread else { return }

        isSending = true
        lastErrorMessage = nil

        defer {
            isSending = false
            currentTask = nil
            streamingMessageID = nil
        }

        do {
            try Task.checkCancellation()
            
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
        } catch is CancellationError {
            print("[ChatViewModel] Retry from message cancelled by user")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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

        // IMPORTANT: Add @ mention context BEFORE message history
        // This ensures all system messages come before the conversation
        // Add context from @ mentioned apps - use CACHED contexts first
        print("[ChatViewModel] Processing \(mentionedApps.count) mentioned apps, cachedContexts has \(cachedContexts.count) entries")
        for app in mentionedApps {
            // First try to use cached context from MentionChipView
            var snapshot: AppContextSnapshot?
            if let cached = cachedContexts[app.bundleIdentifier] {
                print("[ChatViewModel] Using MentionChip cached context for \(app.appName)")
                print("[ChatViewModel]   - Window: \(cached.windowTitle ?? "nil")")
                print("[ChatViewModel]   - Content preview: \(cached.focusedValuePreview?.prefix(50) ?? "nil")")
                snapshot = cached
            } else if let globalCached = ContentCacheService.shared.getCachedSnapshot(for: app.bundleIdentifier) {
                // Try global cache from floating panel
                print("[ChatViewModel] Using FloatingPanel cached context for \(app.appName)")
                print("[ChatViewModel]   - Content preview: \(globalCached.focusedValuePreview?.prefix(50) ?? "nil")")
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

                print("[ChatViewModel] Permission rule for \(app.appName): allowContext=\(rule.allowContext)")

                if rule.allowContext {
                    let contextText = formatAppContext(snapshot, isMentioned: true)
                    print("[ChatViewModel] Formatted context length: \(contextText.count) chars")
                    if !contextText.isEmpty {
                        print("[ChatViewModel] Adding context for \(app.appName):")
                        print(contextText)
                        requestMessages.append(OpenAIChatMessage(role: "user", content: contextText))
                    } else {
                        print("[ChatViewModel] ⚠️ Context text is empty for \(app.appName)!")
                    }
                } else {
                    print("[ChatViewModel] ⚠️ Context NOT allowed by permission rule for \(app.appName)")
                }
            } else {
                print("[ChatViewModel] ⚠️ No snapshot available for \(app.appName)")
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
                            requestMessages.append(OpenAIChatMessage(role: "user", content: contextText))
                        }
                    }
                }
            }
        }

        // NOW add message history AFTER all system messages
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

        // DEBUG: Log final message order to verify system messages come first
        print("[ChatViewModel] === FINAL MESSAGE ORDER ===")
        for (index, msg) in requestMessages.enumerated() {
            print("[ChatViewModel] Message \(index): role=\(msg.role)")
        }
        print("[ChatViewModel] ============================")

        // Create empty assistant message for streaming
        let assistantMessage = ChatMessage(role: .assistant, content: "", thread: thread)
        context.insert(assistantMessage)
        try context.save()

        // Track the streaming message
        streamingMessageID = assistantMessage.id
        
        defer {
            streamingMessageID = nil
        }
        
        // Check for cancellation before streaming
        try Task.checkCancellation()
        
        // Stream the response
        let stream = client.createChatCompletionStream(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            model: provider.selectedModel,
            messages: requestMessages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )
        
        // Track if we've detected tool calls during streaming
        var detectedToolCallDuringStream = false
        var fullResponseWithToolCalls = ""
        var chunkCount = 0  // Track chunk count for batched saves

        for try await chunk in stream {
            // Check for cancellation BEFORE updating UI
            try Task.checkCancellation()

            // Check if this chunk or accumulated content contains tool call start
            if toolRegistry.isMCPEnabled && !detectedToolCallDuringStream {
                // Check if we're starting to see tool call tags
                let combined = assistantMessage.content + chunk
                if combined.contains("<tool_call>") {
                    detectedToolCallDuringStream = true
                    // Extract content before tool call for UI display
                    if let toolCallRange = combined.range(of: "<tool_call>") {
                        let contentBeforeToolCall = String(combined[..<toolCallRange.lowerBound])
                        assistantMessage.content = contentBeforeToolCall
                        // Save before stopping UI updates
                        try context.save()
                        // Save the full combined string (includes start of tool call)
                        fullResponseWithToolCalls = combined
                        // Don't break yet - continue collecting the rest of the tool call
                        continue
                    }
                }
            }

            // If we've detected tool calls, accumulate in fullResponse instead of showing in UI
            if detectedToolCallDuringStream {
                fullResponseWithToolCalls += chunk
            } else {
                // Normal streaming to UI
                // PERFORMANCE FIX: Don't save on every chunk - just update in-memory
                // SwiftData's @Observable will automatically trigger UI updates
                assistantMessage.content += chunk
                chunkCount += 1

                // NO intermediate saves during streaming - they block the UI!
                // We'll save once at the end after all chunks are received
            }
        }

        // Final save after streaming completes
        // PERFORMANCE FIX: Only save once after all streaming is done
        try context.save()

        // If we detected tool calls during streaming, execute them
        if detectedToolCallDuringStream {

            // Check for cancellation before tool calls
            try Task.checkCancellation()

            // Show tool execution indicator
            assistantMessage.content += "\n\n🔧 Executing tools..."

            print("[MCP] Full response with tool calls (first 500): \(fullResponseWithToolCalls.prefix(500))")

            let mcpServers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
            try await executeToolCallsIfNeeded(
                assistantMessage: assistantMessage,
                thread: thread,
                provider: provider,
                mcpServers: mcpServers,
                requestMessages: requestMessages,
                settings: settings,
                in: context,
                fullResponseWithToolCalls: fullResponseWithToolCalls
            )
        } else {
            // No tool calls detected, just save the complete message
            try context.save()
        }

        // Clear streaming indicator after everything is done
        streamingMessageID = nil
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
        depth: Int = 0,
        fullResponseWithToolCalls: String? = nil
    ) async throws {
        // Limit recursion depth to prevent infinite loops
        let maxToolIterations = 5
        guard depth < maxToolIterations else {
            print("[MCP] Max tool iterations reached (\(maxToolIterations))")
            return
        }

        let toolRegistry = MCPToolRegistry.shared

        // Use fullResponseWithToolCalls if provided (when we detected tool calls during streaming)
        // Otherwise use assistantMessage.content
        let contentToCheck = fullResponseWithToolCalls ?? assistantMessage.content

        // Debug: Log the assistant message content to see if it contains tool calls
        print("[MCP] Checking for tool calls in response...")
        print("[MCP] Response content (first 500 chars): \(contentToCheck.prefix(500))")
        print("[MCP] Contains <tool_call>: \(contentToCheck.contains("<tool_call>"))")

        let toolCalls = MCPToolRegistry.parseToolCalls(from: contentToCheck)
        
        print("[MCP] Parsed tool calls count: \(toolCalls.count)")
        
        guard !toolCalls.isEmpty else {
            print("[MCP] No tool calls found, returning")
            return // No tool calls to process
        }
        
        print("[MCP] Found \(toolCalls.count) tool call(s) in response")

        // Store original content (with tool call XML) for sending back to LLM
        let originalContent = contentToCheck

        // Extract the base content (text before any tool execution indicators)
        // Remove any existing tool execution messages
        var baseContent = assistantMessage.content
        if let range = baseContent.range(of: "\n\n🔧 Executing tools...") {
            baseContent = String(baseContent[..<range.lowerBound])
        } else if let range = baseContent.range(of: "\n🔧 Executing") {
            baseContent = String(baseContent[..<range.lowerBound])
        }

        // Execute each tool call and collect results, showing progress to user
        var toolResults: [(name: String, arguments: String, result: String, success: Bool)] = []

        // Set initial state
        toolExecutionMessageID = assistantMessage.id
        toolExecutionState = .preparing(toolCount: toolCalls.count)

        for (index, (name, arguments)) in toolCalls.enumerated() {
            // Convert arguments to string for storage and display
            let argumentsString: String
            if let args = arguments,
               let jsonData = try? JSONSerialization.data(withJSONObject: args),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                argumentsString = jsonString
            } else {
                argumentsString = "{}"
            }

            // Extract query from arguments for display
            let query = extractQueryFromArguments(argumentsString)

            // Update state to executing
            toolExecutionState = .executing(
                current: index + 1,
                total: toolCalls.count,
                toolName: name,
                query: query
            )

            // Keep the base content clean (no need to save on every iteration)
            assistantMessage.content = baseContent

            // Check for cancellation before each tool call
            try Task.checkCancellation()

            print("[MCP] Executing tool: \(name)")
            do {
                let result = try await toolRegistry.callTool(name: name, arguments: arguments, servers: mcpServers)
                toolResults.append((name: name, arguments: argumentsString, result: result, success: true))
                print("[MCP] Tool \(name) returned: \(result.prefix(200))...")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let errorResult = "Error executing tool '\(name)': \(error.localizedDescription)"
                toolResults.append((name: name, arguments: argumentsString, result: errorResult, success: false))
                print("[MCP] Tool \(name) failed: \(error)")
            }
        }

        // Update state to processing
        toolExecutionState = .processing

        // Save once after all tools are executed
        try context.save()

        // Check for cancellation before follow-up
        try Task.checkCancellation()

        // Format tool results and send back to LLM for response based on actual results
        let toolResultsContent = formatToolResults(toolResults)
        print("[MCP] Tool results formatted (length: \(toolResultsContent.count)), making follow-up API call")
        print("[MCP] Tool results content: \(toolResultsContent.prefix(500))")

        // Build updated message history including the tool results
        var updatedMessages = requestMessages
        updatedMessages.append(OpenAIChatMessage(role: "assistant", content: originalContent))
        // Tool results should be sent as a USER message, not system
        updatedMessages.append(OpenAIChatMessage(role: "user", content: toolResultsContent))

        print("[MCP] Updated message count: \(updatedMessages.count)")
        print("[MCP] Last message role: \(updatedMessages.last?.role ?? "unknown")")
        print("[MCP] Message sequence: \(updatedMessages.suffix(3).map { $0.role })")

        // Check for cancellation before streaming follow-up
        try Task.checkCancellation()

        // Stream the follow-up response into the SAME message
        // This response will be based on the ACTUAL tool results
        print("[MCP] Creating stream with baseURL: \(provider.baseURL), model: \(provider.selectedModel)")
        let stream = client.createChatCompletionStream(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            model: provider.selectedModel,
            messages: updatedMessages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )

        // Reset message content to base + prepare for streaming the result-based response
        assistantMessage.content = baseContent + "\n\n"

        print("[MCP] Starting to stream follow-up response based on tool results...")
        streamingMessageID = assistantMessage.id

        var chunkCount = 0
        var totalContent = ""
        var streamError: Error? = nil

        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                // PERFORMANCE FIX: Just update content, no intermediate saves
                assistantMessage.content += chunk
                totalContent += chunk
                chunkCount += 1

                // NO intermediate saves - they block the UI!
            }
        } catch {
            streamError = error
            print("[MCP] ERROR during streaming: \(error)")
            print("[MCP] Error details: \(error.localizedDescription)")
        }

        print("[MCP] Follow-up streaming complete. Received \(chunkCount) chunks, total length: \(totalContent.count)")
        if chunkCount == 0 {
            print("[MCP] ERROR: No chunks received from follow-up stream!")
            print("[MCP] Provider: \(provider.selectedModel), Messages: \(updatedMessages.count)")
            if let error = streamError {
                print("[MCP] Stream error: \(error)")
                // Show error to user
                assistantMessage.content = baseContent + "\n\n⚠️ Error: Failed to get response after tool execution. \(error.localizedDescription)"
            } else {
                print("[MCP] No error thrown - stream just returned empty")
                // Show message to user
                assistantMessage.content = baseContent + "\n\n⚠️ No response received from API after tool execution."
            }
        } else {
            print("[MCP] First 200 chars of response: \(totalContent.prefix(200))")
        }

        streamingMessageID = nil

        // Final save to persist all changes
        try context.save()

        // Update tool execution state to completed with results
        let executionResults = toolResults.map { (name, arguments, result, success) in
            let query = extractQueryFromArguments(arguments)
            let resultPreview = String(result.prefix(500))
            return ToolExecutionResult(
                toolName: name,
                query: query,
                resultPreview: resultPreview,
                fullResult: result,
                success: success
            )
        }
        toolExecutionState = .completed(results: executionResults)

        // Clear state after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if toolExecutionMessageID == assistantMessage.id {
                toolExecutionState = nil
                toolExecutionMessageID = nil
            }
        }

        // Note: Recursive tool calling disabled to prevent infinite loops
        // The LLM should include all necessary tool calls in a single response
        // Multi-turn tool use should be handled by the user asking follow-up questions
        // If you need multi-turn tool support, enable this with stricter limits

        /* DISABLED - causes infinite loop when LLM keeps requesting more searches
        try await executeToolCallsIfNeeded(
            assistantMessage: assistantMessage,
            thread: thread,
            provider: provider,
            mcpServers: mcpServers,
            requestMessages: updatedMessages,
            settings: settings,
            in: context,
            depth: depth + 1
        )
        */
    }
    
    /// Format progress text while tools are executing
    private func formatToolExecutionProgress(
        originalContent: String,
        currentTool: String,
        toolIndex: Int,
        totalTools: Int,
        completedResults: [(name: String, result: String)]
    ) -> String {
        var lines: [String] = []
        
        // Strip tool_call XML from original content for display
        let cleanContent = stripToolCallXML(from: originalContent)
        if !cleanContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(cleanContent.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        
        lines.append("---")
        lines.append("**🔧 Executing Tools (\(toolIndex)/\(totalTools))**")
        lines.append("")
        
        // Show completed results
        for (name, result) in completedResults {
            lines.append("✅ **\(name)**")
            let truncatedResult = result.count > 200 ? String(result.prefix(200)) + "..." : result
            lines.append("```")
            lines.append(truncatedResult)
            lines.append("```")
            lines.append("")
        }
        
        // Show current tool being executed
        lines.append("⏳ **\(currentTool)** - executing...")
        
        return lines.joined(separator: "\n")
    }
    
    /// Format final text after all tools complete
    private func formatToolExecutionComplete(
        originalContent: String,
        results: [(name: String, result: String)]
    ) -> String {
        var lines: [String] = []
        
        // Strip tool_call XML from original content for display
        let cleanContent = stripToolCallXML(from: originalContent)
        if !cleanContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(cleanContent.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        
        lines.append("---")
        lines.append("**🔧 Tool Results:**")
        lines.append("")
        
        for (name, result) in results {
            lines.append("✅ **\(name)**")
            // Show more of the result in final view
            let truncatedResult = result.count > 500 ? String(result.prefix(500)) + "...(truncated)" : result
            lines.append("```")
            lines.append(truncatedResult)
            lines.append("```")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Strip tool call XML from content (supports both JSON and XML formats)
    private func stripToolCallXML(from content: String) -> String {
        var result = content
        
        // Strip JSON format: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
        let jsonPattern = #"<tool_call>\s*\{[\s\S]*?\}\s*</tool_call>"#
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // Strip XML format: <execute><invoke name="...">...</invoke></execute>
        let xmlPattern = #"<(?:execute|tool)>\s*<invoke\s+name="[^"]+">[\s\S]*?</invoke>\s*</(?:execute|tool)>"#
        if let regex = try? NSRegularExpression(pattern: xmlPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result
    }
    
    /// Format tool results for injection into conversation
    private func formatToolResults(_ results: [(name: String, arguments: String, result: String, success: Bool)]) -> String {
        var lines: [String] = ["Tool execution results:"]

        for (name, _, result, _) in results {
            lines.append("")
            lines.append("<tool_result name=\"\(name)\">")
            lines.append(result)
            lines.append("</tool_result>")
        }

        lines.append("")
        lines.append("Please continue your response based on the tool results above. If you need to call more tools, use the <tool_call> format. Otherwise, provide your final answer to the user.")

        return lines.joined(separator: "\n")
    }

    /// Extract query or relevant info from tool arguments for UI display
    private func extractQueryFromArguments(_ arguments: String) -> String? {
        // Try to parse JSON and extract common query fields
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Common query field names
        let queryFields = ["query", "q", "search", "text", "prompt", "url"]
        for field in queryFields {
            if let value = json[field] as? String, !value.isEmpty {
                return value
            }
        }

        return nil
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

        var parts: [String] = []

        // App name
        parts.append("📱 \(snapshot.appName)")

        // Window title
        if let title = snapshot.windowTitle, !title.isEmpty {
            parts.append("Window: \(title)")
        }

        // Content
        if snapshot.focusedIsSecure {
            parts.append("🔒 Secure field (content hidden)")
        } else if let content = snapshot.focusedValuePreview, !content.isEmpty {
            // Check if it's just placeholder text (common in Electron apps)
            let lowerContent = content.lowercased()
            if lowerContent.contains("type a message") ||
               lowerContent.contains("type here") ||
               lowerContent.contains("start typing") {
                parts.append("⚠️ Limited capture: \(content)")
                parts.append("💡 Tip: Select text first, or check permissions")
            } else {
                parts.append("Content: \(content)")
            }
        } else {
            // No content - provide helpful hint based on app
            let bundleId = snapshot.bundleIdentifier.lowercased()
            if bundleId.contains("chrome") || bundleId.contains("safari") || bundleId.contains("brave") {
                parts.append("ℹ️ Grant Automation permission for full page content")
            } else if bundleId.contains("teams") || bundleId.contains("slack") || bundleId.contains("discord") {
                parts.append("ℹ️ Electron app - select text first for better capture")
            } else {
                parts.append("ℹ️ No content captured (check Accessibility permission)")
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Slash Command Handling

    /// Published property to show/hide slash command autocomplete
    @Published var showSlashCommandPicker: Bool = false

    /// Filtered slash commands based on current input
    @Published var filteredSlashCommands: [SlashCommand] = []

    /// Check if text is a slash command and update autocomplete
    func updateSlashCommandAutocomplete() {
        if SlashCommandParser.shouldShowAutocomplete(for: composerText) {
            filteredSlashCommands = SlashCommandParser.filterCommands(for: composerText)
            showSlashCommandPicker = !filteredSlashCommands.isEmpty
        } else {
            showSlashCommandPicker = false
            filteredSlashCommands = []
        }
    }

    /// Execute a slash command
    /// Returns true if command was handled, false if text should be sent as message
    func executeSlashCommand(in context: ModelContext) -> Bool {
        guard let command = SlashCommandParser.parse(composerText) else {
            return false
        }

        print("[SlashCommand] Executing command: \(command.displayName)")

        // Execute command asynchronously to avoid "Publishing changes during view update" errors
        // IMPORTANT: All state changes must happen inside the async block
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Clear composer AFTER view update completes
            self.composerText = ""
            self.showSlashCommandPicker = false

            switch command {
            case .help:
                self.handleHelpCommand()
            case .clear:
                self.handleClearCommand(in: context)
            case .new:
                self.handleNewCommand()
            case .models:
                self.handleModelsCommand()
            case .settings:
                self.handleSettingsCommand()
            case .copy:
                self.handleCopyCommand(in: context)
            }
        }

        return true
    }

    // MARK: - Command Handlers (require context from UI)

    /// Closures for command handlers (set by UI layer)
    var onHelpCommand: (() -> Void)?
    var onClearCommand: (() -> Void)?
    var onNewCommand: (() -> Void)?
    var onModelsCommand: (() -> Void)?
    var onSettingsCommand: (() -> Void)?
    var onCopyCommand: (() -> Void)?

    private func handleHelpCommand() {
        print("[SlashCommand] handleHelpCommand called, handler set: \(onHelpCommand != nil)")
        if let handler = onHelpCommand {
            handler()
        } else {
            // Fallback: show help in console
            print("[SlashCommand] Available commands:")
            for command in SlashCommand.allCases {
                print("  \(command.displayName) - \(command.description)")
            }
        }
    }

    private func handleClearCommand(in context: ModelContext) {
        print("[SlashCommand] handleClearCommand called, handler set: \(onClearCommand != nil)")
        onClearCommand?()
    }

    private func handleNewCommand() {
        print("[SlashCommand] handleNewCommand called, handler set: \(onNewCommand != nil)")
        onNewCommand?()
    }

    private func handleModelsCommand() {
        print("[SlashCommand] handleModelsCommand called, handler set: \(onModelsCommand != nil)")
        onModelsCommand?()
    }

    private func handleSettingsCommand() {
        print("[SlashCommand] handleSettingsCommand called, handler set: \(onSettingsCommand != nil)")
        onSettingsCommand?()
    }

    private func handleCopyCommand(in context: ModelContext) {
        print("[SlashCommand] handleCopyCommand called, handler set: \(onCopyCommand != nil)")
        onCopyCommand?()
    }
}
