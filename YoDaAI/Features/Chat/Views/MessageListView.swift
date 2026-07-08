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

    @State private var displayedMessages: [MessageDisplayData]
    @State private var updateTask: Task<Void, Never>?

    init(thread: ChatThread, viewModel: ChatViewModel) {
        self.thread = thread
        self.viewModel = viewModel
        // Seed the messages SYNCHRONOUSLY so the list is fully populated on the
        // very first render. Loading async (starting from []) made the list grow
        // from empty → full after paint, causing a visible scroll into position
        // (and inconsistent final positions). With defaultScrollAnchor(.bottom)
        // + a full first frame, the chat simply appears at the bottom.
        _displayedMessages = State(initialValue: MessageDisplayData.loadMessages(from: thread))
    }

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
                                    // Remove from local display immediately
                                    displayedMessages.removeAll { $0.id == messageData.id }
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
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                // Render pinned to the bottom from the first paint, so opening or
                // switching a chat shows the newest message immediately with NO
                // visible scroll (like Codex) instead of starting at the top and
                // scrolling down.
                .defaultScrollAnchor(.bottom)
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
                        // Delay one frame so SwiftUI has laid out the new row
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                    }
                }
                // Streaming started → reload list for new row + start smooth auto-scroll
                // Streaming ended → stop auto-scroll
                .onChange(of: viewModel.streamingMessageID) { _, newID in
                    updateTask?.cancel()
                    updateTask = Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        if newID != nil {
                            // Start streaming: ensure we're tracking at bottom
                            isAtBottom = true
                            // Delay one frame for layout, then scroll + start timer
                            DispatchQueue.main.async {
                                scrollToBottom(proxy: proxy, animated: false)
                                scrollTracker.startStreamingScroll()
                            }
                        } else {
                            // Streaming finished — one final scroll then stop
                            DispatchQueue.main.async {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                            scrollTracker.stopStreamingScroll()
                        }
                    }
                }
                // Send started/finished — reload and scroll smoothly
                .onChange(of: viewModel.isSending) { _, newVal in
                    updateTask?.cancel()
                    updateTask = Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                        if newVal {
                            // Send just started: force at-bottom state and scroll
                            isAtBottom = true
                            // Scroll after layout settles. One async hop can fire
                            // before the new (lazy) row is measured, landing in
                            // blank space — so scroll again shortly after.
                            DispatchQueue.main.async {
                                scrollToBottom(proxy: proxy, animated: false)
                                scrollTracker.startStreamingScroll()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        } else {
                            // Sending finished
                            scrollTracker.stopStreamingScroll()
                        }
                    }
                }
                // No onAppear reload: displayedMessages is seeded synchronously in
                // init(), so the list is complete on the first frame and
                // defaultScrollAnchor(.bottom) pins it to the newest message with
                // no visible scroll. Reloading here would trigger a relayout.
                // Messages cleared (header Clear button or /clear) → reload the cache.
                .onChange(of: viewModel.messagesReloadToken) { _, _ in
                    updateTask?.cancel()
                    Task { @MainActor in
                        displayedMessages = MessageDisplayData.loadMessages(from: thread)
                    }
                }
                // Note: switching chats recreates this view via .id(thread.id) in
                // ChatDetailView, so there's no thread.id onChange to handle here —
                // the fresh view seeds messages in init() and renders at the bottom.
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
        // Scroll to the last real message (its bottom edge) rather than a trailing
        // spacer past the bottom padding — scrolling to the spacer could land in
        // blank space, especially with a LazyVStack whose off-screen rows haven't
        // been measured yet. Fall back to the "bottom" anchor if the list is empty.
        let target: AnyHashable = displayedMessages.last?.id ?? AnyHashable("bottom")
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
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
                ctx.duration = 0.15
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

