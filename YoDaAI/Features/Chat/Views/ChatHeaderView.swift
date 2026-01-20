import SwiftUI
import SwiftData
import AppKit

/// Chat header view with title and action buttons
struct ChatHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    let modelName: String
    var onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("C")
                        .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(thread.title)
                    .font(.system(size: 14 * scaleManager.scale, weight: .semibold))
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    // Share: copy thread as markdown
                    let markdown = exportThreadAsMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Export as Markdown")

                Button {
                    // Copy all messages
                    let text = thread.messages
                        .sorted { $0.createdAt < $1.createdAt }
                        .map { "\($0.role == .user ? "You" : "Assistant"): \($0.content)" }
                        .joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy Conversation")

                Button {
                    // Copy link (placeholder - could be deep link)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("yodaai://chat/\(thread.id.uuidString)", forType: .string)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy Link")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete Chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Delete Chat?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will permanently delete \"\(thread.title)\" and all its messages.")
        }
    }

    private func exportThreadAsMarkdown() -> String {
        var lines: [String] = []
        lines.append("# \(thread.title)")
        lines.append("")

        for message in thread.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            let role = message.role == .user ? "**You**" : "**Assistant**"
            lines.append("\(role):")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
