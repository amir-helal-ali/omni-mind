#!/usr/bin/env bash
# scripts/upload-to-github.sh — Upload Omni-Mind to your GitHub repository.
#
# This script:
#   1. Asks for your GitHub username and repository name
#   2. Configures the git remote
#   3. Pushes the project to GitHub
#
# Prerequisites:
#   - A GitHub account
#   - A Personal Access Token (PAT) with 'repo' scope
#     Create one at: https://github.com/settings/tokens
#
# Usage:
#   bash scripts/upload-to-github.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_DIR}"

echo "═══════════════════════════════════════════════════════════════════════"
echo "  Omni-Mind — GitHub Upload Script"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# ─── Check git is initialized ───────────────────────────────────────
if [[ ! -d ".git" ]]; then
    echo "Initializing git repository..."
    git init
    git config user.email "omni-mind@users.noreply.github.com"
    git config user.name "Omni-Mind Project"
    git add .
    git commit -m "Initial commit: Project Omni-Mind v0.2.0"
    echo "✓ Initial commit created"
    echo ""
fi

# ─── Get GitHub info ────────────────────────────────────────────────
echo "Please provide your GitHub information:"
echo ""
read -p "  GitHub username (e.g., johndoe): " GH_USERNAME
read -p "  Repository name (default: omni-mind): " GH_REPO
GH_REPO="${GH_REPO:-omni-mind}"
read -p "  Branch name (default: main): " GH_BRANCH
GH_BRANCH="${GH_BRANCH:-main}"

if [[ -z "${GH_USERNAME}" ]]; then
    echo "✗ GitHub username is required"
    exit 1
fi

REMOTE_URL="https://github.com/${GH_USERNAME}/${GH_REPO}.git"
echo ""
echo "Repository URL: ${REMOTE_URL}"
echo ""

# ─── Rename branch if needed ────────────────────────────────────────
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "master")
if [[ "${CURRENT_BRANCH}" != "${GH_BRANCH}" ]]; then
    echo "Renaming branch '${CURRENT_BRANCH}' → '${GH_BRANCH}'..."
    git branch -M "${GH_BRANCH}"
fi

# ─── Configure remote ───────────────────────────────────────────────
if git remote get-url origin >/dev/null 2>&1; then
    echo "Updating existing 'origin' remote..."
    git remote set-url origin "${REMOTE_URL}"
else
    echo "Adding 'origin' remote..."
    git remote add origin "${REMOTE_URL}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  Ready to push!"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "The next step will push ${GH_BRANCH} branch to:"
echo "  ${REMOTE_URL}"
echo ""
echo "You will be prompted for:"
echo "  - Username: your GitHub username"
echo "  - Password: your GitHub Personal Access Token (PAT)"
echo "    (Create at: https://github.com/settings/tokens)"
echo ""
read -p "Press Enter to continue, or Ctrl-C to cancel..."

# ─── Push to GitHub ─────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push -u origin "${GH_BRANCH}"

if [[ $? -eq 0 ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  ✓ SUCCESS! Project uploaded to GitHub"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Your repository: https://github.com/${GH_USERNAME}/${GH_REPO}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify the repository on GitHub"
    echo "  2. Share the URL with collaborators"
    echo "  3. Clone on another machine:"
    echo "     git clone https://github.com/${GH_USERNAME}/${GH_REPO}.git"
    echo "  4. Build and run with Docker:"
    echo "     cd ${GH_REPO}"
    echo "     docker build -t omni-mind ."
    echo "     docker run --rm -it omni-mind verify"
    echo ""
else
    echo ""
    echo "✗ Push failed. Common causes:"
    echo "  - Incorrect Personal Access Token (PAT)"
    echo "  - Repository doesn't exist on GitHub (create it first at github.com/new)"
    echo "  - Network issues"
    echo ""
    echo "Create a PAT at: https://github.com/settings/tokens"
    echo "Make sure it has 'repo' scope."
    exit 1
fi
