//
//  GeneralSettingsView.swift
//  YoDaAI
//
//  Extracted from ContentView.swift
//

import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var floatingPanelController = FloatingPanelController.shared
    @ObservedObject var cacheService = ContentCacheService.shared
    @ObservedObject var llmSettings = LLMSettings.shared
    @State private var showCachedAppsSheet = false
    @State private var showResetConfirmation = false
    @State private var showClearCacheConfirmation = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            // Startup
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert on failure
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Automatically open YoDaAI when you log in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("LLM Settings") {
                // Temperature slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", llmSettings.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $llmSettings.temperature, in: 0...2, step: 0.1)
                }
                Text("Higher values make output more random, lower values more deterministic")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Max tokens
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    TextField("", value: $llmSettings.maxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum number of tokens in the response (0 = no limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Max message count
                HStack {
                    Text("Max Message History")
                    Spacer()
                    TextField("", value: $llmSettings.maxMessageCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum messages to include in context (0 = all)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // System prompt toggle and text
                Toggle("Use System Prompt", isOn: $llmSettings.useSystemPrompt)

                if llmSettings.useSystemPrompt {
                    TextEditor(text: $llmSettings.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Text("Instructions sent to the model at the start of each conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Reset button
                Button("Reset to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)
            }

            Section("Floating Panel") {
                Toggle("Show floating capture panel", isOn: Binding(
                    get: { floatingPanelController.isVisible },
                    set: { newValue in
                        if newValue {
                            floatingPanelController.show()
                        } else {
                            floatingPanelController.hide()
                        }
                    }
                ))
                Text("Continuously capture content from the foreground app")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Custom title setting
                TextField("Panel title", text: $floatingPanelController.customTitle)
                Text("Customize the floating panel title (e.g., \"Jianqing's YoDaAI\")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if floatingPanelController.isVisible {
                    // Cached apps row - clickable
                    Button {
                        showCachedAppsSheet = true
                    } label: {
                        HStack {
                            Text("Cached apps")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(cacheService.cache.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle("Auto-capture enabled", isOn: $cacheService.isCaptureEnabled)

                    Button("Clear Cache") {
                        showClearCacheConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("App Context") {
                Toggle("Always attach app context", isOn: $llmSettings.alwaysAttachAppContext)
                Text("Include frontmost app info when sending messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Text("YoDaAI")
                    Spacer()
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCachedAppsSheet) {
            CachedAppsDetailView()
        }
        .confirmationDialog("Reset LLM Settings?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) {
                llmSettings.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset temperature, max tokens, message history, and system prompt to their default values.")
        }
        .confirmationDialog("Clear Cache?", isPresented: $showClearCacheConfirmation, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                cacheService.clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all cached app content.")
        }
    }
}
