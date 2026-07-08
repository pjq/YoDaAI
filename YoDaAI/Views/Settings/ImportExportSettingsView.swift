import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportExportSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showImportConfirmation = false
    @State private var importFileURL: URL?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isExporting = false
    @State private var isImporting = false

    var body: some View {
        Form {
            Section("Export") {
                Text("Export all chats, providers, MCP servers, permissions, and settings to a JSON file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    exportData()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export All Data")
                    }
                }
                .disabled(isExporting)
            }

            Section("Import") {
                Text("Import data from a previously exported JSON file. This will **replace all existing data** including chats, providers, and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    selectImportFile()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Data")
                    }
                }
                .disabled(isImporting)
            }
        }
        .formStyle(.grouped)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .alert("Replace All Data?", isPresented: $showImportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                performImport()
            }
        } message: {
            Text("This will permanently delete all existing chats, providers, MCP servers, permissions, and settings, then replace them with the imported data.")
        }
    }

    // MARK: - Export

    private func exportData() {
        let panel = NSSavePanel()
        panel.title = "Export YoDaAI Data"
        let dateStr = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "YoDaAI-Backup-\(dateStr).json"
        panel.allowedContentTypes = [.json]

        guard let window = NSApp.keyWindow else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                writeExport(to: url)
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            writeExport(to: url)
        }
    }

    private func writeExport(to url: URL) {
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let data = try await DataExporter.exportAll(context: modelContext)
                try data.write(to: url, options: .atomic)
                alertTitle = "Export Successful"
                alertMessage = "Data exported to \(url.lastPathComponent)"
                showAlert = true
            } catch {
                alertTitle = "Export Failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    // MARK: - Import

    private func selectImportFile() {
        let panel = NSOpenPanel()
        panel.title = "Import YoDaAI Data"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard let window = NSApp.keyWindow else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                importFileURL = url
                showImportConfirmation = true
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            importFileURL = url
            showImportConfirmation = true
        }
    }

    private func performImport() {
        guard let url = importFileURL else { return }
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let data = try Data(contentsOf: url)
                try await DataExporter.importAll(from: data, context: modelContext)
                alertTitle = "Import Successful"
                alertMessage = "All data has been restored. You may need to restart the app for all changes to take effect."
                showAlert = true
            } catch {
                alertTitle = "Import Failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
