//
//  AppearanceSettingsView.swift
//  YoDaAI
//
//  Appearance settings: theme, text size, display options
//

import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var llmSettings = LLMSettings.shared
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        Form {
            // Theme
            Section {
                Picker("Theme", selection: $llmSettings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how YoDaAI appears. System follows your macOS appearance.")
            }

            // Text Size
            Section("Text Size") {
                HStack {
                    Text("Scale")
                    Spacer()

                    Button {
                        scaleManager.zoomOut()
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.bordered)
                    .disabled(scaleManager.scale <= AppScaleManager.minScale)

                    Text("\(scaleManager.scalePercentage)%")
                        .frame(width: 50)
                        .monospacedDigit()

                    Button {
                        scaleManager.zoomIn()
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.bordered)
                    .disabled(scaleManager.scale >= AppScaleManager.maxScale)

                    Button("Reset") {
                        scaleManager.resetZoom()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                Text("Use Cmd++ to increase, Cmd+- to decrease, Cmd+0 to reset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Message Display
            Section("Message Display") {
                Toggle("Enable Markdown Rendering", isOn: $llmSettings.enableMarkdown)
                Text("Render assistant messages with rich formatting and syntax highlighting")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Message Timestamps", isOn: $llmSettings.showTimestamps)
                Text("Display the time each message was sent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
