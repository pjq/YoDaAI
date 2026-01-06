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
            return nil
        }
        
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        
        let appName = app.localizedName ?? "(Unknown App)"
        
        var windowTitle: String?
        var focusedRole: String?
        var focusedValuePreview: String?
        var focusedIsEditable = false
        var focusedIsSecure = false
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Try to get focused window first, fall back to main window
        if let window = copyAXUIElement(appElement, attribute: kAXFocusedWindowAttribute)
                     ?? copyAXUIElement(appElement, attribute: kAXMainWindowAttribute) {
            windowTitle = copyAXString(window, attribute: kAXTitleAttribute)
            
            // Try to get content from the window - look for text areas, web views, etc.
            if let content = extractWindowContent(from: window) {
                focusedValuePreview = truncate(content, limit: 2000)
            }
        }
        
        // Also try focused element if available
        if let focused = copyAXUIElement(appElement, attribute: kAXFocusedUIElementAttribute) {
            focusedRole = copyAXString(focused, attribute: kAXRoleAttribute)
            
            if let editable = copyAXBool(focused, attribute: axEditableAttribute) {
                focusedIsEditable = editable
            }
            
            let subrole = copyAXString(focused, attribute: kAXSubroleAttribute)
            if subrole == kAXSecureTextFieldSubrole as String {
                focusedIsSecure = true
            }
            
            // If we didn't get content from window, try focused element
            if focusedValuePreview == nil || focusedValuePreview?.isEmpty == true {
                if let value = copyAXString(focused, attribute: kAXValueAttribute) {
                    focusedValuePreview = truncate(value, limit: 2000)
                }
            }
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
    
    /// Extract text content from a window by traversing its element tree
    private func extractWindowContent(from window: AXUIElement) -> String? {
        var contents: [String] = []
        
        // Try to find text content in the window hierarchy
        collectTextContent(from: window, into: &contents, depth: 0, maxDepth: 10)
        
        let combined = contents.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }
    
    /// Recursively collect text content from accessibility elements
    private func collectTextContent(from element: AXUIElement, into contents: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        
        let role = copyAXString(element, attribute: kAXRoleAttribute)
        
        // Get value from text-like elements
        if let role = role {
            let textRoles = ["AXTextArea", "AXTextField", "AXStaticText", "AXWebArea", "AXGroup"]
            if textRoles.contains(role) {
                if let value = copyAXString(element, attribute: kAXValueAttribute), !value.isEmpty {
                    contents.append(value)
                    return // Don't recurse into text elements
                }
            }
        }
        
        // Recurse into children
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard error == .success, let children = childrenRef as? [AXUIElement] else { return }
        
        for child in children.prefix(50) { // Limit to prevent infinite recursion
            collectTextContent(from: child, into: &contents, depth: depth + 1, maxDepth: maxDepth)
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
