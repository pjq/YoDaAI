//
//  CachedAppsViews.swift
//  YoDaAI
//
//  Extracted from GeneralSettingsView.swift
//

import SwiftUI
import AppKit

// MARK: - Cached Apps Detail View
struct CachedAppsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var cacheService = ContentCacheService.shared
    @State private var selectedAppBundleId: String?
    @State private var selectedContent: CachedAppContent?

    var body: some View {
        NavigationSplitView {
            // List of cached apps
            List(selection: $selectedAppBundleId) {
                ForEach(cacheService.getAllCachedApps(), id: \.bundleId) { item in
                    CachedAppListRow(bundleId: item.bundleId, content: item.content)
                        .tag(item.bundleId)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Cached Apps (\(cacheService.cache.count))")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        cacheService.clearCache()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .help("Clear all cached content")
                }
            }
        } detail: {
            if let bundleId = selectedAppBundleId,
               let content = cacheService.getCachedContent(for: bundleId) {
                CachedAppContentView(bundleId: bundleId, content: content)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select an app to view cached content")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Cached App List Row
private struct CachedAppListRow: View {
    let bundleId: String
    let content: CachedAppContent

    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
               let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(content.snapshot.appName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Content status
                    let charCount = content.snapshot.focusedValuePreview?.count ?? 0
                    if charCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(content.isOlderThan(60) ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            Text("\(charCount) chars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("No content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(timeAgo(content.capturedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

// MARK: - Cached App Content View
private struct CachedAppContentView: View {
    let bundleId: String
    let content: CachedAppContent
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // App icon
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
                   let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 36))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.snapshot.appName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let windowTitle = content.snapshot.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Copy button
                Button {
                    if let text = content.snapshot.focusedValuePreview {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(content.snapshot.focusedValuePreview == nil)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Metadata
            HStack(spacing: 20) {
                MetadataItem(label: "Characters", value: "\(content.snapshot.focusedValuePreview?.count ?? 0)")
                MetadataItem(label: "Captured", value: formatDate(content.capturedAt))
                MetadataItem(label: "Role", value: content.snapshot.focusedRole ?? "Unknown")
                MetadataItem(label: "Status", value: content.isOlderThan(60) ? "Stale" : "Fresh", color: content.isOlderThan(60) ? .orange : .green)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Content
            if let text = content.snapshot.focusedValuePreview, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No content captured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("The app may not have had any accessible content when captured.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Metadata Item
struct MetadataItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}
