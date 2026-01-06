import SwiftUI
import SwiftData
import Combine

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
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
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

    var body: some View {
        HStack(spacing: 10) {
            // Chat icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(thread.title)
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
    }
}

// MARK: - Chat Header
private struct ChatHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    let modelName: String
    var onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("C")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(thread.title)
                    .font(.headline)
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
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 48))
            .foregroundStyle(.tertiary)

            Text("Start a Conversation")
                .font(.title2)
                .fontWeight(.medium)

            Text("Create a new chat to get started")
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

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .user {
                    // User message: right-aligned bubble
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                } else {
                    // Assistant message: Markdown rendered
                    MarkdownTextView(content: message.content)
                        .textSelection(.enabled)
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

// MARK: - Markdown Text View
private struct MarkdownTextView: View {
    let content: String
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
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
                    .font(.caption)
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
                    .font(.system(.body, design: .monospaced))
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

    var body: some View {
        HStack {
            Text("Thinking" + String(repeating: ".", count: dotCount))
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

    private var defaultProvider: LLMProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Mentioned apps chips
                if !viewModel.mentionedApps.isEmpty {
                    MentionChipsView(viewModel: viewModel)
                }
                
                // Text Input
                TextField("Ask anything, @ to mention apps", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .font(.body)
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

                        Button { } label: {
                            Image(systemName: "paperclip")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Attach file")
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
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
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
        !viewModel.isSending && !viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
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
}

// MARK: - Mention Chips View
private struct MentionChipsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.mentionedApps) { app in
                    HStack(spacing: 4) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text("@\(app.appName)")
                            .font(.caption)
                        Button {
                            viewModel.removeMention(app)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Mention Picker Popover
private struct MentionPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
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
                    .font(.headline)
                Spacer()
                Text("Include app content in your message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Search field
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            // App list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredApps.isEmpty {
                        Text("No running apps found")
                            .font(.caption)
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
                                            .font(.body)
                                        Text(app.bundleIdentifier)
                                            .font(.caption2)
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
    
    private var filteredProviders: [LLMProvider] {
        providers.filter { !$0.selectedModel.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Model")
                .font(.headline)
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
                                        .font(.body)
                                    Text(provider.name)
                                        .font(.caption)
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

    var body: some View {
        Form {
            Section("App Context") {
                Toggle("Always attach app context", isOn: $viewModel.alwaysAttachAppContext)
                Text("Include frontmost app info when sending messages")
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
                        Text("3. You may need to restart YoDaAI after granting permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
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
        }
    }
    
    private func checkAccessibilityPermission() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    private func requestAccessibilityPermission() {
        // This will show the system prompt to grant permission
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Check again after a delay (user might grant it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkAccessibilityPermission()
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ChatThread.self, ChatMessage.self, ProviderSettings.self, LLMProvider.self, AppPermissionRule.self],
            inMemory: true
        )
}
