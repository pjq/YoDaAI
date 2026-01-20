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
            // Text selection disabled to allow copy button to work
            // This is a limitation of the Textual SDK - cannot have both simultaneously
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

// Copy button view
private struct CopyButtonView: View {
    @Binding var isCopied: Bool
    @ObservedObject var scaleManager: AppScaleManager
    let onCopy: () -> Void

    var body: some View {
        Button(action: {
            onCopy()
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isCopied = false
            }
        }) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13 * scaleManager.scale))
                .foregroundStyle(isCopied ? .green : .secondary)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
