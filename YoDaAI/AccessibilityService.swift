import AppKit
import ApplicationServices
import Foundation

private let axEditableAttribute = "AXEditable" // kAXEditableAttribute is not always imported into Swift

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

        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        if let window = copyAXUIElement(appElement, attribute: kAXFocusedWindowAttribute) {
            windowTitle = copyAXString(window, attribute: kAXTitleAttribute)
        }

        if let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) {
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
        print("[AccessibilityService] Capturing context for: \(appName)")
        
        var windowTitle: String?
        var focusedRole: String?
        var focusedValuePreview: String?
        var focusedIsEditable = false
        var focusedIsSecure = false
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Try multiple approaches to get content
        var contents: [String] = []
        
        // 1. Try to get selected text first (most reliable for active content)
        if let selectedText = copyAXString(appElement, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
            print("[AccessibilityService] Found selected text: \(selectedText.prefix(100))...")
            contents.append(selectedText)
        }
        
        // 2. Get all windows
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            print("[AccessibilityService] Found \(windows.count) windows")
            let mainWindow = windows[0]
            windowTitle = copyAXString(mainWindow, attribute: kAXTitleAttribute)
            print("[AccessibilityService] Window title: \(windowTitle ?? "nil")")
            
            // Try to get document content
            if let docValue = copyAXString(mainWindow, attribute: kAXDocumentAttribute as String), !docValue.isEmpty {
                print("[AccessibilityService] Found document: \(docValue.prefix(100))...")
                contents.append(docValue)
            }
            
            // Extract content from window hierarchy
            extractAllText(from: mainWindow, into: &contents, depth: 0)
        } else {
            print("[AccessibilityService] No windows found, error: \(windowsError.rawValue)")
        }
        
        // 3. Try focused element
        if let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) {
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
                if !contents.contains(value) {
                    contents.append(value)
                }
            }
            
            // Get selected text from focused element
            if let selectedText = copyAXString(focused, attribute: kAXSelectedTextAttribute as String), !selectedText.isEmpty {
                if !contents.contains(selectedText) {
                    contents.append(selectedText)
                }
            }
        }
        
        // Combine all content
        let combinedContent = contents
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        
        if !combinedContent.isEmpty {
            focusedValuePreview = truncate(combinedContent, limit: 4000)
            print("[AccessibilityService] Total content captured: \(focusedValuePreview?.count ?? 0) chars")
        } else {
            print("[AccessibilityService] No content captured")
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
    private func extractAllText(from element: AXUIElement, into contents: inout [String], depth: Int) {
        guard depth < 20 else { return }
        guard contents.joined().count < 8000 else { return }
        
        // Get role
        let role = copyAXString(element, attribute: kAXRoleAttribute)
        
        // Try to get text value
        if let value = copyAXString(element, attribute: kAXValueAttribute) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 3 && !contents.contains(trimmed) {
                contents.append(trimmed)
            }
        }
        
        // For text elements, also check title and description
        if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" {
            if let title = copyAXString(element, attribute: kAXTitleAttribute) {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 3 && !contents.contains(trimmed) {
                    contents.append(trimmed)
                }
            }
        }
        
        // For web areas, get the entire value and stop recursion
        if role == "AXWebArea" {
            if let value = copyAXString(element, attribute: kAXValueAttribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 3 && !contents.contains(trimmed) {
                    contents.append(trimmed)
                }
            }
            return
        }
        
        // Recurse into children
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard error == .success, let children = childrenRef as? [AXUIElement] else { return }
        
        for child in children.prefix(150) {
            extractAllText(from: child, into: &contents, depth: depth + 1)
        }
    }

    func insertTextIntoFocusedElement(_ text: String, promptIfNeeded: Bool) -> Bool {
        guard ensurePermission(promptIfNeeded: promptIfNeeded) else {
            return false
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) else {
            return false
        }

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
        return value as! AXUIElement?
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

    private func truncate(_ string: String, limit: Int) -> String {
        if string.count <= limit {
            return string
        }
        let prefix = String(string.prefix(limit))
        return prefix + "…"
    }
}
