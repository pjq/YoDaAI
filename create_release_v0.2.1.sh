#!/bin/bash

# Manual release script for v0.2.1
# Run this when network connectivity is restored

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Creating release v0.2.1...${NC}\n"

# Step 1: Push commits and tag
echo "Step 1: Pushing commits and tag to GitHub..."
git push origin main
git tag -a "v0.2.1" -m "Release 0.2.1" 2>/dev/null || echo "Tag already exists"
git push origin v0.2.1

echo -e "${GREEN}✓ Commits and tag pushed${NC}\n"

# Step 2: Create GitHub release using gh CLI or API
if command -v gh &> /dev/null; then
    echo "Step 2: Creating GitHub release using gh CLI..."
    gh release create v0.2.1 \
        --title "YoDaAI 0.2.1" \
        --notes-file releases/RELEASE_NOTES_v0.2.1.md \
        releases/YoDaAI-0.2.1.zip \
        releases/YoDaAI-0.2.1.dmg

    echo -e "${GREEN}✓ Release created!${NC}"
    echo -e "${GREEN}View at: https://github.com/pjq/YoDaAI/releases/tag/v0.2.1${NC}"
else
    echo "Step 2: Creating GitHub release using API..."

    if [ -z "$GITHUB_TOKEN" ]; then
        echo "ERROR: GITHUB_TOKEN not set. Please set it first:"
        echo "export GITHUB_TOKEN='your_token_here'"
        exit 1
    fi

    # Read release notes
    RELEASE_BODY=$(cat releases/RELEASE_NOTES_v0.2.1.md)

    # Create release
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/pjq/YoDaAI/releases \
        -d @- <<EOF
{
  "tag_name": "v0.2.1",
  "name": "YoDaAI 0.2.1",
  "body": $(echo "$RELEASE_BODY" | jq -Rs .),
  "draft": false,
  "prerelease": false
}
EOF
)

    RELEASE_ID=$(echo "$RESPONSE" | jq -r .id)

    if [ "$RELEASE_ID" == "null" ] || [ -z "$RELEASE_ID" ]; then
        echo "ERROR: Failed to create release"
        echo "$RESPONSE" | jq .
        exit 1
    fi

    echo -e "${GREEN}✓ Release created (ID: ${RELEASE_ID})${NC}"

    # Upload ZIP
    echo "Uploading ZIP artifact..."
    curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/zip" \
        --data-binary @releases/YoDaAI-0.2.1.zip \
        "https://uploads.github.com/repos/pjq/YoDaAI/releases/${RELEASE_ID}/assets?name=YoDaAI-0.2.1.zip" > /dev/null

    echo -e "${GREEN}✓ ZIP uploaded${NC}"

    # Upload DMG
    echo "Uploading DMG artifact..."
    curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/x-apple-diskimage" \
        --data-binary @releases/YoDaAI-0.2.1.dmg \
        "https://uploads.github.com/repos/pjq/YoDaAI/releases/${RELEASE_ID}/assets?name=YoDaAI-0.2.1.dmg" > /dev/null

    echo -e "${GREEN}✓ DMG uploaded${NC}"
    echo -e "${GREEN}View at: https://github.com/pjq/YoDaAI/releases/tag/v0.2.1${NC}"
fi

echo -e "\n${GREEN}Release v0.2.1 complete!${NC}"
