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
    
    @Query(sort: [SortDescriptor(\MCPServer.updatedAt, order: .reverse)])
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
                            // Auto-connect all enabled servers when MCP is enabled
                            Task { await toolRegistry.refreshTools(servers: servers) }
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
            
            // Tools Summary Section (when enabled and has tools)
            if toolRegistry.isMCPEnabled && !toolRegistry.tools.isEmpty {
                Section("Available Tools (\(toolRegistry.tools.count))") {
                    ForEach(toolRegistry.tools) { toolWithServer in
                        MCPToolRowView(toolWithServer: toolWithServer)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .id(toolRegistry.tools.count) // Force refresh when tools count changes
        .task {
            // Only refresh if tools haven't been loaded yet (fallback if app startup task hasn't run)
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
        try? modelContext.save()
    }
}

// MARK: - MCP Server Row View

private struct MCPServerRowView: View {
    var server: MCPServer
    @ObservedObject var toolRegistry: MCPToolRegistry
    var onEdit: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    // Tools count for this server
    private var serverToolsCount: Int {
        toolRegistry.tools.filter { $0.serverEndpoint == server.endpoint }.count
    }
    
    private var serverStatus: MCPToolRegistry.ServerConnectionStatus {
        toolRegistry.serverStatus[server.endpoint] ?? .unknown
    }
    
    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                // Status indicator
                statusIndicator
                
                // Server info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if !server.isEnabled {
                            Text("Disabled")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Status text and tools count
                    HStack(spacing: 8) {
                        statusText
                        
                        if serverToolsCount > 0 {
                            Text("\(serverToolsCount) tools")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Enable toggle (stop propagation to prevent triggering edit)
                Toggle("", isOn: Binding(
                    get: { server.isEnabled },
                    set: { newValue in
                        server.isEnabled = newValue
                        server.updatedAt = Date()
                        try? modelContext.save()
                        
                        if newValue && toolRegistry.isMCPEnabled {
                            // Auto-connect when enabled
                            Task {
                                await toolRegistry.refreshTools(servers: [server])
                            }
                        } else if !newValue {
                            // Disconnect when disabled
                            toolRegistry.removeClient(for: server.endpoint)
                        }
                    }
                ))
                .labelsHidden()
                .onTapGesture {} // Prevent row tap
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch serverStatus {
        case .unknown:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)
        case .connecting:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch serverStatus {
        case .unknown:
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting...")
                .font(.caption)
                .foregroundStyle(.orange)
        case .connected(let name, let version):
            if let name = name {
                Text("\(name)\(version.map { " v\($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .error(let message):
            Text("Error")
                .font(.caption)
                .foregroundStyle(.red)
                .help(message)
        }
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
    @State private var draftCustomHeaders: [String: String] = [:]
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: String?
    @State private var connectionTestSuccess: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    private var hasUnsavedChanges: Bool {
        server.name != draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            || server.endpoint != draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            || server.apiKey != draftApiKey
            || server.transport != draftTransport
            || server.connectionTimeout != draftTimeout
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
                // Connection Status Section
                Section("Connection Status") {
                    HStack {
                        statusIndicator
                        statusText
                        Spacer()
                        
                        if case .error = serverStatus {
                            Button("Retry") {
                                reconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if case .connected = serverStatus {
                            Button("Refresh") {
                                reconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                
                // Server Configuration Section
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
                }
                
                // Custom Headers Section
                Section {
                    ForEach(draftCustomHeaders.keys.sorted(), id: \.self) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.headline)
                                Text(draftCustomHeaders[key] ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                draftCustomHeaders.removeValue(forKey: key)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Add new header
                    HStack {
                        TextField("Header Name", text: $newHeaderKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Value", text: $newHeaderValue)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let key = newHeaderKey.trimmingCharacters(in: .whitespaces)
                            let value = newHeaderValue.trimmingCharacters(in: .whitespaces)
                            if !key.isEmpty && !value.isEmpty {
                                draftCustomHeaders[key] = value
                                newHeaderKey = ""
                                newHeaderValue = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newHeaderKey.trimmingCharacters(in: .whitespaces).isEmpty || newHeaderValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Custom Headers")
                } footer: {
                    Text("Add custom HTTP headers for authentication or other purposes. API Key header is added automatically if set above.")
                }
                
                // Test Connection Section
                Section {
                    HStack {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(isTestingConnection || draftEndpoint.isEmpty)
                        
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        }
                        
                        Spacer()
                        
                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(connectionTestSuccess ? .green : .red)
                        }
                    }
                }
                
                // Available Tools Section
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveServer()
                        dismiss()
                    }
                    .disabled(!hasUnsavedChanges)
                }
            }
            .onAppear {
                loadDrafts()
            }
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
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch serverStatus {
        case .unknown:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 12, height: 12)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch serverStatus {
        case .unknown:
            Text("Not connected")
                .foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting...")
                .foregroundStyle(.orange)
        case .connected(let name, let version):
            VStack(alignment: .leading) {
                Text("Connected")
                    .foregroundStyle(.green)
                if let name = name {
                    Text("\(name)\(version.map { " v\($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .error(let message):
            VStack(alignment: .leading) {
                Text("Connection Error")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    private func loadDrafts() {
        draftName = server.name
        draftEndpoint = server.endpoint
        draftApiKey = server.apiKey
        draftTransport = server.transport
        draftTimeout = server.connectionTimeout
        draftCustomHeaders = server.customHeaders
    }
    
    private func saveServer() {
        server.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        server.endpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        server.apiKey = draftApiKey
        server.transport = draftTransport
        server.connectionTimeout = draftTimeout
        server.customHeaders = draftCustomHeaders
        server.updatedAt = Date()
        
        try? modelContext.save()
        
        // Reconnect if enabled
        if server.isEnabled && toolRegistry.isMCPEnabled {
            Task { await toolRegistry.refreshTools(servers: [server]) }
        }
    }
    
    private func deleteServer() {
        toolRegistry.removeClient(for: server.endpoint)
        modelContext.delete(server)
        try? modelContext.save()
    }
    
    private func reconnect() {
        guard server.isEnabled && toolRegistry.isMCPEnabled else { return }
        Task { await toolRegistry.refreshTools(servers: [server]) }
    }
    
    private func testConnection() {
        let testServer = MCPServer(
            name: draftName,
            endpoint: draftEndpoint,
            transport: draftTransport,
            apiKey: draftApiKey,
            timeout: draftTimeout
        )
        testServer.customHeaders = draftCustomHeaders
        
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                let result = try await toolRegistry.testConnection(server: testServer)
                await MainActor.run {
                    connectionTestSuccess = true
                    if let name = result.serverName {
                        connectionTestResult = "Connected to \(name)"
                    } else {
                        connectionTestResult = "Connected successfully"
                    }
                }
            } catch {
                await MainActor.run {
                    connectionTestSuccess = false
                    connectionTestResult = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isTestingConnection = false
            }
        }
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
    @State private var customHeaders: [String: String] = [:]
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    @State private var isEnabled: Bool = true
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: String?
    @State private var connectionTestSuccess: Bool = false
    
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
                    
                    Toggle("Enable after adding", isOn: $isEnabled)
                }
                
                // Custom Headers Section
                Section {
                    ForEach(customHeaders.keys.sorted(), id: \.self) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.headline)
                                Text(customHeaders[key] ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                customHeaders.removeValue(forKey: key)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Add new header
                    HStack {
                        TextField("Header Name", text: $newHeaderKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Value", text: $newHeaderValue)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let key = newHeaderKey.trimmingCharacters(in: .whitespaces)
                            let value = newHeaderValue.trimmingCharacters(in: .whitespaces)
                            if !key.isEmpty && !value.isEmpty {
                                customHeaders[key] = value
                                newHeaderKey = ""
                                newHeaderValue = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newHeaderKey.trimmingCharacters(in: .whitespaces).isEmpty || newHeaderValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Custom Headers")
                } footer: {
                    Text("Add custom HTTP headers for authentication or other purposes.")
                }
                
                Section {
                    HStack {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(isTestingConnection || !isValid)
                        
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        }
                        
                        Spacer()
                        
                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(connectionTestSuccess ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
        server.customHeaders = customHeaders
        
        modelContext.insert(server)
        try? modelContext.save()
        
        // Auto-connect if enabled
        if isEnabled && toolRegistry.isMCPEnabled {
            Task { await toolRegistry.refreshTools(servers: [server]) }
        }
    }
    
    private func testConnection() {
        let testServer = MCPServer(
            name: name,
            endpoint: endpoint,
            transport: transport,
            apiKey: apiKey,
            timeout: timeout
        )
        testServer.customHeaders = customHeaders
        
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                let result = try await toolRegistry.testConnection(server: testServer)
                await MainActor.run {
                    connectionTestSuccess = true
                    if let name = result.serverName {
                        connectionTestResult = "Connected to \(name)"
                    } else {
                        connectionTestResult = "Connected successfully"
                    }
                }
            } catch {
                await MainActor.run {
                    connectionTestSuccess = false
                    connectionTestResult = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isTestingConnection = false
            }
        }
    }
}

// MARK: - Permissions Settings Tab
