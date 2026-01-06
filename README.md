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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- UI design inspired by [Alter](https://alter.app/)
- Built with SwiftUI and SwiftData
