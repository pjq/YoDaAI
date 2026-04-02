//
//  MCPSharedComponents.swift
//  YoDaAI
//
//  Shared UI components for MCP server settings
//

import SwiftUI
import Combine

// MARK: - Status Indicator

struct MCPStatusIndicator: View {
    let status: MCPToolRegistry.ServerConnectionStatus
    var size: CGFloat = 10

    var body: some View {
        switch status {
        case .unknown:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: size, height: size)
        case .connecting:
            ProgressView()
                .controlSize(size <= 10 ? .mini : .small)
                .frame(width: size, height: size)
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Status Text (compact, for row views)

struct MCPStatusTextCompact: View {
    let status: MCPToolRegistry.ServerConnectionStatus

    var body: some View {
        switch status {
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

// MARK: - Status Text (detailed, for detail sheets)

struct MCPStatusTextDetailed: View {
    let status: MCPToolRegistry.ServerConnectionStatus

    var body: some View {
        switch status {
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
}

// MARK: - Custom Headers Editor

struct MCPCustomHeadersEditor: View {
    @Binding var headers: [String: String]
    @Binding var newHeaderKey: String
    @Binding var newHeaderValue: String
    var footerText: String = "Add custom HTTP headers for authentication or other purposes."

    var body: some View {
        Section {
            ForEach(headers.keys.sorted(), id: \.self) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key)
                            .font(.headline)
                        Text(headers[key] ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        headers.removeValue(forKey: key)
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
                        headers[key] = value
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
            Text(footerText)
        }
    }
}

// MARK: - Connection Tester

@MainActor
final class MCPConnectionTester: ObservableObject {
    @Published var isTesting = false
    @Published var result: String?
    @Published var success = false

    func test(name: String, endpoint: String, transport: MCPTransport, apiKey: String, timeout: Int, customHeaders: [String: String], toolRegistry: MCPToolRegistry) {
        let testServer = MCPServer(
            name: name,
            endpoint: endpoint,
            transport: transport,
            apiKey: apiKey,
            timeout: timeout
        )
        testServer.customHeaders = customHeaders

        isTesting = true
        result = nil

        Task {
            do {
                let testResult = try await toolRegistry.testConnection(server: testServer)
                success = true
                if let serverName = testResult.serverName {
                    result = "Connected to \(serverName)"
                } else {
                    result = "Connected successfully"
                }
            } catch {
                success = false
                result = error.localizedDescription
            }
            isTesting = false
        }
    }
}

// MARK: - Test Connection Section

struct MCPTestConnectionSection: View {
    @ObservedObject var tester: MCPConnectionTester
    var isDisabled: Bool

    var body: some View {
        Section {
            HStack {
                Button("Test Connection") {
                    // Caller must invoke tester.test() — this is just the UI shell
                }
                .disabled(tester.isTesting || isDisabled)

                if tester.isTesting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                }

                Spacer()

                if let result = tester.result {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(tester.success ? .green : .red)
                }
            }
        }
    }
}
