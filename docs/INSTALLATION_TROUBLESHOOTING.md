# YoDaAI Installation Troubleshooting

## Common Installation Issues

### Issue: "YoDaAI is damaged and can't be opened"

This is a macOS Gatekeeper security feature. The app isn't actually damaged - macOS just doesn't recognize the developer signature.

#### Solution 1: Remove Quarantine Attribute (Recommended)

Open Terminal and run:

```bash
xattr -cr /Applications/YoDaAI.app
```

Or if you haven't moved it to Applications yet:

```bash
xattr -cr ~/Downloads/YoDaAI.app
```

Then open the app normally.

#### Solution 2: Right-Click to Open

1. Right-click (or Control+click) on YoDaAI.app
2. Select "Open" from the menu
3. Click "Open" in the dialog that appears
4. The app will open and be remembered for future launches

#### Solution 3: System Settings Override

1. Try to open YoDaAI normally (it will be blocked)
2. Go to **System Settings** → **Privacy & Security**
3. Scroll down to find: "YoDaAI was blocked from use"
4. Click **"Open Anyway"**
5. Confirm by clicking **"Open"**

### Issue: "YoDaAI can't be opened because Apple cannot check it for malicious software"

This is the same Gatekeeper issue. Use Solution 1 (remove quarantine) above.

### Issue: App opens but immediately crashes

This usually means the app architecture doesn't match your Mac.

**Check your Mac:**
- Apple Silicon (M1/M2/M3): Use the universal build
- Intel: Use the universal build

The YoDaAI release should work on both architectures.

**If it still crashes:**
1. Check Console.app for crash logs
2. Look for error messages mentioning YoDaAI
3. Report the issue with crash logs

### Issue: "The application YoDaAI can't be opened"

**Possible causes:**
1. Downloaded file is corrupted
2. Wrong macOS version (need macOS 13+)
3. Incomplete download

**Solutions:**
1. Re-download the file
2. Check your macOS version: **→ About This Mac**
3. Verify download completed (check file size matches GitHub)

### Issue: Can't grant Accessibility permission

**Solution:**
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **🔒 lock icon** and enter your password
3. Click the **+** button to add YoDaAI
4. Navigate to `/Applications/YoDaAI.app` and add it
5. Make sure the toggle is **ON**
6. Restart YoDaAI

See [QUICKSTART_FIX_PERMISSIONS.md](QUICKSTART_FIX_PERMISSIONS.md) for detailed permission setup.

## Why Does This Happen?

### Gatekeeper Protection

macOS Gatekeeper requires apps to be:
1. **Notarized** by Apple (requires Apple Developer account)
2. **Signed** with a Developer ID certificate (requires Apple Developer account)

Since YoDaAI is an open-source project, it's not signed with an Apple Developer ID. This triggers Gatekeeper warnings.

### The Quarantine Flag

When you download an app from the internet, macOS adds a "quarantine" flag (`com.apple.quarantine`) to mark it as potentially unsafe. This flag triggers Gatekeeper checks.

The `xattr -cr` command removes this flag, allowing the app to open normally.

## Is It Safe?

**Yes!** YoDaAI is open source and you can:
1. Review the source code: https://github.com/pjq/YoDaAI
2. Build from source yourself
3. Check the SHA256 checksum of releases

The "damaged" message is misleading - it's just macOS being cautious about unsigned apps.

## Building from Source (Alternative)

If you prefer, you can build YoDaAI yourself:

```bash
git clone https://github.com/pjq/YoDaAI.git
cd YoDaAI
open YoDaAI.xcodeproj
```

Then build and run in Xcode (⌘R). Apps you build yourself don't trigger Gatekeeper.

## Verifying Downloads

To verify your download hasn't been tampered with:

```bash
# Calculate SHA256 checksum
shasum -a 256 ~/Downloads/YoDaAI-0.1.0.zip

# Compare with checksums published in release notes
```

## For Developers: Signing Your Build

If you're building from source and want to avoid Gatekeeper issues:

```bash
# Ad-hoc signing (local only)
codesign --force --deep --sign - /path/to/YoDaAI.app

# Or with a Developer ID (if you have one)
codesign --force --deep --sign "Developer ID Application: Your Name" /path/to/YoDaAI.app
```

## Getting an Apple Developer ID

If you want to distribute signed builds:

1. Join the Apple Developer Program ($99/year)
2. Create a Developer ID certificate
3. Sign the app with your certificate
4. Optionally notarize the app with Apple

This removes all Gatekeeper warnings for users.

## Still Having Issues?

1. Check our [GitHub Issues](https://github.com/pjq/YoDaAI/issues)
2. Search for similar problems
3. Create a new issue with:
   - Your macOS version
   - Error message (screenshot)
   - Steps you've tried
   - Console.app logs (if crashing)

## Related Documentation

- [QUICKSTART_FIX_PERMISSIONS.md](QUICKSTART_FIX_PERMISSIONS.md) - Permission setup
- [ACCESSIBILITY_SETUP.md](ACCESSIBILITY_SETUP.md) - Accessibility guide
- [README.md](../README.md) - Main documentation
