# URGENT: Fix Content Capture NOW

Your logs show:
```
[AccessibilityService] Permission not granted
```

This means **Accessibility permission is NOT granted**. Here's how to fix it immediately.

---

## Step 1: Grant Accessibility Permission (5 minutes)

### Option A: Reset and Let App Prompt You (Easiest)

1. **Quit YoDaAI** (Cmd+Q)

2. **Open Terminal** and run this command:
   ```bash
   defaults delete com.jianqingpeng.YoDaAI hasRequestedAccessibilityPermission
   ```

3. **Relaunch YoDaAI** - A system dialog should appear saying:
   > "YoDaAI would like to control this computer using accessibility features"

4. Click **"Open System Settings"**

5. In System Settings, find **YoDaAI** in the list and **toggle it ON**

6. **Restart YoDaAI**

### Option B: Manual Grant (If dialog doesn't appear)

1. Open **System Settings** (or System Preferences)
2. Go to **Privacy & Security**
3. Click **Accessibility** in the left sidebar
4. Click the **🔒 lock icon** at the bottom and enter your password
5. Look for **YoDaAI** in the list:
   - **If YoDaAI is listed**: Enable the toggle switch
   - **If YoDaAI is NOT listed**: Click the **+** button, navigate to your YoDaAI app, and add it
6. **Restart YoDaAI**

### Verify Accessibility is Granted

1. Open YoDaAI
2. Press **Cmd+,** to open Settings
3. Go to **Permissions** tab
4. Under "Accessibility Permission", you should see:
   - ✅ **Green checkmark**
   - Status: **"Granted"**

---

## Step 2: Grant Automation Permission (5 minutes)

Now that Accessibility is granted, you need Automation permission for each app.

### Easiest Method: Use @ Mention to Trigger Permission

1. **Open Safari** (or Chrome, or any browser)
2. Click in the **URL bar** or **search box**
3. Switch back to **YoDaAI**
4. In the chat composer, type **`@`**
5. Select **Safari** from the list
6. **WATCH FOR A DIALOG** - it might appear behind other windows!
   > "YoDaAI would like to control Safari"
7. Click **"OK"** or **"Allow"**

### Verify Automation is Granted

1. Open **System Settings** → **Privacy & Security**
2. Click **Automation** in the left sidebar
3. You should now see **YoDaAI** in the list
4. Under YoDaAI, **Safari** (or the app you tested) should be **checked/enabled**

---

## Step 3: Test Content Capture

Now test if content capture works:

1. Open **Safari**
2. Navigate to any website (e.g., google.com)
3. Click in the search box or URL bar
4. Type some text: "Hello World"
5. Switch back to **YoDaAI**
6. Type **`@`** in the composer
7. Select **Safari**
8. You should see: **"Safari • X characters captured"**

Look at the console logs - you should see:
```
[ContentCacheService] Cached content for Safari: X chars
```

If you see this, **IT WORKS!** 🎉

---

## Troubleshooting

### Issue: Still seeing "Permission not granted"

**Solution:**
1. Make sure you completed Step 1 (Accessibility)
2. Restart YoDaAI after granting permission
3. Check System Settings → Privacy & Security → Accessibility
4. YoDaAI should be listed and **enabled**

### Issue: "AppleScript error: [-1743]"

**Solution:**
1. This means Automation permission is not granted
2. The dialog should have appeared when you used @ mention
3. Check System Settings → Privacy & Security → Automation
4. If YoDaAI is listed, enable the toggle for the app you want
5. If YoDaAI is NOT listed, try the @ mention again and watch for the dialog

### Issue: "AppleScript error: [-600]"

**Solution:**
- This is NOT a permission error
- Error -600 means the app is still launching or not responding
- Wait a few seconds and try again
- Make sure the target app is fully open and ready

### Issue: No content captured (0 chars)

**Possible causes:**
1. Accessibility permission not granted → See Step 1
2. No text field is focused in the target app
3. The focused field is empty
4. The app doesn't expose content via Accessibility API

**Solution:**
1. Make sure you clicked in a text field in the target app
2. Type some text in that field
3. Then switch to YoDaAI and use @ mention
4. Try different apps - TextEdit, Notes work well

---

## Quick Checklist

Before testing content capture, make sure:

- [ ] Accessibility permission granted (System Settings → Privacy & Security → Accessibility → YoDaAI enabled)
- [ ] YoDaAI restarted after granting Accessibility
- [ ] Green checkmark shows in YoDaAI Settings → Permissions tab
- [ ] Tested @ mention with Safari/Chrome to trigger Automation permission
- [ ] Clicked "OK" when permission dialog appeared
- [ ] YoDaAI appears in System Settings → Privacy & Security → Automation
- [ ] Target app has a text field focused with some content
- [ ] Target app is fully launched and responsive

---

## Where to Find YoDaAI App

If you're building from Xcode, the app is usually at:
```
~/Library/Developer/Xcode/DerivedData/YoDaAI-*/Build/Products/Debug/YoDaAI.app
```

For installed apps, check:
```
/Applications/YoDaAI.app
```

---

## Still Not Working?

1. **Check console logs** for specific error messages
2. Look for lines starting with `[AccessibilityService]` or `[ContentCacheService]`
3. Share the error codes you see:
   - `-1743` = Automation permission issue
   - `-600` = App not responding (wait and retry)
   - `Permission not granted` = Accessibility not granted

4. **Try a different app first**:
   - Safari can be slow to respond
   - Try **TextEdit** or **Notes** first (faster and more reliable)

5. **Restart macOS** if permission system seems stuck

---

## Summary: The Two Permissions You Need

1. **Accessibility** - System-wide permission to read UI elements
   - Location: System Settings → Privacy & Security → Accessibility
   - Required: **MUST** be granted first

2. **Automation** - Per-app permission to control apps via AppleScript
   - Location: System Settings → Privacy & Security → Automation
   - Required: Grant for each app you want to capture from (Safari, Chrome, etc.)

**Both are required for content capture to work!**
