//
//  APIKeysSettingsView.swift
//  YoDaAI
//
//  Extracted from ContentView.swift
//

import SwiftUI
import SwiftData

struct APIKeysSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var providers: [LLMProvider]

    @Query private var legacySettingsRecords: [ProviderSettings]

    @State private var selectedProviderID: LLMProvider.ID?
    @State private var draftName: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftApiKey: String = ""
    @State private var selectedModelID: String = ""
    @State private var fetchedModels: [OpenAIModel] = []
    @State private var isFetchingModels: Bool = false
    @State private var modelsErrorMessage: String?
    @State private var fetchTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false
    @State private var showApiKey = false

    private var selectedProvider: LLMProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var body: some View {
        Form {
            Section("Custom provider") {
                Picker("Choose your provider", selection: $selectedProviderID) {
                    ForEach(providers) { provider in
                        HStack {
                            Text(provider.name)
                            if provider.isDefault {
                                StatusBadge(text: "Default", color: .accentColor)
                            }
                        }
                        .tag(Optional(provider.id))
                    }
                }
                Text("The URL should point to an OpenAI Compatible API")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Provider name", text: $draftName)

                TextField("Base URL", text: $draftBaseURL)
                    .onChange(of: draftBaseURL) {
                        debouncedFetchModels()
                    }
                if !draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
                    HStack {
                        Spacer()
                        Text("Endpoint: \(base)/chat/completions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    if showApiKey {
                        TextField("API key", text: $draftApiKey)
                    } else {
                        SecureField("API key", text: $draftApiKey)
                    }
                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .onChange(of: draftApiKey) {
                    debouncedFetchModels()
                }

                // Model picker with loading states
                if draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Text("Model")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Enter a base URL to discover models")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else if isFetchingModels {
                    HStack {
                        Text("Model")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching models...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if fetchedModels.isEmpty && modelsErrorMessage == nil {
                    HStack {
                        Text("Model")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("No models found")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else if !fetchedModels.isEmpty {
                    Picker("Model", selection: $selectedModelID) {
                        ForEach(fetchedModels) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                }

                if let modelsErrorMessage {
                    Text(modelsErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Manage models") {
                    Task { await fetchModels() }
                }

                HStack {
                    Spacer()
                    Button("Save Provider") {
                        saveSelectedProvider()
                    }
                    .disabled(!hasUnsavedChanges)
                }
            }

            Section("Manage Providers") {
                if providers.isEmpty {
                    ContentUnavailableView {
                        Label("No Providers", systemImage: "key.slash")
                    } description: {
                        Text("Add an LLM provider to start chatting")
                    } actions: {
                        Button("Add Provider") {
                            addProvider()
                        }
                    }
                } else {
                    HStack {
                        Button("Add Provider") {
                            addProvider()
                        }
                        Spacer()
                        Button("Delete", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(providers.count <= 1)
                    }

                    Button("Set as Default") {
                        setSelectedProviderDefault()
                    }
                    .disabled(selectedProvider?.isDefault == true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            migrateLegacyProviderIfNeeded()
            selectInitialProviderIfNeeded()
        }
        .onChange(of: selectedProviderID) {
            loadSelectedProviderDrafts()
        }
        .confirmationDialog("Delete Provider?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteSelectedProvider()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(selectedProvider?.name ?? "this provider")\" and its configuration.")
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let provider = selectedProvider else { return false }
        return provider.name != draftName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            || provider.baseURL != draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            || provider.apiKey != draftApiKey
            || provider.selectedModel != selectedModelID
    }

    private func selectInitialProviderIfNeeded() {
        if selectedProviderID == nil {
            selectedProviderID = providers.first(where: { $0.isDefault })?.id ?? providers.first?.id
        }
        loadSelectedProviderDrafts()
    }

    private func loadSelectedProviderDrafts() {
        guard let selectedProvider else {
            draftName = ""
            draftBaseURL = ""
            draftApiKey = ""
            selectedModelID = ""
            fetchedModels = []
            modelsErrorMessage = nil
            return
        }

        draftName = selectedProvider.name
        draftBaseURL = selectedProvider.baseURL
        draftApiKey = selectedProvider.apiKey
        selectedModelID = selectedProvider.selectedModel

        fetchedModels = []
        modelsErrorMessage = nil

        Task { await fetchModels() }
    }

    private func debouncedFetchModels() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await fetchModels()
        }
    }

    private func fetchModels() async {
        modelsErrorMessage = nil

        let baseURL = draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let apiKey = draftApiKey

        guard !baseURL.isEmpty else {
            fetchedModels = []
            return
        }

        isFetchingModels = true
        defer { isFetchingModels = false }

        do {
            let models = try await OpenAICompatibleClient().listModels(baseURL: baseURL, apiKey: apiKey)
            fetchedModels = models

            if !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id ?? ""
            }
        } catch {
            modelsErrorMessage = error.localizedDescription
            fetchedModels = []
        }
    }

    private func saveSelectedProvider() {
        guard let selectedProvider else { return }

        selectedProvider.name = draftName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.baseURL = draftBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.apiKey = draftApiKey
        selectedProvider.selectedModel = selectedModelID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        selectedProvider.updatedAt = Date()

        Task { try? modelContext.save() }
    }

    private func addProvider() {
        let provider = LLMProvider(
            name: "New Provider",
            baseURL: "http://localhost:11434/v1",
            apiKey: "",
            selectedModel: "",
            isDefault: providers.isEmpty
        )
        modelContext.insert(provider)
        Task { try? modelContext.save() }

        selectedProviderID = provider.id
    }

    private func deleteSelectedProvider() {
        guard let selectedProvider else { return }
        guard providers.count > 1 else { return }

        let wasDefault = selectedProvider.isDefault
        let deletedID = selectedProvider.id

        modelContext.delete(selectedProvider)
        Task { try? modelContext.save() }

        if wasDefault {
            let remaining = providers.filter { $0.id != deletedID }
            if let first = remaining.first {
                first.isDefault = true
                first.updatedAt = Date()
                Task { try? modelContext.save() }
            }
        }

        selectedProviderID = providers.first(where: { $0.id != deletedID })?.id
    }

    private func setSelectedProviderDefault() {
        guard let selectedProvider else { return }
        for provider in providers {
            provider.isDefault = (provider.id == selectedProvider.id)
            provider.updatedAt = Date()
        }
        Task { try? modelContext.save() }
    }

    private func migrateLegacyProviderIfNeeded() {
        guard providers.isEmpty else { return }
        guard let legacy = legacySettingsRecords.first else { return }

        let trimmedBaseURL = legacy.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeOllama = trimmedBaseURL.contains("localhost:11434") || trimmedBaseURL.contains("127.0.0.1:11434")

        // If legacy settings point to Ollama/localhost, skip migration and require explicit setup.
        guard !looksLikeOllama else { return }

        let migrated = LLMProvider(
            name: "Migrated Provider",
            baseURL: legacy.baseURL,
            apiKey: legacy.apiKey,
            selectedModel: legacy.model,
            isDefault: true
        )
        modelContext.insert(migrated)

        // Clean up legacy records after migration
        for record in legacySettingsRecords {
            modelContext.delete(record)
        }

        Task { try? modelContext.save() }

        selectedProviderID = migrated.id
    }
}
