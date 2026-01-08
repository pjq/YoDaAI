# YoDaAI Release Process

This document describes how to create and publish releases for YoDaAI.

## Prerequisites

### 1. GitHub Personal Access Token

You need a GitHub Personal Access Token with `repo` permissions to create releases.

#### Create Token:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Give it a name: "YoDaAI Release"
4. Select scopes:
   - ✅ `repo` (Full control of private repositories)
5. Click "Generate token"
6. **Copy the token** (you won't see it again!)

#### Add Token to ~/.zshrc:

```bash
echo 'export GITHUB_TOKEN="your_token_here"' >> ~/.zshrc
source ~/.zshrc
```

Verify it's loaded:
```bash
echo $GITHUB_TOKEN
```

### 2. Required Tools

Make sure you have these installed:

- **Xcode** (with command line tools)
- **jq** (JSON processor)
  ```bash
  brew install jq
  ```

## Quick Release (One Command)

The easiest way to create a release:

```bash
./release.sh
```

This will:
1. ✅ Check for uncommitted changes (blocks if found)
2. ✅ Show current version
3. ✅ Ask you to choose version bump type (patch/minor/major)
4. ✅ Generate changelog from git commits
5. ✅ Update version in Info.plist
6. ✅ Build Release configuration
7. ✅ Create ZIP and DMG artifacts
8. ✅ Create git tag
9. ✅ Push to GitHub
10. ✅ Create GitHub release with artifacts
11. ✅ Open release page in browser

## Step-by-Step Usage

### 1. Prepare for Release

Make sure all changes are committed:

```bash
git status
# Should show: "nothing to commit, working tree clean"
```

If you have changes, commit them first:

```bash
git add .
git commit -m "Your commit message"
git push
```

### 2. Run Release Script

```bash
./release.sh
```

### 3. Choose Version Bump

The script will show:

```
Current version: 0.1.0

Select version bump type:
1) Patch (0.1.0 → 0.1.1) - Bug fixes
2) Minor (0.1.0 → 0.2.0) - New features
3) Major (0.1.0 → 1.0.0) - Breaking changes
4) Custom version
Enter choice [1-4]:
```

**Choose based on your changes:**
- **Patch (1)**: Bug fixes, small improvements, no new features
- **Minor (2)**: New features, backward compatible
- **Major (3)**: Breaking changes, major overhaul
- **Custom (4)**: Specify exact version (e.g., 1.0.0-beta.1)

### 4. Review Changelog

The script will generate a changelog from recent commits:

```
Changelog:
- Add Yoda app icon and fix slash command publishing errors
- Add automatic Accessibility permission request on first launch
- Update permissions guide: clarify BOTH Accessibility AND Automation are required
- Improve Automation permission request UX and add troubleshooting guide
```

### 5. Confirm Release

```
Proceed with release v0.1.1? [y/N]: y
```

Type `y` and press Enter.

### 6. Wait for Build

The script will:
- Update Info.plist with new version
- Commit the version bump
- Build Release configuration (takes 1-2 minutes)
- Create ZIP and DMG files
- Create git tag
- Push to GitHub
- Create GitHub release
- Upload artifacts

### 7. Release Published!

When complete, you'll see:

```
==================================
Release Complete!
==================================

Version: v0.1.1
ZIP: /path/to/YoDaAI-0.1.1.zip
DMG: /path/to/YoDaAI-0.1.1.dmg
GitHub Release: https://github.com/pjq/YoDaAI/releases/tag/v0.1.1

✓ Release v0.1.1 published successfully!
```

The release page will open in your browser automatically.

## Release Artifacts

Each release includes two download options:

1. **YoDaAI-X.Y.Z.zip** - Simple ZIP archive
   - Just extract and drag to Applications
   - Smaller file size

2. **YoDaAI-X.Y.Z.dmg** - Disk Image (recommended)
   - Professional installer
   - Includes Applications symlink for easy installation
   - Larger file size

## Semantic Versioning

YoDaAI follows [Semantic Versioning](https://semver.org/):

**Format:** `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (e.g., 1.0.0 → 2.0.0)
  - API changes that break backward compatibility
  - Major UI/UX redesign
  - Removed features

- **MINOR**: New features (e.g., 0.1.0 → 0.2.0)
  - New slash commands
  - New settings or options
  - New integrations
  - Backward compatible

- **PATCH**: Bug fixes (e.g., 0.1.0 → 0.1.1)
  - Bug fixes
  - Performance improvements
  - Documentation updates
  - Security patches

## Changelog Generation

The script automatically generates changelogs from git commit messages since the last tag.

### Writing Good Commit Messages

Use descriptive commit messages for better changelogs:

**Good:**
```
Add /settings slash command to open settings window
Fix Automation permission dialog not appearing
Improve content capture for Safari
```

**Bad:**
```
fix bug
update code
wip
```

### Conventional Commits (Recommended)

Use conventional commit format for even better changelogs:

```
feat: add /settings slash command
fix: automation permission dialog not appearing
perf: improve content capture for Safari
docs: add quickstart guide for permissions
```

## Troubleshooting

### Error: "GITHUB_TOKEN not found"

**Solution:**
```bash
echo 'export GITHUB_TOKEN="your_token_here"' >> ~/.zshrc
source ~/.zshrc
```

### Error: "You have uncommitted changes"

**Solution:**
```bash
git status
git add .
git commit -m "Your message"
# Then run release.sh again
```

### Error: "Build failed"

**Solution:**
1. Check build log: `/tmp/xcodebuild.log`
2. Fix errors in Xcode
3. Commit fixes
4. Run release.sh again

### Error: "Failed to create release"

**Solution:**
1. Check if tag already exists:
   ```bash
   git tag
   ```
2. If tag exists, delete it:
   ```bash
   git tag -d v0.1.1
   git push origin :refs/tags/v0.1.1
   ```
3. Run release.sh again

### Error: "jq: command not found"

**Solution:**
```bash
brew install jq
```

## Manual Release (Alternative)

If the script doesn't work, you can create a release manually:

### 1. Build Release

```bash
xcodebuild -scheme YoDaAI -configuration Release clean build
```

### 2. Find Built App

```bash
find ~/Library/Developer/Xcode/DerivedData -name "YoDaAI.app" -path "*/Release/*"
```

### 3. Create ZIP

```bash
cd /path/to/Release
ditto -c -k --keepParent YoDaAI.app YoDaAI-0.1.1.zip
```

### 4. Create Git Tag

```bash
git tag -a v0.1.1 -m "Release 0.1.1"
git push origin v0.1.1
```

### 5. Create GitHub Release

1. Go to https://github.com/pjq/YoDaAI/releases/new
2. Choose tag: v0.1.1
3. Write release notes
4. Upload ZIP file
5. Publish release

## Best Practices

1. **Always test before releasing**
   - Run the Debug build
   - Test all features
   - Check permissions work

2. **Write clear release notes**
   - What's new
   - What's fixed
   - Breaking changes (if any)
   - Installation instructions

3. **Keep versions consistent**
   - Update Info.plist
   - Update git tags
   - Update GitHub release

4. **Test the release build**
   - Download from GitHub releases
   - Install on clean system
   - Verify it works

5. **Announce releases**
   - Share on social media
   - Update documentation
   - Notify users

## Release Checklist

Before running `./release.sh`:

- [ ] All code changes committed and pushed
- [ ] Tests passing (if you have tests)
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (optional)
- [ ] No uncommitted changes (`git status` is clean)
- [ ] GITHUB_TOKEN is set in ~/.zshrc
- [ ] jq is installed (`brew install jq`)
- [ ] You've tested the latest changes
- [ ] You know which version bump to use (patch/minor/major)

After release:

- [ ] Verify release appears on GitHub
- [ ] Download and test artifacts
- [ ] Check release notes are correct
- [ ] Announce release (optional)

## Continuous Integration (Future)

For future automation, consider setting up GitHub Actions to:
- Automatically build on every push
- Run tests
- Create releases on tag push
- Upload artifacts

Example workflow: `.github/workflows/release.yml`

## Support

If you encounter issues with the release process:

1. Check this documentation
2. Check `/tmp/xcodebuild.log` for build errors
3. Verify GITHUB_TOKEN is valid
4. Try manual release as fallback
5. File an issue on GitHub

## Version History

See all releases: https://github.com/pjq/YoDaAI/releases
