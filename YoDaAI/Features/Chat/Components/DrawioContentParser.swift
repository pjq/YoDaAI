import Foundation

// MARK: - Content Segment

/// Represents a parsed segment of assistant message content.
enum ContentSegment {
    case text(String)
    case drawio(xml: String)
    case svg(content: String)
}

// MARK: - Parser

/// Parses assistant message content into text, draw.io diagram, and SVG segments.
/// Detects ```drawio, ```svg fenced code blocks (and ```xml blocks containing mxGraph/SVG XML).
func parseContentSegments(_ content: String) -> [ContentSegment] {
    print("[Parser] parseContentSegments called, content length: \(content.count)")
    // Normalize line endings — streaming responses may contain \r\n
    let content = content.replacingOccurrences(of: "\r\n", with: "\n")

    // Pattern matches ```drawio ... ``` or ```xml ... ``` (where content looks like mxGraph)
    let pattern = #"```(?:drawio|xml|svg)\n([\s\S]*?)\n?```"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        print("[Parser] regex creation failed")
        return [.text(content)]
    }

    let nsContent = content as NSString
    let fullRange = NSRange(location: 0, length: nsContent.length)
    let matches = regex.matches(in: content, range: fullRange)
    print("[Parser] found \(matches.count) matches")

    if matches.isEmpty {
        return [.text(content)]
    }

    var segments: [ContentSegment] = []
    var lastEnd = 0

    for (i, match) in matches.enumerated() {
        let matchRange = match.range
        let captureRange = match.range(at: 1)
        print("[Parser] match \(i): range=\(matchRange.location)..\(matchRange.location + matchRange.length)")

        // Text before this match
        if matchRange.location > lastEnd {
            let textRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
            let text = nsContent.substring(with: textRange)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(.text(trimmed))
            }
        }

        // The code block content — use NSString to avoid UTF-16 index misalignment on emoji
        if captureRange.location != NSNotFound {
            let xml = nsContent.substring(with: captureRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let fenceStr = nsContent.substring(with: matchRange)
            let explicitDrawio = fenceStr.hasPrefix("```drawio")
            let explicitSvg = fenceStr.hasPrefix("```svg")
            let isSvgBlock = explicitSvg || isSVGContent(xml)
            let isDrawioBlock = explicitDrawio || isDrawioXML(xml)
            print("[Parser] match \(i): explicitSvg=\(explicitSvg), isSvgBlock=\(isSvgBlock), isDrawioBlock=\(isDrawioBlock), contentLength=\(xml.count)")

            if isSvgBlock {
                print("[Parser] -> SVG segment, length=\(xml.count)")
                segments.append(.svg(content: xml))
            } else if isDrawioBlock {
                segments.append(.drawio(xml: xml))
            } else {
                segments.append(.text(fenceStr))
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
    // Primary markers: mxGraph root elements (plain or HTML-entity-encoded)
    if lowered.contains("<mxfile") || lowered.contains("&lt;mxfile") { return true }
    if lowered.contains("<mxgraphmodel") || lowered.contains("&lt;mxgraphmodel") { return true }
    // Secondary markers: common mxGraph child elements
    if lowered.contains("<mxcell") || lowered.contains("&lt;mxcell") { return true }
    if lowered.contains("<mxgeometry") || lowered.contains("&lt;mxgeometry") { return true }
    return false
}

private func isSVGContent(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.hasPrefix("<svg") { return true }
    // Handle XML declaration before SVG root
    if trimmed.hasPrefix("<?xml") && trimmed.contains("<svg") { return true }
    return false
}


// MARK: - XML Declaration Stripping

/// Safely removes the `<?xml ... ?>` processing instruction from the start of an XML string.
/// Uses plain string scanning instead of regex to avoid crashes on unusual Unicode content.
func stripXMLDeclaration(_ xml: String) -> String {
    let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("<?xml") else { return xml }
    // Find the closing '?>' and drop everything up to and including it
    if let closeRange = trimmed.range(of: "?>") {
        let after = trimmed[closeRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? xml : after
    }
    return xml
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
