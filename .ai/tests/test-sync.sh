#!/usr/bin/env bash
# test-sync.sh — Test suite for .ai/sync.sh
#
# Runs sync.sh against a disposable sandbox to verify:
#   1. Blank-slate generation (all expected files created)
#   2. Idempotency (second run changes nothing)
#   3. Override layering (repo-specific files win over framework stubs)
#   4. Pruning (stale .github/ entries removed)
#   5. Stale .claude/ cleanup
#   6. copilot-instructions.md and .claude/rules/ai-framework.md content
#
# Usage:  bash .ai/tests/test-sync.sh           (from workspace root)
#         bash .ai/tests/test-sync.sh -v         (verbose — show sync.sh output)
#
# Exit code: 0 = all tests passed, 1 = failures

set -euo pipefail

# ── Configuration ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX=$(mktemp -d)
VERBOSE=false
[[ "${1:-}" == "-v" ]] && VERBOSE=true

PASS=0
FAIL=0
TEST_NAME=""

# ── Helpers ──────────────────────────────────
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); echo "  ✓ $TEST_NAME"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $TEST_NAME — $1"; }

assert_file_exists() {
    TEST_NAME="$2"
    if [[ -f "$SANDBOX/$1" ]]; then pass; else fail "file not found: $1"; fi
}
assert_file_missing() {
    TEST_NAME="$2"
    if [[ ! -f "$SANDBOX/$1" ]]; then pass; else fail "file should not exist: $1"; fi
}
assert_dir_exists() {
    TEST_NAME="$2"
    if [[ -d "$SANDBOX/$1" ]]; then pass; else fail "directory not found: $1"; fi
}
assert_dir_missing() {
    TEST_NAME="$2"
    if [[ ! -d "$SANDBOX/$1" ]]; then pass; else fail "directory should not exist: $1"; fi
}
assert_file_contains() {
    TEST_NAME="$3"
    if grep -qF "$2" "$SANDBOX/$1" 2>/dev/null; then pass; else fail "'$2' not found in $1"; fi
}
assert_file_not_contains() {
    TEST_NAME="$3"
    if ! grep -qF "$2" "$SANDBOX/$1" 2>/dev/null; then pass; else fail "'$2' should not be in $1"; fi
}
assert_files_identical() {
    TEST_NAME="$3"
    if cmp -s "$SANDBOX/$1" "$SANDBOX/$2" 2>/dev/null; then pass; else fail "$1 ≠ $2"; fi
}
assert_output_contains() {
    TEST_NAME="$2"
    if echo "$SYNC_OUTPUT" | grep -qF "$1"; then pass; else fail "output missing: '$1'"; fi
}
assert_output_not_contains() {
    TEST_NAME="$2"
    if ! echo "$SYNC_OUTPUT" | grep -qF "$1"; then pass; else fail "output should not contain: '$1'"; fi
}

# Run sync.sh inside sandbox, capture output
run_sync() {
    local output
    output=$(cd "$SANDBOX" && bash "$AI_DIR/sync.sh" 2>&1) || true
    SYNC_OUTPUT="$output"
    if $VERBOSE; then
        echo "    ┌─ sync.sh output ─────────"
        echo "$output" | sed 's/^/    │ /'
        echo "    └────────────────────────────"
    fi
}

# Count files matching a glob in the sandbox
count_files() {
    local pattern="$1"
    # Use find to avoid glob issues
    find "$SANDBOX/$pattern" -maxdepth 0 -type f 2>/dev/null | wc -l | tr -d ' '
}

# ── Scaffold a minimal .ai/ + .ai-repo/ fixture in the sandbox ──
scaffold_sandbox() {
    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX"

    # Framework agents
    mkdir -p "$SANDBOX/.ai/agents"
    echo "# Builder agent definition" > "$SANDBOX/.ai/agents/builder.md"
    echo "# Planner agent definition" > "$SANDBOX/.ai/agents/planner.md"
    echo "# Reviewer agent definition" > "$SANDBOX/.ai/agents/reviewer.md"

    # Framework skills
    mkdir -p "$SANDBOX/.ai/skills"
    echo "# Plan-epic skill" > "$SANDBOX/.ai/skills/plan-epic.md"
    echo "# TDD cycle skill" > "$SANDBOX/.ai/skills/tdd-cycle.md"
    echo "# Review-code skill" > "$SANDBOX/.ai/skills/review-code.md"

    # Repo-specific (empty by default — tests add as needed)
    mkdir -p "$SANDBOX/.ai-repo/agents"
    mkdir -p "$SANDBOX/.ai-repo/skills"
    mkdir -p "$SANDBOX/.ai-repo/rules"
    echo "# Placeholder" > "$SANDBOX/.ai-repo/agents/README.md"
    echo "# Placeholder" > "$SANDBOX/.ai-repo/rules/README.md"
}

# ══════════════════════════════════════════════
# Test Suite
# ══════════════════════════════════════════════
echo ""
echo "═══ sync.sh test suite ═══"
echo ""

# ── 1. Blank-slate: fresh sandbox with no .github/ or .claude/ ──
echo "▸ 1. Blank-slate generation"
scaffold_sandbox
run_sync

# Agents
assert_file_exists ".github/agents/builder.agent.md" "builder agent stub created"
assert_file_exists ".github/agents/planner.agent.md" "planner agent stub created"
assert_file_exists ".github/agents/reviewer.agent.md" "reviewer agent stub created"

# Agent stubs should reference .ai/agents/
assert_file_contains ".github/agents/builder.agent.md" ".ai/agents/builder.md" "builder stub references framework definition"
assert_file_contains ".github/agents/builder.agent.md" ".ai/rules.md" "builder stub references rules.md"

# Skills
assert_file_exists ".github/skills/plan-epic/SKILL.md" "plan-epic skill synced"
assert_file_exists ".github/skills/tdd-cycle/SKILL.md" "tdd-cycle skill synced"
assert_file_exists ".github/skills/review-code/SKILL.md" "review-code skill synced"

# Platform entry points
assert_file_exists ".github/copilot-instructions.md" "copilot-instructions.md generated"
assert_file_exists ".claude/rules/ai-framework.md" "claude ai-framework.md generated"

# Content checks
assert_file_contains ".github/copilot-instructions.md" "AUTO-GENERATED" "copilot-instructions has auto-gen marker"
assert_file_contains ".github/copilot-instructions.md" "builder" "copilot-instructions lists builder agent"
assert_file_contains ".github/copilot-instructions.md" "plan-epic" "copilot-instructions lists plan-epic skill"
assert_file_contains ".claude/rules/ai-framework.md" "AUTO-GENERATED" "claude rules has auto-gen marker"
assert_file_contains ".claude/rules/ai-framework.md" ".ai/rules.md" "claude rules references .ai/rules.md"

# Output
assert_output_contains "Synced" "output reports synced files"

echo ""

# ── 2. Idempotency: running again changes nothing ──
echo "▸ 2. Idempotency (second run)"

# Snapshot all generated files
find "$SANDBOX/.github" "$SANDBOX/.claude" -type f 2>/dev/null | sort > "$SANDBOX/_snapshot_files.txt"
for f in $(cat "$SANDBOX/_snapshot_files.txt"); do
    cp "$f" "${f}.snapshot"
done

run_sync

# Output should say "up to date"
assert_output_contains "up to date" "second run reports up to date"
assert_output_not_contains "Synced" "second run does not report synced files"

# All files should be byte-identical to snapshot
TEST_NAME="no files changed on second run"
files_changed=0
for f in $(cat "$SANDBOX/_snapshot_files.txt"); do
    if ! cmp -s "$f" "${f}.snapshot" 2>/dev/null; then
        files_changed=$((files_changed + 1))
        $VERBOSE && echo "    changed: $f"
    fi
done
if [[ $files_changed -eq 0 ]]; then pass; else fail "$files_changed file(s) changed"; fi

# No new files created (exclude .snapshot temp files)
TEST_NAME="no new files on second run"
find "$SANDBOX/.github" "$SANDBOX/.claude" -type f ! -name '*.snapshot' 2>/dev/null | sort > "$SANDBOX/_snapshot_files2.txt"
if diff -q "$SANDBOX/_snapshot_files.txt" "$SANDBOX/_snapshot_files2.txt" >/dev/null 2>&1; then
    pass
else
    fail "file list differs"
fi

echo ""

# ── 3. Override layering: repo-specific agent replaces framework stub ──
echo "▸ 3. Override layering"
scaffold_sandbox

# Add a repo-specific builder override
cat > "$SANDBOX/.ai-repo/agents/builder.agent.md" << 'EOF'
---
description: "Custom builder override"
model: claude-opus-4-6
---

This is the repo-specific builder agent.
EOF

# Add a repo-specific skill override (flat file)
echo "# Custom plan-epic override" > "$SANDBOX/.ai-repo/skills/plan-epic.md"

# Add a repo-only skill (not in framework)
echo "# Deploy skill" > "$SANDBOX/.ai-repo/skills/deploy-to-azure.md"

run_sync

# Builder should be the override, NOT the stub
assert_file_contains ".github/agents/builder.agent.md" "Custom builder override" "builder uses repo override content"
assert_file_not_contains ".github/agents/builder.agent.md" "Read the agent definition from" "builder does not have stub text"

# Planner/reviewer should still be stubs (no override)
assert_file_contains ".github/agents/planner.agent.md" "Read the agent definition from" "planner is still a stub"
assert_file_contains ".github/agents/reviewer.agent.md" "Read the agent definition from" "reviewer is still a stub"

# Plan-epic should be the override
assert_file_contains ".github/skills/plan-epic/SKILL.md" "Custom plan-epic override" "plan-epic uses repo override"

# Deploy-to-azure should exist (repo-only skill)
assert_file_exists ".github/skills/deploy-to-azure/SKILL.md" "repo-only skill deploy-to-azure synced"

# Framework skills still present
assert_file_exists ".github/skills/tdd-cycle/SKILL.md" "framework skill tdd-cycle still present"
assert_file_exists ".github/skills/review-code/SKILL.md" "framework skill review-code still present"

# copilot-instructions should list both framework + repo skills
assert_file_contains ".github/copilot-instructions.md" "deploy-to-azure" "copilot-instructions lists repo skill"

# Idempotency with overrides
run_sync
assert_output_contains "up to date" "second run with overrides is idempotent"

echo ""

# ── 4. Pruning: stale .github/ entries removed ──
echo "▸ 4. Pruning stale entries"
scaffold_sandbox
run_sync  # Generate initial state

# Manually inject stale files into .github/
mkdir -p "$SANDBOX/.github/agents"
echo "stale agent" > "$SANDBOX/.github/agents/ghost.agent.md"
mkdir -p "$SANDBOX/.github/skills/deprecated-skill"
echo "stale skill" > "$SANDBOX/.github/skills/deprecated-skill/SKILL.md"

run_sync

# Stale files should be removed
assert_file_missing ".github/agents/ghost.agent.md" "stale agent pruned"
assert_dir_missing ".github/skills/deprecated-skill" "stale skill directory pruned"

# Legitimate files should remain
assert_file_exists ".github/agents/builder.agent.md" "builder agent survives pruning"
assert_file_exists ".github/skills/plan-epic/SKILL.md" "plan-epic survives pruning"

assert_output_contains "removed" "output mentions removal"

echo ""

# ── 5. Stale .claude/ cleanup ──
echo "▸ 5. Stale .claude/ cleanup"
scaffold_sandbox

# Pre-create stale .claude/ directories
mkdir -p "$SANDBOX/.claude/agents"
echo "stale" > "$SANDBOX/.claude/agents/old-agent.md"
mkdir -p "$SANDBOX/.claude/skills"
echo "stale" > "$SANDBOX/.claude/skills/old-skill.md"
mkdir -p "$SANDBOX/.claude/rules"
echo "stale" > "$SANDBOX/.claude/rules/old-rule.md"

run_sync

# Stale dirs should be removed
assert_dir_missing ".claude/agents" ".claude/agents/ removed"
assert_dir_missing ".claude/skills" ".claude/skills/ removed"

# Stale rules should be removed (only ai-framework.md kept)
assert_file_missing ".claude/rules/old-rule.md" "stale .claude/rules/old-rule.md removed"
assert_file_exists ".claude/rules/ai-framework.md" "ai-framework.md preserved"

echo ""

# ── 6. Rules content appended to platform files ──
echo "▸ 6. Repo-specific rules appended"
scaffold_sandbox

# Add a meaningful rule file
cat > "$SANDBOX/.ai-repo/rules/coding-standards.md" << 'EOF'
Always use nullable reference types.
Prefer records over classes for DTOs.
EOF

run_sync

assert_file_contains ".github/copilot-instructions.md" "nullable reference types" "copilot-instructions includes repo rule content"
assert_file_contains ".github/copilot-instructions.md" "Project-Specific Rules" "copilot-instructions has rules section header"
assert_file_contains ".claude/rules/ai-framework.md" "nullable reference types" "claude rules includes repo rule content"

# README.md in rules dir should be skipped
echo ""

# ── 7. Directory-based repo skills ──
echo "▸ 7. Directory-based repo skills"
scaffold_sandbox

mkdir -p "$SANDBOX/.ai-repo/skills/custom-deploy"
echo "# Custom deploy SKILL" > "$SANDBOX/.ai-repo/skills/custom-deploy/SKILL.md"

run_sync

assert_file_exists ".github/skills/custom-deploy/SKILL.md" "directory-based repo skill synced"
assert_file_contains ".github/skills/custom-deploy/SKILL.md" "Custom deploy SKILL" "directory-based skill has correct content"

echo ""

# ── 8. Removing a framework agent/skill source and re-syncing ──
echo "▸ 8. Source removal triggers pruning"
scaffold_sandbox
run_sync  # initial sync with 3 agents, 3 skills

# Remove one framework agent and one framework skill
rm "$SANDBOX/.ai/agents/reviewer.md"
rm "$SANDBOX/.ai/skills/review-code.md"

run_sync

assert_file_missing ".github/agents/reviewer.agent.md" "removed framework agent pruned from .github/"
assert_dir_missing ".github/skills/review-code" "removed framework skill pruned from .github/"

# Remaining items still intact
assert_file_exists ".github/agents/builder.agent.md" "builder survives after reviewer removed"
assert_file_exists ".github/skills/plan-epic/SKILL.md" "plan-epic survives after review-code removed"

echo ""

# ── 9. Mixed: override + prune in one run ──
echo "▸ 9. Mixed override + prune"
scaffold_sandbox
run_sync

# Add an override AND a stale file simultaneously
cat > "$SANDBOX/.ai-repo/agents/planner.agent.md" << 'EOF'
---
description: "Custom planner"
---
Custom planner body.
EOF
echo "stale" > "$SANDBOX/.github/agents/zombie.agent.md"

run_sync

assert_file_contains ".github/agents/planner.agent.md" "Custom planner body" "override applied in mixed scenario"
assert_file_missing ".github/agents/zombie.agent.md" "stale file pruned in mixed scenario"

echo ""

# ── 10. Empty repo with no .ai-repo/ at all ──
echo "▸ 10. No .ai-repo/ directory"
scaffold_sandbox
rm -rf "$SANDBOX/.ai-repo"

run_sync

assert_file_exists ".github/agents/builder.agent.md" "agents created without .ai-repo/"
assert_file_exists ".github/skills/plan-epic/SKILL.md" "skills created without .ai-repo/"
assert_file_exists ".github/copilot-instructions.md" "copilot-instructions created without .ai-repo/"
assert_file_not_contains ".github/copilot-instructions.md" "Project-specific skills" "no project-specific skills line when .ai-repo/ missing"

echo ""

# ══════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════
TOTAL=$((PASS + FAIL))
echo "═══════════════════════════"
if [[ $FAIL -eq 0 ]]; then
    echo "All $TOTAL tests passed ✓"
else
    echo "$FAIL of $TOTAL tests FAILED ✗"
fi
echo "═══════════════════════════"
echo ""

exit "$FAIL"
