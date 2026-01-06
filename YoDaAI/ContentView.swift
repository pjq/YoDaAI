import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\ChatThread.createdAt, order: .reverse)])
    private var threads: [ChatThread]

    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var providers: [LLMProvider]

    @StateObject private var viewModel = ChatViewModel(
        accessibilityService: AccessibilityService(),
        permissionsStore: AppPermissionsStore()
    )
    @ObservedObject private var floatingPanelController = FloatingPanelController.shared
    @State private var activeThread: ChatThread?
    @State private var isShowingSettings = false
    @State private var searchText = ""

    private var defaultProvider: LLMProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }

    private var filteredThreads: [ChatThread] {
        if searchText.isEmpty {
            return threads
        }
        return threads.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var todayThreads: [ChatThread] {
        filteredThreads.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var olderThreads: [ChatThread] {
        filteredThreads.filter { !Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            List(selection: $activeThread) {
                if !todayThreads.isEmpty {
                    Section("Today") {
                        ForEach(todayThreads) { thread in
                            ThreadRowView(thread: thread)
                        .tag(thread)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        deleteThread(thread)
                                    }
                                }
                        }
                    }
                }

                if !olderThreads.isEmpty {
                    Section("Previous") {
                        ForEach(olderThreads) { thread in
                            ThreadRowView(thread: thread)
                        .tag(thread)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        deleteThread(thread)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar)
            .navigationTitle("YoDaAI")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewChat) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .help("New Chat (Cmd+N)")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        } detail: {
            // MARK: - Chat Detail
            ChatDetailView(
                thread: activeThread ?? threads.first,
                viewModel: viewModel,
                provider: defaultProvider,
                providers: providers,
                onDeleteThread: {
                    if let thread = activeThread {
                        deleteThread(thread)
                    }
                }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if activeThread == nil {
                activeThread = threads.first
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Floating panel toggle
                    Button {
                        if floatingPanelController.isVisible {
                            floatingPanelController.hide()
                        } else {
                            floatingPanelController.show()
                        }
                    } label: {
                        Image(systemName: floatingPanelController.isVisible ? "pip.fill" : "pip")
                    }
                    .help(floatingPanelController.isVisible ? "Hide capture panel" : "Show capture panel")
                    
                    // Settings button
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .help("Settings")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    private func createNewChat() {
        let thread = ChatThread(title: "New Chat")
        modelContext.insert(thread)
        try? modelContext.save()
        activeThread = thread
    }

    private func deleteThread(_ thread: ChatThread) {
        let wasActive = activeThread?.id == thread.id
        modelContext.delete(thread)
        try? modelContext.save()

        if wasActive {
            activeThread = threads.first(where: { $0.id != thread.id })
        }
    }
}

// MARK: - Thread Row
private struct ThreadRowView: View {
    let thread: ChatThread
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Chat icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(thread.title)
                .font(.system(size: 14 * scaleManager.scale))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Detail View
private struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext

    var thread: ChatThread?
    @ObservedObject var viewModel: ChatViewModel
    var provider: LLMProvider?
    var providers: [LLMProvider]
    var onDeleteThread: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                // Header
                ChatHeaderView(
                    thread: thread,
                    modelName: provider?.selectedModel ?? "No model",
                    onDelete: onDeleteThread
                )

                Divider()

                // Messages
                MessageListView(thread: thread, viewModel: viewModel)

                // Composer
                ComposerView(viewModel: viewModel, thread: thread, providers: providers)
            } else {
                EmptyStateView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Error", isPresented: Binding(get: {
            viewModel.lastErrorMessage != nil
        }, set: { newValue in
            if !newValue { viewModel.lastErrorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.lastErrorMessage = nil
            }
        } message: {
            Text(viewModel.lastErrorMessage ?? "Unknown error")
        }
        .alert("Image Error", isPresented: Binding(get: {
            viewModel.imageErrorMessage != nil
        }, set: { newValue in
            if !newValue { viewModel.imageErrorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.imageErrorMessage = nil
            }
        } message: {
            Text(viewModel.imageErrorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Chat Header
private struct ChatHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    let modelName: String
    var onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("C")
                        .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(thread.title)
                    .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    // Share: copy thread as markdown
                    let markdown = exportThreadAsMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Export as Markdown")

                Button {
                    // Copy all messages
                    let text = thread.messages
                        .sorted { $0.createdAt < $1.createdAt }
                        .map { "\($0.role == .user ? "You" : "Assistant"): \($0.content)" }
                        .joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy Conversation")

                Button {
                    // Copy link (placeholder - could be deep link)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("yodaai://chat/\(thread.id.uuidString)", forType: .string)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy Link")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete Chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Delete Chat?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will permanently delete \"\(thread.title)\" and all its messages.")
        }
    }
    
    private func exportThreadAsMarkdown() -> String {
        var lines: [String] = []
        lines.append("# \(thread.title)")
        lines.append("")
        
        for message in thread.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            let role = message.role == .user ? "**You**" : "**Assistant**"
            lines.append("\(role):")
            lines.append(message.content)
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Empty State
private struct EmptyStateView: View {
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 48 * scaleManager.scale))
            .foregroundStyle(.tertiary)

            Text("Start a Conversation")
                .font(.system(size: 22 * scaleManager.scale, weight: .medium))

            Text("Create a new chat to get started")
                .font(.system(size: 14 * scaleManager.scale))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Message List
private struct MessageListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [ChatMessage]
    @ObservedObject var viewModel: ChatViewModel

    init(thread: ChatThread, viewModel: ChatViewModel) {
        let threadId = thread.id
        _messages = Query(filter: #Predicate<ChatMessage> { message in
            message.thread?.id == threadId
        }, sort: \ChatMessage.createdAt)
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(messages) { message in
                        MessageRowView(
                            message: message,
                            viewModel: viewModel,
                            onRetry: {
                                Task { await viewModel.retryFrom(message: message, in: modelContext) }
                            },
                            onDelete: {
                                viewModel.deleteMessage(message, in: modelContext)
                            }
                        )
                        .id(message.id)
                    }

                    if viewModel.isSending {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isSending) { _, isSending in
                if isSending {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Message Row
private struct MessageRowView: View {
    let message: ChatMessage
    @ObservedObject var viewModel: ChatViewModel
    let onRetry: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Show attached images
                if !message.attachments.isEmpty {
                    MessageImageGridView(attachments: message.attachments, alignment: message.role == .user ? .trailing : .leading)
                }

                if message.role == .user {
                    // User message: right-aligned bubble
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message.content)
                            .font(.system(size: 14 * scaleManager.scale))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .textSelection(.enabled)
                    }
                } else {
                    // Assistant message: Markdown rendered
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownTextView(content: message.content)
                            .textSelection(.enabled)
                    }
                }

                // Action buttons on hover
                if isHovering {
                    HStack(spacing: 12) {
                        // Copy button
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy")
                        
                        // Retry button (regenerate from this point)
                        Button {
                            onRetry()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(message.role == .user ? "Resend" : "Regenerate")
                        .disabled(viewModel.isSending)
                        
                        // Delete button
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Delete")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .alert("Delete Message?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This message will be permanently deleted.")
        }
    }
}

// MARK: - Message Image Grid View

/// Grid view for displaying image attachments in messages
private struct MessageImageGridView: View {
    let attachments: [ImageAttachment]
    let alignment: HorizontalAlignment
    @State private var loadedImages: [UUID: NSImage] = [:]
    @State private var previewImage: NSImage?
    @State private var showPreview = false

    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 0)
            }

            VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    if let image = loadedImages[attachment.id] {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onTapGesture {
                                previewImage = image
                                showPreview = true
                            }
                            .help("Click to view full size")
                    } else {
                        ProgressView()
                            .frame(width: 150, height: 150)
                    }
                }
            }

            if alignment == .leading {
                Spacer(minLength: 0)
            }
        }
        .task {
            await loadImages()
        }
        .onChange(of: showPreview) { _, isShowing in
            if isShowing, let image = previewImage {
                showImagePreviewWindow(image: image)
            }
        }
    }

    private func showImagePreviewWindow(image: NSImage) {
        let previewWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        previewWindow.backgroundColor = .black
        previewWindow.isOpaque = false
        previewWindow.level = .floating
        previewWindow.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: ImagePreviewView(image: image, onClose: {
            previewWindow.close()
            showPreview = false
        }))
        previewWindow.contentView = hostingView
        previewWindow.center()
        previewWindow.makeKeyAndOrderFront(nil)
    }

    private func loadImages() async {
        for attachment in attachments {
            do {
                let data = try ImageStorageService.shared.loadImage(filePath: attachment.filePath)
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        loadedImages[attachment.id] = nsImage
                    }
                }
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }
}

// MARK: - Image Preview View

/// Full-screen image preview with zoom support
private struct ImagePreviewView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Image with zoom and pan
            VStack {
                Spacer()
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                // Reset if zoomed out too much
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                Spacer()
            }

            // Controls overlay
            VStack {
                HStack {
                    Spacer()

                    // Close button
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .help("Close (or click background)")
                    .padding()
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 20) {
                    // Zoom out
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = max(scale * 0.8, 0.5)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out")

                    // Reset zoom
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Text("\(Int(scale * 100))%")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Reset zoom")

                    // Zoom in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            scale = min(scale * 1.25, 5.0)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in")
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Enable keyboard shortcuts
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape key
                    onClose()
                    return nil
                }
                return event
            }
        }
    }
}

// MARK: - Markdown Text View
private struct MarkdownTextView: View {
    let content: String
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }
    
    private enum Block {
        case text(String)
        case code(language: String?, code: String)
    }
    
    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var remaining = content
        
        // Pattern to match code blocks: ```language\ncode\n```
        let codeBlockPattern = "```(\\w*)\\n([\\s\\S]*?)```"
        
        while let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []),
              let match = regex.firstMatch(in: remaining, options: [], range: NSRange(remaining.startIndex..., in: remaining)) {
            
            // Text before the code block
            let beforeRange = remaining.startIndex..<remaining.index(remaining.startIndex, offsetBy: match.range.location)
            let beforeText = String(remaining[beforeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !beforeText.isEmpty {
                blocks.append(.text(beforeText))
            }
            
            // Extract language and code
            let languageRange = Range(match.range(at: 1), in: remaining)
            let codeRange = Range(match.range(at: 2), in: remaining)
            
            let language = languageRange.map { String(remaining[$0]) }
            let code = codeRange.map { String(remaining[$0]).trimmingCharacters(in: .newlines) } ?? ""
            
            blocks.append(.code(language: language?.isEmpty == true ? nil : language, code: code))
            
            // Move past this match
            let matchEnd = remaining.index(remaining.startIndex, offsetBy: match.range.location + match.range.length)
            remaining = String(remaining[matchEnd...])
        }
        
        // Remaining text after last code block
        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(.text(trimmed))
        }
        
        return blocks.isEmpty ? [.text(content)] : blocks
    }
    
    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .text(let text):
            Text(attributedString(from: text))
                .font(.system(size: 14 * scaleManager.scale))
                .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        }
    }
    
    private func attributedString(from text: String) -> AttributedString {
        // Try to parse as Markdown
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - Code Block View
private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var isCopied = false
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11 * scaleManager.scale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 11 * scaleManager.scale))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isCopied ? .green : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13 * scaleManager.scale, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Typing Indicator
private struct TypingIndicatorView: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack {
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .font(.system(size: 14 * scaleManager.scale))
                .foregroundStyle(.secondary)
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 4
                }
            Spacer()
        }
    }
}

// MARK: - Composer
private struct ComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: ChatViewModel
    let thread: ChatThread
    let providers: [LLMProvider]
    @FocusState private var isFocused: Bool
    @State private var showModelPicker = false
    @State private var showFilePicker = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    private var defaultProvider: LLMProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Image thumbnails (if any)
                if !viewModel.pendingImages.isEmpty {
                    ImageThumbnailRow(viewModel: viewModel)
                    Divider()
                }

                // Mentioned apps chips
                if !viewModel.mentionedApps.isEmpty {
                    MentionChipsView(viewModel: viewModel)
                }

                // Text Input
                TextField("Ask anything, @ to mention apps", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .font(.system(size: 14 * scaleManager.scale))
                    .focused($isFocused)
                    .onChange(of: viewModel.composerText) { _, newValue in
                        // Check if user typed @
                        if newValue.hasSuffix("@") {
                            viewModel.showMentionPicker = true
                            viewModel.mentionSearchText = ""
                        }
                    }
                    .onSubmit {
                        if !viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !NSEvent.modifierFlags.contains(.shift) {
                            sendMessage()
                        }
                    }
                    .background(PasteInterceptor(onPaste: handleDirectPaste))
                    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                        return handleDrop(providers: providers)
                    }
                    .popover(isPresented: $viewModel.showMentionPicker, arrowEdge: .top) {
                        MentionPickerPopover(viewModel: viewModel)
                    }

                // Toolbar row
                HStack(spacing: 16) {
                    // Left icons
                    HStack(spacing: 12) {
                        Button {
                            viewModel.showMentionPicker = true
                        } label: {
                            Image(systemName: "at")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.mentionedApps.isEmpty ? Color.secondary : Color.accentColor)
                        .help("Add app context (@)")

                        Button {
                            viewModel.alwaysAttachAppContext.toggle()
                        } label: {
                            Image(systemName: viewModel.alwaysAttachAppContext ? "bolt.fill" : "bolt")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.alwaysAttachAppContext ? .yellow : .secondary)
                        .help(viewModel.alwaysAttachAppContext ? "Auto-attach frontmost app: On" : "Auto-attach frontmost app: Off")

                        Button {
                            showFilePicker = true
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.pendingImages.isEmpty ? .secondary : Color.accentColor)
                        .help("Attach image")
                        .fileImporter(
                            isPresented: $showFilePicker,
                            allowedContentTypes: [.image],
                            allowsMultipleSelection: true
                        ) { result in
                            handleFileSelection(result: result)
                        }
                    }

                    // Model selector (clickable)
                    Button {
                        showModelPicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("/")
                                .foregroundStyle(.secondary)
                            Text(defaultProvider?.selectedModel ?? "No model")
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13 * scaleManager.scale))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showModelPicker, arrowEdge: .top) {
                        ModelPickerPopover(providers: providers)
                    }

                    Spacer()

                    // Send button
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var canSend: Bool {
        // Allow sending with images even if text is empty
        !viewModel.isSending && (!viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty || !viewModel.pendingImages.isEmpty)
    }

    private func sendMessage() {
        guard canSend else { return }
        // Remove trailing @ if user was about to mention
        if viewModel.composerText.hasSuffix("@") {
            viewModel.composerText = String(viewModel.composerText.dropLast())
        }
        viewModel.activeThreadID = thread.id
        Task { await viewModel.send(in: modelContext) }
    }

    // MARK: - Image Handling

    /// Handle direct paste from pasteboard (Cmd+V)
    private func handleDirectPaste() {
        let pasteboard = NSPasteboard.general

        // Try to get image from pasteboard
        // Check for various image types that screenshots might use
        if let image = NSImage(pasteboard: pasteboard) {
            // Convert to PNG data
            if let pngData = image.pngData() {
                viewModel.addPendingImage(data: pngData, fileName: "pasted-image.png", mimeType: "image/png")
            }
        } else if let types = pasteboard.types,
                  types.contains(where: { $0.rawValue.contains("image") || $0.rawValue.contains("png") || $0.rawValue.contains("tiff") }) {
            // Fallback: try to read raw data
            for type in types {
                if let data = pasteboard.data(forType: type),
                   let image = NSImage(data: data),
                   let pngData = image.pngData() {
                    viewModel.addPendingImage(data: pngData, fileName: "pasted-image.png", mimeType: "image/png")
                    break
                }
            }
        }
    }

    /// Handle drag and drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.isFileURL else { return }
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            viewModel.addImagesFromURLs(urls)
        }

        return true
    }

    /// Handle file picker selection
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addImagesFromURLs(urls)
        case .failure(let error):
            viewModel.imageErrorMessage = "File selection error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Paste Interceptor

/// NSView wrapper to intercept paste commands
private struct PasteInterceptor: NSViewRepresentable {
    let onPaste: () -> Void

    func makeNSView(context: Context) -> PasteHandlerView {
        let view = PasteHandlerView()
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: PasteHandlerView, context: Context) {
        nsView.onPaste = onPaste
    }

    class PasteHandlerView: NSView {
        var onPaste: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Check for Cmd+V
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                // Check if pasteboard has image
                let pasteboard = NSPasteboard.general
                if NSImage(pasteboard: pasteboard) != nil {
                    onPaste?()
                    return true // Consume event
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        override var acceptsFirstResponder: Bool { true }
    }
}

// MARK: - Mention Chips View
private struct MentionChipsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.mentionedApps) { app in
                    MentionChipView(app: app, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Single Mention Chip
private struct MentionChipView: View {
    let app: RunningApp
    @ObservedObject var viewModel: ChatViewModel
    @State private var showPreview = false
    @State private var previewContent: String?
    @State private var windowTitle: String?
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text("@\(app.appName)")
                .font(.system(size: 11 * scaleManager.scale))
            
            // Preview button
            Button {
                showPreview = true
                if !hasLoadedOnce {
                    loadPreview()
                }
            } label: {
                Image(systemName: isLoading ? "hourglass" : (previewContent != nil && !previewContent!.isEmpty ? "eye.fill" : "eye"))
                    .font(.system(size: 10 * scaleManager.scale))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(previewContent != nil && !previewContent!.isEmpty ? Color.green : Color.secondary)
            .popover(isPresented: $showPreview) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        VStack(alignment: .leading) {
                            Text(app.appName)
                                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                            if let title = windowTitle, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 11 * scaleManager.scale))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            loadPreview()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11 * scaleManager.scale))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                    }
                    
                    Divider()
                    
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Capturing content...")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if let content = previewContent, !content.isEmpty {
                        HStack {
                            Text("\(content.count) characters captured")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        ScrollView {
                            Text(content)
                                .font(.system(size: 11 * scaleManager.scale, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 32 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                            Text("No content captured")
                                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Click refresh to capture content.\nThe app will briefly activate to read its content.")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding()
                .frame(width: 450)
                .frame(minHeight: 150)
            }
            
            // Remove button
            Button {
                viewModel.removeMention(app)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10 * scaleManager.scale))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
        .onAppear {
            // Auto-load preview when chip appears
            loadPreview()
        }
    }
    
    private func loadPreview() {
        isLoading = true
        hasLoadedOnce = true
        Task { @MainActor in
            // First try to use globally cached content from floating panel
            if let globalCached = ContentCacheService.shared.getCachedSnapshot(for: app.bundleIdentifier) {
                print("[MentionChipView] Using cached content from floating panel for \(app.appName)")
                previewContent = globalCached.focusedValuePreview
                windowTitle = globalCached.windowTitle
                isLoading = false
                viewModel.updateMentionContext(for: app.bundleIdentifier, snapshot: globalCached)
                return
            }
            
            // Otherwise, capture by activating the app
            let snapshot = await viewModel.accessibilityService.captureContextWithActivation(for: app.bundleIdentifier, promptIfNeeded: false)
            previewContent = snapshot?.focusedValuePreview
            windowTitle = snapshot?.windowTitle
            isLoading = false
            
            // Cache the snapshot in the ViewModel so it's available when sending
            viewModel.updateMentionContext(for: app.bundleIdentifier, snapshot: snapshot)
        }
    }
}

// MARK: - Image Thumbnail Views

/// Horizontal scroll view showing pending images above composer
private struct ImageThumbnailRow: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.pendingImages) { image in
                    ImageThumbnailView(image: image, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Individual image thumbnail with remove button
private struct ImageThumbnailView: View {
    let image: ChatViewModel.PendingImage
    @ObservedObject var viewModel: ChatViewModel
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            if let thumbnail = image.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            // Remove button (on hover)
            if isHovering {
                Button {
                    viewModel.removePendingImage(image)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Mention Picker Popover
private struct MentionPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    private var filteredApps: [RunningApp] {
        let apps = viewModel.getRunningApps()
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.appName.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Mention App")
                    .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                Spacer()
                Text("Include app content in your message")
                    .font(.system(size: 11 * scaleManager.scale))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Search field
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14 * scaleManager.scale))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            // App list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredApps.isEmpty {
                        Text("No running apps found")
                            .font(.system(size: 11 * scaleManager.scale))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(filteredApps) { app in
                            Button {
                                selectApp(app)
                            } label: {
                                HStack(spacing: 10) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .frame(width: 24, height: 24)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.appName)
                                            .font(.system(size: 14 * scaleManager.scale))
                                        Text(app.bundleIdentifier)
                                            .font(.system(size: 10 * scaleManager.scale))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if viewModel.mentionedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.primary.opacity(0.001)) // For hover
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 320)
    }
    
    private func selectApp(_ app: RunningApp) {
        // Remove the @ from composer if it's there
        if viewModel.composerText.hasSuffix("@") {
            viewModel.composerText = String(viewModel.composerText.dropLast())
        }
        
        viewModel.addMention(app)
        dismiss()
    }
}

// MARK: - Model Picker Popover
private struct ModelPickerPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let providers: [LLMProvider]
    @ObservedObject private var scaleManager = AppScaleManager.shared
    
    private var filteredProviders: [LLMProvider] {
        providers.filter { !$0.selectedModel.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Model")
                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredProviders) { (provider: LLMProvider) in
                        Button {
                            setDefaultProvider(provider)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.selectedModel)
                                        .font(.system(size: 14 * scaleManager.scale))
                                    Text(provider.name)
                                        .font(.system(size: 11 * scaleManager.scale))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if provider.isDefault {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(provider.isDefault ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 250)
    }
    
    private func setDefaultProvider(_ provider: LLMProvider) {
        for p in providers {
            p.isDefault = (p.id == provider.id)
            p.updatedAt = Date()
        }
        try? modelContext.save()
    }
}

// MARK: - Settings View
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            APIKeysSettingsTab()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
            
            PermissionsSettingsTab()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 450)
        .padding()
        .overlay(alignment: .bottomTrailing) {
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding()
        }
    }
}

// MARK: - General Settings Tab
private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var floatingPanelController = FloatingPanelController.shared
    @ObservedObject var cacheService = ContentCacheService.shared
    @ObservedObject var llmSettings = LLMSettings.shared
    @State private var showCachedAppsSheet = false

    var body: some View {
        Form {
            Section("LLM Settings") {
                // Temperature slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", llmSettings.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $llmSettings.temperature, in: 0...2, step: 0.1)
                }
                Text("Higher values make output more random, lower values more deterministic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Max tokens
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    TextField("", value: $llmSettings.maxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum number of tokens in the response (0 = no limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Max message count
                HStack {
                    Text("Max Message History")
                    Spacer()
                    TextField("", value: $llmSettings.maxMessageCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum messages to include in context (0 = all)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // System prompt toggle and text
                Toggle("Use System Prompt", isOn: $llmSettings.useSystemPrompt)
                
                if llmSettings.useSystemPrompt {
                    TextEditor(text: $llmSettings.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Text("Instructions sent to the model at the start of each conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Reset button
                Button("Reset to Defaults") {
                    llmSettings.reset()
                }
                .foregroundStyle(.red)
            }
            
            Section("Floating Panel") {
                Toggle("Show floating capture panel", isOn: Binding(
                    get: { floatingPanelController.isVisible },
                    set: { newValue in
                        if newValue {
                            floatingPanelController.show()
                        } else {
                            floatingPanelController.hide()
                        }
                    }
                ))
                Text("Continuously capture content from the foreground app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Custom title setting
                TextField("Panel title", text: $floatingPanelController.customTitle)
                Text("Customize the floating panel title (e.g., \"Jianqing's YoDaAI\")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if floatingPanelController.isVisible {
                    // Cached apps row - clickable
                    Button {
                        showCachedAppsSheet = true
                    } label: {
                        HStack {
                            Text("Cached apps")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(cacheService.cache.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Toggle("Auto-capture enabled", isOn: $cacheService.isCaptureEnabled)
                    
                    Button("Clear Cache") {
                        cacheService.clearCache()
                    }
                    .foregroundStyle(.red)
                }
            }
            
            Section("App Context") {
                Toggle("Always attach app context", isOn: $viewModel.alwaysAttachAppContext)
                Text("Include frontmost app info when sending messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Appearance") {
                HStack {
                    Text("Text Size")
                    Spacer()
                    
                    Button {
                        AppScaleManager.shared.zoomOut()
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.bordered)
                    .disabled(AppScaleManager.shared.scale <= AppScaleManager.minScale)
                    
                    Text("\(AppScaleManager.shared.scalePercentage)%")
                        .frame(width: 50)
                        .monospacedDigit()
                    
                    Button {
                        AppScaleManager.shared.zoomIn()
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.bordered)
                    .disabled(AppScaleManager.shared.scale >= AppScaleManager.maxScale)
                    
                    Button("Reset") {
                        AppScaleManager.shared.resetZoom()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Text("Use Cmd++ to increase, Cmd+- to decrease, Cmd+0 to reset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("About") {
                HStack {
                    Text("YoDaAI")
                    Spacer()
                    Text("Version 1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCachedAppsSheet) {
            CachedAppsDetailView()
        }
    }
}

// MARK: - Cached Apps Detail View
private struct CachedAppsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var cacheService = ContentCacheService.shared
    @State private var selectedAppBundleId: String?
    @State private var selectedContent: CachedAppContent?
    
    var body: some View {
        NavigationSplitView {
            // List of cached apps
            List(selection: $selectedAppBundleId) {
                ForEach(cacheService.getAllCachedApps(), id: \.bundleId) { item in
                    CachedAppListRow(bundleId: item.bundleId, content: item.content)
                        .tag(item.bundleId)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Cached Apps (\(cacheService.cache.count))")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        cacheService.clearCache()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .help("Clear all cached content")
                }
            }
        } detail: {
            if let bundleId = selectedAppBundleId,
               let content = cacheService.getCachedContent(for: bundleId) {
                CachedAppContentView(bundleId: bundleId, content: content)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select an app to view cached content")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Cached App List Row
private struct CachedAppListRow: View {
    let bundleId: String
    let content: CachedAppContent
    
    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
               let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(content.snapshot.appName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Content status
                    let charCount = content.snapshot.focusedValuePreview?.count ?? 0
                    if charCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(content.isOlderThan(60) ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            Text("\(charCount) chars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("No content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Text(timeAgo(content.capturedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

// MARK: - Cached App Content View
private struct CachedAppContentView: View {
    let bundleId: String
    let content: CachedAppContent
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // App icon
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
                   let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 36))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.snapshot.appName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let windowTitle = content.snapshot.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Copy button
                Button {
                    if let text = content.snapshot.focusedValuePreview {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(content.snapshot.focusedValuePreview == nil)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Metadata
            HStack(spacing: 20) {
                MetadataItem(label: "Characters", value: "\(content.snapshot.focusedValuePreview?.count ?? 0)")
                MetadataItem(label: "Captured", value: formatDate(content.capturedAt))
                MetadataItem(label: "Role", value: content.snapshot.focusedRole ?? "Unknown")
                MetadataItem(label: "Status", value: content.isOlderThan(60) ? "Stale" : "Fresh", color: content.isOlderThan(60) ? .orange : .green)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Content
            if let text = content.snapshot.focusedValuePreview, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No content captured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("The app may not have had any accessible content when captured.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Metadata Item
private struct MetadataItem: View {
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

// MARK: - API Keys Settings Tab
private struct APIKeysSettingsTab: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var providers: [LLMProvider]

    @Query private var legacySettingsRecords: [ProviderSettings]

    @State private var selectedProviderID: LLMProvider.ID?
    @State private var draftName: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftApiKey: String = ""
    @State private var selectedModelID: String = ""
    @State private var fetchedModels: [OpenAIModel] = []
    @State private var isFetchingModels: Bool = false
    @State private var modelsErrorMessage: String?
    @State private var fetchTask: Task<Void, Never>?

    private var selectedProvider: LLMProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var body: some View {
        Form {
            Section("Custom provider") {
                Picker("Choose your provider", selection: $selectedProviderID) {
                    ForEach(providers) { provider in
                        Text(provider.name).tag(Optional(provider.id))
                    }
                }
                Text("The URL should point to an OpenAI Compatible API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("Provider name", text: $draftName)
                
                TextField("Base URL", text: $draftBaseURL)
                    .onChange(of: draftBaseURL) {
                        debouncedFetchModels()
                    }
                
                SecureField("API key", text: $draftApiKey)
                    .onChange(of: draftApiKey) {
                        debouncedFetchModels()
                    }
                
                if !fetchedModels.isEmpty || isFetchingModels {
                    HStack {
                        Picker("Model", selection: $selectedModelID) {
                            ForEach(fetchedModels) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                
                if let modelsErrorMessage {
                    Text(modelsErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Button("Manage models") {
                    Task { await fetchModels() }
                }
                
                HStack {
                    Spacer()
                    Button("Save Provider") {
                        saveSelectedProvider()
                    }
                    .disabled(!hasUnsavedChanges)
                }
            }
            
            Section("Manage Providers") {
                HStack {
                    Button("Add Provider") {
                        addProvider()
                    }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        deleteSelectedProvider()
                    }
                    .disabled(providers.count <= 1)
                }
                
                Button("Set as Default") {
                    setSelectedProviderDefault()
                }
                .disabled(selectedProvider?.isDefault == true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            migrateLegacyProviderIfNeeded()
            selectInitialProviderIfNeeded()
        }
        .onChange(of: selectedProviderID) {
            loadSelectedProviderDrafts()
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let provider = selectedProvider else { return false }
        return provider.name != draftName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            || provider.baseURL != draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            || provider.apiKey != draftApiKey
            || provider.selectedModel != selectedModelID
    }

    private func selectInitialProviderIfNeeded() {
        if selectedProviderID == nil {
            selectedProviderID = providers.first(where: { $0.isDefault })?.id ?? providers.first?.id
        }
        loadSelectedProviderDrafts()
    }

    private func loadSelectedProviderDrafts() {
        guard let selectedProvider else {
            draftName = ""
            draftBaseURL = ""
            draftApiKey = ""
            selectedModelID = ""
            fetchedModels = []
            modelsErrorMessage = nil
            return
        }

        draftName = selectedProvider.name
        draftBaseURL = selectedProvider.baseURL
        draftApiKey = selectedProvider.apiKey
        selectedModelID = selectedProvider.selectedModel

        fetchedModels = []
        modelsErrorMessage = nil

        Task { await fetchModels() }
    }

    private func debouncedFetchModels() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await fetchModels()
        }
    }

    private func fetchModels() async {
        modelsErrorMessage = nil

        let baseURL = draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let apiKey = draftApiKey

        guard !baseURL.isEmpty else {
            fetchedModels = []
            return
        }

        isFetchingModels = true
        defer { isFetchingModels = false }

        do {
            let models = try await OpenAICompatibleClient().listModels(baseURL: baseURL, apiKey: apiKey)
            fetchedModels = models

            if !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id ?? ""
            }
        } catch {
            modelsErrorMessage = error.localizedDescription
            fetchedModels = []
        }
    }

    private func saveSelectedProvider() {
        guard let selectedProvider else { return }

        selectedProvider.name = draftName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.baseURL = draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.apiKey = draftApiKey
        selectedProvider.selectedModel = selectedModelID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.updatedAt = Date()

        try? modelContext.save()
    }

    private func addProvider() {
        let provider = LLMProvider(
            name: "New Provider",
            baseURL: "http://localhost:11434/v1",
            apiKey: "",
            selectedModel: "",
            isDefault: providers.isEmpty
        )
        modelContext.insert(provider)
        try? modelContext.save()

        selectedProviderID = provider.id
    }

    private func deleteSelectedProvider() {
        guard let selectedProvider else { return }
        guard providers.count > 1 else { return }

        let wasDefault = selectedProvider.isDefault
        let deletedID = selectedProvider.id

        modelContext.delete(selectedProvider)
        try? modelContext.save()

        if wasDefault {
            let remaining = providers.filter { $0.id != deletedID }
            if let first = remaining.first {
                first.isDefault = true
                first.updatedAt = Date()
                try? modelContext.save()
            }
        }

        selectedProviderID = providers.first(where: { $0.id != deletedID })?.id
    }

    private func setSelectedProviderDefault() {
        guard let selectedProvider else { return }
        for provider in providers {
            provider.isDefault = (provider.id == selectedProvider.id)
            provider.updatedAt = Date()
        }
        try? modelContext.save()
    }

    private func migrateLegacyProviderIfNeeded() {
        guard providers.isEmpty else { return }
        guard let legacy = legacySettingsRecords.first else { return }

        let migrated = LLMProvider(
            name: "Migrated Provider",
            baseURL: legacy.baseURL,
            apiKey: legacy.apiKey,
            selectedModel: legacy.model,
            isDefault: true
        )
        modelContext.insert(migrated)
        try? modelContext.save()

        selectedProviderID = migrated.id
    }
}

// MARK: - Permissions Settings Tab
private struct PermissionsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\AppPermissionRule.updatedAt, order: .reverse)])
    private var permissionRules: [AppPermissionRule]
    
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("Accessibility Permission") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isAccessibilityGranted ? Color.green : Color.red)
                                .font(.title2)
                            Text(isAccessibilityGranted ? "Granted" : "Not Granted")
                                .font(.headline)
                                .foregroundStyle(isAccessibilityGranted ? Color.primary : Color.red)
                        }
                        Text("Required to capture content from other apps and insert text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Refresh button
                    Button {
                        checkAccessibilityPermission()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh status")
                    
                    if !isAccessibilityGranted {
                        Button("Grant Access") {
                            requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
                
                if !isAccessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to enable:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("1. Click \"Grant Access\" to open System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("2. Find YoDaAI in the list and enable the toggle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("3. Click the refresh button or restart YoDaAI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            
            Section("Automation Permission") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.2")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Required for App Control")
                                .font(.headline)
                            Text("Click each app below to trigger the permission request")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                // App permission request buttons
                AutomationAppRow(appName: "Safari", bundleId: "com.apple.Safari", icon: "safari")
                AutomationAppRow(appName: "Google Chrome", bundleId: "com.google.Chrome", icon: "globe")
                AutomationAppRow(appName: "Notes", bundleId: "com.apple.Notes", icon: "note.text")
                AutomationAppRow(appName: "Mail", bundleId: "com.apple.mail", icon: "envelope")
                AutomationAppRow(appName: "TextEdit", bundleId: "com.apple.TextEdit", icon: "doc.text")
                
                HStack {
                    Spacer()
                    Button("Open Automation Settings") {
                        openAutomationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note: Permission dialogs only appear once per app. If you previously denied, use \"Open Automation Settings\" to enable manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Section("Per-App Permissions") {
                if permissionRules.isEmpty {
                    Text("No apps recorded yet. Use @ mentions or enable auto-context to populate this list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(permissionRules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.displayName)
                                Text(rule.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            VStack {
                                Text("Context")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Toggle("Context", isOn: Binding(get: {
                                    rule.allowContext
                                }, set: { newValue in
                                    rule.allowContext = newValue
                                    rule.updatedAt = Date()
                                    try? modelContext.save()
                                }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                            
                            VStack {
                                Text("Insert")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Toggle("Insert", isOn: Binding(get: {
                                    rule.allowInsert
                                }, set: { newValue in
                                    rule.allowInsert = newValue
                                    rule.updatedAt = Date()
                                    try? modelContext.save()
                                }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkAccessibilityPermission()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    private func checkAccessibilityPermission() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    private func startRefreshTimer() {
        // Check every 2 seconds while the view is visible
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                checkAccessibilityPermission()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func requestAccessibilityPermission() {
        // First try to trigger the system prompt (works only on first request)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let result = AXIsProcessTrustedWithOptions(options)
        
        // If still not trusted, the prompt may not have shown (already denied before)
        // In that case, open System Settings directly
        if !result {
            openAccessibilitySettings()
        }
    }
    
    private func openAccessibilitySettings() {
        // Try the modern macOS 13+ URL first
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAutomationSettings() {
        // Open Automation section in Privacy & Security
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Automation App Row
private struct AutomationAppRow: View {
    let appName: String
    let bundleId: String
    let icon: String
    
    @State private var status: PermissionStatus = .unknown
    @State private var isRequesting = false
    
    enum PermissionStatus {
        case unknown
        case requesting
        case granted
        case denied
        case notInstalled
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            
            Text(appName)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            switch status {
            case .unknown:
                Button("Request Permission") {
                    requestPermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRequesting)
                
            case .requesting:
                ProgressView()
                    .controlSize(.small)
                Text("Requesting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            case .granted:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
            case .denied:
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Denied")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
            case .notInstalled:
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Not Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func requestPermission() {
        print("[AutomationAppRow] Requesting permission for \(appName) (\(bundleId))...")
        isRequesting = true
        status = .requesting
        
        // Run AppleScript in background to trigger permission dialog
        DispatchQueue.global(qos: .userInitiated).async {
            let result = triggerAutomationPermission(for: bundleId, appName: appName)
            
            DispatchQueue.main.async {
                print("[AutomationAppRow] Result for \(appName): \(result)")
                isRequesting = false
                status = result
            }
        }
    }
    
    private func triggerAutomationPermission(for bundleId: String, appName: String) -> PermissionStatus {
        print("[AutomationAppRow] Running AppleScript for \(appName)...")
        
        // First, try to launch the app using NSWorkspace (this doesn't require permission)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            print("[AutomationAppRow] Found app at: \(appURL.path)")
            
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            let semaphore = DispatchSemaphore(value: 0)
            var launchError: Error?
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                launchError = error
                semaphore.signal()
            }
            
            semaphore.wait()
            
            if let error = launchError {
                print("[AutomationAppRow] Failed to launch \(appName): \(error)")
            } else {
                print("[AutomationAppRow] Launched \(appName), waiting for app to start...")
                Thread.sleep(forTimeInterval: 1.0)  // Wait for app to fully launch
            }
        } else {
            print("[AutomationAppRow] App not found: \(bundleId)")
            return .notInstalled
        }
        
        // Now run AppleScript to trigger the permission dialog
        // Using NSAppleScript directly since we're not sandboxed
        let script: String
        
        switch bundleId {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                count of windows
            end tell
            """
        case "com.google.Chrome":
            script = """
            tell application "Google Chrome"
                count of windows
            end tell
            """
        case "com.apple.Notes":
            script = """
            tell application "Notes"
                count of notes
            end tell
            """
        case "com.apple.mail":
            script = """
            tell application "Mail"
                count of mailboxes
            end tell
            """
        case "com.apple.TextEdit":
            script = """
            tell application "TextEdit"
                count of documents
            end tell
            """
        default:
            return .unknown
        }
        
        print("[AutomationAppRow] Executing AppleScript: \(script.prefix(50))...")
        
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            print("[AutomationAppRow] Failed to create AppleScript")
            return .unknown
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown"
            print("[AutomationAppRow] AppleScript error for \(appName): [\(errorNumber)] \(errorMessage)")
            
            if errorNumber == -1743 {
                return .denied
            }
            return .unknown
        }
        
        print("[AutomationAppRow] AppleScript succeeded for \(appName), result: \(result.stringValue ?? "nil")")
        return .granted
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ChatThread.self, ChatMessage.self, ProviderSettings.self, LLMProvider.self, AppPermissionRule.self],
            inMemory: true
        )
}
