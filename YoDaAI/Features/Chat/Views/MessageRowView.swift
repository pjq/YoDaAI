import SwiftUI
import AppKit

/// Individual message row displaying user or assistant messages
struct MessageRowView: View, Equatable {
    let message: ChatMessage
    let hasAttachments: Bool
    let hasAppContexts: Bool
    let firstAppContext: AppContextAttachment?
    let toolExecutionState: ToolExecutionState?
    let toolExecutionMessageID: UUID?
    let streamingMessageID: UUID?
    let isSending: Bool
    let onRetry: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showCopiedFeedback = false
    @State private var isHovered = false

    @Environment(\.appScaleManager) private var scaleManager

    private enum MessageAction {
        case copy, retry, delete
    }

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.content == rhs.message.content &&
        lhs.hasAttachments == rhs.hasAttachments &&
        lhs.hasAppContexts == rhs.hasAppContexts &&
        lhs.streamingMessageID == rhs.streamingMessageID &&
        lhs.toolExecutionMessageID == rhs.toolExecutionMessageID &&
        lhs.isSending == rhs.isSending
    }

    private var isStreaming: Bool {
        message.role == .assistant && streamingMessageID == message.id
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if hasAttachments {
                    MessageImageGridView(
                        attachments: message.attachments,
                        alignment: message.role == .user ? .trailing : .leading
                    )
                }

                // Message bubble with action toolbar overlaid at bottom
                messageBubble
                    .overlay(alignment: message.role == .user ? .bottomTrailing : .bottomLeading) {
                        if !isStreaming {
                            actionToolbar
                                // Shift upward so toolbar sits just outside the bubble bottom
                                .offset(y: 28)
                                .opacity(isHovered ? 1 : 0)
                                .animation(.easeInOut(duration: 0.12), value: isHovered)
                        }
                    }
                    // Track hover on the bubble itself — no gap possible
                    .onHover { isHovered = $0 }

                // Tool execution card (assistant only)
                if let state = toolExecutionState, toolExecutionMessageID == message.id {
                    MCPToolExecutionCard(state: state).padding(.top, 4)
                }
            }
            // Extra bottom padding to make room for the action toolbar offset
            .padding(.bottom, isStreaming ? 0 : 24)

            if message.role != .user { Spacer(minLength: 60) }
        }
        .alert("Delete Message?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete this message.")
        }
    }

    // MARK: - Message bubble

    @ViewBuilder
    private var messageBubble: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    @ViewBuilder
    private var userBubble: some View {
        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if hasAppContexts, let appContext = firstAppContext {
                // @ Mention context card
                HStack(alignment: .top, spacing: 10) {
                    AppIconView(bundleIdentifier: appContext.bundleIdentifier)
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appContext.appName)
                            .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                        Text(message.content)
                            .font(.system(size: 12 * scaleManager.scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
                )
                .textSelection(.enabled)
            } else {
                Text(message.content)
                    .font(.system(size: 14 * scaleManager.scale))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var assistantBubble: some View {
        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AssistantMessageContentView(content: message.content)
        }
    }

    // MARK: - Action toolbar

    private var actionToolbar: some View {
        HStack(spacing: 4) {
            actionButton(
                systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc",
                help: "Copy",
                tint: showCopiedFeedback ? .green : nil
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                showCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopiedFeedback = false
                }
            }

            actionButton(
                systemImage: "arrow.clockwise",
                help: message.role == .user ? "Resend" : "Regenerate",
                isDisabled: isSending
            ) {
                onRetry()
            }

            actionButton(
                systemImage: "trash",
                help: "Delete",
                tint: .red
            ) {
                showDeleteConfirmation = true
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        // Extend hover area to cover toolbar itself so it stays visible when mouse moves onto it
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func actionButton(
        systemImage: String,
        help: String,
        tint: Color? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12 * scaleManager.scale, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(help)
    }
}
