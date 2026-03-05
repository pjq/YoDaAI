import Foundation

// MARK: - Content Segment

/// Represents a parsed segment of assistant message content.
enum ContentSegment {
    case text(String)
    case drawio(xml: String)
}

// MARK: - Parser

/// Parses assistant message content into text and draw.io diagram segments.
/// Detects ```drawio fenced code blocks (and ```xml blocks containing mxGraph XML).
func parseDrawioSegments(_ content: String) -> [ContentSegment] {
    // Pattern matches ```drawio ... ``` or ```xml ... ``` (where content looks like mxGraph)
    let pattern = #"```(?:drawio|xml)\n([\s\S]*?)\n?```"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return [.text(content)]
    }

    let nsContent = content as NSString
    let fullRange = NSRange(location: 0, length: nsContent.length)
    let matches = regex.matches(in: content, range: fullRange)

    if matches.isEmpty {
        return [.text(content)]
    }

    var segments: [ContentSegment] = []
    var lastEnd = 0

    for match in matches {
        let matchRange = match.range
        let captureRange = match.range(at: 1)

        // Text before this match
        if matchRange.location > lastEnd {
            let textRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
            let text = nsContent.substring(with: textRange)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(.text(trimmed))
            }
        }

        // The code block content
        if captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: content) {
            let xml = String(content[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Must look like XML (starts with <) to be treated as a diagram
            let looksLikeXML = xml.hasPrefix("<")
            let isDrawioBlock = looksLikeXML && (isDrawioXML(xml) || isExplicitDrawioFence(match, in: content))
            if isDrawioBlock {
                segments.append(.drawio(xml: xml))
            } else {
                // Not valid diagram XML — restore original fenced block as text
                let original = nsContent.substring(with: matchRange)
                segments.append(.text(original))
            }
        }

        lastEnd = matchRange.location + matchRange.length
    }

    // Remaining text after last match
    if lastEnd < nsContent.length {
        let textRange = NSRange(location: lastEnd, length: nsContent.length - lastEnd)
        let text = nsContent.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            segments.append(.text(text))
        }
    }

    return segments
}

// MARK: - Helpers

private func isDrawioXML(_ xml: String) -> Bool {
    let lowered = xml.lowercased()
    return lowered.contains("<mxfile") || lowered.contains("<mxgraphmodel")
}

private func isExplicitDrawioFence(_ match: NSTextCheckingResult, in content: String) -> Bool {
    guard let range = Range(match.range, in: content) else { return false }
    let fence = String(content[range])
    return fence.hasPrefix("```drawio")
}

// MARK: - Tool Call Stripping

private let toolCallStripRegex: NSRegularExpression? = {
    let pattern = #"<tool_call>[\s\S]*?</tool_call>|<tool_result[^>]*>[\s\S]*?</tool_result>"#
    return try? NSRegularExpression(pattern: pattern, options: [])
}()

/// Strips tool call/result XML tags from a text string.
func stripToolCallXML(_ text: String) -> String {
    guard let regex = toolCallStripRegex else { return text }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
