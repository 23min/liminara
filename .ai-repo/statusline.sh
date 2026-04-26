#!/usr/bin/env bash
# statusline.sh — Liminara-specific Claude Code status line (repo override).
#
# Diverges from the framework's .ai/statusline/statusline.sh in three ways:
#   1. Shows the current git branch (or worktree basename) — the framework
#      statusline only shows the cwd basename.
#   2. Active epic is the first UNCHECKED top-level `E-NN` line in
#      work/roadmap.md — the framework statusline grabs the first `E-NN`
#      match anywhere, which is always E-01 in a chronological roadmap.
#   3. Active milestone uses this repo's `milestoneIdPattern`
#      (`M-<TRACK>-<NN>`, e.g. `M-CONTRACT-01`) instead of the framework
#      default (`m-E<NN>-<NN>-<slug>`).
#
# Wire-up: .claude/settings.json's `statusLine.command` points at
#   "bash .ai-repo/statusline.sh". Because that path is not
#   ".claude/statusline.sh", the framework's sync.sh leaves the setting alone
#   (see .ai/sync.sh statusline-wire-up clause).
#
# Output: <threshold-icon>  <model>  <branch-or-dir>  [<epic> <milestone>]  <tokens>
#
# Requires: jq, bash, git, coreutils.

set -u

input=$(cat)

cwd=$(jq -r '.cwd // .workspace.current_dir // empty' <<<"$input" 2>/dev/null)
model_name=$(jq -r '.model.display_name // .model.id // "Claude"' <<<"$input" 2>/dev/null)
transcript_path=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
cwd=${cwd:-$PWD}

# ── Git branch (or worktree basename if not in a git repo) ──
branch=""
if command -v git >/dev/null 2>&1; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  # Detached HEAD → show short SHA
  if [ "$branch" = "HEAD" ]; then
    sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)
    [ -n "$sha" ] && branch="detached@$sha"
  fi
fi
dir_fallback=$(basename "$cwd")
label=${branch:-$dir_fallback}

# ── Active epic: first unchecked top-level E-NN line in work/roadmap.md ──
# Roadmap convention: top-level epics are "- [ ] E-NN ..." (no leading indent);
# sub-epics and milestones are nested with "  - [ ] ...".
roadmap_path="work/roadmap.md"
if [ -f "$cwd/.ai-repo/config/artifact-layout.json" ] && command -v jq >/dev/null 2>&1; then
  cfg=$(jq -r '.roadmapPath // empty' "$cwd/.ai-repo/config/artifact-layout.json" 2>/dev/null)
  [ -n "$cfg" ] && roadmap_path="$cfg"
fi

epic=""
if [ -f "$cwd/$roadmap_path" ]; then
  # Match "- [ ] E-NN" at line start (no leading space) — top-level unchecked epic.
  epic=$(grep -m1 -oE '^- \[ \] E-[0-9]+[a-z]*' "$cwd/$roadmap_path" 2>/dev/null \
    | grep -oE 'E-[0-9]+[a-z]*' || true)
fi

# ── Active milestone: M-<TRACK>-<NN> in CLAUDE.md Current Work section ──
#
# Only the top-level milestone-header lines count — those that start with
# "**M-...". Sub-bullets (Spec:, Tracking:, Delivered:) are ignored because
# they still reference M-ids for already-completed milestones. If every
# header line is marked complete, show no milestone (we're between
# milestones; the active epic alone represents state).
milestone=""
if [ -f "$cwd/CLAUDE.md" ]; then
  current_work=$(awk '/^## Current Work/{found=1} found' "$cwd/CLAUDE.md" 2>/dev/null)
  milestone=$(printf '%s\n' "$current_work" \
    | grep -E '^\*\*M-[A-Z0-9]+-[0-9]+' \
    | grep -v -iE '\*\*complete\*\*|— complete|: complete' \
    | grep -m1 -oE 'M-[A-Z0-9]+-[0-9]+[a-z]*' || true)
fi

tag=""
if [ -n "$epic" ] && [ -n "$milestone" ]; then
  tag="$epic $milestone"
elif [ -n "$epic" ]; then
  tag="$epic"
elif [ -n "$milestone" ]; then
  tag="$milestone"
fi

# ── Context tokens (last usage record in the transcript) ──
tokens=0
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  usage_line=$(tac "$transcript_path" 2>/dev/null | grep -m1 '"usage"' || true)
  if [ -n "$usage_line" ]; then
    tokens=$(jq -r '
      (.message.usage // .usage // {}) |
      ((.input_tokens // 0)
        + (.cache_read_input_tokens // 0)
        + (.cache_creation_input_tokens // 0))
    ' <<<"$usage_line" 2>/dev/null || echo 0)
  fi
fi
tokens=${tokens:-0}

# ── Threshold icon / colour / warning ──
if   [ "$tokens" -ge 500000 ]; then icon="🔴"; color=31; warn=" · START NEW SESSION"
elif [ "$tokens" -ge 250000 ]; then icon="🟡"; color=33; warn=" · consider new session"
else                                icon="🟢"; color=32; warn=""
fi
tokens_k=$((tokens / 1000))

parts=("$model_name" "$label")
[ -n "$tag" ] && parts+=("$tag")
parts+=("$(printf '\033[%sm%dk tokens\033[0m%s' "$color" "$tokens_k" "$warn")")

body=""
for p in "${parts[@]}"; do
  if [ -z "$body" ]; then body="$p"; else body="$body · $p"; fi
done
printf '%s %s' "$icon" "$body"
