import SwiftUI
import AppKit

/// NSView wrapper to intercept paste commands
struct PasteInterceptor: NSViewRepresentable {
    let onPaste: () -> Void

    func makeNSView(context: Context) -> PasteHandlerView {
        let view = PasteHandlerView()
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: PasteHandlerView, context: Context) {
        nsView.onPaste = onPaste
    }

    class PasteHandlerView: NSView {
        var onPaste: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Check for Cmd+V
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                // Check if pasteboard has image
                let pasteboard = NSPasteboard.general
                if NSImage(pasteboard: pasteboard) != nil {
                    onPaste?()
                    return true // Consume event
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        override var acceptsFirstResponder: Bool { true }
    }
}
