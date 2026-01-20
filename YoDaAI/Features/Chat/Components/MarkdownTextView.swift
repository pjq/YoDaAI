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
            .textual.textSelection(.enabled)  // Enable text selection using Textual's modifier
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

            // Copy button as an overlay - outside the text selection context
            CopyButtonView(
                isCopied: $isCopied,
                scaleManager: scaleManager,
                onCopy: {
                    configuration.codeBlock.copyToPasteboard()
                }
            )
            .padding(.top, 8)
            .padding(.trailing, 12)
            .allowsHitTesting(true)  // Ensure button receives clicks
            .zIndex(1000)  // Ensure button is on top of text selection
        }
    }
}

// Separate view for the copy button to completely isolate it from text selection
private struct CopyButtonView: View {
    @Binding var isCopied: Bool
    @ObservedObject var scaleManager: AppScaleManager
    let onCopy: () -> Void

    var body: some View {
        Button(action: {
            print("[CodeBlock] Copy button clicked")
            onCopy()
            print("[CodeBlock] Setting isCopied = true")
            withAnimation {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("[CodeBlock] Resetting isCopied = false")
                withAnimation {
                    isCopied = false
                }
            }
        }) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13 * scaleManager.scale))
                .foregroundStyle(isCopied ? .green : .secondary)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)  // Explicitly allow button to receive events
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
