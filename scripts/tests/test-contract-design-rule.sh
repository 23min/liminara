#!/bin/sh
# Smoke test for the Liminara contract-design reviewer rule
# (M-PACK-A-01 AC8).
#
# Validates structure (which assertions appear), not prose quality.
# Quality is a wrap-time reviewer pass.
#
# Asserts:
#   - File exists at .ai-repo/rules/contract-design.md.
#   - Codifies the four reviewer-discipline rules from AC7's overlay:
#       1. anchored admin-pack citations + D2-A E-22-pending allowance
#       2. contract-matrix rows verified at wrap
#       3. Radar-primary / admin-pack-secondary reference structure
#       4. reference-implementation citations follow two acceptable shapes
#   - References the contract-matrix index by path.
#   - References the parent sub-epic spec by path.
#   - References the AC7 authoring overlay (.ai-repo/skills/design-contract.md)
#     so the rule and the skill cross-reference rather than duplicate.
#   - Does NOT duplicate the upstream tech-neutral 7-step workflow
#     (rule scope is reviewer enforcement; workflow lives in
#     .ai/skills/design-contract.md).
#   - States that this rule is read by the reviewer agent at PR review.
#
# Run from any cwd:  sh scripts/tests/test-contract-design-rule.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULE="$REPO_ROOT/.ai-repo/rules/contract-design.md"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# 1. File exists.
[ -f "$RULE" ] || fail "$RULE missing"

# 2. Names the reviewer agent as the consumer.
grep -qiE 'reviewer agent|reviewer rule|enforced by.*reviewer|reviewer.*enforces' "$RULE" \
    || fail "rule does not name the reviewer agent as the consumer"

# 3. Rule 1 — anchored admin-pack citations.
grep -qiE 'anchored.*citation|admin-pack/v2/docs/architecture|file.{1,15}section anchor' "$RULE" \
    || fail "rule does not codify the anchored admin-pack citation discipline (rule 1)"

# 3b. Rule 1 — D2-A E-22-pending allowance (anchor target may not yet exist).
grep -qiE 'may not.{0,15}exist|target.{0,30}E-22|validate.{0,15}E-22|pending.{0,30}E-22' "$RULE" \
    || fail "rule does not codify the D2-A E-22-pending allowance (anchor may not yet exist)"

# 4. Rule 2 — contract-matrix rows verified at wrap.
grep -qiE 'contract.matrix.*row|matrix.row.*wrap|wrap.*verifies.*row|verify.*matrix' "$RULE" \
    || fail "rule does not codify the contract-matrix-row-at-wrap discipline (rule 2)"

# 5. Rule 3 — Radar-primary / admin-pack-secondary structure.
grep -qiE 'Radar.*primary|primary.{0,20}Radar' "$RULE" \
    || fail "rule does not state the Radar-primary reference (rule 3)"
grep -qiE 'admin-pack.*secondary|secondary.{0,30}admin-pack' "$RULE" \
    || fail "rule does not state the admin-pack-secondary reference (rule 3)"
grep -qiE 'one-pack.*abstraction|single-pack.*abstraction|one-consumer.*abstraction' "$RULE" \
    || fail "rule does not name the one-pack-abstraction failure mode (rule 3)"

# 6. Rule 4 — reference-implementation citation shapes.
grep -qiE 'TBD.{0,15}(not|reject)|no TBD|TBD is rejected' "$RULE" \
    || fail "rule does not reject TBD reference-implementation citations (rule 4)"
grep -qE 'file:line|<file>:<line>' "$RULE" \
    || fail "rule does not document the file:line citation shape (rule 4)"
grep -qE 'M-PACK-[A-Z]-' "$RULE" \
    || fail "rule does not document the M-PACK-* milestone citation shape (rule 4)"

# 7. References the contract-matrix index by path.
grep -q 'docs/architecture/indexes/contract-matrix\.md' "$RULE" \
    || fail "rule does not reference docs/architecture/indexes/contract-matrix.md"

# 8. References the parent sub-epic spec by path.
grep -q 'E-21a-contract-design\.md' "$RULE" \
    || fail "rule does not reference the parent sub-epic spec"

# 9. References the AC7 authoring overlay.
grep -q '\.ai-repo/skills/design-contract\.md' "$RULE" \
    || fail "rule does not cross-reference .ai-repo/skills/design-contract.md (AC7 authoring overlay)"

# 10. Does NOT duplicate the upstream 7-step workflow.
#     Heuristic: the upstream skill names the seven steps using the
#     phrase "Draft the ADR" / "Write the authoritative schema" /
#     "Write valid + invalid fixtures" / "Write a worked example" /
#     "Name the reference implementation" / "Verify locally" / "Open
#     the PR with the whole bundle". A rule file that copies any of
#     those step headings is duplicating, not delegating.
if grep -qiE '^#+.*(draft the ADR|write the authoritative schema|write valid \+ invalid fixtures|write a worked example|verify locally|open the PR with the whole bundle)' "$RULE"; then
    grep -niE '^#+.*(draft the ADR|write the authoritative schema|write valid \+ invalid fixtures|write a worked example|verify locally|open the PR with the whole bundle)' "$RULE" >&2
    fail "rule duplicates upstream 7-step workflow headings; rule scope is reviewer enforcement, not authoring workflow"
fi

# 11. References the upstream skill so the rule scope is bounded.
grep -q '\.ai/skills/design-contract\.md' "$RULE" \
    || fail "rule does not reference upstream .ai/skills/design-contract.md (defines what reviewer enforces vs. what skill teaches)"

echo "PASS: .ai-repo/rules/contract-design.md codifies the AC8 reviewer assertions"
