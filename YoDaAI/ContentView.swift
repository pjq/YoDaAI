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

    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)])
    private var projects: [Project]

    @StateObject private var viewModel = ChatViewModel(
        accessibilityService: AccessibilityService(),
        permissionsStore: AppPermissionsStore()
    )
    @ObservedObject private var floatingPanelController = FloatingPanelController.shared
    @ObservedObject private var mcpToolRegistry = MCPToolRegistry.shared
    @State private var activeThread: ChatThread?
    @State private var activeProject: Project?
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

    /// Loose chats: those not attached to any project, newest first. Shown under
    /// the "Chats" group. Project chats appear under their project section.
    private var looseThreads: [ChatThread] {
        filteredThreads.filter { $0.project == nil }
    }

    /// Chats belonging to a project, newest first, filtered by search.
    private func threads(for project: Project) -> [ChatThread] {
        filteredThreads
            .filter { $0.project?.id == project.id }
            .sorted { $0.createdAt > $1.createdAt }
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
                // MARK: Projects
                Section {
                    ForEach(projects) { project in
                        DisclosureGroup {
                            ForEach(threads(for: project)) { thread in
                                ThreadRowView(thread: thread)
                                    .tag(thread)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { deleteThread(thread) }
                                    }
                            }
                            Button {
                                createNewChat(in: project)
                            } label: {
                                Label("New chat", systemImage: "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        } label: {
                            Label(project.displayName, systemImage: "folder")
                                .contextMenu {
                                    Button("New Chat") { createNewChat(in: project) }
                                    Button("Remove Project", role: .destructive) { removeProject(project) }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("Projects")
                        Spacer()
                        Button(action: addProject) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("Add a project folder")
                    }
                }

                if !looseThreads.isEmpty {
                    Section("Chats") {
                        ForEach(looseThreads) { thread in
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
        .sheet(item: $viewModel.pendingApproval) { approval in
            ApprovalSheet(approval: approval)
        }
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
        // ⌘N / the toolbar "+" always create a loose chat in the "Chats" group
        // (no project). Use a project's own "New chat" button to create one inside
        // that project.
        createNewChat(in: nil)
    }

    private func createNewChat(in project: Project?) {
        let thread = ChatThread(title: "New Chat")
        thread.project = project
        modelContext.insert(thread)
        activeThread = thread
        activeProject = project

        // Save changes (ModelContext must stay on its thread)
        Task {
            try? modelContext.save()
        }

        // Focus the composer after the new thread's view has rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .focusComposer, object: nil)
        }
    }

    /// Present an open panel to pick a directory and create a Project for it.
    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project folder for the agent to work in"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let project = Project(name: url.lastPathComponent, workingDirectory: url.path)
        modelContext.insert(project)
        activeProject = project
        Task { try? modelContext.save() }
    }

    /// Remove a project (chats are nullified back to loose chats, not deleted).
    private func removeProject(_ project: Project) {
        if activeProject?.id == project.id { activeProject = nil }
        // Shut down the pi process for this working directory.
        let dir = URL(fileURLWithPath: project.workingDirectory)
        Task { await PiChatEngine.shared.shutdown(workingDirectory: dir) }
        modelContext.delete(project)
        Task { try? modelContext.save() }
    }

    private func deleteThread(_ thread: ChatThread) {
        let wasActive = activeThread?.id == thread.id
        modelContext.delete(thread)

        if wasActive {
            activeThread = threads.first(where: { $0.id != thread.id })
        }

        // Save changes (ModelContext must stay on its thread)
        Task {
            try? modelContext.save()
        }
    }
}

// MARK: - General Settings Tab
