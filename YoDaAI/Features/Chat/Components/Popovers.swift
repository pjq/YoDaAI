import SwiftUI
import SwiftData
import AppKit

// MARK: - Mention Picker Popover
struct MentionPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @ObservedObject private var scaleManager = AppScaleManager.shared

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
    @ObservedObject private var scaleManager = AppScaleManager.shared

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
    @ObservedObject private var scaleManager = AppScaleManager.shared

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
