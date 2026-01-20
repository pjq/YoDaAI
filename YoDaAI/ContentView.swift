import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
import Textual

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsRouter: SettingsRouter

    @Query(sort: [SortDescriptor(\ChatThread.createdAt, order: .reverse)])
    private var threads: [ChatThread]

    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var providers: [LLMProvider]
    
    @Query private var mcpServers: [MCPServer]

    @StateObject private var viewModel = ChatViewModel(
        accessibilityService: AccessibilityService(),
        permissionsStore: AppPermissionsStore()
    )
    @ObservedObject private var floatingPanelController = FloatingPanelController.shared
    @ObservedObject private var mcpToolRegistry = MCPToolRegistry.shared
    @State private var activeThread: ChatThread?
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
            List(selection: Binding(
                get: { activeThread },
                set: { newValue in
                    // Only allow changing threads when not sending
                    if !viewModel.isSending {
                        activeThread = newValue
                    }
                }
            )) {
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
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewChat) {
                        Image(systemName: "plus.message")
                    }
                    .help("New Chat (Cmd+N)")
                    .disabled(viewModel.isSending) // Disable new chat during API calls
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
                },
                onCreateNewChat: {
                    createNewChat()
                },
                onOpenAPIKeysSettings: {
                    settingsRouter.open(.apiKeys)
                }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            // Initialize MCP connections on app start
            if mcpToolRegistry.isMCPEnabled && !mcpServers.isEmpty {
                print("[ContentView] Initializing MCP connections on app start...")
                await mcpToolRegistry.refreshTools(servers: mcpServers)
            }
        }
        .onAppear {
            if activeThread == nil {
                activeThread = threads.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewChat)) { _ in
            // Only create new chat when not sending
            if !viewModel.isSending {
                createNewChat()
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
                    
                    // Settings button using SettingsLink
                    SettingsLink {
                        Image(systemName: "gear")
                    }
                    .help("Settings")
                }
            }
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

// MARK: - General Settings Tab
