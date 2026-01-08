# Automation Permission Troubleshooting

## The Issue: YoDaAI Not Appearing in Automation Settings

If you can't see **YoDaAI** in System Settings → Privacy & Security → Automation, this is **NORMAL** and **EXPECTED**.

### Why This Happens

macOS **only adds apps to the Automation list AFTER they try to control another app for the first time**. The list is populated dynamically, not statically.

### How Automation Permissions Work

1. **First Attempt**: When YoDaAI first tries to control Safari (or any app) via AppleScript:
   - macOS shows a permission dialog: "YoDaAI would like to control Safari"
   - You click "OK" or "Allow"
   - macOS adds YoDaAI to the Automation list with Safari enabled

2. **Subsequent Attempts**: YoDaAI can control that app without asking again

3. **List Population**: The Automation settings list only shows apps that have **attempted** to control other apps

### Step-by-Step: Triggering the Permission Dialog

#### Method 1: Use YoDaAI's Permission Buttons (Recommended)

1. Open **YoDaAI Settings** (Cmd+,)
2. Go to **Permissions** tab
3. Scroll to "Automation Permission" section
4. Click **"Request Permission"** for Safari (or any app)
5. A dialog appears explaining what will happen
6. Click **"Continue"**
7. **Wait and watch for the system permission dialog** (it may appear behind windows!)
8. The dialog says: **"YoDaAI would like to control Safari"**
9. Click **"OK"** to grant permission

#### Method 2: Just Use the @ Mention Feature

The permission dialog will appear automatically when you:

1. Open Safari and focus on the URL bar
2. Switch back to YoDaAI
3. Type `@` in the chat composer
4. Select "Safari" from the list
5. **The permission dialog appears automatically**
6. Click "OK"

This is actually the easiest way!

#### Method 3: Manual AppleScript Test

You can test manually by running this in Terminal:

```bash
osascript -e 'tell application "Safari" to count windows'
```

If permission is not granted, you'll see:
```
execution error: Not authorized to send Apple events to Safari. (-1743)
```

### Common Issues & Solutions

#### Issue 1: "I clicked Request Permission but no dialog appeared"

**Possible causes:**
- The dialog appeared but got hidden behind other windows
- Safari (or the target app) wasn't fully launched yet
- Permission was already granted (check Automation settings)
- The app is still starting up (error -600)

**Solutions:**
- Check **all open windows** - the dialog may be hiding
- Wait a few seconds for the app to fully launch
- Check System Settings → Privacy & Security → Automation to see if YoDaAI is there now
- Try again - click the button multiple times if needed
- Look at Console logs for error messages

#### Issue 2: "Still can't see YoDaAI in Automation settings"

**This means:** YoDaAI hasn't successfully executed an AppleScript command yet.

**Solutions:**
1. **Restart YoDaAI** after granting Accessibility permission
2. Make sure **Accessibility permission is granted first** (it's required!)
3. Try the @ mention method (Method 2 above) instead
4. Check if the target app is actually installed and working
5. Look for error codes in the console:
   - **-1743**: Permission denied (dialog should have appeared)
   - **-600**: App not responding (wait and try again)
   - **-1728**: App doesn't support AppleScript (can't fix)

#### Issue 3: "Error -1743 but I didn't see a dialog"

The dialog appeared but you might have:
- Clicked "Don't Allow" by mistake
- Closed it accidentally
- Missed it behind another window

**Solution:**
1. The permission is now **denied** and saved
2. You must go to **System Settings → Privacy & Security → Automation** manually
3. Find **YoDaAI** in the list (it should be there now!)
4. Enable the toggle for the app you want to control

#### Issue 4: "YoDaAI appears in Automation list but app is disabled"

Perfect! This means the dialog appeared and you clicked "Don't Allow" (or it was denied automatically).

**Solution:**
1. In System Settings → Privacy & Security → Automation
2. Find **YoDaAI**
3. **Enable the toggle** next to the app name
4. No restart needed - it works immediately!

### Checking Permission Status

#### Via Console Logs

Look for these messages when clicking "Request Permission":

**✅ SUCCESS** (Permission granted):
```
[AutomationAppRow] ✅ AppleScript succeeded for Safari!
[AutomationAppRow] → Permission is GRANTED
```

**❌ DENIED** (Permission not granted):
```
[AutomationAppRow] AppleScript error: [-1743]
[AutomationAppRow] ⚠️ Permission DENIED or NOT YET GRANTED
[AutomationAppRow] → Go to: System Settings → Privacy & Security → Automation
```

**⏳ WAITING** (App still launching):
```
[AutomationAppRow] AppleScript error: [-600]
[AutomationAppRow] ⚠️ Error -600: Safari is not responding to AppleScript
[AutomationAppRow] → Try again in a few seconds
```

#### Via System Settings

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Click **Automation** in left sidebar
4. Look for **YoDaAI** in the list
5. If it's there, check which apps are enabled
6. If it's not there, permissions haven't been triggered yet

### Best Practice: Full Setup Flow

Do these steps **in order**:

1. ✅ **Grant Accessibility Permission First**
   - System Settings → Privacy & Security → Accessibility
   - Enable YoDaAI
   - Restart YoDaAI

2. ✅ **Test with @ Mention** (Easiest way to trigger permissions)
   - Open Safari
   - Click in URL bar
   - Switch to YoDaAI
   - Type `@`
   - Select Safari
   - **Watch for permission dialog** and click "OK"

3. ✅ **Verify Automation Permission Granted**
   - System Settings → Privacy & Security → Automation
   - YoDaAI should now appear in list
   - Safari should be enabled
   - Repeat for Chrome, Notes, etc.

4. ✅ **Test Content Capture**
   - Use @ mention again
   - Should see "X characters captured"
   - No more errors in console

### Technical Details

**Why the dialog may not show:**
- macOS caches permission decisions
- If you previously denied, it won't ask again without manual enable
- The dialog is modal but can be hidden by other windows
- Some apps take time to respond to AppleScript

**Entitlements required:**
```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```
✅ YoDaAI has this entitlement enabled

**Sandbox status:**
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```
✅ YoDaAI is NOT sandboxed, which is correct for AppleScript

### Alternative: Manual Permission Grant

If the automatic method doesn't work, you can manually add YoDaAI:

1. Open **Terminal**
2. Run this command (replace Safari with your target app):
   ```bash
   osascript -e 'tell application "Safari" to count windows'
   ```
3. The permission dialog will appear
4. Click "OK"
5. Now YoDaAI is added to Automation settings
6. Enable other apps manually in System Settings

### Still Not Working?

If you've tried everything and it still doesn't work:

1. **Check YoDaAI is in the Automation list**
   - If not there → Permissions never triggered
   - If there but disabled → Enable the toggles

2. **Check Accessibility permission is granted**
   - Must be granted BEFORE Automation
   - Restart YoDaAI after granting Accessibility

3. **Check console logs for specific errors**
   - -1743 = Permission issue
   - -600 = App not ready (not a permission issue)
   - -1728 = App doesn't support command (can't fix)

4. **Try a different app first**
   - Safari can be slow to respond
   - Try TextEdit or Notes first (faster)

5. **Restart macOS**
   - Sometimes permission system gets stuck
   - Restart clears the cache
