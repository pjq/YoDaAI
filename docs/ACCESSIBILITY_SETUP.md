# Accessibility Permission Setup Guide

YoDaAI requires **Accessibility** permission to capture content from other apps. This is the **MVP feature** for the application.

## Why Accessibility Permission is Required

- **Content Capture**: Read text from focused fields in other apps (e.g., Safari URL bar, text editors)
- **Window Information**: Get app names, window titles, and focused element details
- **Text Insertion**: Insert AI responses back into apps (optional feature)

## Current Status Check

The app logs show:
```
[AccessibilityService] Permission not granted
```

This means Accessibility permission has **NOT** been granted yet.

## How to Grant Accessibility Permission

### Method 1: Automatic Prompt (First Launch)

1. **Quit YoDaAI** completely (Cmd+Q)
2. **Relaunch YoDaAI**
3. On first launch, a system dialog should appear asking for Accessibility permission
4. Click **"Open System Settings"** in the dialog
5. In System Settings, find **YoDaAI** in the list
6. **Enable the toggle** next to YoDaAI
7. Restart YoDaAI

### Method 2: Manual Setup (If Prompt Doesn't Appear)

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Privacy & Security**
3. Click **Accessibility** in the left sidebar
4. Look for **YoDaAI** in the list of apps
5. If YoDaAI is in the list but **disabled**:
   - Click the toggle to **enable** it
6. If YoDaAI is **NOT** in the list:
   - Click the **"+"** button at the bottom
   - Navigate to your YoDaAI app (usually in `/Applications` or your build folder)
   - Select it and click **"Open"**
   - Enable the toggle
7. Restart YoDaAI

### Method 3: Using the App's Settings

1. Open **YoDaAI**
2. Open **Settings** (Cmd+, or `/settings` command)
3. Go to the **Permissions** tab
4. Under "Accessibility Permission", click **"Grant Access"**
5. This will open System Settings to the Accessibility pane
6. Follow steps 4-7 from Method 2

## Verifying Permission is Granted

After granting permission:

1. Open YoDaAI Settings (Cmd+,)
2. Go to **Permissions** tab
3. Under "Accessibility Permission", you should see:
   - ✅ **Green checkmark**
   - Status: **"Granted"**

## Testing Content Capture

Once permission is granted:

1. Open **Safari** or any other app
2. Click in a text field (e.g., URL bar, search box)
3. Switch back to YoDaAI
4. In the composer, click the **@ button** or type `@`
5. Select the app from the list
6. You should see content captured (character count shown)

## Troubleshooting

### Issue: "Permission not granted" after enabling in System Settings

**Solution:**
- Restart YoDaAI completely (Quit and relaunch)
- If still not working, disable and re-enable the toggle in System Settings
- Check that you enabled the correct app (make sure it's your YoDaAI build)

### Issue: YoDaAI not appearing in Accessibility list

**Solution:**
1. Click the **"+"** button in System Settings → Privacy & Security → Accessibility
2. Navigate to your YoDaAI app location
3. If building from Xcode, it's usually at:
   ```
   ~/Library/Developer/Xcode/DerivedData/YoDaAI-*/Build/Products/Debug/YoDaAI.app
   ```
4. For installed apps, check `/Applications/YoDaAI.app`

### Issue: "No content captured" even with permission granted

**Solution:**
- Make sure the target app is **active** and a text field is **focused**
- Some apps may not expose their content via Accessibility API
- Try different apps:
  - ✅ **Works well**: TextEdit, Safari, Notes, Mail, VS Code
  - ⚠️ **Limited**: Some secure fields, password fields
  - ❌ **Won't work**: Apps that block Accessibility API

### Issue: AppleScript errors (-600)

**Solution:**
- Error -600 means "Application isn't running"
- Make sure the target app is fully launched before capturing
- Some apps take time to respond to AppleScript commands
- This is normal during app launch - content capture will work once app is ready

## macOS Version Compatibility

- **macOS 13 (Ventura) and later**: Use System Settings
- **macOS 12 (Monterey) and earlier**: Use System Preferences

## Security & Privacy Notes

- Accessibility permission allows YoDaAI to read content from other apps
- This is a standard macOS permission used by many productivity apps
- YoDaAI only captures content when you explicitly use the @ mention feature
- No data is sent to external servers without your knowledge
- All content capture is logged in the console for transparency

## Support

If you continue to have issues after following this guide:

1. Check the console logs for detailed error messages
2. Look for lines starting with `[AccessibilityService]` or `[ContentCacheService]`
3. File an issue at: https://github.com/pjq/YoDaAI/issues

## Technical Details

The app checks for Accessibility permission using:
```swift
AXIsProcessTrusted() // Returns true if permission granted
```

Permission request is triggered by:
```swift
let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
AXIsProcessTrustedWithOptions(options)
```

This opens the System Settings permission dialog automatically.
