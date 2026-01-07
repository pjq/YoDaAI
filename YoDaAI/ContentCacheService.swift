import Foundation
import AppKit
import Combine

// MARK: - Timeout Configuration
private let kAppleScriptTimeout: TimeInterval = 5.0
private let kCaptureInterval: TimeInterval = 5.0  // Increased from 3 to reduce overhead

/// Cached content from an app
struct CachedAppContent: Sendable {
    let snapshot: AppContextSnapshot
    let capturedAt: Date
    let isStale: Bool
    
    init(snapshot: AppContextSnapshot, capturedAt: Date = Date()) {
        self.snapshot = snapshot
        self.capturedAt = capturedAt
        self.isStale = false
    }
    
    /// Check if content is older than the given interval
    func isOlderThan(_ interval: TimeInterval) -> Bool {
        return Date().timeIntervalSince(capturedAt) > interval
    }
}

/// Service that caches captured content from apps
/// This allows the floating panel to continuously capture content
/// so it's ready when the user wants to @ mention an app
@MainActor
final class ContentCacheService: ObservableObject {
    static let shared = ContentCacheService()
    
    /// Cached content by bundle identifier
    @Published private(set) var cache: [String: CachedAppContent] = [:]
    
    /// Currently monitored foreground app
    @Published private(set) var currentForegroundApp: RunningApp?
    
    /// Whether continuous capture is enabled
    @Published var isCaptureEnabled: Bool = true
    
    /// Capture interval in seconds (increased to reduce overhead)
    let captureInterval: TimeInterval = kCaptureInterval
    
    /// Content expiration time (how long before content is considered stale)
    let contentExpirationTime: TimeInterval = 60.0
    
    private var captureTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var isCapturing: Bool = false  // Prevent overlapping captures
    private let accessibilityService = AccessibilityService()
    
    private init() {
        setupWorkspaceObserver()
    }
    
    func cleanup() {
        stopCapturing()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    // MARK: - Public API
    
    /// Start continuous background capture
    func startCapturing() {
        guard captureTimer == nil else { return }
        
        print("[ContentCacheService] Starting continuous capture...")
        
        // Capture immediately
        Task {
            await captureCurrentForegroundApp()
        }
        
        // Set up periodic capture
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureCurrentForegroundApp()
            }
        }
    }
    
    /// Stop continuous capture
    func stopCapturing() {
        captureTimer?.invalidate()
        captureTimer = nil
        print("[ContentCacheService] Stopped continuous capture")
    }
    
    /// Get cached content for an app
    func getCachedContent(for bundleIdentifier: String) -> CachedAppContent? {
        return cache[bundleIdentifier]
    }
    
    /// Get cached snapshot for an app (convenience method)
    func getCachedSnapshot(for bundleIdentifier: String) -> AppContextSnapshot? {
        return cache[bundleIdentifier]?.snapshot
    }
    
    /// Check if we have fresh content for an app
    func hasFreshContent(for bundleIdentifier: String) -> Bool {
        guard let cached = cache[bundleIdentifier] else { return false }
        return !cached.isOlderThan(contentExpirationTime)
    }
    
    /// Manually trigger capture for the current foreground app
    func captureNow() async {
        await captureCurrentForegroundApp()
    }
    
    /// Clear all cached content
    func clearCache() {
        cache.removeAll()
        print("[ContentCacheService] Cache cleared")
    }
    
    /// Get all cached apps sorted by capture time (most recent first)
    func getAllCachedApps() -> [(bundleId: String, content: CachedAppContent)] {
        return cache
            .map { ($0.key, $0.value) }
            .sorted { $0.1.capturedAt > $1.1.capturedAt }
    }
    
    /// Open System Settings to the Automation privacy pane
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open System Settings to the Accessibility privacy pane  
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupWorkspaceObserver() {
        // Observe app activation changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAppActivation(notification)
            }
        }
    }
    
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName else {
            return
        }
        
        // Don't capture our own app
        guard bundleId != Bundle.main.bundleIdentifier else {
            return
        }
        
        print("[ContentCacheService] App activated: \(appName)")
        
        // Update current foreground app
        currentForegroundApp = RunningApp(
            appName: appName,
            bundleIdentifier: bundleId,
            icon: app.icon
        )
        
        // Capture content for the newly activated app
        if isCaptureEnabled {
            Task {
                // Small delay to let the app settle
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await captureCurrentForegroundApp()
            }
        }
    }
    
    private func captureCurrentForegroundApp() async {
        guard isCaptureEnabled else { return }
        
        // Prevent overlapping captures
        guard !isCapturing else {
            print("[ContentCacheService] Skipping capture - already in progress")
            return
        }
        
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier,
              let appName = frontmost.localizedName else {
            return
        }
        
        // Don't capture our own app
        guard bundleId != Bundle.main.bundleIdentifier else {
            return
        }
        
        isCapturing = true
        defer { isCapturing = false }
        
        // Update current foreground app
        currentForegroundApp = RunningApp(
            appName: appName,
            bundleIdentifier: bundleId,
            icon: frontmost.icon
        )
        
        // Try AppleScript first for supported apps (most reliable)
        // Use async version with timeout
        if let appleScriptSnapshot = await captureViaAppleScriptAsync(bundleIdentifier: bundleId, appName: appName) {
            let cached = CachedAppContent(snapshot: appleScriptSnapshot)
            cache[bundleId] = cached
            let contentLength = appleScriptSnapshot.focusedValuePreview?.count ?? 0
            print("[ContentCacheService] Cached content for \(appName) via AppleScript: \(contentLength) chars")
            return
        }
        
        // Fall back to full context capture (traverses window hierarchy)
        print("[ContentCacheService] Trying Accessibility API for \(appName)...")
        let snapshot = accessibilityService.captureContext(for: bundleId, promptIfNeeded: false)
        
        if let snapshot = snapshot {
            let cached = CachedAppContent(snapshot: snapshot)
            cache[bundleId] = cached
            
            let contentLength = snapshot.focusedValuePreview?.count ?? 0
            print("[ContentCacheService] Cached content for \(appName): \(contentLength) chars")
        } else {
            // Still cache a basic snapshot so we know about the app
            let basicSnapshot = AppContextSnapshot(
                appName: appName,
                bundleIdentifier: bundleId,
                windowTitle: getWindowTitle(for: frontmost),
                focusedRole: nil,
                focusedValuePreview: nil,
                focusedIsEditable: false,
                focusedIsSecure: false
            )
            cache[bundleId] = CachedAppContent(snapshot: basicSnapshot)
            print("[ContentCacheService] Cached basic info for \(appName) (no content captured)")
        }
    }
    
    /// Get window title using CGWindowList (works without Accessibility permission)
    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == app.processIdentifier,
               let title = windowInfo[kCGWindowName as String] as? String,
               !title.isEmpty {
                return title
            }
        }
        return nil
    }
    
    // MARK: - AppleScript Capture (copied from AccessibilityService for background capture)
    
    /// Async version with timeout for AppleScript execution
    private func captureViaAppleScriptAsync(bundleIdentifier: String, appName: String) async -> AppContextSnapshot? {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            let workItem = DispatchWorkItem { [self] in
                let result = self.captureViaAppleScriptSync(bundleIdentifier: bundleIdentifier, appName: appName)
                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    lock.unlock()
                    continuation.resume(returning: result)
                } else {
                    lock.unlock()
                }
            }
            
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
            
            // Cancel after timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + kAppleScriptTimeout) {
                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    workItem.cancel()
                    lock.unlock()
                    print("[ContentCacheService] AppleScript timed out for \(appName)")
                    continuation.resume(returning: nil)
                } else {
                    lock.unlock()
                }
            }
        }
    }
    
    /// Synchronous AppleScript capture
    private func captureViaAppleScriptSync(bundleIdentifier: String, appName: String) -> AppContextSnapshot? {
        var script: String?
        var windowTitle: String?
        
        // Use bundle identifier to target apps more reliably (tell application id "...")
        switch bundleIdentifier {
        case "com.apple.Safari":
            script = """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then
                    return ""
                end if
                set tabTitle to name of current tab of front window
                set tabURL to URL of current tab of front window
                try
                    set pageText to do JavaScript "document.body.innerText" in current tab of front window
                on error
                    set pageText to ""
                end try
                return tabTitle & linefeed & tabURL & linefeed & linefeed & pageText
            end tell
            """
            
        case "com.google.Chrome":
            script = """
            tell application id "com.google.Chrome"
                if (count of windows) is 0 then
                    return ""
                end if
                set tabTitle to title of active tab of front window
                set tabURL to URL of active tab of front window
                try
                    set pageText to execute active tab of front window javascript "document.body.innerText"
                on error
                    set pageText to ""
                end try
                return tabTitle & linefeed & tabURL & linefeed & linefeed & pageText
            end tell
            """
            
        case "com.google.Chrome.canary":
            script = """
            tell application id "com.google.Chrome.canary"
                if (count of windows) is 0 then
                    return ""
                end if
                set tabTitle to title of active tab of front window
                set tabURL to URL of active tab of front window
                try
                    set pageText to execute active tab of front window javascript "document.body.innerText"
                on error
                    set pageText to ""
                end try
                return tabTitle & linefeed & tabURL & linefeed & linefeed & pageText
            end tell
            """
            
        case "com.apple.Notes":
            script = """
            tell application id "com.apple.Notes"
                set noteContent to ""
                try
                    set theNote to selection
                    if theNote is not {} then
                        set noteContent to body of item 1 of theNote as text
                    else
                        set noteContent to body of first note as text
                    end if
                end try
                return noteContent
            end tell
            """
            
        case "com.apple.mail":
            script = """
            tell application id "com.apple.mail"
                set msgContent to ""
                try
                    set theMessages to selection
                    if theMessages is not {} then
                        set theMessage to item 1 of theMessages
                        set msgSubject to subject of theMessage
                        set msgSender to sender of theMessage
                        set msgContent to content of theMessage
                        return "Subject: " & msgSubject & linefeed & "From: " & msgSender & linefeed & linefeed & msgContent
                    end if
                end try
                return msgContent
            end tell
            """
            
        case "com.apple.TextEdit":
            script = """
            tell application id "com.apple.TextEdit"
                set docContent to ""
                try
                    set docContent to text of front document
                end try
                return docContent
            end tell
            """
            
        default:
            return nil
        }
        
        guard let scriptSource = script else { return nil }
        
        print("[ContentCacheService] Running AppleScript for \(appName) (id: \(bundleIdentifier))...")
        
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: scriptSource) else {
            print("[ContentCacheService] Failed to create AppleScript")
            return nil
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            print("[ContentCacheService] AppleScript error for \(appName): [\(errorNumber)] \(errorMessage)")
            
            // Common errors:
            // -600: Application isn't running (but it might be - try using id instead of name)
            // -1743: Not authorized to send Apple events (needs Automation permission)
            // -1728: Can't get object (app may not support the scripting interface)
            switch errorNumber {
            case -600:
                print("[ContentCacheService] ⚠️ Error -600: App may not be responding to AppleScript. Make sure \(appName) is running and responsive.")
            case -1743:
                print("[ContentCacheService] ⚠️ Error -1743: YoDaAI needs Automation permission for \(appName)")
                print("[ContentCacheService] Please grant permission in: System Settings → Privacy & Security → Automation")
                DispatchQueue.main.async {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case -1728:
                print("[ContentCacheService] ⚠️ Error -1728: \(appName) may not support this AppleScript command")
            default:
                break
            }
            return nil
        }
        
        guard let content = result.stringValue, !content.isEmpty else {
            print("[ContentCacheService] AppleScript returned empty result for \(appName)")
            return nil
        }
        
        print("[ContentCacheService] AppleScript captured \(content.count) chars for \(appName)")
        
        // Extract window title from content if available
        let lines = content.components(separatedBy: "\n")
        if lines.count > 1 {
            windowTitle = lines[0]
        }
        
        return AppContextSnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            focusedRole: "AppleScript",
            focusedValuePreview: truncate(content, limit: 4000),
            focusedIsEditable: false,
            focusedIsSecure: false
        )
    }
    
    private func truncate(_ string: String, limit: Int) -> String {
        if string.count <= limit {
            return string
        }
        return String(string.prefix(limit)) + "…"
    }
}
