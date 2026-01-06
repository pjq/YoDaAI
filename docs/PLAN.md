# YouDaAI – MVP Plan (local-first)

This plan tracks a solo-developer MVP for **YouDaAI**, focused on:
- local-first data storage
- OpenAI-compatible providers (incl. local endpoints like Ollama / LM Studio)
- “Alter-like” fast UX primitives (launcher, context capture, insert)

Audio / meeting intelligence is intentionally deferred.

## Guiding principles
- **Local-first by default**: store chats/settings locally; avoid uploading user data unless explicitly configured.
- **Provider-agnostic**: treat model providers as adapters behind a single interface.
- **Permission-minimal MVP**: only request sensitive permissions (Accessibility, Screen Recording) when a feature needs it.
- **Safe automation**: actions that can change data should require explicit user confirmation.

## Current status (done)
- Chat UI (threads + messages + composer)
- SwiftData persistence for threads/messages
- Provider settings persisted locally
- OpenAI-compatible `/v1/chat/completions` client

Implementation lives in:
- `YoDaAI/ContentView.swift`
- `YoDaAI/ChatViewModel.swift`
- `YoDaAI/OpenAICompatibleClient.swift`
- `YoDaAI/ProviderSettings.swift`
- `YoDaAI/Item.swift` (chat data models)

## MVP v0.1 scope (recommended)
### 1) Fast UX shell
- Menu bar app (status item)
- Global hotkey to open/close a floating chat panel
- Basic keyboard shortcuts (new chat, focus prompt, send)

### 2) Provider configuration (local-first)
- Multiple providers (in UI) as a future enhancement
- MVP: one active OpenAI-compatible provider config
  - base URL
  - API key (optional)
  - model name

### 3) Basic context capture (lightweight)
- Frontmost app bundle id + app name
- Active window title
- Optional: selected text (best-effort)

### 4) “Insert into focused app” (later in MVP)
- Insert last assistant message into focused input
- Use Accessibility where possible
- Fallback to pasteboard + Cmd+V

## Next feature decision: “Chat with any app”
### Decision: Accessibility-based app context (always-on)
Goal: YouDaAI can answer with awareness of the **frontmost app** and the user’s **current focused field**, for any macOS app.

MVP context pack (best-effort):
- frontmost app name + bundle identifier
- focused window title
- focused UI element role
- focused UI element value preview (truncated)

This requires Accessibility permission, and YouDaAI should request it only when enabling context capture.

### Insert into focused app (MVP)
- Primary: set AX value on focused editable element
- Fallback: pasteboard + Cmd+V simulated keypress

### Privacy guardrails (MVP)
- Per-app allow/deny for context capture
- Per-app allow/deny for insertion
- Redact secure text fields (password fields)

Teams, Chrome, etc. are handled uniformly as “frontmost app + focused element”—deep per-app parsing is deferred.

## MVP milestones (suggested order)
1. Menu bar + global hotkey floating panel
2. Chrome page integration (A1)
3. Context pack plumbing (attach app/page context to prompts)
4. Insert into focused app
5. Screen capture + OCR (Vision) (optional, behind a toggle)

## Deferred (post-MVP)
- Live Notepad (real-time transcript)
- Offline transcription (Whisper) + diarization
- Automation workflows / integrations (Slack/Notion/Gmail)
- Multi-model routing and automatic selection
- Encrypted local DB beyond default store (SQLCipher design)

## Notes / open questions
- Which “next MVP feature” are we building first?
  - Chrome Page chat (recommended)
  - Teams support (Accessibility-limited)
- Do we want a background helper/daemon for hotkeys and local HTTP server, or keep everything in-app?
