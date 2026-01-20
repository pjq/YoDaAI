import AppKit
import ApplicationServices
import Foundation

private let axEditableAttribute = "AXEditable" // kAXEditableAttribute is not always imported into Swift

// MARK: - Timeout Configuration
// Timeout for AX element operations (in seconds) - prevents hangs when target app is unresponsive
private let kAXTimeout: Float = 2.0

// Reduced limits for tree traversal to prevent hangs
private let kMaxTreeDepth = 10  // Increased for email clients with nested content
private let kMaxTotalChars = 8000  // Increased to capture more email content
private let kMaxChildrenPerLevel = 30

struct AppContextSnapshot: Sendable {
    var appName: String
    var bundleIdentifier: String
    var windowTitle: String?

    var focusedRole: String?
    var focusedValuePreview: String?
    var focusedIsEditable: Bool
    var focusedIsSecure: Bool
}

/// Represents a running application for @ mention selection
struct RunningApp: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    var appName: String
    var bundleIdentifier: String
    var icon: NSImage?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
    
    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

@MainActor
final class AccessibilityService {

    // Track if we've already prompted for Accessibility permission
    private var hasPromptedForAccessibility = false

    // MARK: - Private Helpers for Timeout
    
    /// Set timeout on an AXUIElement to prevent hangs
    private func setAXTimeout(for element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, kAXTimeout)
    }
    
    /// Create an app element with timeout already set
    private func createAppElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        setAXTimeout(for: element)
        return element
    }
    
    /// Create the system-wide element with timeout
    private func createSystemWideElement() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        setAXTimeout(for: element)
        return element
    }
    
    func ensurePermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard promptIfNeeded else {
            return false
        }

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    func captureFrontmostContext(promptIfNeeded: Bool) -> AppContextSnapshot? {
        guard ensurePermission(promptIfNeeded: promptIfNeeded) else {
            return nil
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = application.localizedName ?? "(Unknown App)"
        let bundleId = application.bundleIdentifier ?? "(unknown.bundle)"

        var windowTitle: String?
        var focusedRole: String?
        var focusedValuePreview: String?
        var focusedIsEditable = false
        var focusedIsSecure = false

        let appElement = createAppElement(pid: application.processIdentifier)

        if let window = copyAXUIElement(appElement, attribute: kAXFocusedWindowAttribute) {
            setAXTimeout(for: window)
            windowTitle = copyAXString(window, attribute: kAXTitleAttribute)
        }

        if let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) {
            setAXTimeout(for: focused)
            focusedRole = copyAXString(focused, attribute: kAXRoleAttribute)

            if let editable = copyAXBool(focused, attribute: axEditableAttribute) {
                focusedIsEditable = editable
            }

            let subrole = copyAXString(focused, attribute: kAXSubroleAttribute)
            if subrole == kAXSecureTextFieldSubrole as String {
                focusedIsSecure = true
            }

            if let value = copyAXString(focused, attribute: kAXValueAttribute) {
                focusedValuePreview = truncate(value, limit: 400)
            }
        }

        return AppContextSnapshot(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            focusedRole: focusedRole,
            focusedValuePreview: focusedValuePreview,
            focusedIsEditable: focusedIsEditable,
            focusedIsSecure: focusedIsSecure
        )
    }

    /// List all running applications that can be mentioned with @
    func listRunningApps() -> [RunningApp] {
        let workspace = NSWorkspace.shared
        let ownBundleId = Bundle.main.bundleIdentifier ?? ""
        
        return workspace.runningApplications
            .filter { app in
                // Only include regular apps (not background agents)
                app.activationPolicy == .regular &&
                app.bundleIdentifier != ownBundleId &&
                app.localizedName != nil
            }
            .compactMap { app -> RunningApp? in
                guard let name = app.localizedName,
                      let bundleId = app.bundleIdentifier else {
                    return nil
                }
                return RunningApp(
                    appName: name,
                    bundleIdentifier: bundleId,
                    icon: app.icon
                )
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
    
    /// Capture context from a specific app by bundle identifier
    /// Note: For best results, the app should be brought to front first
    func captureContext(for bundleIdentifier: String, promptIfNeeded: Bool) -> AppContextSnapshot? {
        guard ensurePermission(promptIfNeeded: promptIfNeeded) else {
            print("[AccessibilityService] Permission not granted")
            return nil
        }
        
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            print("[AccessibilityService] App not found: \(bundleIdentifier)")
            return nil
        }
        
        let appName = app.localizedName ?? "(Unknown App)"
        print("[AccessibilityService] Capturing context for: \(appName) (pid: \(app.processIdentifier))")
        
        var windowTitle: String?
        var focusedRole: String?
        var focusedValuePreview: String?
        var focusedIsEditable = false
        var focusedIsSecure = false
        
        let appElement = createAppElement(pid: app.processIdentifier)
        
        // Try multiple approaches to get content
        var contents: [String] = []
        
        // 1. If this is the frontmost app, try system-wide focused element first
        //    This is more reliable for getting selected text
        if app.isActive {
            print("[AccessibilityService] App is active, trying system-wide focused element")
            let systemWide = createSystemWideElement()
            if let focused = copyAXUIElement(systemWide, attribute: kAXFocusedUIElementAttribute) {
                setAXTimeout(for: focused)
                // Try selected text first (most useful)
                if let selectedText = copyAXString(focused, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
                    print("[AccessibilityService] Found selected text via system-wide: \(selectedText.prefix(100))...")
                    contents.append("Selected Text:\n\(selectedText)")
                }
                
                // Get the focused element's value
                if let value = copyAXString(focused, attribute: kAXValueAttribute), !value.isEmpty {
                    print("[AccessibilityService] Found focused value via system-wide: \(value.prefix(100))...")
                    if !contents.contains(where: { $0.contains(value) }) {
                        contents.append(value)
                    }
                }
                
                focusedRole = copyAXString(focused, attribute: kAXRoleAttribute)
                print("[AccessibilityService] System-wide focused role: \(focusedRole ?? "nil")")
            }
        }
        
        // 2. Try to get selected text from app element (for non-frontmost apps)
        if let selectedText = copyAXString(appElement, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
            print("[AccessibilityService] Found selected text from app: \(selectedText.prefix(100))...")
            if !contents.contains(where: { $0.contains(selectedText) }) {
                contents.append("Selected Text:\n\(selectedText)")
            }
        }
        
        // 3. Get all windows
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            print("[AccessibilityService] Found \(windows.count) windows")
            
            // Try focused window first, fall back to first window
            let mainWindow: AXUIElement
            if let focusedWindow = copyAXUIElement(appElement, attribute: kAXFocusedWindowAttribute) {
                mainWindow = focusedWindow
                setAXTimeout(for: mainWindow)
                print("[AccessibilityService] Using focused window")
            } else {
                mainWindow = windows[0]
                setAXTimeout(for: mainWindow)
                print("[AccessibilityService] Using first window")
            }
            
            windowTitle = copyAXString(mainWindow, attribute: kAXTitleAttribute)
            print("[AccessibilityService] Window title: \(windowTitle ?? "nil")")
            
            // Try to get document URL (useful for file-based apps)
            if let docValue = copyAXString(mainWindow, attribute: kAXDocumentAttribute as String), !docValue.isEmpty {
                print("[AccessibilityService] Found document: \(docValue.prefix(100))...")
                contents.append("Document: \(docValue)")
            }
            
            // Try main content area first - look for known content roles
            if let mainContent = findMainContentArea(in: mainWindow) {
                print("[AccessibilityService] Found main content area")
                extractAllText(from: mainContent, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
            } else {
                // Extract content from window hierarchy
                extractAllText(from: mainWindow, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
            }
        } else {
            print("[AccessibilityService] No windows found, error: \(windowsError.rawValue)")
        }
        
        // 4. Try focused element from app (for non-active apps)
        if !app.isActive {
            if let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) {
                setAXTimeout(for: focused)
                focusedRole = copyAXString(focused, attribute: kAXRoleAttribute)
                print("[AccessibilityService] Focused element role: \(focusedRole ?? "nil")")
                
                if let editable = copyAXBool(focused, attribute: axEditableAttribute) {
                    focusedIsEditable = editable
                }
                
                let subrole = copyAXString(focused, attribute: kAXSubroleAttribute)
                if subrole == kAXSecureTextFieldSubrole as String {
                    focusedIsSecure = true
                }
                
                // Get value from focused element
                if let value = copyAXString(focused, attribute: kAXValueAttribute), !value.isEmpty {
                    print("[AccessibilityService] Focused element value: \(value.prefix(100))...")
                    if !contents.contains(where: { $0.contains(value) }) {
                        contents.append(value)
                    }
                }
                
                // Get selected text from focused element
                if let selectedText = copyAXString(focused, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
                    if !contents.contains(where: { $0.contains(selectedText) }) {
                        contents.append("Selected: \(selectedText)")
                    }
                }
            }
        }
        
        // Combine all content, removing duplicates
        let uniqueContents = removeDuplicateContent(contents)
        let combinedContent = uniqueContents
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        
        if !combinedContent.isEmpty {
            focusedValuePreview = truncate(combinedContent, limit: 4000)
            print("[AccessibilityService] Total content captured: \(focusedValuePreview?.count ?? 0) chars")
        } else {
            print("[AccessibilityService] No content captured - app may need to be brought to front")
        }
        
        return AppContextSnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            focusedRole: focusedRole,
            focusedValuePreview: focusedValuePreview,
            focusedIsEditable: focusedIsEditable,
            focusedIsSecure: focusedIsSecure
        )
    }
    
    /// Find the main content area in a window (web area, scroll area with text, etc.)
    private func findMainContentArea(in element: AXUIElement) -> AXUIElement? {
        // Priority roles for main content - expanded list for email clients
        let contentRoles = [
            "AXWebArea",        // Web content (Teams, Outlook web view)
            "AXScrollArea",     // Scrollable content areas
            "AXTextArea",       // Text areas
            "AXGroup",          // Generic groups
            "AXStaticText",     // Static text (email body)
            "AXTextField",      // Text fields
            "AXList",           // Lists (email threads)
            "AXTable",          // Tables (email content)
            "AXOutline"         // Outlines (folder structures)
        ]

        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard error == .success, let children = childrenRef as? [AXUIElement] else { return nil }

        // First pass: Look for elements with substantial content
        for child in children.prefix(kMaxChildrenPerLevel) {
            setAXTimeout(for: child)
            let role = copyAXString(child, attribute: kAXRoleAttribute)

            // Check for substantial text content
            if let value = copyAXString(child, attribute: kAXValueAttribute), value.count > 100 {
                print("[AccessibilityService] Found content area with \(value.count) chars, role: \(role ?? "unknown")")
                return child
            }

            // For email clients, look for scroll areas that might contain the message body
            if role == "AXScrollArea" {
                // Recursively check if this scroll area has content
                if let found = findMainContentArea(in: child) {
                    return found
                }
            }
        }

        // Second pass: Recursively search in priority roles
        for child in children.prefix(kMaxChildrenPerLevel) {
            setAXTimeout(for: child)
            let role = copyAXString(child, attribute: kAXRoleAttribute)
            if let role = role, contentRoles.contains(role) {
                if let found = findMainContentArea(in: child) {
                    return found
                }
            }
        }

        return nil
    }
    
    /// Remove duplicate content from the array
    private func removeDuplicateContent(_ contents: [String]) -> [String] {
        var unique: [String] = []
        for content in contents {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip if this content is already contained in another entry or vice versa
            let isDuplicate = unique.contains { existing in
                existing.contains(trimmed) || trimmed.contains(existing)
            }
            if !isDuplicate && !trimmed.isEmpty {
                unique.append(content)
            }
        }
        return unique
    }
    
    /// Capture context by briefly activating the target app, then returning to YoDaAI
    /// This is more reliable for capturing content from background apps
    func captureContextWithActivation(for bundleIdentifier: String, promptIfNeeded: Bool) async -> AppContextSnapshot? {
        guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            print("[AccessibilityService] App not found: \(bundleIdentifier)")
            return nil
        }
        
        let appName = targetApp.localizedName ?? "(Unknown App)"
        print("[AccessibilityService] Capturing content from: \(appName)")
        
        // 1. First try AppleScript for supported apps (doesn't need Accessibility permission)
        //    Use async version with timeout to prevent hangs
        if let appleScriptResult = await captureViaAppleScriptAsync(bundleIdentifier: bundleIdentifier, appName: appName) {
            print("[AccessibilityService] AppleScript capture successful!")
            return appleScriptResult
        }
        
        // 2. Check Accessibility permission for remaining methods
        let hasAccessibility = ensurePermission(promptIfNeeded: promptIfNeeded)
        print("[AccessibilityService] Accessibility permission: \(hasAccessibility ? "granted" : "NOT granted")")
        
        if !hasAccessibility {
            // Open System Settings to Accessibility pane (only once per session)
            if promptIfNeeded && !hasPromptedForAccessibility {
                print("[AccessibilityService] Opening System Settings for Accessibility (first time)...")
                hasPromptedForAccessibility = true
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            // Return a basic snapshot with just the app name
            return AppContextSnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: nil,
                focusedRole: nil,
                focusedValuePreview: "[Accessibility permission required to capture content]",
                focusedIsEditable: false,
                focusedIsSecure: false
            )
        }
        
        // 3. Try clipboard-based capture (Cmd+C) - works for Electron apps
        let clipboardResult = await captureViaClipboard(for: targetApp)
        if let result = clipboardResult, result.focusedValuePreview != nil && !result.focusedValuePreview!.isEmpty {
            print("[AccessibilityService] Clipboard capture successful!")
            return result
        }
        
        // 4. Fall back to Accessibility API with activation
        print("[AccessibilityService] Falling back to Accessibility API...")
        
        // Remember the current app (YoDaAI) to return to it later
        let currentApp = NSRunningApplication.current
        
        print("[AccessibilityService] Activating \(appName) to capture content...")
        
        // Activate the target app
        let activated = targetApp.activate()
        print("[AccessibilityService] Activation request sent, result: \(activated)")
        
        // Wait for the app to become active (up to 1 second)
        var waitCount = 0
        while !targetApp.isActive && waitCount < 20 {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            waitCount += 1
        }
        
        print("[AccessibilityService] App isActive: \(targetApp.isActive) after \(waitCount * 50)ms")
        
        // Give Electron/web apps more time to settle their accessibility tree
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        // Now capture the content while the app is active
        let snapshot = captureContextEnhanced(for: targetApp)
        
        // Small delay before switching back
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Return to YoDaAI
        print("[AccessibilityService] Returning to YoDaAI...")
        currentApp.activate()
        
        return snapshot
    }
    
    // MARK: - AppleScript Capture
    
    /// Capture content using AppleScript for apps that support it
    /// Now runs with a timeout to prevent hangs
    private func captureViaAppleScript(bundleIdentifier: String, appName: String) -> AppContextSnapshot? {
        // Run the AppleScript synchronously but with a timeout wrapper
        return captureViaAppleScriptSync(bundleIdentifier: bundleIdentifier, appName: appName)
    }
    
    /// Async version with timeout for AppleScript execution
    func captureViaAppleScriptAsync(bundleIdentifier: String, appName: String) async -> AppContextSnapshot? {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            let workItem = DispatchWorkItem {
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
            
            // Cancel after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    workItem.cancel()
                    lock.unlock()
                    print("[AccessibilityService] AppleScript timed out for \(appName)")
                    continuation.resume(returning: nil)
                } else {
                    lock.unlock()
                }
            }
        }
    }
    
    /// Synchronous AppleScript capture (used by both sync and async versions)
    private func captureViaAppleScriptSync(bundleIdentifier: String, appName: String) -> AppContextSnapshot? {
        print("[AccessibilityService] Trying AppleScript for: \(bundleIdentifier)")
        
        var script: String?
        var windowTitle: String?
        
        // Use bundle identifier to target apps more reliably (tell application id "...")
        switch bundleIdentifier {
        case "com.apple.Safari":
            // Safari: Get current tab URL and page content
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
            // Chrome: Get current tab URL and page content
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
            // Notes: Get content of selected/current note
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
            // Mail: Get content of selected message
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

        case "com.microsoft.Outlook":
            // Outlook: Get content of selected message
            script = """
            tell application "Microsoft Outlook"
                set msgContent to ""
                try
                    set theMessages to current messages
                    if theMessages is not {} then
                        set theMessage to item 1 of theMessages
                        set msgSubject to subject of theMessage
                        set msgSender to sender of theMessage
                        set msgBody to plain text content of theMessage
                        return "Subject: " & msgSubject & linefeed & "From: " & (address of msgSender) & linefeed & linefeed & msgBody
                    end if
                end try
                return msgContent
            end tell
            """
            
        case "com.apple.TextEdit":
            // TextEdit: Get document content
            script = """
            tell application id "com.apple.TextEdit"
                set docContent to ""
                try
                    set docContent to text of front document
                end try
                return docContent
            end tell
            """
            
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            // VS Code: Try to get content (limited support)
            script = """
            tell application "System Events"
                tell process "Code"
                    set windowName to name of front window
                    return windowName
                end tell
            end tell
            """

        case "com.microsoft.teams2", "com.microsoft.teams", "com.microsoft.Teams":
            // Teams: Limited AppleScript support, mainly window info
            script = """
            tell application "System Events"
                tell process "Microsoft Teams"
                    if (count of windows) is 0 then
                        return ""
                    end if
                    set windowName to name of front window
                    return windowName
                end tell
            end tell
            """

        default:
            // For unsupported apps, return nil to try other methods
            print("[AccessibilityService] No AppleScript support for: \(bundleIdentifier)")
            return nil
        }
        
        guard let scriptSource = script else { return nil }
        
        // Execute the AppleScript
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: scriptSource) else {
            print("[AccessibilityService] Failed to create AppleScript")
            return nil
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            print("[AccessibilityService] AppleScript error [\(errorNumber)]: \(errorMessage)")
            
            // Common errors:
            // -600: Application isn't running
            // -1743: Not authorized to send Apple events (needs Automation permission)
            // -1728: Can't get object
            switch errorNumber {
            case -600:
                print("[AccessibilityService] ⚠️ Error -600: App may not be responding to AppleScript")
            case -1743:
                print("[AccessibilityService] ⚠️ Error -1743: YoDaAI needs Automation permission for \(appName)")
                print("[AccessibilityService] Grant in: System Settings → Privacy & Security → Automation")
            case -1728:
                print("[AccessibilityService] ⚠️ Error -1728: \(appName) may not support this AppleScript command")
            default:
                break
            }
            return nil
        }
        
        guard let content = result.stringValue, !content.isEmpty else {
            print("[AccessibilityService] AppleScript returned empty result")
            return nil
        }
        
        print("[AccessibilityService] AppleScript captured \(content.count) chars")
        
        // Extract window title from content if available (first line for Safari/Chrome)
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
    
    // MARK: - Clipboard-based Capture
    
    /// Capture content by simulating Cmd+A, Cmd+C (select all, copy)
    /// This works for most apps including Electron apps
    private func captureViaClipboard(for app: NSRunningApplication) async -> AppContextSnapshot? {
        let appName = app.localizedName ?? "(Unknown App)"
        let bundleIdentifier = app.bundleIdentifier ?? "(unknown.bundle)"
        
        print("[AccessibilityService] Trying clipboard capture for: \(appName)")
        
        // Save current clipboard content (for potential future restoration)
        let pasteboard = NSPasteboard.general
        _ = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let types = item.types.first,
                  let data = item.data(forType: types) else { return nil }
            return (types, data)
        }
        
        // Remember the current app (YoDaAI) to return to it later
        let currentApp = NSRunningApplication.current
        
        // Activate the target app
        app.activate()
        
        // Wait for activation
        var waitCount = 0
        while !app.isActive && waitCount < 20 {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            waitCount += 1
        }
        
        guard app.isActive else {
            print("[AccessibilityService] Failed to activate app for clipboard capture")
            return nil
        }
        
        // Small delay to ensure app is ready
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Clear clipboard
        pasteboard.clearContents()
        
        // Simulate Cmd+C to copy current selection (don't select all - too invasive)
        simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // Cmd+C
        
        // Wait for clipboard to be populated
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Get clipboard content
        let copiedText = pasteboard.string(forType: .string)
        
        // Get window title via CGWindowList
        var windowTitle: String?
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            for windowInfo in windowList {
                if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                   windowPID == app.processIdentifier,
                   let title = windowInfo[kCGWindowName as String] as? String,
                   !title.isEmpty {
                    windowTitle = title
                    break
                }
            }
        }
        
        // Return to YoDaAI
        currentApp.activate()
        
        // Restore original clipboard (optional - might be confusing for users)
        // For now, leave the copied content in clipboard as it might be useful
        
        if let text = copiedText, !text.isEmpty {
            print("[AccessibilityService] Clipboard captured \(text.count) chars")
            return AppContextSnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                focusedRole: "Clipboard",
                focusedValuePreview: truncate(text, limit: 4000),
                focusedIsEditable: false,
                focusedIsSecure: false
            )
        }
        
        print("[AccessibilityService] Clipboard capture returned empty")
        return nil
    }
    
    /// Simulate a key press with modifiers
    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    /// Enhanced capture that works better with Electron apps
    private func captureContextEnhanced(for app: NSRunningApplication) -> AppContextSnapshot? {
        let appName = app.localizedName ?? "(Unknown App)"
        let bundleIdentifier = app.bundleIdentifier ?? "(unknown.bundle)"
        let pid = app.processIdentifier
        
        print("[AccessibilityService] Enhanced capture for: \(appName) (pid: \(pid))")
        
        var windowTitle: String?
        var focusedRole: String?
        var focusedValuePreview: String?
        let focusedIsEditable = false
        let focusedIsSecure = false
        
        let appElement = createAppElement(pid: pid)
        var contents: [String] = []
        
        // Debug: List all available attributes on the app element
        var attrNames: CFArray?
        let attrError = AXUIElementCopyAttributeNames(appElement, &attrNames)
        print("[AccessibilityService] App attributes query result: \(attrError.rawValue)")
        if attrError == .success, let names = attrNames as? [String] {
            print("[AccessibilityService] App element attributes: \(names.joined(separator: ", "))")
        } else {
            print("[AccessibilityService] Failed to get app attributes, trying CGWindowList fallback...")
            // Try CGWindowListCopyWindowInfo as fallback to get window titles
            if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                for windowInfo in windowList {
                    if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                       windowPID == pid,
                       let title = windowInfo[kCGWindowName as String] as? String,
                       !title.isEmpty {
                        print("[AccessibilityService] Found window via CGWindowList: \(title)")
                        if windowTitle == nil {
                            windowTitle = title
                        }
                    }
                }
            }
        }
        
        // 1. Try system-wide focused element (most reliable when app is active)
        print("[AccessibilityService] Trying system-wide focused element...")
        let systemWide = createSystemWideElement()
        var focusedRef: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        print("[AccessibilityService] System-wide focused query result: \(focusedError.rawValue)")
        
        if focusedError == .success, let focused = focusedRef {
            let focusedElement = focused as! AXUIElement
            setAXTimeout(for: focusedElement)
            focusedRole = copyAXString(focusedElement, attribute: kAXRoleAttribute)
            print("[AccessibilityService] System-wide focused role: \(focusedRole ?? "nil")")
            
            // Debug: List attributes on focused element
            var focusedAttrNames: CFArray?
            let focusedAttrError = AXUIElementCopyAttributeNames(focusedElement, &focusedAttrNames)
            if focusedAttrError == .success, let names = focusedAttrNames as? [String] {
                print("[AccessibilityService] Focused element attributes: \(names.prefix(20).joined(separator: ", "))...")
            }
            
            // Try selected text first
            if let selectedText = copyAXString(focusedElement, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
                print("[AccessibilityService] Found selected text: \(selectedText.prefix(100))...")
                contents.append("Selected Text:\n\(selectedText)")
            }
            
            // Get value
            if let value = copyAXString(focusedElement, attribute: kAXValueAttribute), !value.isEmpty {
                print("[AccessibilityService] Found focused value: \(value.prefix(100))...")
                if !contents.contains(where: { $0.contains(value) }) {
                    contents.append(value)
                }
            }
            
            // Try to get parent window title from focused element
            if let window = copyAXUIElement(focusedElement, attribute: kAXWindowAttribute as String) {
                windowTitle = copyAXString(window, attribute: kAXTitleAttribute)
                print("[AccessibilityService] Window from focused: \(windowTitle ?? "nil")")
            }
            
            // For Electron apps, try walking up to find content
            if focusedRole == "AXWebArea" || focusedRole == "AXGroup" || focusedRole == "AXTextField" || focusedRole == "AXTextArea" {
                extractAllText(from: focusedElement, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
            }
        }
        
        // 2. Try to get focused window directly from app
        print("[AccessibilityService] Trying focused window from app...")
        var focusedWindowRef: CFTypeRef?
        let focusedWindowError = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        print("[AccessibilityService] Focused window query result: \(focusedWindowError.rawValue)")
        
        if focusedWindowError == .success, let focusedWindow = focusedWindowRef as! AXUIElement? {
            setAXTimeout(for: focusedWindow)
            print("[AccessibilityService] Got focused window directly")
            if windowTitle == nil {
                windowTitle = copyAXString(focusedWindow, attribute: kAXTitleAttribute)
                print("[AccessibilityService] Focused window title: \(windowTitle ?? "nil")")
            }
            extractAllText(from: focusedWindow, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
        }
        
        // 3. Try windows array as fallback
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        print("[AccessibilityService] Windows array query result: \(windowsError.rawValue)")
        
        if windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            print("[AccessibilityService] Found \(windows.count) windows via array")
            let mainWindow = windows[0]
            setAXTimeout(for: mainWindow)
            if windowTitle == nil {
                windowTitle = copyAXString(mainWindow, attribute: kAXTitleAttribute)
            }
            if contents.isEmpty {
                extractAllText(from: mainWindow, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
            }
        }
        
        // 4. Try AXMainWindow attribute
        var mainWindowRef: CFTypeRef?
        let mainWindowError = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef)
        print("[AccessibilityService] Main window query result: \(mainWindowError.rawValue)")
        
        if mainWindowError == .success, let mainWindow = mainWindowRef as! AXUIElement? {
            setAXTimeout(for: mainWindow)
            print("[AccessibilityService] Got main window")
            if windowTitle == nil {
                windowTitle = copyAXString(mainWindow, attribute: kAXTitleAttribute)
            }
            if contents.isEmpty {
                extractAllText(from: mainWindow, into: &contents, depth: 0, maxTotal: kMaxTotalChars)
            }
        }
        
        // Combine content
        let uniqueContents = removeDuplicateContent(contents)
        let combinedContent = uniqueContents
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        
        if !combinedContent.isEmpty {
            focusedValuePreview = truncate(combinedContent, limit: 4000)
            print("[AccessibilityService] Total content captured: \(focusedValuePreview?.count ?? 0) chars")
        } else {
            print("[AccessibilityService] No content captured - accessibility may be restricted for this app")
        }
        
        return AppContextSnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            focusedRole: focusedRole,
            focusedValuePreview: focusedValuePreview,
            focusedIsEditable: focusedIsEditable,
            focusedIsSecure: focusedIsSecure
        )
    }
    
    /// Extract all text from an accessibility element tree
    /// Uses reduced depth and limits to prevent hangs
    private func extractAllText(from element: AXUIElement, into contents: inout [String], depth: Int, maxTotal: Int = 4000) {
        guard depth < kMaxTreeDepth else { return } // Reduced depth for performance
        guard contents.joined().count < maxTotal else { return }

        // Set timeout on each element we process
        setAXTimeout(for: element)

        // Get role and identifier
        let role = copyAXString(element, attribute: kAXRoleAttribute)
        let identifier = copyAXString(element, attribute: kAXIdentifierAttribute as String)

        // Skip UI framework identifiers (common in Electron apps)
        // These are internal React/Electron component identifiers, not user content
        let skipIdentifiers = [
            "messageHeaderFromContent",
            "messageHeaderRecipientsContent",
            "messageBody",
            "messageHeader",
            "toolbar",
            "sidebar",
            "navigation",
            "button",
            "icon"
        ]

        let shouldSkipValue = identifier != nil && skipIdentifiers.contains(where: { identifier!.lowercased().contains($0.lowercased()) })

        if !shouldSkipValue {
            // Try to get text value
            if let value = copyAXString(element, attribute: kAXValueAttribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out UI identifiers that look like camelCase variable names
                let looksLikeIdentifier = trimmed.range(of: "^[a-z][a-zA-Z]+Content$", options: .regularExpression) != nil ||
                                        trimmed.range(of: "^[a-z][a-zA-Z]+Header$", options: .regularExpression) != nil ||
                                        trimmed.range(of: "^[a-z][a-zA-Z]+Footer$", options: .regularExpression) != nil

                if trimmed.count > 3 && !looksLikeIdentifier && !contents.contains(where: { $0.contains(trimmed) || trimmed.contains($0) }) {
                    contents.append(trimmed)
                    print("[AccessibilityService] Found text (\(role ?? "unknown")): \(trimmed.prefix(50))...")
                }
            }

            // For text elements, also check title and description
            if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" {
                if let title = copyAXString(element, attribute: kAXTitleAttribute) {
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let looksLikeIdentifier = trimmed.range(of: "^[a-z][a-zA-Z]+Content$", options: .regularExpression) != nil
                    if trimmed.count > 3 && !looksLikeIdentifier && !contents.contains(where: { $0.contains(trimmed) }) {
                        contents.append(trimmed)
                    }
                }
                // Also try description attribute
                if let desc = copyAXString(element, attribute: kAXDescriptionAttribute as String) {
                    let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                    let looksLikeIdentifier = trimmed.range(of: "^[a-z][a-zA-Z]+Content$", options: .regularExpression) != nil
                    if trimmed.count > 3 && !looksLikeIdentifier && !contents.contains(where: { $0.contains(trimmed) }) {
                        contents.append(trimmed)
                    }
                }
            }

            // For list and table elements (common in email clients), try to get their content
            if role == "AXList" || role == "AXTable" || role == "AXOutline" {
                // Try to get row content from lists/tables
                if let rows = copyAXArray(element, attribute: kAXRowsAttribute as String) {
                    for row in rows.prefix(50) { // Limit rows to prevent hanging
                        setAXTimeout(for: row)
                        if let rowValue = copyAXString(row, attribute: kAXValueAttribute) {
                            let trimmed = rowValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.count > 3 && !contents.contains(where: { $0.contains(trimmed) }) {
                                contents.append(trimmed)
                                print("[AccessibilityService] Found row text: \(trimmed.prefix(50))...")
                            }
                        }
                    }
                }
            }

            // Try AXHelp attribute (sometimes contains useful text)
            if let help = copyAXString(element, attribute: kAXHelpAttribute as String) {
                let trimmed = help.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 10 && !contents.contains(where: { $0.contains(trimmed) }) {
                    contents.append(trimmed)
                }
            }
        }
        
        // For web areas, get the entire value and stop recursion
        if role == "AXWebArea" {
            if let value = copyAXString(element, attribute: kAXValueAttribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 3 && !contents.contains(where: { $0.contains(trimmed) }) {
                    contents.append(trimmed)
                }
            }
            // Still recurse into web area children but with limited depth
            var childrenRef: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if error == .success, let children = childrenRef as? [AXUIElement] {
                for child in children.prefix(kMaxChildrenPerLevel) {
                    extractAllText(from: child, into: &contents, depth: depth + 1, maxTotal: maxTotal)
                }
            }
            return
        }
        
        // Recurse into children
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard error == .success, let children = childrenRef as? [AXUIElement] else { return }
        
        for child in children.prefix(kMaxChildrenPerLevel) {
            extractAllText(from: child, into: &contents, depth: depth + 1, maxTotal: maxTotal)
        }
    }

    func insertTextIntoFocusedElement(_ text: String, promptIfNeeded: Bool) -> Bool {
        guard ensurePermission(promptIfNeeded: promptIfNeeded) else {
            return false
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = createAppElement(pid: application.processIdentifier)
        guard let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) else {
            return false
        }
        
        setAXTimeout(for: focused)

        if copyAXBool(focused, attribute: axEditableAttribute) == true {
            let error = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, text as CFTypeRef)
            if error == .success {
                return true
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(9)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        cmdUp?.flags = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        return true
    }

    private func copyAXUIElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        if let result = value as! AXUIElement? {
            setAXTimeout(for: result)
            return result
        }
        return nil
    }

    private func copyAXString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value as? String
    }

    private func copyAXBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func copyAXArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func truncate(_ string: String, limit: Int) -> String {
        if string.count <= limit {
            return string
        }
        let prefix = String(string.prefix(limit))
        return prefix + "…"
    }
}
