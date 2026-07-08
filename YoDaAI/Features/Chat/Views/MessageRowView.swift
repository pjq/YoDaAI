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

    private var hasContent: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasToolCard: Bool {
        toolExecutionState != nil && toolExecutionMessageID == message.id
    }

    /// An assistant message that finished with no text and no tool activity —
    /// e.g. the agent produced no response. We show a subtle placeholder instead
    /// of an empty row with floating action buttons.
    private var isEmptyAssistantResult: Bool {
        message.role == .assistant && !hasContent && !isStreaming && !hasToolCard
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if hasAttachments {
                    MessageImageGridView(
                        attachments: message.attachments,
                        alignment: message.role == .user ? .trailing : .leading
                    )
                }

                if isEmptyAssistantResult {
                    // No text and no tool activity: show a quiet placeholder with
                    // just a retry affordance, instead of an empty row.
                    emptyResultRow
                } else {
                    // Message bubble
                    messageBubble

                    // Inline action toolbar — only when there's something to act on
                    // (real content or attachments) and not while streaming.
                    if !isStreaming && (hasContent || hasAttachments) {
                        actionToolbar
                            .padding(.top, 2)
                    }

                    // Tool execution card (assistant only)
                    if let state = toolExecutionState, toolExecutionMessageID == message.id {
                        MCPToolExecutionCard(state: state).padding(.top, 4)
                    }
                }
            }

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

    // MARK: - Empty assistant result

    private var emptyResultRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(.tertiary)
            Text("No response")
                .font(.system(size: 13 * scaleManager.scale))
                .foregroundStyle(.secondary)
            Button {
                onRetry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12 * scaleManager.scale))
            }
            .buttonStyle(.borderless)
            .disabled(isSending)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Action toolbar (inline, flat style)

    private var actionToolbar: some View {
        HStack(spacing: 2) {
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
                help: "Delete"
            ) {
                showDeleteConfirmation = true
            }
        }
        .padding(.horizontal, 2)
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
                .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary.opacity(0.7))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(help)
    }
}
