import SwiftUI
import AppKit
import Textual

// MARK: - Markdown Text View (Textual SDK)
/// Simplified markdown rendering using Textual SDK
/// Replaces ~275 lines of custom parsing with production-ready library
struct MarkdownTextView: View {
    let content: String
    /// When set, a "View Diagram" button is shown in the code block header (drawio XML blocks).
    var drawioXML: String? = nil
    @Environment(\.appScaleManager) private var scaleManager

    var body: some View {
        StructuredText(markdown: content)
            .font(.system(size: 14 * scaleManager.scale))
            .textual.overflowMode(.wrap)
            .textual.codeBlockStyle(CustomCodeBlockStyle(drawioXML: drawioXML))
    }
}

// MARK: - Custom Code Block Style with Copy Button
private struct CustomCodeBlockStyle: StructuredText.CodeBlockStyle {
    let drawioXML: String?
    @Environment(\.appScaleManager) private var scaleManager

    func makeBody(configuration: Configuration) -> some View {
        CustomCodeBlockView(configuration: configuration, drawioXML: drawioXML)
    }
}

private struct CustomCodeBlockView: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    let drawioXML: String?
    @Environment(\.appScaleManager) private var scaleManager
    @State private var isCopied = false
    @State private var showDiagramSheet = false

    // Number of action buttons shown in the header overlay
    private var buttonCount: Int { drawioXML != nil ? 2 : 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main code block content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    if let language = configuration.languageHint, !language.isEmpty {
                        Text(language)
                            .font(.system(size: 11 * scaleManager.scale))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Reserve space for the button overlay so text doesn't underlap buttons
                    Color.clear.frame(width: CGFloat(buttonCount) * 32, height: 24)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

                configuration.label
                    .textual.lineSpacing(.fontScaled(0.39))
                    .textual.fontScale(0.882 * scaleManager.scale)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Button row overlay (top-right)
            HStack(spacing: 4) {
                if let xml = drawioXML {
                    DiagramButtonView(showSheet: $showDiagramSheet)
                        .sheet(isPresented: $showDiagramSheet) {
                            DrawioDiagramSheet(xmlContent: xml)
                        }
                }
                CopyButtonView(isCopied: $isCopied) {
                    if let xml = drawioXML {
                        // Strip XML declaration header — draw.io app can't parse it
                        let cleaned = xml.replacingOccurrences(
                            of: #"<\?xml[^?]*\?>\s*"#,
                            with: "",
                            options: .regularExpression
                        )
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cleaned, forType: .string)
                    } else {
                        configuration.codeBlock.copyToPasteboard()
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
    }
}

// "View Diagram" button
private struct DiagramButtonView: View {
    @Binding var showSheet: Bool
    @Environment(\.appScaleManager) private var scaleManager

    var body: some View {
        Button(action: { showSheet = true }) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 13 * scaleManager.scale))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("View Diagram")
    }
}

// Copy button view
private struct CopyButtonView: View {
    @Binding var isCopied: Bool
    @Environment(\.appScaleManager) private var scaleManager
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
