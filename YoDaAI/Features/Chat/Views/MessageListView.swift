import SwiftUI
import SwiftData

/// Scrollable list of messages in a chat thread
struct MessageListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [ChatMessage]
    @ObservedObject var viewModel: ChatViewModel

    // PERFORMANCE: Track last scrolled message to avoid redundant scroll animations
    @State private var lastScrolledMessageID: UUID?

    init(thread: ChatThread, viewModel: ChatViewModel) {
        let threadId = thread.id
        _messages = Query(filter: #Predicate<ChatMessage> { message in
            message.thread?.id == threadId
        }, sort: \ChatMessage.createdAt)
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(messages) { message in
                        MessageRowView(
                            message: message,
                            toolExecutionState: viewModel.toolExecutionState,
                            toolExecutionMessageID: viewModel.toolExecutionMessageID,
                            streamingMessageID: viewModel.streamingMessageID,
                            isSending: viewModel.isSending,
                            onRetry: {
                                Task { await viewModel.retryFrom(message: message, in: modelContext) }
                            },
                            onDelete: {
                                viewModel.deleteMessage(message, in: modelContext)
                            }
                        )
                        .id(message.id)
                    }

                    if viewModel.isSending {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: messages.count) {
                // PERFORMANCE: Only scroll if we have a new message
                // This prevents redundant scrolling during streaming updates
                if let lastMessageID = messages.last?.id, lastMessageID != lastScrolledMessageID {
                    lastScrolledMessageID = lastMessageID
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessageID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isSending) { _, isSending in
                // PERFORMANCE: Only scroll when starting to send, not on every state change
                if isSending {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }
}
