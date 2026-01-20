# AGENTS.md - YoDaAI Project Guide

This document provides AI agents with the necessary context to understand and contribute to the YoDaAI project.

## Project Overview

**YoDaAI** is a macOS SwiftUI chat application that connects to OpenAI-compatible LLM providers. It features:

- Multi-threaded chat conversations with persistent storage
- Multiple LLM provider management with auto-fetch models from `/v1/models`
- Accessibility-based "chat with any app" context capture
- Per-app permissions for context capture and text insertion
- Clean, minimal UI inspired by the "Alter" app design

## Tech Stack

- **Language**: Swift 5 with Swift 6 concurrency (`@MainActor`, `nonisolated`, `Sendable`)
- **UI Framework**: SwiftUI (macOS 26.1+)
- **Data Persistence**: SwiftData
- **Networking**: URLSession with async/await
- **Accessibility**: macOS Accessibility APIs (AXUIElement)
- **Markdown Rendering**: Textual SDK (syntax highlighting, code blocks)
- **Build System**: Xcode project (`.xcodeproj`)

## Project Structure

```
YoDaAI/
├── YoDaAI.xcodeproj/          # Xcode project file
├── YoDaAI/                    # Main app source
│   ├── YoDaAIApp.swift        # App entry point, SwiftData container setup
│   ├── ContentView.swift      # Main UI (183 lines, refactored from 2,187)
│   ├── ChatViewModel.swift    # Chat logic, message sending
│   │
│   ├── Features/              # Feature-based architecture (15 component files)
│   │   ├── Chat/
│   │   │   ├── Components/
│   │   │   │   ├── AssistantMessageComponents.swift  # Tool calls, tool results
│   │   │   │   ├── ImageThumbnailRow.swift
│   │   │   │   ├── MarkdownTextView.swift  # Textual SDK rendering
│   │   │   │   ├── MentionChipsView.swift
│   │   │   │   ├── MessageImageComponents.swift
│   │   │   │   ├── PasteInterceptor.swift
│   │   │   │   ├── Popovers.swift
│   │   │   │   └── TypingIndicatorView.swift
│   │   │   └── Views/
│   │   │       ├── ChatDetailView.swift
│   │   │       ├── ChatHeaderView.swift
│   │   │       ├── ComposerView.swift
│   │   │       ├── EmptyStateView.swift
│   │   │       ├── MessageListView.swift
│   │   │       └── MessageRowView.swift
│   │   ├── Sidebar/
│   │   │   └── Views/
│   │   │       └── ThreadRowView.swift
│   │   └── Settings/          # (in Views/ directory)
│   │       ├── APIKeysSettingsView.swift
│   │       ├── GeneralSettingsView.swift
│   │       ├── MCPServersSettingsView.swift
│   │       └── PermissionsSettingsView.swift
│   │
│   ├── OpenAICompatibleClient.swift  # API client for LLM providers
│   ├── AccessibilityService.swift    # macOS accessibility integration
│   ├── AppPermissionsStore.swift     # Per-app permission management
│   ├── Item.swift             # ChatThread, ChatMessage models
│   ├── LLMProvider.swift      # LLM provider model
│   ├── AppPermissionRule.swift       # Per-app permission model
│   ├── ProviderSettings.swift        # Legacy settings (for migration)
│   ├── YoDaAI.entitlements    # App sandbox entitlements
│   └── Assets.xcassets/       # App icons and colors
├── YoDaAITests/               # Unit tests
├── YoDaAIUITests/             # UI tests
└── docs/
    ├── PLAN.md                # Original project plan
    └── refer/                 # Reference UI screenshots (Alter app)
        ├── chatting_main.png
        ├── settings_general.png
        ├── settings_api_keys.png
        ├── settings_permissions.png
        └── settings_appearance.png
```

## Key Files Reference

### Data Models (SwiftData `@Model`)

| File | Models | Purpose |
|------|--------|---------|
| `Item.swift` | `ChatThread`, `ChatMessage` | Chat conversations and messages |
| `LLMProvider.swift` | `LLMProvider` | LLM provider configuration (URL, API key, model) |
| `AppPermissionRule.swift` | `AppPermissionRule` | Per-app permissions for context/insert |
| `ProviderSettings.swift` | `ProviderSettings` | Legacy settings (migrated to LLMProvider) |

### Core Services

| File | Class | Purpose |
|------|-------|---------|
| `OpenAICompatibleClient.swift` | `OpenAICompatibleClient` | HTTP client for OpenAI-compatible APIs |
| `AccessibilityService.swift` | `AccessibilityService` | Capture app context, insert text |
| `AppPermissionsStore.swift` | `AppPermissionsStore` | Manage per-app permission rules |
| `ChatViewModel.swift` | `ChatViewModel` | Main chat logic, coordinates sending messages |

### UI Components (Feature-based Architecture)

**Note**: ContentView.swift was refactored from 2,187 lines to 183 lines (91.6% reduction) by extracting components into a feature-based architecture.

| Component | Location | Purpose |
|-----------|----------|---------|
| `ContentView` | Root | Main view with NavigationSplitView (183 lines) |
| **Chat Components** | `Features/Chat/Components/` | |
| `MarkdownTextView` | Components | Textual SDK markdown rendering with code blocks |
| `AssistantMessageComponents` | Components | Tool calls, tool results display |
| `TypingIndicatorView` | Components | Animated "thinking" indicator |
| `ImageThumbnailRow` | Components | Image attachment preview |
| `MentionChipsView` | Components | @mention chips display |
| `PasteInterceptor` | Components | Intercept paste events for images |
| `Popovers` | Components | Model picker, image viewer popovers |
| **Chat Views** | `Features/Chat/Views/` | |
| `ChatDetailView` | Views | Chat message area |
| `ChatHeaderView` | Views | Chat title and action buttons |
| `MessageListView` | Views | Scrollable message list |
| `MessageRowView` | Views | Individual message bubble |
| `ComposerView` | Views | Text input and toolbar |
| `EmptyStateView` | Views | Empty state placeholder |
| **Sidebar** | `Features/Sidebar/Views/` | |
| `ThreadRowView` | Views | Sidebar thread list item |
| **Settings** | `Views/Settings/` | |
| `GeneralSettingsView` | Settings | General settings (app context toggle) |
| `APIKeysSettingsView` | Settings | Provider management |
| `PermissionsSettingsView` | Settings | Per-app permissions |
| `MCPServersSettingsView` | Settings | MCP server configuration |

## Build Commands

```bash
# Build the project (Debug)
cd /Users/i329817/SAPDevelop/workspace/YoDaAI
xcodebuild -scheme YoDaAI -configuration Debug build

# Build Release configuration
xcodebuild -scheme YoDaAI -configuration Release build

# Build and check for errors only
xcodebuild -scheme YoDaAI -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD)"

# Clean build
xcodebuild -scheme YoDaAI -configuration Debug clean build
```

## Release Process

YoDaAI has an automated release script (`release.sh`) that handles the entire release workflow with a single command.

### Prerequisites (One-time Setup)

Before first use, set up required tools and credentials:

```bash
# 1. Install jq for JSON processing
brew install jq

# 2. Create GitHub Personal Access Token
# Go to: https://github.com/settings/tokens
# Generate new token (classic) with 'repo' scope
# Copy the token

# 3. Add token to ~/.zshrc
echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
source ~/.zshrc

# 4. Verify setup
jq --version
echo $GITHUB_TOKEN
```

**Required environment variables:**
- `GITHUB_TOKEN` - GitHub Personal Access Token with `repo` scope

### Running a Release

**Interactive Mode** (recommended for manual releases):

```bash
./release.sh
```

The script will:
1. Display current version (from last git tag)
2. Prompt you to select version bump type:
   - 1) Patch (0.2.1 → 0.2.2) - Bug fixes, minor improvements
   - 2) Minor (0.2.1 → 0.3.0) - New features, backward compatible
   - 3) Major (0.2.1 → 1.0.0) - Breaking changes
   - 4) Custom version - Specify exact version (e.g., 1.0.0-beta.1)
3. Generate and display changelog from commit messages since last tag
4. Ask for confirmation to proceed
5. Execute the full release workflow

**Automated Mode** (for scripts or CI/CD):

```bash
# Patch version bump
./release.sh --type patch --yes

# Minor version bump
./release.sh --type minor --yes

# Major version bump
./release.sh --type major --yes

# Custom version
./release.sh --version 1.0.0 --yes
```

**Command-line Parameters:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-t, --type TYPE` | Version bump type: `patch`, `minor`, or `major` | `--type minor` |
| `-v, --version VERSION` | Custom version number (e.g., 1.2.3) | `--version 1.0.0` |
| `-y, --yes` | Skip confirmation prompt (auto-confirm) | `--yes` |
| `-h, --help` | Show help message | `--help` |

### What the Script Does

The automated release workflow:

1. **Pre-flight checks**:
   - Verify in git repository
   - Check for uncommitted changes (fails if dirty)
   - Validate GITHUB_TOKEN is set

2. **Version management**:
   - Get current version from git tags
   - Determine new version (bump or custom)
   - Generate changelog from commits since last tag
   - Update version in `YoDaAI/Info.plist`
   - Commit version bump

3. **Build artifacts**:
   - Clean build folder
   - Build Release configuration
   - Locate built app in DerivedData
   - Code sign app (ad-hoc signing)

4. **Create release artifacts**:
   - Create `releases/` directory
   - Generate ZIP: `YoDaAI-X.Y.Z.zip`
   - Generate DMG: `YoDaAI-X.Y.Z.dmg` (with Applications symlink)

5. **Publish release**:
   - Create git tag: `vX.Y.Z`
   - Push commits and tag to GitHub
   - Create GitHub release via API (with changelog)
   - Upload ZIP artifact to release
   - Upload DMG artifact to release
   - Open release page in browser

### Release Files Created

After successful release, you'll find:

- **Local artifacts**:
  - `releases/YoDaAI-X.Y.Z.zip` - ZIP archive (5-7MB)
  - `releases/YoDaAI-X.Y.Z.dmg` - Disk image (6-8MB)

- **Git artifacts**:
  - Git commit: "Bump version to X.Y.Z"
  - Git tag: `vX.Y.Z`

- **GitHub release**:
  - Release page: `https://github.com/pjq/YoDaAI/releases/tag/vX.Y.Z`
  - Attached artifacts: ZIP and DMG files
  - Auto-generated changelog from commit messages
  - Installation instructions (auto-generated)

### Changelog Generation

The script automatically generates changelogs from commit messages between the last tag and HEAD.

**Writing good commit messages for changelogs:**

Standard format:
```
Add /settings slash command to open settings window
Fix Automation permission dialog not appearing
Improve content capture for Safari
```

Conventional Commits (recommended):
```
feat: add /settings slash command
fix: automation permission dialog not appearing
perf: improve content capture for Safari
docs: add quickstart guide for permissions
refactor: extract chat components into Features/ directory
```

The generated changelog will list all commits, so write clear, user-facing commit messages.

### Semantic Versioning

YoDaAI follows [Semantic Versioning](https://semver.org/):

- **PATCH** (0.1.0 → 0.1.1): Bug fixes, minor improvements, no breaking changes
- **MINOR** (0.1.0 → 0.2.0): New features, enhancements, backward compatible
- **MAJOR** (0.1.0 → 1.0.0): Breaking changes, major refactoring

**Examples:**
- Fix UI alignment bug → **PATCH**
- Add multiline composer support → **MINOR**
- Change SwiftData schema (breaking) → **MAJOR**

### Troubleshooting

**"GITHUB_TOKEN not found in environment"**
- Add token to ~/.zshrc: `export GITHUB_TOKEN="ghp_..."`
- Source the file: `source ~/.zshrc`
- Verify: `echo $GITHUB_TOKEN`

**"You have uncommitted changes"**
- Commit or stash changes first: `git status`
- The script requires a clean working directory

**"Build failed"**
- Check detailed logs: `cat /tmp/xcodebuild.log`
- Common issues: Swift 6 warnings, missing dependencies

**"Failed to upload ZIP artifact" or "Failed to upload DMG artifact"**
- Check GITHUB_TOKEN has `repo` scope
- Verify token is valid: `curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user`
- Check file exists: `ls -lh releases/YoDaAI-*.{zip,dmg}`
- The script now shows upload errors (previously hidden by `> /dev/null`)

**Release created but artifacts not uploaded**
- Manually upload using GitHub API:
  ```bash
  # Get release ID
  RELEASE_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/repos/pjq/YoDaAI/releases/tags/vX.Y.Z | jq -r .id)

  # Upload ZIP
  curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary @releases/YoDaAI-X.Y.Z.zip \
    "https://uploads.github.com/repos/pjq/YoDaAI/releases/${RELEASE_ID}/assets?name=YoDaAI-X.Y.Z.zip"

  # Upload DMG
  curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/x-apple-diskimage" \
    --data-binary @releases/YoDaAI-X.Y.Z.dmg \
    "https://uploads.github.com/repos/pjq/YoDaAI/releases/${RELEASE_ID}/assets?name=YoDaAI-X.Y.Z.dmg"
  ```

### Examples

**Example 1: Interactive release (recommended)**
```bash
$ ./release.sh

===================================
YoDaAI Release Automation
===================================

→ Current version: 0.2.1

Select version bump type:
1) Patch (0.2.1 → 0.2.2)
2) Minor (0.2.1 → 0.3.0)
3) Major (0.2.1 → 1.0.0)
4) Custom version
Enter choice [1-4]: 2

→ New version: 0.3.0

Changelog:
- feat: Enhance composer with multiline support and scrolling
- fix: Improve composer UX - compact height and Return to send
- fix: Initialize attachments array in ChatMessage to prevent SwiftData crash
- perf: Remove blocking .value calls on Task.detached saves

Proceed with release v0.3.0? [y/N]: y

✓ Updated Info.plist: v0.3.0 (125)
✓ Build completed successfully
✓ Found: /Users/.../DerivedData/.../YoDaAI.app
✓ App signed successfully
✓ Created: releases/YoDaAI-0.3.0.zip
✓ Created: releases/YoDaAI-0.3.0.dmg
✓ Created release: v0.3.0 (ID: 278178326)
✓ Uploaded: YoDaAI-0.3.0.zip
✓ Uploaded: YoDaAI-0.3.0.dmg
✓ Release published: https://github.com/pjq/YoDaAI/releases/tag/v0.3.0

===================================
Release Complete!
===================================
Version: v0.3.0
ZIP: releases/YoDaAI-0.3.0.zip
DMG: releases/YoDaAI-0.3.0.dmg
GitHub Release: https://github.com/pjq/YoDaAI/releases/tag/v0.3.0

✓ Release v0.3.0 published successfully!
```

**Example 2: Automated patch release**
```bash
./release.sh --type patch --yes

# Output:
# → Current version: 0.3.0
# → Bumping patch version: 0.3.0 → 0.3.1
# → Auto-confirming release (--yes flag set)
# ...
# ✓ Release v0.3.1 published successfully!
```

**Example 3: Custom version for beta release**
```bash
./release.sh --version 1.0.0-beta.1 --yes

# Creates release: v1.0.0-beta.1
```

### For AI Agents

When asked to create a release:

1. **Check working directory is clean**:
   ```bash
   git status
   ```

2. **Run release script with appropriate parameters**:
   - For normal releases: `./release.sh --type minor --yes` (or patch/major)
   - For specific versions: `./release.sh --version X.Y.Z --yes`

3. **Verify release was created**:
   - Check for success message: "✓ Release vX.Y.Z published successfully!"
   - Verify artifacts were uploaded: "✓ Uploaded: YoDaAI-X.Y.Z.zip" and "✓ Uploaded: YoDaAI-X.Y.Z.dmg"
   - Check release URL: `https://github.com/pjq/YoDaAI/releases/tag/vX.Y.Z`

4. **Handle errors**:
   - If upload fails, the script now shows detailed error messages
   - Check GITHUB_TOKEN is set and valid
   - Verify artifacts exist in `releases/` directory
   - If needed, manually upload artifacts (see Troubleshooting section above)

See [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) for detailed documentation.

## Architecture Notes

### SwiftData Schema

The app uses SwiftData with these models registered in `YoDaAIApp.swift`:
- `ChatThread` - Has cascade delete relationship with `ChatMessage`
- `ChatMessage` - Belongs to `ChatThread`
- `LLMProvider` - Stores provider configs (one marked as default)
- `AppPermissionRule` - Per-app permissions
- `ProviderSettings` - Legacy (kept for migration)

### Message Flow

1. User types in `ComposerView`
2. `ChatViewModel.send()` is called
3. Creates `ChatMessage` (user role) in SwiftData
4. Optionally captures `AppContextSnapshot` via `AccessibilityService`
5. Calls `OpenAICompatibleClient.createChatCompletion()`
6. Creates `ChatMessage` (assistant role) with response
7. Auto-generates thread title if first message

**Performance**: All `context.save()` operations are wrapped in `Task.detached` to run on background threads, preventing UI freezing when saving messages. The ChatViewModel is marked `@MainActor`, so explicit background threading is required for database operations.

```swift
// Save on background thread to prevent UI blocking
try await Task.detached {
    try context.save()
}.value
```

### Textual SDK Integration

The app uses the Textual SDK for markdown rendering in assistant messages, providing:
- Syntax-highlighted code blocks
- Custom code block styling with copy button
- Rich text formatting (bold, italic, lists, tables)
- Wrapping overflow mode for long code lines

**Known limitation**: Text selection and code block copy button cannot work simultaneously. The text selection layer at the StructuredText level intercepts all mouse events, preventing button clicks. Current implementation prioritizes the copy button functionality:
- Copy button works for code blocks
- Mouse text selection disabled on message content
- Keyboard shortcuts (Cmd+C) still work for copying text

Located in: `Features/Chat/Components/MarkdownTextView.swift`

### Accessibility Features

- **Context Capture**: Gets frontmost app name, window title, focused element value
- **Text Insert**: Sets focused element value or uses Cmd+V paste fallback
- **Permissions**: Uses macOS Accessibility API (`AXIsProcessTrusted`)

### Entitlements Required

```xml
com.apple.security.app-sandbox = true
com.apple.security.files.user-selected.read-only = true
com.apple.security.network.client = true
```

Note: For full accessibility features, the app needs to be granted Accessibility permissions in System Preferences.

## UI Design Guidelines

The UI follows the "Alter" app design (see `docs/refer/` screenshots):

### Chat Screen
- **Sidebar**: Search bar, date-grouped threads (Today/Previous), "C" icon prefix
- **Messages**: User messages right-aligned with subtle background bubble, AI messages left-aligned plain text
- **Composer**: Toolbar with @, bolt (context toggle), paperclip icons + model selector (`/ model-name`) + send button
- **Header**: Chat title with action buttons (share, copy, link, delete)

### Settings
- Tabbed interface with icon tabs at top (General, API Keys, Permissions)
- Clean row-based layout with title + subtitle + control

## Common Tasks

### Adding a New SwiftData Model

1. Create model file in `YoDaAI/`
2. Add `@Model` class with properties
3. Register in `YoDaAIApp.swift` schema array
4. Run build to verify

### Adding a New Settings Tab

1. Add case to `SettingsTab` enum in `ContentView.swift`
2. Create new tab view struct (e.g., `NewSettingsTab`)
3. Add to switch statement in `SettingsView.body`

### Adding API Endpoints

1. Add request/response structs in `OpenAICompatibleClient.swift`
2. Add method using `sendJSONRequest` helper
3. Handle errors with `OpenAICompatibleError` enum

## Known Issues & Considerations

1. **Swift 6 Concurrency**: Uses `@MainActor` extensively; be careful with `nonisolated` contexts. All SwiftData `context.save()` operations must be wrapped in `Task.detached` to prevent UI blocking.
2. **SwiftData ForEach**: May need explicit type annotations (e.g., `ForEach(items) { (item: Type) in }`)
3. **Accessibility Permissions**: App must be granted permissions manually in System Preferences
4. **Network Sandbox**: Requires `com.apple.security.network.client` entitlement
5. **Textual SDK Limitation**: Cannot have both text selection and interactive buttons (like copy button) in StructuredText. Current implementation disables text selection to preserve copy button functionality. If text selection is needed, consider using a different markdown rendering library or wait for Textual SDK updates.
6. **Performance Best Practices**:
   - Always move database operations off main thread using `Task.detached`
   - Keep image operations on main thread if using `@MainActor` services like `ImageStorageService`
   - Monitor main thread blocking with Instruments if experiencing UI freezes

## Testing

```bash
# Run unit tests
xcodebuild -scheme YoDaAI -configuration Debug test

# Run UI tests
xcodebuild -scheme YoDaAI -configuration Debug -destination 'platform=macOS' test
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New chat |
| Cmd+Return | Send message |
| Cmd+, | Open settings (standard macOS) |

## Future Enhancements (Ideas)

- Streaming responses
- File attachments
- System prompt customization
- Export/import conversations
- Global hotkey to activate
- Menu bar mode
