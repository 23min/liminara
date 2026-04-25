#!/bin/sh
# Smoke test for the docs/schemas/ fixture-library layout placeholder
# (M-PACK-A-01 AC6).
#
# Validates:
#   - docs/schemas/ directory exists at repo root.
#   - docs/schemas/README.md exists and documents the layout convention:
#       docs/schemas/<topic>/schema.cue
#       docs/schemas/<topic>/fixtures/v<N>/<name>.yaml
#   - The README references the cue-vet entry point and the schema-
#     evolution loop, so contributors landing schemas know where the
#     validation runs.
#
# Run from any cwd:  sh scripts/tests/test-schemas-layout.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMAS_DIR="$REPO_ROOT/docs/schemas"
README="$SCHEMAS_DIR/README.md"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# 1. Directory exists.
[ -d "$SCHEMAS_DIR" ] || fail "$SCHEMAS_DIR directory missing"

# 2. README exists.
[ -f "$README" ] || fail "$README missing"

# 3. README documents the schema-pair layout.
grep -q '<topic>/schema\.cue' "$README" \
    || fail "README does not document the <topic>/schema.cue layout"

# 4. README documents the versioned-fixture layout WITH the valid/invalid split.
grep -qE '<topic>/fixtures/v<N>/\{valid,invalid\}' "$README" \
    || fail "README does not document the <topic>/fixtures/v<N>/{valid,invalid}/ split"

# 4b. README explains the valid/invalid distinction (not just the path shape).
grep -qiE 'valid.*must.*pass|valid.*must.*accept|cue vet must accept' "$README" \
    || fail "README does not explain that valid/ fixtures must pass cue vet"
grep -qiE 'invalid.*must.*fail|invalid.*must.*reject|cue vet must reject' "$README" \
    || fail "README does not explain that invalid/ fixtures must fail cue vet"

# 5. README references the cue-vet entry point so contributors know how
#    to run validation locally.
grep -q 'scripts/cue-vet' "$README" \
    || fail "README does not reference scripts/cue-vet"

# 6. README explicitly mentions the schema-evolution loop or the no-arg
#    walk so contributors land fixtures in the right place.
grep -qiE 'schema[-]evolution|no[- ]arg|fixtures? library' "$README" \
    || fail "README does not explain the schema-evolution loop / fixture-library walk"

echo "PASS: docs/schemas/ + README.md document the AC6 layout convention"
