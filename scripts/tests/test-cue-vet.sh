#!/bin/sh
# Test scripts/cue-vet entry point (M-PACK-A-01 AC3 + AC5).
#
# Validates:
#   - Script exists and is executable.
#   - Single-file mode passes the .cue file through to `cue vet`, exits 0
#     on success and non-zero on failure.
#   - No-arg mode walks docs/schemas/<topic>/fixtures/v<N>/{valid,invalid}/
#     with mirrored exit-code expectations:
#       - every fixture under valid/   must pass `cue vet` (exit 0);
#       - every fixture under invalid/ must fail `cue vet` (exit non-zero).
#     A valid fixture that fails or an invalid fixture that passes is a
#     regression with a distinct failure-format string.
#   - No-arg mode exits 0 on a missing or empty docs/schemas/ tree (the
#     fixture library is empty at M-PACK-A-01 wrap; M-PACK-A-02a lands the
#     first fixtures).
#   - Standard failure (valid rejected) output matches the spec format:
#       <fixture path> fails against <topic>.cue at <schema path>: <CUE error>
#   - Inverted failure (invalid accepted) output matches the regression
#     format:
#       <fixture path> in invalid/ unexpectedly passed against <topic>.cue at <schema path>
#   - cwd-independence: the script resolves docs/schemas/ relative to its
#     own location, not the caller's $PWD.
#   - Too-many-args prints a usage message and exits 2.
#
# Uses a mock `cue` injected on PATH; does not require real cue to be
# installed. Real-cue integration is covered transitively by AC2's runtime
# install test (which already proves cue 0.16.1 works) and by the eventual
# devcontainer rebuild.
#
# Layout convergence with upstream framework convention is recorded in
# work/decisions.md D-2026-04-25-033.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CUE_VET="$REPO_ROOT/scripts/cue-vet"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Mock cue. Treats `vet <args>` as success unless the BASENAME of any
# argument starts with "bad-" (test-affordance, not a real cue heuristic).
# Match-on-basename keeps the heuristic isolated from sandbox directory
# names that may incidentally contain "bad-".
cat > "$SANDBOX/cue" << 'EOF'
#!/bin/sh
if [ "${1:-}" = "vet" ]; then
    shift
    for a in "$@"; do
        base="$(basename "$a")"
        case "$base" in
            bad-*) echo "mock-cue: $a does not satisfy schema" >&2; exit 1 ;;
        esac
    done
    exit 0
fi
exit 0
EOF
chmod +x "$SANDBOX/cue"
PATH="$SANDBOX:$PATH"
export PATH

# Test 1: script exists and is executable.
[ -x "$CUE_VET" ] || fail "scripts/cue-vet not executable"

# Test 2: single-file mode, success.
GOOD_CUE="$SANDBOX/sample.cue"
echo 'pkg: "test"' > "$GOOD_CUE"
"$CUE_VET" "$GOOD_CUE" >/dev/null 2>&1 || fail "single-file (success) returned non-zero"

# Test 3: single-file mode, failure (path triggers mock fail).
BAD_CUE="$SANDBOX/bad-sample.cue"
echo 'pkg: "test"' > "$BAD_CUE"
exit_code=0
"$CUE_VET" "$BAD_CUE" >/dev/null 2>&1 || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "single-file (failure) returned 0; expected non-zero"

# Build a sandbox repo skeleton for the no-arg mode tests. The script
# resolves docs/schemas/ relative to its own location, so each scenario
# gets a fresh repo dir with scripts/cue-vet copied in.
make_repo() {
    repo="$1"
    mkdir -p "$repo/scripts"
    cp "$CUE_VET" "$repo/scripts/cue-vet"
    chmod +x "$repo/scripts/cue-vet"
}

# Test 4: no-arg mode + missing docs/schemas/ → exit 0.
REPO4="$SANDBOX/repo-no-schemas"
make_repo "$REPO4"
sh "$REPO4/scripts/cue-vet" || fail "no-arg + missing schemas/ should exit 0"

# Test 5: no-arg mode + empty docs/schemas/ → exit 0.
REPO5="$SANDBOX/repo-empty-schemas"
make_repo "$REPO5"
mkdir -p "$REPO5/docs/schemas"
sh "$REPO5/scripts/cue-vet" || fail "no-arg + empty schemas/ should exit 0"

# Test 6: no-arg + valid fixture under valid/ → exit 0.
REPO6="$SANDBOX/repo-valid"
make_repo "$REPO6"
mkdir -p "$REPO6/docs/schemas/topicA/fixtures/v1.0.0/valid"
echo '#TopicA: {x: int}' > "$REPO6/docs/schemas/topicA/schema.cue"
echo 'x: 1' > "$REPO6/docs/schemas/topicA/fixtures/v1.0.0/valid/example.yaml"
sh "$REPO6/scripts/cue-vet" || fail "no-arg + valid fixture under valid/ should exit 0"

# Test 7: no-arg + valid fixture that FAILS cue vet → exit non-zero,
# spec-standard failure format.
REPO7="$SANDBOX/repo-failing-valid"
make_repo "$REPO7"
mkdir -p "$REPO7/docs/schemas/topicA/fixtures/v1.0.0/valid"
echo '#TopicA: {x: int}' > "$REPO7/docs/schemas/topicA/schema.cue"
echo 'x: "wrong"' > "$REPO7/docs/schemas/topicA/fixtures/v1.0.0/valid/bad-example.yaml"
output=""
exit_code=0
output=$(sh "$REPO7/scripts/cue-vet" 2>&1) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "no-arg + failing valid fixture should exit non-zero"
echo "$output" | grep -qE "bad-example\.yaml fails against topicA\.cue at .*schema\.cue: " \
    || fail "output does not match standard failure format. got: $output"

# Test 8: no-arg + invalid fixture that FAILS cue vet → exit 0 (correct
# behavior — the schema is rejecting a shape declared invalid).
REPO8="$SANDBOX/repo-correctly-invalid"
make_repo "$REPO8"
mkdir -p "$REPO8/docs/schemas/topicA/fixtures/v1.0.0/invalid"
echo '#TopicA: {x: int}' > "$REPO8/docs/schemas/topicA/schema.cue"
echo 'x: "wrong"' > "$REPO8/docs/schemas/topicA/fixtures/v1.0.0/invalid/bad-shape.yaml"
sh "$REPO8/scripts/cue-vet" \
    || fail "invalid fixture that fails cue vet should exit 0 (correct behavior)"

# Test 9: no-arg + invalid fixture that PASSES cue vet → exit non-zero,
# inverted-format regression message ("unexpectedly passed").
REPO9="$SANDBOX/repo-invalid-passes"
make_repo "$REPO9"
mkdir -p "$REPO9/docs/schemas/topicA/fixtures/v1.0.0/invalid"
echo '#TopicA: {x: int}' > "$REPO9/docs/schemas/topicA/schema.cue"
echo 'x: 1' > "$REPO9/docs/schemas/topicA/fixtures/v1.0.0/invalid/should-fail.yaml"
output=""
exit_code=0
output=$(sh "$REPO9/scripts/cue-vet" 2>&1) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "no-arg + invalid fixture that passes should exit non-zero"
echo "$output" | grep -qE "should-fail\.yaml in invalid/ unexpectedly passed against topicA\.cue at .*schema\.cue" \
    || fail "output does not match inverted regression format. got: $output"

# Test 10: no-arg + mixed library (valid passing, invalid failing
# correctly, valid passing across multiple topics) → exit 0.
REPO10="$SANDBOX/repo-mixed-happy"
make_repo "$REPO10"
mkdir -p "$REPO10/docs/schemas/topicA/fixtures/v1.0.0/valid"
mkdir -p "$REPO10/docs/schemas/topicA/fixtures/v1.0.0/invalid"
mkdir -p "$REPO10/docs/schemas/topicB/fixtures/v1.0.0/valid"
echo '#TopicA: {x: int}' > "$REPO10/docs/schemas/topicA/schema.cue"
echo '#TopicB: {y: string}' > "$REPO10/docs/schemas/topicB/schema.cue"
echo 'x: 1' > "$REPO10/docs/schemas/topicA/fixtures/v1.0.0/valid/good.yaml"
echo 'x: "wrong"' > "$REPO10/docs/schemas/topicA/fixtures/v1.0.0/invalid/bad-shape.yaml"
echo 'y: "ok"' > "$REPO10/docs/schemas/topicB/fixtures/v1.0.0/valid/good.yaml"
sh "$REPO10/scripts/cue-vet" || fail "mixed happy library should exit 0"

# Test 11: cwd-independence — call from /tmp, script resolves paths via
# its own location, not the caller's PWD.
( cd /tmp && sh "$REPO6/scripts/cue-vet" ) \
    || fail "no-arg invocation from /tmp failed; script is not cwd-independent"

# Test 12: too-many-args → exit 2, usage to stderr.
output=""
exit_code=0
output=$("$CUE_VET" foo.cue bar.cue 2>&1) || exit_code=$?
[ "$exit_code" -eq 2 ] || fail "too-many-args should exit 2, got $exit_code"
echo "$output" | grep -qi "usage:" || fail "no usage message for too-many-args"

# Test 13: defensive branch — topic dir with fixtures but no schema.cue.
# Script should silently skip the topic and exit 0.
REPO13="$SANDBOX/repo-no-schema"
make_repo "$REPO13"
mkdir -p "$REPO13/docs/schemas/topicA/fixtures/v1.0.0/valid"
echo 'x: 1' > "$REPO13/docs/schemas/topicA/fixtures/v1.0.0/valid/example.yaml"
sh "$REPO13/scripts/cue-vet" || fail "topic with no schema.cue should be silently skipped, exit 0"

# Test 14: defensive branch — topic with schema.cue but no fixtures/ subdir.
REPO14="$SANDBOX/repo-no-fixtures-dir"
make_repo "$REPO14"
mkdir -p "$REPO14/docs/schemas/topicA"
echo '#TopicA: {x: int}' > "$REPO14/docs/schemas/topicA/schema.cue"
sh "$REPO14/scripts/cue-vet" || fail "topic with no fixtures/ subdir should exit 0"

# Test 15: defensive branch — fixtures/v<N>/{valid,invalid}/ exists but
# contains no .yaml. Glob expansion yields no matches; the [ -f ] guard
# skips the literal pattern; script exits 0.
REPO15="$SANDBOX/repo-empty-version-dir"
make_repo "$REPO15"
mkdir -p "$REPO15/docs/schemas/topicA/fixtures/v1.0.0/valid"
mkdir -p "$REPO15/docs/schemas/topicA/fixtures/v1.0.0/invalid"
echo '#TopicA: {x: int}' > "$REPO15/docs/schemas/topicA/schema.cue"
sh "$REPO15/scripts/cue-vet" || fail "topic with empty valid/+invalid/ dirs should exit 0"

# Test 16: defensive branch — fixtures/v<N>/ exists but neither valid/
# nor invalid/ subdir is present. Topic is silently skipped.
REPO16="$SANDBOX/repo-version-no-split"
make_repo "$REPO16"
mkdir -p "$REPO16/docs/schemas/topicA/fixtures/v1.0.0"
echo '#TopicA: {x: int}' > "$REPO16/docs/schemas/topicA/schema.cue"
sh "$REPO16/scripts/cue-vet" || fail "version dir with no valid/invalid/ subdirs should exit 0"

echo "PASS: scripts/cue-vet handles single-file + no-arg modes per AC3/AC5"
