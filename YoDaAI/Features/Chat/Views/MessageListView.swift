import SwiftUI
import SwiftData

/// Value type wrapper to avoid lazy loading during render
struct MessageDisplayData: Identifiable {
    let id: UUID
    let message: ChatMessage
    let hasAttachments: Bool
    let hasAppContexts: Bool
    let firstAppContext: AppContextAttachment?

    @MainActor
    init(from message: ChatMessage) {
        self.id = message.id
        self.message = message
        self.hasAttachments = !message.attachments.isEmpty
        self.hasAppContexts = !message.appContexts.isEmpty
        self.firstAppContext = message.appContexts.first
    }

    @MainActor
    static func loadMessages(from thread: ChatThread) -> [MessageDisplayData] {
        let sorted = thread.messages.sorted { $0.createdAt < $1.createdAt }
        return sorted.map { MessageDisplayData(from: $0) }
    }
}

/// Scrollable list of messages in a chat thread
struct MessageListView: View {
    @Environment(\.modelContext) private var modelContext
    let thread: ChatThread
    @ObservedObject var viewModel: ChatViewModel

    @State private var displayedMessages: [MessageDisplayData] = []
    @State private var updateTask: Task<Void, Never>?

    /// True when the user is at (or very near) the bottom of the scroll view.
    /// Only auto-scroll for new content when this is true.
    @State private var isAtBottom = true
    @State private var showScrollToBottom = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(messages) { messageData in
                            MessageRowView(
                                message: messageData.message,
                                hasAttachments: messageData.hasAttachments,
                                hasAppContexts: messageData.hasAppContexts,
                                firstAppContext: messageData.firstAppContext,
                                toolExecutionState: viewModel.toolExecutionState,
                                toolExecutionMessageID: viewModel.toolExecutionMessageID,
                                streamingMessageID: viewModel.streamingMessageID,
                                isSending: viewModel.isSending,
                                onRetry: {
                                    Task { await viewModel.retryFrom(message: messageData.message, in: modelContext) }
                                },
                                onDelete: {
                                    viewModel.deleteMessage(messageData.message, in: modelContext)
                                }
                            )
                            .id(messageData.id)
                        }

                        if viewModel.isSending {
                            TypingIndicatorView()
                                .id("typing")
                        }

                        // Invisible bottom anchor for reliable scrolling
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .background(
                    ScrollPositionTracker(isAtBottom: $isAtBottom, showScrollToBottom: $showScrollToBottom)
                )
                // New message added — scroll only if already at bottom
                .onChange(of: messages.count) {
                    if isAtBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // Streaming started — reload list to show new assistant row, scroll if at bottom
                .onChange(of: viewModel.streamingMessageID) { _, newID in
                    if newID != nil {
                        updateTask?.cancel()
                        updateTask = Task { @MainActor in
                            displayedMessages = MessageDisplayData.loadMessages(from: thread)
                            if isAtBottom {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        }
                    }
                }
                // Send started/finished — reload and scroll only if at bottom
                .onChange(of: viewModel.isSending) { _, _ in
                    updateTask?.cancel()
                    updateTask = Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        if isAtBottom {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        // Jump instantly on first load
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: thread.id) { _, _ in
                    updateTask?.cancel()
                    isAtBottom = true
                    showScrollToBottom = false
                    Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshMessages"))) { _ in
                    Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToBottom"))) { _ in
                    isAtBottom = true
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }

            // Scroll-to-bottom FAB — only when user has scrolled up
            if showScrollToBottom {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollToBottom"), object: nil)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }

    private var messages: [MessageDisplayData] { displayedMessages }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Scroll Position Tracker

/// Hooks into the underlying NSScrollView to accurately detect whether the user
/// is at the bottom. This avoids false positives from container resize events.
private struct ScrollPositionTracker: NSViewRepresentable {
    @Binding var isAtBottom: Bool
    @Binding var showScrollToBottom: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.bind(isAtBottom: $isAtBottom, showScrollToBottom: $showScrollToBottom)
        // Attach to scroll view after layout
        DispatchQueue.main.async {
            context.coordinator.attachToScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var isAtBottom: Binding<Bool>?
        private var showScrollToBottom: Binding<Bool>?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        func bind(isAtBottom: Binding<Bool>, showScrollToBottom: Binding<Bool>) {
            self.isAtBottom = isAtBottom
            self.showScrollToBottom = showScrollToBottom
        }

        func attachToScrollView(from view: NSView) {
            var v: NSView? = view
            while v != nil {
                if let sv = v as? NSScrollView {
                    scrollView = sv
                    // Only respond to live user scroll gestures — NOT layout/bounds changes
                    observer = NotificationCenter.default.addObserver(
                        forName: NSScrollView.didLiveScrollNotification,
                        object: sv,
                        queue: .main
                    ) { [weak self] _ in
                        self?.handleLiveScroll(sv)
                    }
                    break
                }
                v = v?.superview
            }
        }

        private func handleLiveScroll(_ sv: NSScrollView) {
            let contentHeight = sv.documentView?.frame.height ?? 0
            let visibleHeight = sv.contentView.bounds.height
            let offsetY = sv.contentView.bounds.origin.y
            let distanceFromBottom = contentHeight - visibleHeight - offsetY
            // User is considered "at bottom" within 60pt — generous to avoid false negatives
            let atBottom = distanceFromBottom < 60

            if isAtBottom?.wrappedValue != atBottom {
                isAtBottom?.wrappedValue = atBottom
            }
            let shouldShow = !atBottom
            if showScrollToBottom?.wrappedValue != shouldShow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollToBottom?.wrappedValue = shouldShow
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

