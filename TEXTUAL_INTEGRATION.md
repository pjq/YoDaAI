# Textual Markdown SDK Integration Plan

## Current Status
- ✅ Branch created: `feature/integrate-textual-markdown`
- ✅ Import statement added to ContentView.swift
- ⏳ Package dependency needs to be added in Xcode
- ⏳ Implementation replacement pending

## What Needs to Be Replaced

**File:** `YoDaAI/ContentView.swift`
**Section:** Lines 1139-1413 (~275 lines)

### Current Custom Implementation

```swift
// MARK: - Markdown Text View
private struct MarkdownTextView: View {
    // ~275 lines of custom parsing logic
    // - parseBlocks() - regex-based block parser
    // - parseTextBlock() - line-by-line parser
    // - attributedString() - inline formatting
    // - Custom views for headers, lists, blockquotes, etc.
}
```

**Problems with current implementation:**
- Complex regex patterns
- Manual block-level parsing
- Edge case handling
- ~300 lines of maintenance burden
- Performance concerns (now cached, but still heavy)

## Integration Steps

### Step 1: Add Package Dependency (IN PROGRESS)

**Manual Steps in Xcode:**
1. Open `YoDaAI.xcodeproj`
2. Project navigator → Select project → Package Dependencies tab
3. Click '+' button
4. Enter URL: `https://github.com/gonzalezreal/textual`
5. Version: "Up to Next Major Version" starting from "1.0.0"
6. Add to YoDaAI target
7. Build to verify package resolves

**Or via command line** (if you have swift-package CLI set up):
```bash
# This may not work for .xcodeproj, but worth trying
swift package resolve
```

### Step 2: Test Textual API

Once package is added, we'll:
1. Build the project to see what API Textual provides
2. Check for `Text.markdown()`, `MarkdownText()`, or similar views
3. Understand customization options for fonts, colors, etc.

### Step 3: Replace Implementation

Based on typical markdown libraries, the replacement should look like:

```swift
// MARK: - Markdown Text View (Textual)
private struct MarkdownTextView: View {
    let content: String
    @ObservedObject private var scaleManager = AppScaleManager.shared

    var body: some View {
        // Textual's API (exact syntax TBD)
        Text(markdown: content)
            .font(.system(size: 14 * scaleManager.scale))
            // Custom styling if supported
    }
}
```

**Expected reduction:** ~275 lines → ~20 lines

### Step 4: Verify Features

Test that Textual supports all current features:
- ✅ Code blocks with syntax highlighting
- ✅ Headers (H1-H6)
- ✅ Bold/italic text
- ✅ Links
- ✅ Lists (ordered/unordered)
- ✅ Blockquotes
- ✅ Horizontal rules
- ✅ Inline code

### Step 5: Handle Edge Cases

Check if Textual handles:
- Empty content
- Invalid markdown syntax
- Very long content
- Special characters
- Nested structures

### Step 6: Code Cleanup

Remove old implementation:
- Delete parseBlocks()
- Delete parseTextBlock()
- Delete attributedString() (if no longer needed)
- Delete Block enum
- Delete custom view builders

## Benefits of Textual

1. **Less code:** ~275 lines → ~20 lines (93% reduction)
2. **Better parsing:** Production-tested CommonMark parser
3. **More features:** Likely supports tables, task lists, strikethrough
4. **Better performance:** Optimized rendering
5. **No maintenance:** SDK handles bug fixes and updates
6. **Standard compliance:** Follows CommonMark spec

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| API doesn't match expectations | Keep old code until verified |
| Missing features | Check documentation, file issues |
| Performance regression | Benchmark before/after |
| Styling limitations | Check customization options |
| Breaking changes in updates | Pin to specific version |

## Testing Plan

1. **Visual comparison:** Render same content with both implementations
2. **Feature parity:** Test all markdown features
3. **Edge cases:** Test error handling
4. **Performance:** Measure render time for long documents
5. **Streaming:** Verify works during live streaming
6. **Scrolling:** Ensure no performance regression

## Rollback Plan

If Textual doesn't work out:
```bash
git checkout main
# Old implementation remains intact
```

## Next Actions

1. ✅ Add package dependency in Xcode (YOU)
2. Build and check API (CLAUDE)
3. Implement replacement (CLAUDE)
4. Test thoroughly (BOTH)
5. Commit changes (CLAUDE)
6. Merge to main or keep branch (YOU)

---

**Status:** Waiting for package dependency to be added in Xcode

**Branch:** `feature/integrate-textual-markdown`

**Contact:** Ready to proceed once package is added!
