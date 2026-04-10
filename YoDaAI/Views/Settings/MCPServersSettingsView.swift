//
//  MCPServersSettingsView.swift
//  YoDaAI
//
//  Extracted from ContentView.swift
//

import SwiftUI
import SwiftData

struct MCPServersSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\MCPServer.name)])
    private var servers: [MCPServer]

    @ObservedObject private var toolRegistry = MCPToolRegistry.shared

    @State private var editingServer: MCPServer?
    @State private var showingAddSheet: Bool = false

    var body: some View {
        Form {
            // MCP Enable Toggle Section
            Section {
                Toggle("Enable MCP Tools", isOn: $toolRegistry.isMCPEnabled)
                    .onChange(of: toolRegistry.isMCPEnabled) { _, newValue in
                        if newValue {
                            Task { await toolRegistry.refreshTools(servers: servers) }
                        } else {
                            toolRegistry.clearCache()
                        }
                    }
            } footer: {
                Text("When enabled, tools from MCP servers are available to the AI assistant")
            }

            // Servers List Section
            Section {
                if servers.isEmpty {
                    ContentUnavailableView {
                        Label("No MCP Servers", systemImage: "server.rack")
                    } description: {
                        Text("Add an MCP server to extend AI capabilities with external tools")
                    } actions: {
                        Button("Add Server") {
                            showingAddSheet = true
                        }
                    }
                } else {
                    ForEach(servers) { server in
                        MCPServerRowView(
                            server: server,
                            toolRegistry: toolRegistry,
                            onEdit: { editingServer = server }
                        )
                    }
                    .onDelete(perform: deleteServers)
                }
            } header: {
                HStack {
                    Text("MCP Servers")
                    Spacer()
                    if !servers.isEmpty {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // Tools Summary Section
            if toolRegistry.isMCPEnabled && !toolRegistry.tools.isEmpty {
                Section("Available Tools (\(toolRegistry.tools.count))") {
                    ForEach(toolRegistry.tools) { toolWithServer in
                        MCPToolRowView(toolWithServer: toolWithServer)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if toolRegistry.isMCPEnabled && !servers.isEmpty && toolRegistry.tools.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
                await toolRegistry.refreshTools(servers: servers)
            }
        }
        .sheet(item: $editingServer) { server in
            MCPServerDetailSheet(server: server, toolRegistry: toolRegistry)
        }
        .sheet(isPresented: $showingAddSheet) {
            MCPServerAddSheet(toolRegistry: toolRegistry)
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = servers[index]
            toolRegistry.removeClient(for: server.endpoint)
            modelContext.delete(server)
        }
        Task { try? modelContext.save() }
    }
}

// MARK: - MCP Server Row View

private struct MCPServerRowView: View {
    var server: MCPServer
    @ObservedObject var toolRegistry: MCPToolRegistry
    var onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext

    private var serverToolsCount: Int {
        toolRegistry.tools.filter { $0.serverEndpoint == server.endpoint }.count
    }

    private var serverStatus: MCPToolRegistry.ServerConnectionStatus {
        toolRegistry.serverStatus[server.endpoint] ?? .unknown
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                MCPStatusIndicator(status: serverStatus)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if !server.isEnabled {
                            StatusBadge(text: "Disabled", color: .secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        MCPStatusTextCompact(status: serverStatus)

                        if serverToolsCount > 0 {
                            Text("\(serverToolsCount) tools")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { server.isEnabled },
                    set: { newValue in
                        server.isEnabled = newValue
                        Task { try? modelContext.save() }

                        if newValue && toolRegistry.isMCPEnabled {
                            Task {
                                await toolRegistry.refreshTools(servers: [server])
                            }
                        } else if !newValue {
                            toolRegistry.removeClient(for: server.endpoint)
                        }
                    }
                ))
                .labelsHidden()
                .onTapGesture {}

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MCP Tool Row View

private struct MCPToolRowView: View {
    let toolWithServer: MCPToolWithServer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(toolWithServer.tool.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(toolWithServer.serverName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            if let description = toolWithServer.tool.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MCP Server Detail Sheet

private struct MCPServerDetailSheet: View {
    var server: MCPServer
    @ObservedObject var toolRegistry: MCPToolRegistry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var draftEndpoint: String = ""
    @State private var draftApiKey: String = ""
    @State private var draftTransport: MCPTransport = .httpStreamable
    @State private var draftTimeout: Int = 60
    @State private var draftToolCallTimeout: Int = 300
    @State private var draftCustomHeaders: [String: String] = [:]
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    @StateObject private var connectionTester = MCPConnectionTester()
    @State private var showDeleteConfirmation: Bool = false

    private var hasUnsavedChanges: Bool {
        server.name != draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            || server.endpoint != draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            || server.apiKey != draftApiKey
            || server.transport != draftTransport
            || server.connectionTimeout != draftTimeout
            || server.toolCallTimeout != draftToolCallTimeout
            || server.customHeaders != draftCustomHeaders
    }

    private var serverStatus: MCPToolRegistry.ServerConnectionStatus {
        toolRegistry.serverStatus[server.endpoint] ?? .unknown
    }

    private var serverTools: [MCPToolWithServer] {
        toolRegistry.tools.filter { $0.serverEndpoint == server.endpoint }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Connection Status
                Section("Connection Status") {
                    HStack {
                        MCPStatusIndicator(status: serverStatus, size: 12)
                        MCPStatusTextDetailed(status: serverStatus)
                        Spacer()

                        if case .error = serverStatus {
                            Button("Retry") { reconnect() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        } else if case .connected = serverStatus {
                            Button("Refresh") { reconnect() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                // Server Configuration
                Section("Server Configuration") {
                    TextField("Name", text: $draftName)
                    TextField("Endpoint URL", text: $draftEndpoint)
                        .textContentType(.URL)
                    Picker("Transport", selection: $draftTransport) {
                        ForEach(MCPTransport.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }
                    SecureField("API Key (optional)", text: $draftApiKey)
                    Picker("Connection Timeout", selection: $draftTimeout) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                    }
                    Picker("Tool Call Timeout", selection: $draftToolCallTimeout) {
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("30 minutes").tag(1800)
                    }
                }

                // Custom Headers
                MCPCustomHeadersEditor(
                    headers: $draftCustomHeaders,
                    newHeaderKey: $newHeaderKey,
                    newHeaderValue: $newHeaderValue,
                    footerText: "Add custom HTTP headers for authentication or other purposes. API Key header is added automatically if set above."
                )

                // Test Connection
                Section {
                    HStack {
                        Button("Test Connection") {
                            connectionTester.test(
                                name: draftName, endpoint: draftEndpoint,
                                transport: draftTransport, apiKey: draftApiKey,
                                timeout: draftTimeout, customHeaders: draftCustomHeaders,
                                toolRegistry: toolRegistry
                            )
                        }
                        .disabled(connectionTester.isTesting || draftEndpoint.isEmpty)

                        if connectionTester.isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        }

                        Spacer()

                        if let result = connectionTester.result {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(connectionTester.success ? .green : .red)
                        }
                    }
                }

                // Available Tools
                if !serverTools.isEmpty {
                    Section("Available Tools (\(serverTools.count))") {
                        ForEach(serverTools) { toolWithServer in
                            MCPToolRowView(toolWithServer: toolWithServer)
                        }
                    }
                }

                // Danger Zone
                Section {
                    Button("Delete Server", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveServer()
                        dismiss()
                    }
                    .disabled(!hasUnsavedChanges)
                }
            }
            .onAppear { loadDrafts() }
            .confirmationDialog("Delete Server?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteServer()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the server and disconnect all its tools.")
            }
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private func loadDrafts() {
        draftName = server.name
        draftEndpoint = server.endpoint
        draftApiKey = server.apiKey
        draftTransport = server.transport
        draftTimeout = server.connectionTimeout
        draftToolCallTimeout = server.toolCallTimeout
        draftCustomHeaders = server.customHeaders
    }

    private func saveServer() {
        server.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        server.endpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        server.apiKey = draftApiKey
        server.transport = draftTransport
        server.connectionTimeout = draftTimeout
        server.toolCallTimeout = draftToolCallTimeout
        server.customHeaders = draftCustomHeaders
        server.updatedAt = Date()
        Task { try? modelContext.save() }
        if server.isEnabled && toolRegistry.isMCPEnabled {
            Task { await toolRegistry.refreshTools(servers: [server]) }
        }
    }

    private func deleteServer() {
        toolRegistry.removeClient(for: server.endpoint)
        modelContext.delete(server)
        Task { try? modelContext.save() }
    }

    private func reconnect() {
        guard server.isEnabled && toolRegistry.isMCPEnabled else { return }
        Task { await toolRegistry.refreshTools(servers: [server]) }
    }
}

// MARK: - MCP Server Add Sheet

private struct MCPServerAddSheet: View {
    @ObservedObject var toolRegistry: MCPToolRegistry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var endpoint: String = "https://"
    @State private var apiKey: String = ""
    @State private var transport: MCPTransport = .sse
    @State private var timeout: Int = 60
    @State private var toolCallTimeout: Int = 300
    @State private var customHeaders: [String: String] = [:]
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    @State private var isEnabled: Bool = true
    @StateObject private var connectionTester = MCPConnectionTester()

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endpoint.hasPrefix("http")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Configuration") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Endpoint URL", text: $endpoint)
                        .textContentType(.URL)
                        .textFieldStyle(.roundedBorder)
                    Picker("Transport", selection: $transport) {
                        ForEach(MCPTransport.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }
                    SecureField("API Key (optional)", text: $apiKey)
                    Picker("Connection Timeout", selection: $timeout) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                    }
                    Picker("Tool Call Timeout", selection: $toolCallTimeout) {
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("30 minutes").tag(1800)
                    }
                    Toggle("Enable after adding", isOn: $isEnabled)
                }

                MCPCustomHeadersEditor(
                    headers: $customHeaders,
                    newHeaderKey: $newHeaderKey,
                    newHeaderValue: $newHeaderValue
                )

                Section {
                    HStack {
                        Button("Test Connection") {
                            connectionTester.test(
                                name: name, endpoint: endpoint,
                                transport: transport, apiKey: apiKey,
                                timeout: timeout, customHeaders: customHeaders,
                                toolRegistry: toolRegistry
                            )
                        }
                        .disabled(connectionTester.isTesting || !isValid)

                        if connectionTester.isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        }

                        Spacer()

                        if let result = connectionTester.result {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(connectionTester.success ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addServer()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func addServer() {
        let server = MCPServer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: transport,
            apiKey: apiKey,
            timeout: timeout
        )
        server.isEnabled = isEnabled
        server.toolCallTimeout = toolCallTimeout
        server.customHeaders = customHeaders
        modelContext.insert(server)
        Task { try? modelContext.save() }
        if isEnabled && toolRegistry.isMCPEnabled {
            Task { await toolRegistry.refreshTools(servers: [server]) }
        }
    }
}
