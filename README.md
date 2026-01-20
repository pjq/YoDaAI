# YoDaAI

A native macOS chat application that connects to OpenAI-compatible LLM providers. Built with SwiftUI and SwiftData.

![macOS](https://img.shields.io/badge/macOS-26.1+-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Multi-threaded conversations** with persistent storage using SwiftData
- **Multiple LLM providers** - Connect to OpenAI, Ollama, LM Studio, or any OpenAI-compatible API
- **Auto-fetch models** from provider's `/v1/models` endpoint
- **Streaming responses** - See AI responses in real-time
- **Markdown rendering** with syntax-highlighted code blocks and copy button
- **@ Mentions** - Include content from other running macOS apps in your chat
- **Per-app permissions** for context capture and text insertion
- **Clean, minimal UI** inspired by modern chat interfaces

## Screenshots

*Coming soon*

## Requirements

- macOS 26.1 or later
- Xcode 16+ for building from source

## Installation

### Build from Source

```bash
git clone https://github.com/pnewsam/YoDaAI.git
cd YoDaAI
open YoDaAI.xcodeproj
```

Then build and run in Xcode (⌘R).

## Setup

### 1. Add an LLM Provider

1. Open Settings (⌘,)
2. Go to the "API Keys" tab
3. Click "+" to add a new provider
4. Enter your provider details:
   - **Name**: Display name (e.g., "OpenAI", "Ollama")
   - **Base URL**: API endpoint (e.g., `https://api.openai.com/v1` or `http://localhost:11434/v1`)
   - **API Key**: Your API key (leave empty for local providers like Ollama)
5. Click "Fetch Models" to load available models
6. Select a default model

### 2. Grant Accessibility Permission (Optional)

To use the @ mention feature for capturing content from other apps:

1. Open Settings > Permissions tab
2. Click "Grant Access"
3. Enable YoDaAI in System Settings > Privacy & Security > Accessibility

## Usage

### Basic Chat

1. Click "+" or press ⌘N to start a new chat
2. Type your message and press ⌘Return to send
3. The AI response will stream in real-time

### @ Mentions

Include content from other running apps in your chat:

1. Type `@` in the composer to see running apps
2. Select an app to mention it
3. Click the eye icon to preview captured content
4. Send your message - the app's content will be included as context

**Note**: The app will briefly switch to the mentioned app to capture its content, then return to YoDaAI.

### Message Actions

Hover over any message to see action buttons:
- **Copy** - Copy message to clipboard
- **Retry** - Regenerate the AI response
- **Delete** - Remove the message

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New chat |
| ⌘Return | Send message |
| ⌘, | Open settings |

## Architecture

```
YoDaAI/
├── YoDaAIApp.swift           # App entry point, SwiftData setup
├── ContentView.swift         # Main UI components
├── ChatViewModel.swift       # Chat logic and state management
├── OpenAICompatibleClient.swift  # API client with streaming
├── AccessibilityService.swift    # macOS accessibility integration
├── Item.swift                # ChatThread, ChatMessage models
├── LLMProvider.swift         # Provider configuration model
└── AppPermissionsStore.swift # Per-app permission management
```

## Supported Providers

Any OpenAI-compatible API, including:

- [OpenAI](https://platform.openai.com/)
- [Ollama](https://ollama.ai/) (local)
- [LM Studio](https://lmstudio.ai/) (local)
- [OpenRouter](https://openrouter.ai/)
- [Together AI](https://together.ai/)
- [Groq](https://groq.com/)
- And many more...

## Known Limitations

- **Electron apps** (Teams, Slack, VS Code) may have limited accessibility support
- **Web-based content** in browsers may not expose text via accessibility APIs
- Accessibility permission requires manual grant in System Settings

## Development

### Building from Source

```bash
git clone https://github.com/pjq/YoDaAI.git
cd YoDaAI
open YoDaAI.xcodeproj
```

Build with Xcode (⌘B) or command line:

```bash
# Debug build
xcodebuild -scheme YoDaAI -configuration Debug build

# Release build
xcodebuild -scheme YoDaAI -configuration Release build
```

### Creating Releases

YoDaAI includes an automated release script that handles everything with one command:

```bash
./release.sh
```

#### One-Time Setup

1. **Install jq** (JSON processor):
   ```bash
   brew install jq
   ```

2. **Create GitHub Personal Access Token**:
   - Go to https://github.com/settings/tokens
   - Generate new token (classic) with `repo` scope
   - Copy the token

3. **Add token to ~/.zshrc**:
   ```bash
   echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
   source ~/.zshrc
   ```

4. **Verify setup**:
   ```bash
   jq --version
   echo $GITHUB_TOKEN
   ```

#### Release Process

**Interactive Mode** (recommended):

```bash
./release.sh
```

The script will prompt you to select version bump type and confirm before proceeding.

**Automated Mode** (for CI/CD or scripts):

```bash
# Patch version bump (0.1.0 → 0.1.1)
./release.sh --type patch --yes

# Minor version bump (0.1.0 → 0.2.0)
./release.sh --type minor --yes

# Major version bump (0.1.0 → 1.0.0)
./release.sh --type major --yes

# Custom version
./release.sh --version 1.0.0 --yes
```

**Available Options:**

| Option | Description | Example |
|--------|-------------|---------|
| `-t, --type TYPE` | Version bump type: `patch`, `minor`, or `major` | `--type minor` |
| `-v, --version VERSION` | Custom version number (e.g., 1.2.3) | `--version 1.0.0` |
| `-y, --yes` | Skip confirmation prompt (auto-confirm) | `--yes` |
| `-h, --help` | Show help message | `--help` |

**What the script does:**

1. ✅ Check for uncommitted changes (fails if dirty)
2. ✅ Determine version (from bump type or custom version)
3. ✅ Generate changelog from git commits since last tag
4. ✅ Update version in Info.plist
5. ✅ Commit version bump
6. ✅ Build Release configuration
7. ✅ Code sign app (ad-hoc signing)
8. ✅ Create ZIP and DMG artifacts in `releases/` directory
9. ✅ Create git tag and push to GitHub
10. ✅ Create GitHub release via API
11. ✅ Upload ZIP and DMG artifacts to release
12. ✅ Open release page in browser

**Example - Interactive:**
```bash
$ ./release.sh

Current version: 0.2.1

Select version bump type:
1) Patch (0.2.1 → 0.2.2)
2) Minor (0.2.1 → 0.3.0)
3) Major (0.2.1 → 1.0.0)
4) Custom version
Enter choice [1-4]: 2

Changelog:
- feat: Enhance composer with multiline support
- fix: Improve composer UX - compact height
- perf: Remove blocking .value calls on Task.detached saves

Proceed with release v0.3.0? [y/N]: y

✓ Release v0.3.0 published successfully!
```

**Example - Automated:**
```bash
# Automated minor version bump
./release.sh --type minor --yes

# Output:
# Current version: 0.2.1
# Bumping minor version: 0.2.1 → 0.3.0
# ...
# ✓ Release v0.3.0 published successfully!
```

**Troubleshooting:**

- **"GITHUB_TOKEN not found"**: Add token to ~/.zshrc (see One-Time Setup above)
- **"Build failed"**: Check `/tmp/xcodebuild.log` for errors
- **"Failed to upload artifacts"**: Check GITHUB_TOKEN permissions (needs `repo` scope)
- **"You have uncommitted changes"**: Commit or stash changes first

See [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) for detailed documentation.

#### Semantic Versioning

YoDaAI follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes (1.0.0 → 2.0.0)
- **MINOR**: New features, backward compatible (0.1.0 → 0.2.0)
- **PATCH**: Bug fixes, improvements (0.1.0 → 0.1.1)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- UI design inspired by [Alter](https://alter.app/)
- Built with SwiftUI and SwiftData
