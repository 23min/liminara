#!/bin/sh
# Smoke test for the Liminara-local design-contract skill overlay
# (M-PACK-A-01 AC7).
#
# Validates structure (which references appear), not prose quality.
# Quality is a wrap-time reviewer pass, not a grep-able invariant.
#
# Asserts:
#   - File exists at .ai-repo/skills/design-contract.md (the source-of-
#     truth path; never .claude/skills/.../SKILL.md, which is generated).
#   - References the upstream framework skill + CUE recipe by path so
#     the overlay genuinely composes with upstream rather than
#     duplicating the workflow.
#   - References ai-workflow#37 / PR #72 as the trigger that brought
#     the upstream skill into existence.
#   - Documents Liminara's path overrides (docs/schemas/) and the
#     valid/invalid split per D-2026-04-25-033.
#   - References scripts/cue-vet and scripts/install-cue-hook so
#     contributors know which local tooling to invoke.
#   - References the contract-matrix index path and the contract-matrix
#     discipline section in .ai-repo/rules/liminara.md.
#   - References the parent sub-epic spec by path so the reviewer
#     has a citation chase path.
#   - References the AC8 reviewer-rule path .ai-repo/rules/contract-design.md.
#   - Documents the admin-pack anchored-citation discipline AND notes
#     the D2-A approach (anchor target may not yet exist; record
#     intended anchor and validate at E-22).
#   - States the Radar-primary / admin-pack-secondary reference rule.
#   - States the sync caveat: this file is the source; never hand-edit
#     the generated folder-form output.
#
# Run from any cwd:  sh scripts/tests/test-design-contract-skill.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$REPO_ROOT/.ai-repo/skills/design-contract.md"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# 1. File exists at .ai-repo/skills/design-contract.md.
[ -f "$SKILL" ] || fail "$SKILL missing — overlay must live at the .ai-repo/ source path, never .claude/skills/.../SKILL.md"

# 2. References the upstream framework skill by path.
grep -q '\.ai/skills/design-contract\.md' "$SKILL" \
    || fail "overlay does not reference upstream .ai/skills/design-contract.md"

# 3. References the upstream CUE recipe by path.
grep -q 'design-contract-cue\.md' "$SKILL" \
    || fail "overlay does not reference the upstream CUE recipe"

# 4. Cites ai-workflow#37 (or PR #72) as the upstream trigger.
grep -qE 'ai-workflow#37|ai-workflow.*PR.?#?72|PR.?#?72' "$SKILL" \
    || fail "overlay does not cite the upstream issue/PR (ai-workflow#37 or PR #72)"

# 5. Documents the Liminara path override (docs/schemas/).
grep -q 'docs/schemas/' "$SKILL" \
    || fail "overlay does not document the Liminara docs/schemas/ path override"

# 6. Documents the valid/invalid split (per D-2026-04-25-033).
grep -qE 'valid/.*invalid/|valid,invalid|valid and invalid' "$SKILL" \
    || fail "overlay does not document the valid/invalid fixture split"
grep -q 'D-2026-04-25-033' "$SKILL" \
    || fail "overlay does not cite D-2026-04-25-033 for the layout convergence"

# 7. References the local tooling — cue-vet + hook installer.
grep -q 'scripts/cue-vet' "$SKILL" \
    || fail "overlay does not reference scripts/cue-vet"
grep -q 'scripts/install-cue-hook' "$SKILL" \
    || fail "overlay does not reference scripts/install-cue-hook"

# 8. References the contract-matrix index by path.
grep -q 'docs/architecture/indexes/contract-matrix\.md' "$SKILL" \
    || fail "overlay does not reference docs/architecture/indexes/contract-matrix.md"

# 9. References the .ai-repo/rules/liminara.md contract-matrix discipline.
grep -qE '\.ai-repo/rules/liminara\.md' "$SKILL" \
    || fail "overlay does not reference .ai-repo/rules/liminara.md"

# 10. References the parent sub-epic spec.
grep -q 'E-21a-contract-design\.md' "$SKILL" \
    || fail "overlay does not reference the parent sub-epic spec"

# 11. References the AC8 reviewer rule path.
grep -q '\.ai-repo/rules/contract-design\.md' "$SKILL" \
    || fail "overlay does not reference the AC8 reviewer rule .ai-repo/rules/contract-design.md"

# 12. Documents the admin-pack anchored-citation discipline.
grep -qiE 'admin-pack.*anchor|anchored.*citation|file.*section anchor|admin-pack/v2/docs/architecture' "$SKILL" \
    || fail "overlay does not document the admin-pack anchored-citation discipline"

# 13. Notes the D2-A "anchor target may not yet exist" approach.
grep -qiE 'may not.{0,15}exist|target.{0,30}E-22|anchor.{0,30}E-22|validate.{0,15}E-22' "$SKILL" \
    || fail "overlay does not note the D2-A anchor-target-may-not-yet-exist approach (validate at E-22)"

# 14. States the Radar-primary / admin-pack-secondary reference rule.
grep -qiE 'Radar.*primary|primary.{0,20}Radar' "$SKILL" \
    || fail "overlay does not state Radar-as-primary reference rule"
grep -qiE 'admin-pack.*secondary|secondary.{0,30}admin-pack' "$SKILL" \
    || fail "overlay does not state admin-pack-as-secondary reference rule"

# 15. Documents acceptable reference-implementation citation shapes for Liminara.
grep -qE 'file:line|<file>:<line>' "$SKILL" \
    || fail "overlay does not document file:line citation shape for existing reference impls"
grep -qE 'M-PACK-[A-Z]-' "$SKILL" \
    || fail "overlay does not document M-PACK-* milestone citation shape for scheduled reference impls"

# 16. States the sync caveat: source-of-truth lives here, generated
#     folder-form output must not be hand-edited.
grep -qiE 'sync\.sh|generated.*output|never.*hand-edit|never hand-write' "$SKILL" \
    || fail "overlay does not state the sync.sh / no-hand-edit caveat"

echo "PASS: .ai-repo/skills/design-contract.md overlay carries the AC7 Liminara bindings"
