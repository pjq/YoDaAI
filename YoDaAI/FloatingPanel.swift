import SwiftUI
import AppKit
import Combine

/// Controller that manages the floating panel window
@MainActor
final class FloatingPanelController: NSObject, ObservableObject {
    static let shared = FloatingPanelController()
    
    private var panel: NSPanel?
    @Published var isVisible: Bool = false
    @Published var isExpanded: Bool = false
    
    /// Custom title for the floating panel (stored in UserDefaults)
    @Published var customTitle: String {
        didSet {
            UserDefaults.standard.set(customTitle, forKey: "floatingPanelTitle")
        }
    }
    
    private override init() {
        self.customTitle = UserDefaults.standard.string(forKey: "floatingPanelTitle") ?? "YoDaAI"
        super.init()
    }
    
    /// Show the floating panel
    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFront(nil)
        isVisible = true
        
        // Start content capture
        ContentCacheService.shared.startCapturing()
    }
    
    /// Hide the floating panel
    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }
    
    /// Toggle panel visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// Toggle expanded state (called from outside SwiftUI layout cycle)
    func toggleExpanded() {
        let newExpanded = !isExpanded
        isExpanded = newExpanded
        
        // Update panel size outside of SwiftUI's layout cycle
        DispatchQueue.main.async { [weak self] in
            self?.updatePanelSizeAsync(expanded: newExpanded)
        }
    }
    
    private func createPanel() {
        // Create a floating panel - start with compact size
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 70),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel behavior
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        // Don't show in dock or app switcher
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        
        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 280
            let panelHeight: CGFloat = 70
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - panelHeight - 10
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }
        
        // Set SwiftUI content
        let contentView = FloatingPanelView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        
        // Handle window close
        panel.delegate = self
        
        self.panel = panel
    }
    
    /// Update the panel size asynchronously to avoid layout loops
    private func updatePanelSizeAsync(expanded: Bool) {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = expanded ? 340 : 70
        
        let currentFrame = panel.frame
        // Keep the top-left position stable, grow/shrink downward
        let newX = currentFrame.origin.x
        let newY = currentFrame.maxY - panelHeight
        
        // Ensure we don't go off screen
        let clampedY = max(screenFrame.minY, min(newY, screenFrame.maxY - panelHeight))
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(x: newX, y: clampedY, width: panelWidth, height: panelHeight),
                display: true
            )
        }
    }
}

// MARK: - NSWindowDelegate
extension FloatingPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}

/// The SwiftUI view shown in the floating panel
struct FloatingPanelView: View {
    @ObservedObject var controller: FloatingPanelController
    @ObservedObject private var cacheService = ContentCacheService.shared
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main compact view
            mainView
            
            // Expanded cached apps list
            if controller.isExpanded {
                expandedContent
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            ZStack {
                // Glassmorphism effect
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                
                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var mainView: some View {
        HStack(spacing: 10) {
            // App icon with glow effect
            appIconView
            
            // App info
            VStack(alignment: .leading, spacing: 3) {
                // Custom title or app name
                if let app = cacheService.currentForegroundApp {
                    Text(app.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // Content status with badge
                    contentStatusView(for: app)
                } else {
                    Text(controller.customTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Monitoring apps...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Control buttons
            HStack(spacing: 8) {
                // Expand/collapse button
                Button {
                    controller.toggleExpanded()
                } label: {
                    Image(systemName: controller.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(controller.isExpanded ? "Collapse" : "Show cached apps")
                
                // Capture toggle
                Button {
                    cacheService.isCaptureEnabled.toggle()
                } label: {
                    Image(systemName: cacheService.isCaptureEnabled ? "record.circle.fill" : "record.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(cacheService.isCaptureEnabled ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(cacheService.isCaptureEnabled ? "Stop capturing" : "Start capturing")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var appIconView: some View {
        ZStack {
            // Glow background
            if let app = cacheService.currentForegroundApp,
               let cached = cacheService.getCachedContent(for: app.bundleIdentifier),
               let content = cached.snapshot.focusedValuePreview,
               !content.isEmpty {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .blur(radius: 8)
            }
            
            // Icon container
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                if let app = cacheService.currentForegroundApp, let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func contentStatusView(for app: RunningApp) -> some View {
        if let cached = cacheService.getCachedContent(for: app.bundleIdentifier) {
            let charCount = cached.snapshot.focusedValuePreview?.count ?? 0
            let isFresh = !cached.isOlderThan(30)
            
            HStack(spacing: 5) {
                // Status indicator
                Circle()
                    .fill(charCount > 0 ? (isFresh ? Color.green : Color.orange) : Color.red)
                    .frame(width: 6, height: 6)
                
                if charCount > 0 {
                    Text(formatCharCount(charCount))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isFresh ? Color.green : Color.orange)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    
                    Text(timeAgo(cached.capturedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No content")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Capturing...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            // Header
            HStack {
                Text("Cached Apps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(cacheService.cache.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            // Cached apps list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(cacheService.getAllCachedApps(), id: \.bundleId) { item in
                        CachedAppRowView(bundleId: item.bundleId, content: item.content)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(height: 220)
        }
    }
    
    private func formatCharCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count) chars"
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

/// Row showing a single cached app in the expanded view
private struct CachedAppRowView: View {
    let bundleId: String
    let content: CachedAppContent
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
               let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
            
            // App info
            VStack(alignment: .leading, spacing: 2) {
                Text(content.snapshot.appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    let charCount = content.snapshot.focusedValuePreview?.count ?? 0
                    
                    if charCount > 0 {
                        Text("\(charCount) chars")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else {
                        Text("No content")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    
                    Text(timeAgo(content.capturedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Freshness indicator
            Circle()
                .fill(content.isOlderThan(60) ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
        )
        .onHover { hovering in
            isHovering = hovering
        }
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

// MARK: - Visual Effect View (for glassmorphism)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview
#Preview {
    FloatingPanelView(controller: FloatingPanelController.shared)
        .frame(width: 280)
        .padding()
        .background(Color.gray.opacity(0.3))
}
