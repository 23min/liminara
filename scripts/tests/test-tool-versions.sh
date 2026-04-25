#!/bin/sh
# Smoke test for .tool-versions contract (M-PACK-A-01 AC1).
# Validates: file exists at repo root, contains a parseable `cue` line,
# canonical extractor returns a non-empty semver-shaped value.
#
# Run from any cwd:  sh scripts/tests/test-tool-versions.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOL_VERSIONS="$REPO_ROOT/.tool-versions"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# 1. File exists at repo root.
[ -f "$TOOL_VERSIONS" ] || fail ".tool-versions not found at $TOOL_VERSIONS"

# 2. Contains a `cue <version>` line.
grep -q '^cue ' "$TOOL_VERSIONS" || fail "no 'cue <version>' line in $TOOL_VERSIONS"

# 3. Canonical extractor (the same one-liner the Dockerfile, scripts/cue-vet,
#    and the pre-commit hook will use) returns a non-empty value.
version="$(grep '^cue ' "$TOOL_VERSIONS" | awk '{print $2}')"
[ -n "$version" ] || fail "cue line present but version field is empty"

# 4. Version is shaped like X.Y.Z with no v prefix (asdf/mise convention).
echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "cue version '$version' does not match semver shape (expected X.Y.Z)"

echo "PASS: .tool-versions pins cue $version"
