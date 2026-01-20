import SwiftUI
import AppKit
import Textual

// MARK: - Markdown Text View (Textual SDK)
/// Simplified markdown rendering using Textual SDK
/// Replaces ~275 lines of custom parsing with production-ready library
struct MarkdownTextView: View {
    let content: String
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        // Textual's StructuredText provides rich markdown rendering
        // with code blocks, tables, syntax highlighting, and more
        StructuredText(markdown: content)
            .font(.system(size: 14 * scaleManager.scale))
            .textual.overflowMode(.wrap)      // Wrap long code blocks instead of scroll
            .textual.codeBlockStyle(CustomCodeBlockStyle())  // Custom style with copy button
            .textual.textSelection(.enabled)  // Enable text selection
    }
}

// MARK: - Custom Code Block Style with Copy Button
private struct CustomCodeBlockStyle: StructuredText.CodeBlockStyle {
    @ObservedObject private var scaleManager = AppScaleManager.shared

    func makeBody(configuration: Configuration) -> some View {
        CustomCodeBlockView(
            configuration: configuration,
            scaleManager: scaleManager
        )
    }
}

private struct CustomCodeBlockView: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    @ObservedObject var scaleManager: AppScaleManager
    @State private var isCopied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main code block content
            VStack(alignment: .leading, spacing: 0) {
                // Header with language hint (no button here - it's in overlay)
                HStack {
                    if let language = configuration.languageHint, !language.isEmpty {
                        Text(language)
                            .font(.system(size: 11 * scaleManager.scale))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Empty space for the button overlay
                    Color.clear.frame(width: 80, height: 24)
                        .allowsHitTesting(false)  // Don't block button clicks
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

                // Code content rendered by Textual with syntax highlighting
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.39))
                    .textual.fontScale(0.882 * scaleManager.scale)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Copy button as an overlay
            CopyButtonView(
                isCopied: $isCopied,
                scaleManager: scaleManager,
                onCopy: {
                    configuration.codeBlock.copyToPasteboard()
                }
            )
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
    }
}

// Custom NSButton with cursor tracking
private class CopyButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// Native AppKit button that sits outside the text selection layer
private struct CopyButtonView: NSViewRepresentable {
    @Binding var isCopied: Bool
    @ObservedObject var scaleManager: AppScaleManager
    let onCopy: () -> Void

    func makeNSView(context: Context) -> CopyButton {
        let button = CopyButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)
        return button
    }

    func updateNSView(_ button: CopyButton, context: Context) {
        context.coordinator.parent = self
        button.image = NSImage(
            systemSymbolName: isCopied ? "checkmark" : "doc.on.doc",
            accessibilityDescription: isCopied ? "Copied" : "Copy"
        )
        button.contentTintColor = isCopied ? .systemGreen : .secondaryLabelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: CopyButtonView

        init(parent: CopyButtonView) {
            self.parent = parent
        }

        @objc func buttonClicked() {
            print("[CodeBlock] Native button clicked")
            parent.onCopy()
            print("[CodeBlock] Setting isCopied = true")
            parent.isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("[CodeBlock] Resetting isCopied = false")
                self.parent.isCopied = false
            }
        }
    }
}
