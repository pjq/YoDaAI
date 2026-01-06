import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\ChatThread.createdAt, order: .reverse)])
    private var threads: [ChatThread]

    @StateObject private var viewModel = ChatViewModel(
        accessibilityService: AccessibilityService(),
        permissionsStore: AppPermissionsStore()
    )
    @State private var activeThread: ChatThread?
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $activeThread) {
                ForEach(threads) { thread in
                    Text(thread.title)
                        .tag(thread as ChatThread?)
                }
            }
            .navigationTitle("YouDaAI")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewChat()
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                }

                ToolbarItem {
                    Button {
                        viewModel.alwaysAttachAppContext.toggle()
                    } label: {
                        Label(
                            viewModel.alwaysAttachAppContext ? "Context: On" : "Context: Off",
                            systemImage: viewModel.alwaysAttachAppContext ? "bolt.fill" : "bolt.slash"
                        )
                    }
                }

                ToolbarItem {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        } detail: {
            ChatDetailView(
                thread: activeThread ?? threads.first,
                viewModel: viewModel
            )
        }
        .onAppear {
            if activeThread == nil {
                activeThread = threads.first
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
}

private struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext

    var thread: ChatThread?
    @ObservedObject var viewModel: ChatViewModel

    @State private var composerIsFocused = false

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                MessageListView(thread: thread)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    ComposerView(viewModel: viewModel) {
                        Task { await viewModel.send(in: modelContext) }
                    }

                    Button("Insert") {
                        viewModel.insertLastAssistantMessageIntoFocusedApp(in: modelContext)
                    }
                    .disabled(viewModel.isSending)
                }
                .padding(12)
            } else {
                ContentUnavailableView("New Chat", systemImage: "sparkles", description: Text("Create a chat to get started."))
            }
        }
        .navigationTitle(thread?.title ?? "Chat")
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

private struct MessageListView: View {
    @Query private var messages: [ChatMessage]

    init(thread: ChatThread) {
        let threadId = thread.id
        _messages = Query(filter: #Predicate<ChatMessage> { message in
            message.thread?.id == threadId
        }, sort: \ChatMessage.createdAt)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    MessageRowView(message: message)
                }
            }
            .padding(16)
        }
    }
}

private struct MessageRowView: View {
    var message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.content)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(message.role == .user ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch message.role {
        case .system: return "System"
        case .user: return "You"
        case .assistant: return "YouDaAI"
        }
    }
}

private struct ComposerView: View {
    @ObservedObject var viewModel: ChatViewModel
    var onSend: () -> Void

    var body: some View {
        HStack {
            TextField("Ask anything…", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1...6)

            Button {
                onSend()
            } label: {
                if viewModel.isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSending || viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [ProviderSettings]
    @Query(sort: [SortDescriptor(\AppPermissionRule.updatedAt, order: .reverse)])
    private var permissionRules: [AppPermissionRule]

    @ObservedObject var viewModel: ChatViewModel

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""

    var body: some View {
        Form {
            Section("OpenAI-Compatible Provider") {
                TextField("Base URL", text: $baseURL)
                SecureField("API Key (optional)", text: $apiKey)
                TextField("Model", text: $model)
            }

            Section("App Permissions") {
                if permissionRules.isEmpty {
                    Text("No apps recorded yet. Use YouDaAI with apps to populate this list.")
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
                            Toggle("Context", isOn: Binding(get: {
                                rule.allowContext
                            }, set: { newValue in
                                rule.allowContext = newValue
                                rule.updatedAt = Date()
                                try? modelContext.save()
                            }))
                            .labelsHidden()

                            Toggle("Insert", isOn: Binding(get: {
                                rule.allowInsert
                            }, set: { newValue in
                                rule.allowInsert = newValue
                                rule.updatedAt = Date()
                                try? modelContext.save()
                            }))
                            .labelsHidden()
                        }
                    }
                }
            }

            Section {
                Button("Save") {
                    saveProvider()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            loadProvider()
        }
    }

    private func loadProvider() {
        let existing = settingsRecords.first
        baseURL = existing?.baseURL ?? "http://localhost:11434/v1"
        apiKey = existing?.apiKey ?? ""
        model = existing?.model ?? "llama3.1"
    }

    private func saveProvider() {
        let record: ProviderSettings
        if let existing = settingsRecords.first {
            record = existing
        } else {
            record = ProviderSettings()
            modelContext.insert(record)
        }

        record.baseURL = baseURL
        record.apiKey = apiKey
        record.model = model
        record.updatedAt = Date()

        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ChatThread.self, ChatMessage.self, ProviderSettings.self, AppPermissionRule.self],
            inMemory: true
        )
}
