import SwiftUI
import SwiftData
import AppKit

// MARK: - Mention Picker Popover
struct MentionPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @Environment(\.appScaleManager) private var scaleManager

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

// MARK: - Slash Command Picker Popover
struct SlashCommandPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appScaleManager) private var scaleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Commands")
                    .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                Spacer()
                Text("Type / to see commands")
                    .font(.system(size: 11 * scaleManager.scale))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Command list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.filteredSlashCommands.isEmpty {
                        Text("No matching commands")
                            .font(.system(size: 11 * scaleManager.scale))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.filteredSlashCommands) { command in
                            Button {
                                selectCommand(command)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: command.icon)
                                        .frame(width: 20, height: 20)
                                        .foregroundStyle(.blue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(command.displayName)
                                            .font(.system(size: 14 * scaleManager.scale, weight: .medium))
                                        Text(command.description)
                                            .font(.system(size: 10 * scaleManager.scale))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
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

    private func selectCommand(_ command: SlashCommand) {
        viewModel.composerText = command.displayName
        dismiss()
    }
}

// MARK: - Model Picker Popover
struct ModelPickerPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let providers: [LLMProvider]
    @Environment(\.appScaleManager) private var scaleManager

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

// MARK: - pi Model Picker Popover

/// Lists the pi agent's available models and switches the active one. Used for
/// pi chats (project chats + loose chats in pi mode) instead of the LLMProvider
/// picker.
struct PiModelPickerPopover: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var piConfig = PiConfigStore.shared
    @Environment(\.appScaleManager) private var scaleManager
    let workingDirectory: URL

    @State private var models: [PiChatEngine.PiModel] = []
    @State private var isLoading = true
    @State private var search = ""

    private var currentID: String {
        "\(piConfig.defaultProvider)/\(piConfig.defaultModel)"
    }

    /// Provider keys defined in the user's models.json (their proxy/local servers).
    private var customProviderKeys: Set<String> {
        Set(piConfig.providers.map(\.key).filter { !$0.isEmpty })
    }

    /// Models to show: custom-provider (user-configured) models first, then the
    /// built-ins, filtered by the search text.
    private var filteredModels: [PiChatEngine.PiModel] {
        let custom = customProviderKeys
        let matched = models.filter { m in
            search.isEmpty
                || m.name.localizedCaseInsensitiveContains(search)
                || m.modelId.localizedCaseInsensitiveContains(search)
                || m.provider.localizedCaseInsensitiveContains(search)
        }
        return matched.sorted { a, b in
            let aCustom = custom.contains(a.provider)
            let bCustom = custom.contains(b.provider)
            if aCustom != bCustom { return aCustom }       // custom providers first
            if a.provider != b.provider { return a.provider < b.provider }
            return a.name < b.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("pi Model")
                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search models", text: $search)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 12 * scaleManager.scale))
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading models…").foregroundStyle(.secondary)
                }
                .font(.system(size: 12 * scaleManager.scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if models.isEmpty {
                Text("No models available. Check the pi Agent settings.")
                    .font(.system(size: 12 * scaleManager.scale))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredModels) { model in
                            Button {
                                Task {
                                    await PiChatEngine.shared.setModel(model, workingDirectory: workingDirectory)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.name)
                                            .font(.system(size: 13 * scaleManager.scale))
                                        Text(model.provider)
                                            .font(.system(size: 11 * scaleManager.scale))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.id == currentID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(model.id == currentID ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 320, height: 440)
        .task {
            models = await PiChatEngine.shared.availableModels(workingDirectory: workingDirectory)
            isLoading = false
        }
    }
}
