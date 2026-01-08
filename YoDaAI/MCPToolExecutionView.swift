//
//  MCPToolExecutionView.swift
//  YoDaAI
//
//  Created by Claude Code
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

// MARK: - Tool Execution Card View

struct MCPToolExecutionCard: View {
    let state: ToolExecutionState
    @State private var expandedResults: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            iconView

            Text(titleText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if case .executing = state {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private var iconView: some View {
        Group {
            switch state {
            case .preparing:
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
            case .executing:
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
            case .processing:
                Image(systemName: "gearshape.2.fill")
                    .foregroundColor(.orange)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 16))
    }

    private var titleText: String {
        switch state {
        case .preparing: return "Preparing Tools"
        case .executing: return "Executing Tool"
        case .processing: return "Processing Results"
        case .completed: return "Tool Execution Complete"
        case .failed: return "Tool Execution Failed"
        }
    }

    // MARK: - State Views

    private func preparingView(toolCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preparing to execute \(toolCount) tool\(toolCount == 1 ? "" : "s")...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private func executingView(current: Int, total: Int, toolName: String, query: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(current) of \(total)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(Double(current) / Double(total) * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * (Double(current) / Double(total)), height: 6)
                            .animation(.easeInOut(duration: 0.3), value: current)
                    }
                }
                .frame(height: 6)
            }

            // Tool details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)

                    Text(formatToolName(toolName))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }

                if let query = query {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text(query)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.05))
            )
        }
    }

    private var processingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Processing tool results...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedView(results: [ToolExecutionResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Executed \(results.count) tool\(results.count == 1 ? "" : "s") successfully")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            // Results list
            VStack(spacing: 8) {
                ForEach(results) { result in
                    resultRow(result: result)
                }
            }
        }
    }

    private func resultRow(result: ToolExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if expandedResults.contains(result.id) {
                    expandedResults.remove(result.id)
                } else {
                    expandedResults.insert(result.id)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(result.success ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatToolName(result.toolName))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let query = result.query {
                            Text(query)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: expandedResults.contains(result.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedResults.contains(result.id) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text("Result Preview:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(result.resultPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                        )

                    if result.fullResult.count > result.resultPreview.count {
                        Text("+ \(result.fullResult.count - result.resultPreview.count) more characters")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(result.success ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: expandedResults.contains(result.id))
    }

    private func failedView(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool execution failed")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)

            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                )
        }
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        switch state {
        case .preparing, .executing, .processing:
            return Color.blue.opacity(0.03)
        case .completed:
            return Color.green.opacity(0.03)
        case .failed:
            return Color.red.opacity(0.03)
        }
    }

    private var borderColor: Color {
        switch state {
        case .preparing, .executing, .processing:
            return Color.blue.opacity(0.3)
        case .completed:
            return Color.green.opacity(0.3)
        case .failed:
            return Color.red.opacity(0.3)
        }
    }

    private func formatToolName(_ toolName: String) -> String {
        // Remove prefix like "TailySearch."
        if let dotIndex = toolName.lastIndex(of: ".") {
            let name = String(toolName[toolName.index(after: dotIndex)...])
            // Convert snake_case or camelCase to Title Case
            return name
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return toolName
    }
}

// MARK: - Preview

#Preview("Preparing") {
    MCPToolExecutionCard(state: .preparing(toolCount: 3))
        .padding()
        .frame(maxWidth: 400)
}

#Preview("Executing") {
    MCPToolExecutionCard(state: .executing(
        current: 2,
        total: 3,
        toolName: "TailySearch.tavily_search",
        query: "What's happening in 2026 events predictions"
    ))
    .padding()
    .frame(maxWidth: 400)
}

#Preview("Completed") {
    MCPToolExecutionCard(state: .completed(results: [
        ToolExecutionResult(
            toolName: "TailySearch.tavily_search",
            query: "pjq.me website owner",
            resultPreview: "{\"query\":\"pjq.me\",\"results\":[{\"title\":\"Jianqing's Blog\",\"url\":\"https://pjq.me\"}]}",
            fullResult: "{\"query\":\"pjq.me website owner\",\"results\":[{\"title\":\"Jianqing's Blog\",\"url\":\"https://pjq.me\",\"content\":\"Personal blog of Peng Jianqing covering tech, AI, and SAP development topics.\"}]}",
            success: true
        ),
        ToolExecutionResult(
            toolName: "TailySearch.tavily_extract",
            query: nil,
            resultPreview: "{\"results\":[{\"url\":\"https://pjq.me\",\"title\":\"Jianqing's Blog\"}]}",
            fullResult: "{\"results\":[{\"url\":\"https://pjq.me\",\"title\":\"Jianqing's Blog\",\"raw_content\":\"Jianqing's Blog - Thoughts and Future\"}]}",
            success: true
        )
    ]))
    .padding()
    .frame(maxWidth: 400)
}
