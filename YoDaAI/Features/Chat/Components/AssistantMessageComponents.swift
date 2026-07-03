import SwiftUI
import AppKit
import Textual

/// Renders assistant message content as markdown (or plain text).
/// Tool call XML tags are stripped, and draw.io fenced blocks are rendered as diagrams.
struct AssistantMessageContentView: View {
    let content: String
    @ObservedObject private var llmSettings = LLMSettings.shared
    @Environment(\.appScaleManager) private var scaleManager

    private var segments: [ContentSegment] {
        let stripped = stripToolCallXML(content)
        let result = parseContentSegments(stripped)
        for (i, seg) in result.enumerated() {
            switch seg {
            case .text(let t): print("[AssistantContent] segment[\(i)] = .text(\(t.prefix(80))...)")
            case .drawio: print("[AssistantContent] segment[\(i)] = .drawio")
            case .svg(let s): print("[AssistantContent] segment[\(i)] = .svg(length=\(s.count))")
            }
        }
        return result
    }

    var body: some View {
        let _ = print("[AssistantContent] body called, \(segments.count) segments, markdown=\(llmSettings.enableMarkdown)")
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if !text.isEmpty {
                        if llmSettings.enableMarkdown {
                            MarkdownTextView(content: text)
                        } else {
                            Text(text)
                                .font(.system(size: 14 * scaleManager.scale))
                                .textSelection(.enabled)
                        }
                    }
                case .drawio(let xml):
                    if llmSettings.enableMarkdown {
                        MarkdownTextView(content: "```drawio\n\(xml)\n```", drawioXML: xml)
                    } else {
                        DrawioView(xmlContent: xml)
                    }
                case .svg(let svgContent):
                    // Show a compact preview with View SVG button — don't pass large SVG to markdown parser
                    SvgPreviewView(svgContent: svgContent, enableMarkdown: llmSettings.enableMarkdown)
                }
            }
        }
    }
}
