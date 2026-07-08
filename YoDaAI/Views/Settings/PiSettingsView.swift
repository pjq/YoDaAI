//
//  PiSettingsView.swift
//  YoDaAI
//
//  Editor for the pi agent's shared configuration (~/.pi/agent/settings.json and
//  models.json), plus a live status panel. Gated on LLMSettings.usePiAgent.
//
//  Editing this config affects the user's terminal pi and Claude Code too, so
//  PiConfigStore writes defensively (merge-edit, .bak, atomic). See PiConfigStore.
//

import SwiftUI
import SwiftData

struct PiSettingsView: View {
    @ObservedObject private var llmSettings = LLMSettings.shared
    @ObservedObject private var config = PiConfigStore.shared

    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var llmProviders: [LLMProvider]

    @State private var editingProvider: PiConfigStore.CustomProvider?
    @State private var status: String = ""
    @State private var statusModel: String = ""
    @State private var isLoadingStatus = false

    private var defaultProvider: LLMProvider? {
        llmProviders.first(where: { $0.isDefault }) ?? llmProviders.first
    }

    /// Provider keys available for the defaultProvider picker (custom + a few built-ins).
    private var providerChoices: [String] {
        let builtins = ["anthropic", "openai", "google", "sapaicore"]
        let custom = config.providers.map(\.key).filter { !$0.isEmpty }
        var seen = Set<String>()
        return (custom + builtins).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            if !llmSettings.usePiAgent {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The pi agent is off", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("These settings configure the pi agent. Enable it in General to use them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Enable pi agent") { llmSettings.usePiAgent = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }

            statusSection
            defaultsSection
            providersSection
            credentialsSection

            if let err = config.lastError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!llmSettings.usePiAgent)
        .sheet(item: $editingProvider) { provider in
            PiProviderDetailSheet(provider: provider) { updated in
                if let idx = config.providers.firstIndex(where: { $0.id == updated.id }) {
                    config.providers[idx] = updated
                    config.saveModels()
                }
            }
        }
        .task { await loadStatus() }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("pi binary") {
                Text(PiExecutable.resolve()?.executable.path ?? "not found")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("Config") {
                Text("~/.pi/agent").font(.system(.caption, design: .monospaced))
            }
            if isLoadingStatus {
                HStack { ProgressView().controlSize(.small); Text("Querying pi…").foregroundStyle(.secondary) }
            } else if !statusModel.isEmpty {
                LabeledContent("Active model", value: statusModel)
            }
            Button("Refresh status") { Task { await loadStatus() } }
                .controlSize(.small)
                .disabled(isLoadingStatus || !llmSettings.usePiAgent)
        }
    }

    // MARK: - Defaults (settings.json)

    private var defaultsSection: some View {
        Section("Defaults") {
            Picker("Default provider", selection: $config.defaultProvider) {
                Text("(pi default)").tag("")
                ForEach(providerChoices, id: \.self) { Text($0).tag($0) }
            }
            TextField("Default model", text: $config.defaultModel)
                .textFieldStyle(.roundedBorder)
            Picker("Thinking level", selection: $config.defaultThinkingLevel) {
                ForEach(PiThinkingLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Hide thinking blocks", isOn: $config.hideThinkingBlock)
            Toggle("Auto-compaction", isOn: $config.compactionEnabled)
            Button("Save defaults") { config.saveSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Text("Merged into ~/.pi/agent/settings.json — other keys are preserved.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Custom Providers (models.json)

    private var providersSection: some View {
        Section {
            if config.providers.isEmpty {
                Text("No custom providers. Add one to use a proxy or local server (Ollama, LM Studio, SAP AI Core, …).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(config.providers) { provider in
                Button {
                    editingProvider = provider
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.key.isEmpty ? "(unnamed)" : provider.key)
                                .fontWeight(.medium)
                            Text("\(provider.api.rawValue) · \(provider.models.count) model(s)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for i in indexSet { config.removeProvider(config.providers[i]) }
                config.saveModels()
            }
            Button {
                config.addProvider()
                if let last = config.providers.last { editingProvider = last }
            } label: {
                Label("Add Provider", systemImage: "plus")
            }
        } header: {
            Text("Custom Providers (models.json)")
        }
    }

    // MARK: - Credentials (auth.json, read-only)

    private var credentialsSection: some View {
        Section("Credentials") {
            if config.authProviderKeys.isEmpty {
                Text("No API keys stored in ~/.pi/agent/auth.json. pi may use environment variables (e.g. $OPENAI_API_KEY) or subscription login. Use `pi` in a terminal and `/login` to add keys.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(config.authProviderKeys, id: \.self) { key in
                    LabeledContent(key) {
                        Label("stored", systemImage: "key.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadStatus() async {
        guard llmSettings.usePiAgent, let provider = defaultProvider else { return }
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        statusModel = await PiChatEngine.shared.activeModelDescription(
            workingDirectory: PiExecutable.scratchDirectory(), provider: provider)
    }
}

// MARK: - Provider Detail Sheet

private struct PiProviderDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var provider: PiConfigStore.CustomProvider
    let onSave: (PiConfigStore.CustomProvider) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Key (e.g. sapaicore, ollama)", text: $provider.key)
                        .textFieldStyle(.roundedBorder)
                    TextField("Display name (optional)", text: $provider.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Base URL", text: $provider.baseUrl)
                        .textFieldStyle(.roundedBorder)
                    Picker("API", selection: $provider.api) {
                        ForEach(PiConfigStore.ProviderAPI.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("API key ($ENV_VAR or literal)", text: $provider.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Supports config-value syntax: $OPENAI_API_KEY, ${VAR}, or !command.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Models") {
                    ForEach($provider.models) { $model in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Model ID", text: $model.modelId)
                                .textFieldStyle(.roundedBorder)
                            TextField("Display name (optional)", text: $model.name)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Reasoning", isOn: $model.reasoning)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { provider.models.remove(atOffsets: $0) }
                    Button {
                        provider.models.append(PiConfigStore.CustomModel(
                            modelId: "", name: "", reasoning: false,
                            contextWindow: nil, maxTokens: nil))
                    } label: {
                        Label("Add Model", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Custom Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(provider); dismiss() }
                        .disabled(provider.key.isEmpty || provider.baseUrl.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 480)
    }
}
