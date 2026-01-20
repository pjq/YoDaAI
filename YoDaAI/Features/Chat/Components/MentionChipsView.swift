import SwiftUI
import AppKit

/// Horizontal scrollable row of mention chips
struct MentionChipsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.mentionedApps) { app in
                    MentionChipView(app: app, viewModel: viewModel)
                }
            }
        }
    }
}

/// Individual mention chip with preview popover
struct MentionChipView: View {
    let app: RunningApp
    @ObservedObject var viewModel: ChatViewModel
    @State private var showPreview = false
    @State private var previewContent: String?
    @State private var windowTitle: String?
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack(spacing: 4) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text("@\(app.appName)")
                .font(.system(size: 11 * scaleManager.scale))

            // Preview button
            Button {
                showPreview = true
                if !hasLoadedOnce {
                    loadPreview()
                }
            } label: {
                Image(systemName: isLoading ? "hourglass" : (previewContent != nil && !previewContent!.isEmpty ? "eye.fill" : "eye"))
                    .font(.system(size: 10 * scaleManager.scale))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(previewContent != nil && !previewContent!.isEmpty ? Color.green : Color.secondary)
            .popover(isPresented: $showPreview) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        VStack(alignment: .leading) {
                            Text(app.appName)
                                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                            if let title = windowTitle, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 11 * scaleManager.scale))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            loadPreview()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11 * scaleManager.scale))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                    }

                    Divider()

                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Capturing content...")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if let content = previewContent, !content.isEmpty {
                        HStack {
                            Text("\(content.count) characters captured")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        ScrollView {
                            Text(content)
                                .font(.system(size: 11 * scaleManager.scale, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 32 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                            Text("No content captured")
                                .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Click refresh to capture content.\nThe app will briefly activate to read its content.")
                                .font(.system(size: 11 * scaleManager.scale))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding()
                .frame(width: 450)
                .frame(minHeight: 150)
            }

            // Remove button
            Button {
                viewModel.removeMention(app)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10 * scaleManager.scale))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
        .onAppear {
            // Auto-load preview when chip appears
            loadPreview()
        }
    }

    private func loadPreview() {
        isLoading = true
        hasLoadedOnce = true
        Task { @MainActor in
            // First try to use globally cached content from floating panel
            if let globalCached = ContentCacheService.shared.getCachedSnapshot(for: app.bundleIdentifier) {
                print("[MentionChipView] Using cached content from floating panel for \(app.appName)")
                previewContent = globalCached.focusedValuePreview
                windowTitle = globalCached.windowTitle
                isLoading = false
                viewModel.updateMentionContext(for: app.bundleIdentifier, snapshot: globalCached)
                return
            }

            // Otherwise, capture by activating the app
            let snapshot = await viewModel.accessibilityService.captureContextWithActivation(for: app.bundleIdentifier, promptIfNeeded: false)
            previewContent = snapshot?.focusedValuePreview
            windowTitle = snapshot?.windowTitle
            isLoading = false

            // Cache the snapshot in the ViewModel so it's available when sending
            viewModel.updateMentionContext(for: app.bundleIdentifier, snapshot: snapshot)
        }
    }
}
