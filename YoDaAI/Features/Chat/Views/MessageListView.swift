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

    /// Tracker instance held in state so we can call scrollToBottom on it directly.
    @State private var scrollTracker = ScrollPositionTracker.Coordinator()

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
                    ScrollPositionTrackerView(
                        coordinator: scrollTracker,
                        isAtBottom: $isAtBottom,
                        showScrollToBottom: $showScrollToBottom
                    )
                )
                // New message added — scroll only if already at bottom
                .onChange(of: messages.count) {
                    if isAtBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // Streaming started → reload list for new row + start smooth auto-scroll
                // Streaming ended → stop auto-scroll
                .onChange(of: viewModel.streamingMessageID) { _, newID in
                    updateTask?.cancel()
                    updateTask = Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        if newID != nil {
                            // Start streaming: scroll to bottom immediately, then keep tracking
                            if isAtBottom {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                            scrollTracker.startStreamingScroll()
                        } else {
                            // Streaming finished
                            scrollTracker.stopStreamingScroll()
                        }
                    }
                }
                // Send started/finished — reload and scroll only if at bottom
                .onChange(of: viewModel.isSending) { _, newVal in
                    updateTask?.cancel()
                    updateTask = Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        if isAtBottom {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                        if !newVal {
                            scrollTracker.stopStreamingScroll()
                        }
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: thread.id) { _, _ in
                    updateTask?.cancel()
                    scrollTracker.stopStreamingScroll()
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
                    scrollTracker.stopStreamingScroll()
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
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Scroll Position Tracker

/// NSViewRepresentable wrapper that injects a pre-created Coordinator into the view hierarchy.
private struct ScrollPositionTrackerView: NSViewRepresentable {
    let coordinator: ScrollPositionTracker.Coordinator
    @Binding var isAtBottom: Bool
    @Binding var showScrollToBottom: Bool

    func makeCoordinator() -> ScrollPositionTracker.Coordinator { coordinator }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.bind(isAtBottom: $isAtBottom, showScrollToBottom: $showScrollToBottom)
        DispatchQueue.main.async {
            context.coordinator.attachToScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Coordinator that hooks into the underlying NSScrollView for:
/// 1. Tracking user scroll position (live scroll only, no layout-triggered jumps)
/// 2. Smooth streaming auto-scroll using CVDisplayLink (60 fps)
private struct ScrollPositionTracker {

    final class Coordinator: NSObject {
        private var isAtBottom: Binding<Bool>?
        private var showScrollToBottom: Binding<Bool>?
        private weak var scrollView: NSScrollView?
        private var liveScrollObserver: NSObjectProtocol?

        // Timer fires every ~16ms (≈60fps) during streaming for smooth auto-scroll
        private var streamTimer: Timer?
        private var isStreamingScrolling = false

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
                    liveScrollObserver = NotificationCenter.default.addObserver(
                        forName: NSScrollView.didLiveScrollNotification,
                        object: sv,
                        queue: .main
                    ) { [weak self] _ in
                        guard let self else { return }
                        self.handleLiveScroll(sv)
                        // If user scrolls up during streaming, stop auto-scroll
                        if self.isStreamingScrolling {
                            let dist = self.distanceFromBottom(sv)
                            if dist > 80 { self.stopStreamingScroll() }
                        }
                    }
                    break
                }
                v = v?.superview
            }
        }

        // MARK: Streaming scroll

        /// Start a ~60fps timer that continuously scrolls to bottom during streaming.
        /// Each tick animates a short easing curve so motion is butter-smooth.
        func startStreamingScroll() {
            guard !isStreamingScrolling else { return }
            isStreamingScrolling = true
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.scrollToBottomNow()
            }
            RunLoop.main.add(timer, forMode: .common)
            streamTimer = timer
        }

        func stopStreamingScroll() {
            isStreamingScrolling = false
            streamTimer?.invalidate()
            streamTimer = nil
        }

        // MARK: Helpers

        private func scrollToBottomNow() {
            guard let sv = scrollView,
                  let docView = sv.documentView else { return }
            let maxY = max(0, docView.frame.height - sv.contentView.bounds.height)
            let currentY = sv.contentView.bounds.origin.y
            guard maxY > currentY + 1 else { return }  // already at bottom
            // Use NSAnimationContext for smooth per-frame easing
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sv.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: maxY))
                sv.reflectScrolledClipView(sv.contentView)
            }
        }

        private func distanceFromBottom(_ sv: NSScrollView) -> CGFloat {
            let contentHeight = sv.documentView?.frame.height ?? 0
            let visibleHeight = sv.contentView.bounds.height
            let offsetY = sv.contentView.bounds.origin.y
            return contentHeight - visibleHeight - offsetY
        }

        private func handleLiveScroll(_ sv: NSScrollView) {
            let dist = distanceFromBottom(sv)
            let atBottom = dist < 60
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
            streamTimer?.invalidate()
            if let obs = liveScrollObserver { NotificationCenter.default.removeObserver(obs) }
        }
    }
}

