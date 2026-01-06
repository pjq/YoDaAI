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
                        MessageRowView(message: message)
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
    @State private var isHovering = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .user {
                    // User message: right-aligned bubble
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                } else {
                    // Assistant message: left-aligned plain text
                    Text(message.content)
                        .textSelection(.enabled)
                }

                // Copy button on hover
                if isHovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity)
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
                // Text Input
                TextField("Ask Anything, @ for context, / for models", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .font(.body)
                    .focused($isFocused)
                    .onSubmit {
                        if !viewModel.composerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !NSEvent.modifierFlags.contains(.shift) {
                            sendMessage()
                        }
                    }

                // Toolbar row
                HStack(spacing: 16) {
                    // Left icons
                    HStack(spacing: 12) {
                        Button { } label: {
                            Image(systemName: "at")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Add context")

                        Button {
                            viewModel.alwaysAttachAppContext.toggle()
                        } label: {
                            Image(systemName: viewModel.alwaysAttachAppContext ? "bolt.fill" : "bolt")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.alwaysAttachAppContext ? .yellow : .secondary)
                        .help(viewModel.alwaysAttachAppContext ? "App context: On" : "App context: Off")

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
        viewModel.activeThreadID = thread.id
        Task { await viewModel.send(in: modelContext) }
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

    var body: some View {
        Form {
            Section("Accessibility permissions") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Accessibility permissions")
                        Text("Used to get selected text system-wide and to paste text anywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Accessibility") {
                        // Open System Preferences
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Section("App permissions") {
                if permissionRules.isEmpty {
                    Text("No apps recorded yet. Use YoDaAI with other apps to populate this list.")
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
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ChatThread.self, ChatMessage.self, ProviderSettings.self, LLMProvider.self, AppPermissionRule.self],
            inMemory: true
        )
}
