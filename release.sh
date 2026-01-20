#!/bin/bash

# YoDaAI Release Script
# This script automates the entire release process:
# 1. Auto-bump version (patch/minor/major)
# 2. Generate changelog from git commits
# 3. Build Release configuration
# 4. Create DMG and ZIP artifacts
# 5. Create GitHub release with artifacts
# 6. Update version in Xcode project

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="YoDaAI"
SCHEME_NAME="YoDaAI"
INFO_PLIST="${PROJECT_DIR}/YoDaAI/Info.plist"
REPO_OWNER="pjq"
REPO_NAME="YoDaAI"

# Load GitHub token from environment or zshrc
# Try to load from .zshrc but ignore Oh My Zsh errors
if [ -z "$GITHUB_TOKEN" ] && [ -f ~/.zshrc ]; then
    # Extract GITHUB_TOKEN from .zshrc without fully sourcing it
    GITHUB_TOKEN=$(grep "^export GITHUB_TOKEN" ~/.zshrc | sed 's/export GITHUB_TOKEN=//' | tr -d '"' | tr -d "'")
    export GITHUB_TOKEN
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}ERROR: GITHUB_TOKEN not found in environment${NC}"
    echo "Please add to ~/.zshrc:"
    echo "export GITHUB_TOKEN='your_github_token_here'"
    exit 1
fi

# Functions
print_header() {
    echo -e "\n${BLUE}===================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Get current version from git tags
get_current_version() {
    local version=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "${version#v}"  # Remove 'v' prefix
}

# Parse semantic version
parse_version() {
    local version=$1
    local major=$(echo $version | cut -d. -f1)
    local minor=$(echo $version | cut -d. -f2)
    local patch=$(echo $version | cut -d. -f3)
    echo "$major $minor $patch"
}

# Bump version
bump_version() {
    local version=$1
    local bump_type=$2

    read major minor patch <<< $(parse_version $version)

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            print_error "Invalid bump type: $bump_type"
            exit 1
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Generate changelog from git commits since last tag
generate_changelog() {
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
    local commits=$(git log ${last_tag}..HEAD --pretty=format:"- %s" --no-merges)

    if [ -z "$commits" ]; then
        echo "- Minor bug fixes and improvements"
    else
        echo "$commits"
    fi
}

# Update version in Info.plist
update_info_plist() {
    local version=$1
    local build_number=$(git rev-list --count HEAD)

    if [ ! -f "$INFO_PLIST" ]; then
        print_info "Creating Info.plist..."
        cat > "$INFO_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleVersion</key>
    <string>${build_number}</string>
</dict>
</plist>
EOF
    else
        # Update existing Info.plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$INFO_PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$INFO_PLIST"

        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$INFO_PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$INFO_PLIST"
    fi

    print_success "Updated Info.plist: v${version} (${build_number})"
}

# Build Release configuration
build_release() {
    print_header "Building Release Configuration"

    cd "$PROJECT_DIR"

    # Clean build folder
    print_info "Cleaning build folder..."
    xcodebuild clean -scheme "$SCHEME_NAME" -configuration Release > /dev/null 2>&1

    # Build
    print_info "Building ${SCHEME_NAME}..."
    xcodebuild -scheme "$SCHEME_NAME" -configuration Release build \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
        2>&1 | tee /tmp/xcodebuild.log | grep -E "(error:|warning:|BUILD)" || true

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        print_error "Build failed! Check /tmp/xcodebuild.log for details"
        exit 1
    fi

    print_success "Build completed successfully"
}

# Find the built app
find_built_app() {
    local app_path=$(find ~/Library/Developer/Xcode/DerivedData -name "${PROJECT_NAME}.app" -path "*/Release/*" -print -quit 2>/dev/null)

    if [ -z "$app_path" ]; then
        print_error "Could not find built app"
        exit 1
    fi

    echo "$app_path"
}

# Code sign the app (ad-hoc signing to avoid Gatekeeper issues)
sign_app() {
    local app_path=$1

    print_info "Code signing app (ad-hoc)..."

    # Remove existing signature if any
    codesign --remove-signature "$app_path" 2>/dev/null || true

    # Sign with ad-hoc identity
    codesign --force --deep --sign - "$app_path"

    if [ $? -eq 0 ]; then
        print_success "App signed successfully"
    else
        print_error "Failed to sign app (non-fatal, continuing...)"
    fi

    # Verify signature
    codesign --verify --verbose "$app_path" 2>/dev/null && \
        print_success "Signature verified" || \
        print_info "Note: App is unsigned (users will need to bypass Gatekeeper)"
}

# Create ZIP artifact
create_zip() {
    local app_path=$1
    local version=$2
    local output_dir="${PROJECT_DIR}/releases"
    local zip_name="${PROJECT_NAME}-${version}.zip"

    mkdir -p "$output_dir"

    print_info "Creating ZIP: ${zip_name}"

    cd "$(dirname "$app_path")"
    ditto -c -k --keepParent "${PROJECT_NAME}.app" "${output_dir}/${zip_name}"

    print_success "Created: ${output_dir}/${zip_name}"
    echo "${output_dir}/${zip_name}"
}

# Create DMG artifact (optional, more professional)
create_dmg() {
    local app_path=$1
    local version=$2
    local output_dir="${PROJECT_DIR}/releases"
    local dmg_name="${PROJECT_NAME}-${version}.dmg"
    local temp_dmg="/tmp/${PROJECT_NAME}-temp.dmg"

    mkdir -p "$output_dir"

    print_info "Creating DMG: ${dmg_name}"

    # Create temporary DMG
    hdiutil create -size 100m -fs HFS+ -volname "$PROJECT_NAME" "$temp_dmg" > /dev/null 2>&1

    # Mount it
    local mount_point=$(hdiutil attach "$temp_dmg" | grep Volumes | awk '{print $3}')

    # Copy app
    cp -R "$app_path" "$mount_point/"

    # Create Applications symlink
    ln -s /Applications "$mount_point/Applications"

    # Unmount
    hdiutil detach "$mount_point" > /dev/null 2>&1

    # Convert to compressed DMG
    hdiutil convert "$temp_dmg" -format UDZO -o "${output_dir}/${dmg_name}" > /dev/null 2>&1
    rm "$temp_dmg"

    print_success "Created: ${output_dir}/${dmg_name}"
    echo "${output_dir}/${dmg_name}"
}

# Create GitHub release
create_github_release() {
    local version=$1
    local changelog=$2
    local zip_path=$3
    local dmg_path=$4

    print_header "Creating GitHub Release"

    local tag="v${version}"
    local release_name="YoDaAI ${version}"

    # Create release body
    local body=$(cat <<EOF
# YoDaAI ${version}

## What's New

${changelog}

## Installation

### macOS (Apple Silicon & Intel)

1. Download ${PROJECT_NAME}-${version}.zip or ${PROJECT_NAME}-${version}.dmg
2. Open the downloaded file
3. Drag YoDaAI to your Applications folder
4. **Important**: Remove the quarantine flag (first time only):
   - Run in Terminal: xattr -cr /Applications/YoDaAI.app
5. Open YoDaAI
6. Grant Accessibility and Automation permissions (see docs)

### Troubleshooting: "YoDaAI is damaged"

If you see this error, it is just macOS Gatekeeper being cautious. The app is **not** actually damaged.

**Quick fix:** Run in Terminal: xattr -cr /Applications/YoDaAI.app

**Alternative:** Right-click YoDaAI → Open → Click "Open" in the dialog.

See [Installation Troubleshooting](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/docs/INSTALLATION_TROUBLESHOOTING.md) for more solutions.

## Permissions Required

⚠️ **Important**: YoDaAI needs two permissions to capture content from other apps:

- **Accessibility**: System Settings → Privacy & Security → Accessibility → Enable YoDaAI
- **Automation**: Will be requested per-app when you use @ mentions

See [QUICKSTART_FIX_PERMISSIONS.md](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/docs/QUICKSTART_FIX_PERMISSIONS.md) for detailed setup instructions.

## Documentation

- [Quick Start Guide](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/docs/QUICKSTART_FIX_PERMISSIONS.md)
- [Accessibility Setup](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/docs/ACCESSIBILITY_SETUP.md)
- [Automation Troubleshooting](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/docs/AUTOMATION_PERMISSION_TROUBLESHOOTING.md)

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
EOF
)

    # Create release via GitHub API
    print_info "Creating release ${tag}..."

    local response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases \
        -d @- <<EOF
{
  "tag_name": "${tag}",
  "name": "${release_name}",
  "body": $(echo "$body" | jq -Rs .),
  "draft": false,
  "prerelease": false
}
EOF
)

    local release_id=$(echo "$response" | jq -r .id)

    if [ "$release_id" == "null" ] || [ -z "$release_id" ]; then
        print_error "Failed to create release"
        echo "$response" | jq .
        exit 1
    fi

    print_success "Created release: ${tag} (ID: ${release_id})"

    # Upload ZIP artifact
    if [ -f "$zip_path" ]; then
        print_info "Uploading ZIP artifact..."
        local zip_filename=$(basename "$zip_path")

        local upload_response=$(curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Content-Type: application/zip" \
            --data-binary @"${zip_path}" \
            "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${release_id}/assets?name=${zip_filename}")

        if echo "$upload_response" | jq -e '.browser_download_url' > /dev/null 2>&1; then
            print_success "Uploaded: ${zip_filename}"
        else
            print_error "Failed to upload ZIP artifact"
            echo "$upload_response" | jq . 2>/dev/null || echo "$upload_response"
        fi
    fi

    # Upload DMG artifact
    if [ -f "$dmg_path" ]; then
        print_info "Uploading DMG artifact..."
        local dmg_filename=$(basename "$dmg_path")

        local upload_response=$(curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Content-Type: application/x-apple-diskimage" \
            --data-binary @"${dmg_path}" \
            "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${release_id}/assets?name=${dmg_filename}")

        if echo "$upload_response" | jq -e '.browser_download_url' > /dev/null 2>&1; then
            print_success "Uploaded: ${dmg_filename}"
        else
            print_error "Failed to upload DMG artifact"
            echo "$upload_response" | jq . 2>/dev/null || echo "$upload_response"
        fi
    fi

    local release_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${tag}"
    print_success "Release published: ${release_url}"
    echo "$release_url"
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    -t, --type TYPE       Version bump type: patch, minor, major
    -v, --version VERSION Custom version number (e.g., 1.2.3)
    -y, --yes            Skip confirmation prompt
    -h, --help           Show this help message

Examples:
    $0 --type minor --yes          # Bump minor version without confirmation
    $0 -t patch -y                 # Bump patch version without confirmation
    $0 -v 1.0.0 --yes              # Release specific version
    $0                             # Interactive mode (default)

EOF
}

# Parse command-line arguments
parse_args() {
    BUMP_TYPE=""
    CUSTOM_VERSION=""
    AUTO_CONFIRM=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BUMP_TYPE="$2"
                if [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
                    print_error "Invalid bump type: $BUMP_TYPE. Must be patch, minor, or major."
                    exit 1
                fi
                shift 2
                ;;
            -v|--version)
                CUSTOM_VERSION="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main release process
main() {
    # Parse command-line arguments
    parse_args "$@"

    print_header "YoDaAI Release Automation"

    # Check if in git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_error "You have uncommitted changes. Please commit or stash them first."
        exit 1
    fi

    # Get current version
    local current_version=$(get_current_version)
    print_info "Current version: ${current_version}"

    local new_version=""

    # Determine version based on arguments or interactive input
    if [ -n "$CUSTOM_VERSION" ]; then
        new_version="$CUSTOM_VERSION"
        print_info "Using custom version: ${new_version}"
    elif [ -n "$BUMP_TYPE" ]; then
        new_version=$(bump_version $current_version $BUMP_TYPE)
        print_info "Bumping $BUMP_TYPE version: ${current_version} → ${new_version}"
    else
        # Interactive mode
        echo -e "\n${YELLOW}Select version bump type:${NC}"
        echo "1) Patch (${current_version} → $(bump_version $current_version patch))"
        echo "2) Minor (${current_version} → $(bump_version $current_version minor))"
        echo "3) Major (${current_version} → $(bump_version $current_version major))"
        echo "4) Custom version"
        read -p "Enter choice [1-4]: " choice

        case $choice in
            1) new_version=$(bump_version $current_version patch) ;;
            2) new_version=$(bump_version $current_version minor) ;;
            3) new_version=$(bump_version $current_version major) ;;
            4)
                read -p "Enter custom version (e.g., 1.2.3): " new_version
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac

        print_info "New version: ${new_version}"
    fi

    # Generate changelog
    print_info "Generating changelog..."
    local changelog=$(generate_changelog)

    echo -e "\n${YELLOW}Changelog:${NC}"
    echo "$changelog"

    # Confirm (skip if --yes flag is set)
    if [ "$AUTO_CONFIRM" = false ]; then
        echo ""
        read -p "Proceed with release v${new_version}? [y/N]: " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            print_info "Release cancelled"
            exit 0
        fi
    else
        print_info "Auto-confirming release (--yes flag set)"
    fi

    # Update version
    print_header "Updating Version"
    update_info_plist "$new_version"

    # Commit version bump
    git add "$INFO_PLIST"
    git commit -m "Bump version to ${new_version}" || true

    # Build release
    build_release

    # Find built app
    print_info "Locating built app..."
    local app_path=$(find_built_app)
    print_success "Found: ${app_path}"

    # Sign the app
    sign_app "$app_path"

    # Create artifacts
    print_header "Creating Release Artifacts"
    local zip_path=$(create_zip "$app_path" "$new_version")
    local dmg_path=$(create_dmg "$app_path" "$new_version")

    # Create git tag
    print_info "Creating git tag v${new_version}..."
    git tag -a "v${new_version}" -m "Release ${new_version}"

    # Push changes
    print_info "Pushing changes to GitHub..."
    git push origin main
    git push origin "v${new_version}"

    # Create GitHub release
    local release_url=$(create_github_release "$new_version" "$changelog" "$zip_path" "$dmg_path")

    # Final summary
    print_header "Release Complete!"
    echo -e "${GREEN}Version:${NC} v${new_version}"
    echo -e "${GREEN}ZIP:${NC} ${zip_path}"
    echo -e "${GREEN}DMG:${NC} ${dmg_path}"
    echo -e "${GREEN}GitHub Release:${NC} ${release_url}"
    echo ""
    print_success "Release v${new_version} published successfully!"

    # Open release page
    open "$release_url"
}

# Run main function
main "$@"
