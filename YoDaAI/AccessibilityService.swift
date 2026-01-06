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
