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
        return parseDrawioSegments(stripped)
    }

    var body: some View {
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
                        // Pass xml so the code block header shows a "View Diagram" button
                        MarkdownTextView(content: "```xml\n\(xml)\n```", drawioXML: xml)
                    } else {
                        // Plain text mode: just show the button
                        DrawioView(xmlContent: xml)
                    }
                }
            }
        }
    }
}
