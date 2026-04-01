#!/usr/bin/env bash
# AI Framework v2 — Update
# Pulls the latest framework version and re-syncs platform files.
# Run from workspace root: bash .ai/update.sh
#
# Usage:
#   bash .ai/update.sh              # update from default branch (v2)
#   bash .ai/update.sh main         # update from a specific branch
#   bash .ai/update.sh v2.1.0       # update to a specific tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX=".ai"
REMOTE="ai-framework"
BRANCH="${1:-v2}"

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' BLUE='' NC=''
fi

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
err() { echo -e "${RED}✗${NC} $1" >&2; }

cd "$WORKSPACE_ROOT"

echo ""
echo "AI Framework v2 — Update"
echo "========================="
echo ""

# --- Verify we're in a git repo ---
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    err "Not a git repository. Run this from your project root."
    exit 1
fi

# --- Check for uncommitted changes ---
if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "You have uncommitted changes. Commit or stash them first."
    warn "Subtree pull may fail or create confusing merge commits."
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# --- Check remote exists ---
if ! git remote get-url "$REMOTE" &>/dev/null; then
    err "Remote '$REMOTE' not found."
    err "Add it first: git remote add $REMOTE <your-framework-repo-url>"
    exit 1
fi

# --- Pull latest ---
info "Pulling $BRANCH from $REMOTE into $PREFIX/ ..."
echo ""

if git subtree pull --prefix="$PREFIX" "$REMOTE" "$BRANCH" --squash -m "chore: update ai-framework to latest $BRANCH"; then
    echo ""
    log "Framework updated."
else
    echo ""
    err "Subtree pull failed. Check the error above."
    err "Common fixes:"
    err "  - Commit or stash local changes"
    err "  - Ensure the remote and branch exist: git fetch $REMOTE"
    exit 1
fi

# --- Re-sync platform files ---
if [[ -f "$PREFIX/sync.sh" ]]; then
    info "Re-syncing platform files ..."
    bash "$PREFIX/sync.sh"
    log "Platform files synced."
else
    warn "sync.sh not found — skipping platform sync."
fi

echo ""
log "Done. Review changes with: git log --oneline -5"
echo ""
