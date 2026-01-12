# YoDaAI 0.2.1

## What's New

### Bug Fixes

- **Fix: Prevent System Settings from opening repeatedly for Automation permission** - The background content capture service no longer opens System Settings repeatedly when Automation permission is needed. It now only prompts once per app per session, greatly improving user experience.

- **Fix: Stop auto-opening System Settings repeatedly** - Added session tracking to prevent Accessibility permission prompts from repeating when user closes System Settings.

- **Add context-aware hints for content capture limitations** - Smart hints now appear in @ mention context cards based on the app type and captured content:
  - Chrome/Safari: Reminds users to grant Automation permission for full page content
  - Teams/Slack/Electron apps: Explains limited capture and suggests selecting text first
  - Secure fields: Shows lock icon and hides content
  - Empty captures: Provides app-specific troubleshooting hints

- **Add command-line parameters to release script for non-interactive use** - Release script now supports `-t/--type`, `-v/--version`, and `-y/--yes` flags for automation.

## Installation

### macOS (Apple Silicon & Intel)

1. Download YoDaAI-0.2.1.zip or YoDaAI-0.2.1.dmg
2. Open the downloaded file
3. Drag YoDaAI to your Applications folder
4. **Important**: Remove the quarantine flag (first time only):
   - Run in Terminal: `xattr -cr /Applications/YoDaAI.app`
5. Open YoDaAI
6. Grant Accessibility and Automation permissions (see docs)

### Troubleshooting: "YoDaAI is damaged"

If you see this error, it is just macOS Gatekeeper being cautious. The app is **not** actually damaged.

**Quick fix:** Run in Terminal: `xattr -cr /Applications/YoDaAI.app`

**Alternative:** Right-click YoDaAI → Open → Click "Open" in the dialog.

See [Installation Troubleshooting](https://github.com/pjq/YoDaAI/blob/main/docs/INSTALLATION_TROUBLESHOOTING.md) for more solutions.

## Permissions Required

⚠️ **Important**: YoDaAI needs two permissions to capture content from other apps:

- **Accessibility**: System Settings → Privacy & Security → Accessibility → Enable YoDaAI
- **Automation**: Will be requested per-app when you use @ mentions (only once per app now!)

See [QUICKSTART_FIX_PERMISSIONS.md](https://github.com/pjq/YoDaAI/blob/main/docs/QUICKSTART_FIX_PERMISSIONS.md) for detailed setup instructions.

## Documentation

- [Quick Start Guide](https://github.com/pjq/YoDaAI/blob/main/docs/QUICKSTART_FIX_PERMISSIONS.md)
- [Content Capture Limitations](https://github.com/pjq/YoDaAI/blob/main/docs/CONTENT_CAPTURE_LIMITATIONS.md)
- [Accessibility Setup](https://github.com/pjq/YoDaAI/blob/main/docs/ACCESSIBILITY_SETUP.md)
- [Automation Troubleshooting](https://github.com/pjq/YoDaAI/blob/main/docs/AUTOMATION_PERMISSION_TROUBLESHOOTING.md)

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
