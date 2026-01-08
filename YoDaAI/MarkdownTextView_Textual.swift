//
//  MarkdownTextView_Textual.swift
//  YoDaAI
//
//  Created by Claude Code
//  Textual SDK Integration - Simplified Markdown Rendering
//

import SwiftUI
import Textual

// MARK: - Textual-based Markdown Text View
/// Simplified markdown rendering using Textual SDK
/// Replaces ~275 lines of custom parsing with production-ready library
struct TextualMarkdownView: View {
    let content: String
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        // Note: Exact API will be determined once package is added
        // Common patterns from similar libraries:

        // Option 1: Direct Text extension
        // Text(markdown: content)

        // Option 2: Custom view
        // MarkdownText(content)

        // Option 3: AttributedString conversion
        // Text(AttributedString(markdown: content))

        // Textual's StructuredText provides rich markdown rendering
        // with code blocks, tables, syntax highlighting, and more
        StructuredText(markdown: content)
            .font(.system(size: 14 * scaleManager.scale))
            .textual.textSelection(.enabled)  // Enable text selection
            .textual.overflowMode(.wrap)      // Wrap long code blocks instead of scroll
    }
}

// MARK: - Preview
#Preview {
    TextualMarkdownView(content: """
    # Header 1
    ## Header 2

    This is **bold** and *italic* text.

    - List item 1
    - List item 2

    1. Ordered item
    2. Another item

    > Blockquote text

    ```swift
    func example() {
        print("Code block")
    }
    ```

    [Link](https://example.com)
    """)
    .padding()
}
