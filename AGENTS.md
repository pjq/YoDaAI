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
- **Build System**: Xcode project (`.xcodeproj`)

## Project Structure

```
YoDaAI/
├── YoDaAI.xcodeproj/          # Xcode project file
├── YoDaAI/                    # Main app source
│   ├── YoDaAIApp.swift        # App entry point, SwiftData container setup
│   ├── ContentView.swift      # Main UI (sidebar, chat, settings)
│   ├── ChatViewModel.swift    # Chat logic, message sending
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

### UI Components (in `ContentView.swift`)

| Component | Purpose |
|-----------|---------|
| `ContentView` | Main view with NavigationSplitView |
| `ThreadRowView` | Sidebar thread list item |
| `ChatDetailView` | Chat message area |
| `ChatHeaderView` | Chat title and action buttons |
| `MessageListView` | Scrollable message list |
| `MessageRowView` | Individual message bubble |
| `ComposerView` | Text input and toolbar |
| `ModelPickerPopover` | Model/provider selection dropdown |
| `SettingsView` | Tabbed settings sheet |
| `GeneralSettingsTab` | General settings (app context toggle) |
| `APIKeysSettingsTab` | Provider management |
| `PermissionsSettingsTab` | Per-app permissions |

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

YoDaAI has an automated release script that handles the entire release workflow:

### Quick Release

```bash
./release.sh
```

This single command will:
1. Check for uncommitted changes
2. Show current version and ask for bump type (patch/minor/major)
3. Generate changelog from git commits since last tag
4. Update version in Info.plist
5. Build Release configuration
6. Create ZIP and DMG artifacts
7. Create git tag
8. Push to GitHub
9. Create GitHub release with artifacts via API
10. Open release page in browser

### Setup (One-time)

Before first use, set up GitHub token:

```bash
# Install jq for JSON processing
brew install jq

# Add GitHub token to ~/.zshrc
echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
source ~/.zshrc
```

Get GitHub token from: https://github.com/settings/tokens (needs `repo` scope)

### Release Files

The script creates:
- **releases/YoDaAI-X.Y.Z.zip** - ZIP archive for download
- **releases/YoDaAI-X.Y.Z.dmg** - Professional disk image with Applications symlink
- **Git tag** - vX.Y.Z
- **GitHub release** - With auto-generated changelog and artifacts

### Version Bumping

The script supports semantic versioning:
- **Patch** (0.1.0 → 0.1.1): Bug fixes, minor improvements
- **Minor** (0.1.0 → 0.2.0): New features, backward compatible
- **Major** (0.1.0 → 1.0.0): Breaking changes
- **Custom**: Specify exact version (e.g., 1.0.0-beta.1)

### Changelog Generation

The script automatically generates changelogs from commit messages since the last git tag. Write clear commit messages for better changelogs:

**Good commit messages:**
```
Add /settings slash command to open settings window
Fix Automation permission dialog not appearing
Improve content capture for Safari
```

**Conventional commits (recommended):**
```
feat: add /settings slash command
fix: automation permission dialog not appearing
perf: improve content capture for Safari
docs: add quickstart guide for permissions
```

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

1. **Swift 6 Concurrency**: Uses `@MainActor` extensively; be careful with `nonisolated` contexts
2. **SwiftData ForEach**: May need explicit type annotations (e.g., `ForEach(items) { (item: Type) in }`)
3. **Accessibility Permissions**: App must be granted permissions manually in System Preferences
4. **Network Sandbox**: Requires `com.apple.security.network.client` entitlement

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
