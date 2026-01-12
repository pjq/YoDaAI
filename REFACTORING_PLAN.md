# YoDaAI Refactoring Plan

## Problem 1: ContentView.swift is Too Large (4156 lines)

### Current Structure
- ContentView (main view)
- GeneralSettingsContent
- APIKeysSettingsContent
- MCPServersSettingsContent
- PermissionsSettingsContent
- Many helper views and components

### Proposed Refactoring

#### Phase 1: Extract Settings Views (Priority: High)
Create new files in `YoDaAI/Views/Settings/`:
- `GeneralSettingsView.swift` - General settings tab
- `APIKeysSettingsView.swift` - LLM provider management
- `MCPServersSettingsView.swift` - MCP server configuration
- `PermissionsSettingsView.swift` - Per-app permissions
- `SettingsView.swift` - Main settings container

#### Phase 2: Extract Chat Components (Priority: High)
Create new files in `YoDaAI/Views/Chat/`:
- `ChatDetailView.swift` - Main chat area
- `MessageRowView.swift` - Individual message bubble
- `MessageListView.swift` - Scrollable message list
- `ComposerView.swift` - Message input area
- `ChatHeaderView.swift` - Chat title bar
- `MentionChipView.swift` - @ mention chips
- `AppIconView.swift` - App icon helper

#### Phase 3: Extract Thread Components (Priority: Medium)
Create new files in `YoDaAI/Views/Sidebar/`:
- `ThreadListView.swift` - Sidebar thread list
- `ThreadRowView.swift` - Individual thread row

#### Phase 4: Extract Helper Views (Priority: Low)
Create new files in `YoDaAI/Views/Components/`:
- `ModelPickerView.swift` - Model selection dropdown
- `FloatingPanelView.swift` - Floating capture panel

---

## Problem 2: UI Freezing / Main Thread Blocking

### Root Causes

#### 1. **SwiftData saves on Main Thread**
**Location**: ChatViewModel.swift lines 399, 408, 439, 657, 699, 718, 725, 867, 950
```swift
try context.save()  // Blocks UI thread!
```

**Impact**: Every message send/receive blocks UI for database write

**Solution**: Use background ModelContext
```swift
// Create background context
let backgroundContext = ModelContext(container)

Task.detached {
    // Perform heavy work on background
    backgroundContext.insert(message)
    try backgroundContext.save()

    await MainActor.run {
        // Update UI after save completes
    }
}
```

#### 2. **Accessibility API Calls on Main Thread**
**Location**: ChatViewModel.swift lines 347, 552, 584
```swift
snapshot = await accessibilityService.captureContextWithActivation(...)
```

**Impact**: Capturing content can take 300ms+ (app activation + wait time)

**Solution**: Already async, but need to ensure it doesn't block UI updates

#### 3. **Image Processing on Main Thread**
**Location**: ChatViewModel.swift lines 382-395 (saving images during send)
```swift
let result = try ImageStorageService.shared.saveImage(...)
```

**Impact**: Large images block UI during save

**Solution**: Move to background task

#### 4. **Streaming Updates Too Frequent**
**Location**: ChatViewModel.swift lines 714-719
```swift
assistantMessage.content += chunk
chunkCount += 1

// Batch save every 20 chunks
if chunkCount % 20 == 0 {
    try context.save()  // Still too frequent!
}
```

**Impact**: Saving every 20 chunks (maybe every 0.5s) causes stuttering

**Solution**: Use debouncing or only save on completion

---

## Proposed Fixes

### Fix 1: Background Context for Database Operations (Priority: CRITICAL)

Create a helper in ChatViewModel:
```swift
private func saveInBackground(_ block: @escaping (ModelContext) throws -> Void) async throws {
    let container = modelContainer

    try await Task.detached(priority: .userInitiated) {
        let backgroundContext = ModelContext(container)
        try block(backgroundContext)
        try backgroundContext.save()
    }.value
}
```

Use it for message creation:
```swift
// Instead of:
context.insert(message)
try context.save()

// Do:
await saveInBackground { context in
    context.insert(message)
}
```

### Fix 2: Debounced UI Updates During Streaming

```swift
private var updateTimer: Timer?
private var pendingContent: String = ""

// In streaming loop:
pendingContent += chunk

// Debounce updates (every 100ms instead of every chunk)
updateTimer?.invalidate()
updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
    await MainActor.run {
        assistantMessage.content = pendingContent
    }
}
```

### Fix 3: Move Image Processing Off Main Thread

```swift
// In send() method:
for pendingImage in imagesToSend {
    // Move to background
    let result = try await Task.detached {
        try ImageStorageService.shared.saveImage(
            data: pendingImage.data,
            originalFileName: pendingImage.fileName
        )
    }.value

    let attachment = ImageAttachment(...)
    context.insert(attachment)
}
```

### Fix 4: Reduce ContentCacheService Polling Frequency

**Current**: Captures every 5 seconds (too aggressive)
**Proposed**: Capture every 10-15 seconds, or only when user interacts

```swift
// In ContentCacheService.swift
let captureInterval: TimeInterval = 15.0  // Was 5.0
```

---

## Implementation Priority

### Phase 1 (Critical - Do Now)
1. ✅ Fix background context for database saves
2. ✅ Debounce streaming updates
3. ✅ Move image processing off main thread

### Phase 2 (High - This Week)
1. Extract Settings views to separate files
2. Extract Chat components to separate files
3. Reduce ContentCacheService polling

### Phase 3 (Medium - Next Week)
1. Extract Sidebar components
2. Add performance monitoring
3. Optimize SwiftData queries

### Phase 4 (Low - Future)
1. Extract remaining helper views
2. Add unit tests for view models
3. Profile and optimize further

---

## Testing Strategy

After each fix:
1. Test message sending (should be smooth, no freezing)
2. Test @ mention capture (should not block UI)
3. Test streaming responses (should update smoothly)
4. Test image attachments (should not freeze)
5. Monitor with Instruments (Time Profiler + Main Thread Checker)

---

## Success Metrics

- **Before**: UI freezes for 200-500ms on message send
- **After**: UI stays responsive (<16ms per frame, 60fps)
- **Before**: ContentView.swift = 4156 lines
- **After**: ContentView.swift < 500 lines, split into 10+ files
