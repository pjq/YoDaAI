import SwiftUI
import AppKit

// MARK: - Tool Call View

/// View for displaying MCP tool calls in assistant messages
struct ToolCallView: View {
    let toolName: String
    let arguments: String?
    let isExpanded: Bool
    let onToggle: () -> Void

    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10 * scaleManager.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11 * scaleManager.scale))
                        .foregroundStyle(.orange)

                    Text("Tool: \(toolName)")
                        .font(.system(size: 12 * scaleManager.scale, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            if isExpanded, let args = arguments, !args.isEmpty {
                Text(args)
                    .font(.system(size: 11 * scaleManager.scale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    .padding(.leading, 18)
            }
        }
    }
}

/// View for displaying MCP tool results in assistant messages
struct ToolResultView: View {
    let toolName: String
    let result: String
    let isExpanded: Bool
    let onToggle: () -> Void

    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10 * scaleManager.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11 * scaleManager.scale))
                        .foregroundStyle(.green)

                    Text("Result: \(toolName)")
                        .font(.system(size: 12 * scaleManager.scale, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(result)
                    .font(.system(size: 11 * scaleManager.scale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    .padding(.leading, 18)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Helper to parse and render content with tool calls/results
struct AssistantMessageContentView: View {
    let content: String
    @State private var expandedToolCalls: Set<Int> = []
    @State private var expandedToolResults: Set<Int> = []
    @State private var cachedSegments: [ContentSegment]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let segments = cachedSegments ?? parseContentSegments(content)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                switch segment {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownTextView(content: text)
                    }

                case .toolCall(let name, let args):
                    ToolCallView(
                        toolName: name,
                        arguments: args,
                        isExpanded: expandedToolCalls.contains(index),
                        onToggle: {
                            if expandedToolCalls.contains(index) {
                                expandedToolCalls.remove(index)
                            } else {
                                expandedToolCalls.insert(index)
                            }
                        }
                    )

                case .toolResult(let name, let result):
                    ToolResultView(
                        toolName: name,
                        result: result,
                        isExpanded: expandedToolResults.contains(index),
                        onToggle: {
                            if expandedToolResults.contains(index) {
                                expandedToolResults.remove(index)
                            } else {
                                expandedToolResults.insert(index)
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            if cachedSegments == nil {
                cachedSegments = parseContentSegments(content)
            }
        }
        .onChange(of: content) { _, newContent in
            // Re-parse when content changes (during streaming)
            cachedSegments = parseContentSegments(newContent)
        }
    }

    private enum ContentSegment {
        case text(String)
        case toolCall(name: String, arguments: String?)
        case toolResult(name: String, result: String)
    }

    private func parseContentSegments(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        let remaining = content

        // Pattern for tool calls: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
        let toolCallPattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
        // Pattern for tool results: <tool_result name="...">...</tool_result>
        let toolResultPattern = #"<tool_result name="([^"]+)">([\s\S]*?)</tool_result>"#

        // Combined pattern to find either
        let combinedPattern = "(\(toolCallPattern))|(\(toolResultPattern))"

        guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: []) else {
            return [.text(content)]
        }

        var lastEnd = remaining.startIndex
        let nsRange = NSRange(remaining.startIndex..., in: remaining)

        regex.enumerateMatches(in: remaining, options: [], range: nsRange) { match, _, _ in
            guard let match = match else { return }

            let matchRange = Range(match.range, in: remaining)!

            // Add text before this match
            if lastEnd < matchRange.lowerBound {
                let textBefore = String(remaining[lastEnd..<matchRange.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(textBefore))
                }
            }

            // Check if it's a tool call (group 2) or tool result (groups 4,5)
            if let jsonRange = Range(match.range(at: 2), in: remaining) {
                // Tool call
                let jsonString = String(remaining[jsonRange])
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["name"] as? String {
                    let args: String?
                    if let argsDict = json["arguments"] {
                        if let argsData = try? JSONSerialization.data(withJSONObject: argsDict, options: .prettyPrinted) {
                            args = String(data: argsData, encoding: .utf8)
                        } else {
                            args = nil
                        }
                    } else {
                        args = nil
                    }
                    segments.append(.toolCall(name: name, arguments: args))
                }
            } else if let nameRange = Range(match.range(at: 4), in: remaining),
                      let resultRange = Range(match.range(at: 5), in: remaining) {
                // Tool result
                let name = String(remaining[nameRange])
                let result = String(remaining[resultRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                segments.append(.toolResult(name: name, result: result))
            }

            lastEnd = matchRange.upperBound
        }

        // Add remaining text
        if lastEnd < remaining.endIndex {
            let textAfter = String(remaining[lastEnd...])
            if !textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(textAfter))
            }
        }

        // If no segments found, return the whole content as text
        if segments.isEmpty {
            return [.text(content)]
        }

        return segments
    }
}
