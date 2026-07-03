import SwiftUI
import AppKit
import Textual

// MARK: - Markdown Text View (Textual SDK)
/// Simplified markdown rendering using Textual SDK
/// Replaces ~275 lines of custom parsing with production-ready library
struct MarkdownTextView: View {
    let content: String
    /// When set, a "Open Diagram" button is shown in the code block header (drawio XML blocks).
    var drawioXML: String? = nil
    /// When set, a "View SVG" button is shown in the code block header (SVG blocks).
    var svgContent: String? = nil
    @Environment(\.appScaleManager) private var scaleManager

    /// Threshold above which we skip the Textual markdown parser to avoid stack overflow
    /// on deeply nested XML/SVG content.
    private static let markdownSizeLimit = 20_000

    var body: some View {
        if content.count > Self.markdownSizeLimit {
            // Large content can crash the markdown parser (stack overflow on nested XML)
            Text(content)
                .font(.system(size: 14 * scaleManager.scale))
                .textSelection(.enabled)
        } else {
            StructuredText(markdown: content)
                .font(.system(size: 14 * scaleManager.scale))
                .textual.overflowMode(.wrap)
                .textual.codeBlockStyle(CustomCodeBlockStyle(drawioXML: drawioXML, svgContent: svgContent))
        }
    }
}

// MARK: - Custom Code Block Style with Copy Button
private struct CustomCodeBlockStyle: StructuredText.CodeBlockStyle {
    let drawioXML: String?
    let svgContent: String?
    @Environment(\.appScaleManager) private var scaleManager

    func makeBody(configuration: Configuration) -> some View {
        CustomCodeBlockView(configuration: configuration, drawioXML: drawioXML, svgContent: svgContent)
    }
}

private struct CustomCodeBlockView: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    let drawioXML: String?
    let svgContent: String?
    @Environment(\.appScaleManager) private var scaleManager
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                // Language label
                if let language = configuration.languageHint, !language.isEmpty {
                    Text(drawioXML != nil ? "draw.io" : svgContent != nil ? "SVG" : language)
                        .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Draw.io: Open Diagram pill button
                if let xml = drawioXML {
                    Button {
                        openDiagramWindow(xmlContent: xml)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flowchart")
                                .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                            Text("Open Diagram")
                                .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help("Open diagram viewer")
                }

                // SVG: View SVG pill button
                if let svg = svgContent {
                    Button {
                        openSvgWindow(svgContent: svg)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                            Text("View SVG")
                                .font(.system(size: 11 * scaleManager.scale, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help("Open SVG viewer")
                }

                // Copy button
                CopyButtonView(isCopied: $isCopied) {
                    if let xml = drawioXML {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(stripXMLDeclaration(xml), forType: .string)
                    } else if let svg = svgContent {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(svg, forType: .string)
                    } else {
                        configuration.codeBlock.copyToPasteboard()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
                .font(.system(size: 12 * scaleManager.scale))
                .foregroundStyle(isCopied ? .green : .secondary)
                .padding(5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(isCopied ? "Copied!" : "Copy code")
    }
}
