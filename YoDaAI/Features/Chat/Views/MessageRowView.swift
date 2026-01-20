import SwiftUI
import AppKit

/// Individual message row displaying user or assistant messages
struct MessageRowView: View {
    let message: ChatMessage
    // PERFORMANCE: Only pass the specific properties needed, not entire viewModel
    let toolExecutionState: ToolExecutionState?
    let toolExecutionMessageID: UUID?
    let streamingMessageID: UUID?
    let isSending: Bool
    let onRetry: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var pressedAction: MessageAction?
    @State private var showCopiedFeedback = false


    @ObservedObject private var scaleManager = AppScaleManager.shared

    private enum MessageAction {
        case copy
        case retry
        case delete
    }

    var body: some View {
        HStack(alignment: .top) {
            // User messages (including context cards) are right-aligned
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Show attached images
                if !message.attachments.isEmpty {
                    MessageImageGridView(attachments: message.attachments, alignment: message.role == .user ? .trailing : .leading)
                }

                if message.role == .user {
                    // Check if this is an @ mention context message
                    let isContextMessage = !message.appContexts.isEmpty

                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if isContextMessage, let appContext = message.appContexts.first {
                            // @ Mention context card - styled differently
                            HStack(alignment: .top, spacing: 10) {
                                AppIconView(bundleIdentifier: appContext.bundleIdentifier)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appContext.appName)
                                        .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                                        .foregroundStyle(.primary)

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
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .textSelection(.enabled)
                        } else {
                            // Regular user message: right-aligned bubble
                            Text(message.content)
                                .font(.system(size: 14 * scaleManager.scale))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    // Assistant message: Markdown rendered with tool call support
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        AssistantMessageContentView(content: message.content)
                    }

                    // Show tool execution card if this message has active tool execution
                    if let state = toolExecutionState,
                       toolExecutionMessageID == message.id {
                        MCPToolExecutionCard(state: state)
                            .padding(.top, 8)
                    }
                }

                let isStreamingAssistantMessage = (message.role == .assistant && streamingMessageID == message.id)
                if !isStreamingAssistantMessage {
                    HStack(spacing: 8) {
                        actionButton(
                            action: .copy,
                            systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc",
                            help: "Copy",
                            isDestructive: false,
                            isDisabled: false
                        ) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)

                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                showCopiedFeedback = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showCopiedFeedback = false
                                }
                            }
                        }

                        actionButton(
                            action: .retry,
                            systemImage: "arrow.clockwise",
                            help: message.role == .user ? "Resend" : "Regenerate",
                            isDestructive: false,
                            isDisabled: isSending
                        ) {
                            onRetry()
                        }

                        actionButton(
                            action: .delete,
                            systemImage: "trash",
                            help: "Delete",
                            isDestructive: true,
                            isDisabled: false
                        ) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }

            // Add spacer on right for assistant messages only
            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
        .alert("Delete Message?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This message will be permanently deleted.")
        }
    }

    @ViewBuilder
    private func actionButton(
        action: MessageAction,
        systemImage: String,
        help: String,
        isDestructive: Bool,
        isDisabled: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        let isShowingFeedback = (action == .copy && showCopiedFeedback)

        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) {
                pressedAction = action
            }

            onTap()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    if pressedAction == action {
                        pressedAction = nil
                    }
                }
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13 * scaleManager.scale, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .opacity(0.9)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .scaleEffect(pressedAction == action ? 0.92 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressedAction)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isShowingFeedback ? .green :
            isDestructive ? Color.red.opacity(0.9) :
            Color.secondary
        )
        .help(help)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }
}
