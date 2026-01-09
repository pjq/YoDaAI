# Content Capture Limitations

YoDaAI uses macOS Accessibility APIs and AppleScript to capture content from other applications. However, some apps have limitations due to their architecture.

## Browser Limitations (Chrome, Edge, Brave, etc.)

### Issue
- Only captures **title and URL**, not the actual page content
- You see: "Google - https://google.com" instead of the actual page text

### Why This Happens
Chrome requires **Automation permission** for YoDaAI to execute JavaScript (`document.body.innerText`) to read page content.

### Solution: Grant Automation Permission

1. Mention @Chrome in YoDaAI (this triggers a permission request)
2. macOS will show a dialog: **"YoDaAI would like to control Google Chrome"**
3. Click **"OK"** to grant permission
4. Try capturing again - you should now see full page content!

**Alternative:** Grant manually
1. Open **System Settings** → **Privacy & Security** → **Automation**
2. Find **YoDaAI**
3. Enable the checkbox for **Google Chrome**

### Supported Browsers
- Safari (com.apple.Safari)
- Google Chrome (com.google.Chrome)
- Chrome Canary (com.google.Chrome.canary)
- Brave (com.brave.Browser) ⚠️ *Needs implementation*
- Microsoft Edge (com.microsoft.edgemac) ⚠️ *Needs implementation*

## Electron App Limitations (Teams, Slack, VS Code, etc.)

### Issue
- Only captures input field placeholders like "Type a message"
- Cannot capture actual message history or content

### Why This Happens
Electron apps render content using web technologies (Chromium) inside a native wrapper. The Accessibility API only exposes:
- Window title
- Input fields (and their placeholder text)
- Some UI controls

**Actual message content is not exposed** through the Accessibility tree.

### Workaround: Clipboard Capture

YoDaAI has a fallback method that:
1. Simulates **Cmd+A** (select all)
2. Simulates **Cmd+C** (copy)
3. Reads from clipboard

This works for **text editors** and some apps, but has limitations:
- May select/copy unwanted content
- Doesn't work in message history views
- May trigger app notifications
- Requires manual selection first

### Limited Support Apps
- Microsoft Teams (com.microsoft.teams)
- Slack (com.tinyspeck.slackmacgap)
- VS Code (com.microsoft.VSCode)
- Discord (com.DiscordApp.Discord)
- Other Electron-based apps

## Apps with Good Support

These apps expose content properly through Accessibility or AppleScript:

### ✅ Full Support
- **Safari** - Full page text via AppleScript + JavaScript
- **Chrome** - Full page text (with Automation permission)
- **Notes** - Note content via AppleScript
- **TextEdit** - Full text via Accessibility
- **Terminal** - Visible text via Accessibility
- **Mail** - Email content via AppleScript
- **Messages** - Conversation text via AppleScript

### ⚠️ Partial Support
- **Xcode** - Code editor text only
- **Finder** - Window title, selected files
- **System Settings** - Current pane info

### ❌ Poor Support
- **Teams** - Input fields only
- **Slack** - Input fields only
- **VS Code** - Limited (Electron-based)
- **Spotify** - UI only, no content
- **Figma** - Web app in Electron wrapper

## Troubleshooting

### "No content captured"
**Possible causes:**
1. Accessibility permission not granted
2. Automation permission not granted (for browsers)
3. App doesn't expose content via Accessibility API
4. Secure field (password input)

**Solutions:**
1. Grant **Accessibility** permission: System Settings → Privacy & Security → Accessibility
2. Grant **Automation** permission: System Settings → Privacy & Security → Automation
3. Try mentioning the app first to trigger permission requests
4. Check if the app is in the "Limited Support" list above

### "Content is just placeholder text"
This usually means:
- You're focusing on an input field (capture happens at moment of @mention)
- The app is Electron-based with limited accessibility

**Solution:** Select the content you want first, then use @mention.

### Chrome/Safari: No page content
**Most likely:** Missing Automation permission

**Fix:**
1. Mention @Chrome
2. Approve the "YoDaAI would like to control Chrome" dialog
3. Try again

### Teams/Slack: Only seeing input fields
**This is expected behavior.** Electron apps don't expose message history.

**Workaround:**
1. Manually select the text you want (Cmd+A)
2. Then mention @Teams
3. The clipboard capture fallback may work

## Feature Request: Better Electron Support

Unfortunately, improving Electron app support is difficult because:
- Content is rendered in a sandboxed web view
- Accessibility APIs don't expose web content
- No AppleScript support in Electron apps
- Browser extensions can't communicate with native apps

**Possible future improvements:**
- Add browser extension for deep web page analysis
- Integrate with app-specific APIs (Teams API, Slack API)
- OCR-based capture (capture screenshot, extract text)

## Reporting Issues

If you find an app that should work but doesn't:

1. Check Console.app for YoDaAI logs (filter by "AccessibilityService")
2. Note the error codes (-600, -1743, -1728)
3. Report at: https://github.com/pjq/YoDaAI/issues

Include:
- App name and bundle identifier
- Error message from logs
- Whether Accessibility/Automation permissions are granted
