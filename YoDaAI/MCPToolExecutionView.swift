//
//  MCPToolExecutionView.swift
//  YoDaAI
//

import SwiftUI

// MARK: - Tool Execution State

enum ToolExecutionState: Equatable {
    case preparing(toolCount: Int)
    case executing(current: Int, total: Int, toolName: String, query: String?)
    case processing
    case completed(results: [ToolExecutionResult])
    case failed(error: String)
}

struct ToolExecutionResult: Identifiable, Equatable {
    let id = UUID()
    let toolName: String
    let query: String?
    let resultPreview: String
    let fullResult: String
    let success: Bool

    static func == (lhs: ToolExecutionResult, rhs: ToolExecutionResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tool Execution Card View (Perplexity-style)

struct MCPToolExecutionCard: View {
    let state: ToolExecutionState
    @State private var isExpanded = false

    var body: some View {
        switch state {
        case .preparing(let toolCount):
            preparingView(toolCount: toolCount)
        case .executing(let current, let total, let toolName, let query):
            executingView(current: current, total: total, toolName: toolName, query: query)
        case .processing:
            processingView
        case .completed(let results):
            completedView(results: results)
        case .failed(let error):
            failedView(error: error)
        }
    }

    // MARK: - Preparing

    private func preparingView(toolCount: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)

            Text("Preparing \(toolCount) tool\(toolCount == 1 ? "" : "s")…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Executing

    private func executingView(current: Int, total: Int, toolName: String, query: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)

                Text(formatToolName(toolName))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if total > 1 {
                    Text("\(current)/\(total)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let query = query {
                Text("\"\(query)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if total > 1 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: geometry.size.width * (Double(current) / Double(total)), height: 3)
                            .animation(.easeInOut(duration: 0.3), value: current)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Processing

    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)

            Text("Processing results…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Completed (Perplexity-style collapsible pill)

    private func completedView(results: [ToolExecutionResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pill header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Used \(results.count) tool\(results.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expanded tool list
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { result in
                        toolResultRow(result: result)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolResultRow(result: ToolExecutionResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.success ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(result.success ? Color.green : Color.red)
                .frame(width: 14)

            Text(formatToolName(result.toolName))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            if let query = result.query {
                Text("\"\(query)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Failed

    private func failedView(error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tool failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)

                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.06))
        )
    }

    // MARK: - Helpers

    private func formatToolName(_ toolName: String) -> String {
        // Remove server prefix like "TavilySearch."
        let base: String
        if let dotIndex = toolName.lastIndex(of: ".") {
            base = String(toolName[toolName.index(after: dotIndex)...])
        } else {
            base = toolName
        }
        // Convert snake_case to readable name
        return base
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Previews

#Preview("Preparing") {
    MCPToolExecutionCard(state: .preparing(toolCount: 3))
        .padding()
        .frame(maxWidth: 380)
}

#Preview("Executing") {
    MCPToolExecutionCard(state: .executing(
        current: 2,
        total: 3,
        toolName: "TavilySearch.tavily_search",
        query: "What's happening in AI in 2026"
    ))
    .padding()
    .frame(maxWidth: 380)
}

#Preview("Processing") {
    MCPToolExecutionCard(state: .processing)
        .padding()
        .frame(maxWidth: 380)
}

#Preview("Completed") {
    MCPToolExecutionCard(state: .completed(results: [
        ToolExecutionResult(
            toolName: "TavilySearch.tavily_search",
            query: "AI news 2026",
            resultPreview: "{}",
            fullResult: "{}",
            success: true
        ),
        ToolExecutionResult(
            toolName: "TavilySearch.tavily_extract",
            query: "https://pjq.me",
            resultPreview: "{}",
            fullResult: "{}",
            success: true
        )
    ]))
    .padding()
    .frame(maxWidth: 380)
}

#Preview("Failed") {
    MCPToolExecutionCard(state: .failed(error: "Connection timeout after 60s"))
        .padding()
        .frame(maxWidth: 380)
}
