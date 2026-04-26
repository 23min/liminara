#!/bin/sh
# Test scripts/install-cue-hook + scripts/pre-commit-cue (M-CONTRACT-01 AC4).
#
# Validates:
#   - install-cue-hook installs .git/hooks/pre-commit on first run.
#   - Re-running the installer is a no-op (idempotent).
#   - Installer refuses to clobber a foreign pre-existing
#     .git/hooks/pre-commit (different bytes); foreign hook stays untouched
#     and the installer exits non-zero.
#   - The installed hook is a thin wrapper: it execs scripts/pre-commit-cue
#     from the repo's working tree, so updates to the wrapper-logic file
#     take effect without re-installing.
#   - pre-commit-cue is a no-op when nothing relevant is staged.
#   - pre-commit-cue runs cue vet on staged .cue files and blocks on
#     violation.
#   - pre-commit-cue runs the schema-evolution loop (no-arg) when any
#     fixture under docs/schemas/<topic>/fixtures/v<N>/ is staged, and
#     blocks on violation.
#   - git commit --no-verify continues to bypass the hook.
#
# Uses a sandboxed `git init` repo in tmpdir — never touches the real .git/.
# Mock cue on PATH (paths containing "bad-" fail) — same affordance used by
# test-cue-vet.sh.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-cue-hook"
HOOK_LOGIC="$REPO_ROOT/scripts/pre-commit-cue"
CUE_VET="$REPO_ROOT/scripts/cue-vet"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Mock cue. Treats `vet <args>` as success unless the BASENAME of any
# argument starts with "bad-". Match-on-basename (vs. anywhere in the
# path) keeps the heuristic isolated from test-fixture directory names
# that may incidentally contain "bad-" (e.g. $SANDBOX/repo-bad-fixture/).
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

# Pre-check: AC3 deliverables must be present.
[ -x "$CUE_VET" ] || fail "scripts/cue-vet not present (AC3 prerequisite)"
[ -x "$INSTALLER" ] || fail "scripts/install-cue-hook not executable"
[ -x "$HOOK_LOGIC" ] || fail "scripts/pre-commit-cue not executable"

# Construct a sandbox repo for each scenario.
make_sandbox_repo() {
    repo="$1"
    mkdir -p "$repo/scripts/tests"
    cp "$CUE_VET" "$repo/scripts/cue-vet"
    cp "$HOOK_LOGIC" "$repo/scripts/pre-commit-cue"
    cp "$INSTALLER" "$repo/scripts/install-cue-hook"
    chmod +x "$repo/scripts/cue-vet" "$repo/scripts/pre-commit-cue" "$repo/scripts/install-cue-hook"
    (
        cd "$repo"
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test"
        git config commit.gpgsign false
    )
}

# Stage one or more files inside a sandbox repo.
stage() {
    repo="$1"; shift
    ( cd "$repo" && git add "$@" )
}

# Test 1: clean install.
REPO1="$SANDBOX/repo-clean-install"
make_sandbox_repo "$REPO1"
( cd "$REPO1" && sh scripts/install-cue-hook ) || fail "install-cue-hook failed on first run"
[ -x "$REPO1/.git/hooks/pre-commit" ] || fail ".git/hooks/pre-commit not installed/executable"

# Test 2: idempotent re-run on already-installed hook.
( cd "$REPO1" && sh scripts/install-cue-hook ) || fail "second install-cue-hook run should be a no-op (exit 0)"

# Test 3: refuses to clobber a foreign pre-existing hook.
REPO3="$SANDBOX/repo-foreign-hook"
make_sandbox_repo "$REPO3"
mkdir -p "$REPO3/.git/hooks"
printf '#!/bin/sh\necho "foreign hook"\nexit 0\n' > "$REPO3/.git/hooks/pre-commit"
chmod +x "$REPO3/.git/hooks/pre-commit"
foreign_before="$(cat "$REPO3/.git/hooks/pre-commit")"
exit_code=0
output=$(cd "$REPO3" && sh scripts/install-cue-hook 2>&1) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "installer should refuse to clobber foreign hook (non-zero exit)"
foreign_after="$(cat "$REPO3/.git/hooks/pre-commit")"
[ "$foreign_before" = "$foreign_after" ] || fail "installer modified foreign hook"
echo "$output" | grep -qi "exists\|present\|refuse" || fail "installer did not print clear notice. got: $output"

# Test 4: thin wrapper — installed hook execs scripts/pre-commit-cue from
# the working tree (so editing pre-commit-cue takes effect without re-install).
REPO4="$SANDBOX/repo-thin-wrapper"
make_sandbox_repo "$REPO4"
( cd "$REPO4" && sh scripts/install-cue-hook ) >/dev/null
grep -q 'pre-commit-cue' "$REPO4/.git/hooks/pre-commit" \
    || fail "installed hook is not a wrapper around scripts/pre-commit-cue"

# Test 5: hook is a no-op when nothing relevant is staged.
REPO5="$SANDBOX/repo-noop"
make_sandbox_repo "$REPO5"
( cd "$REPO5" && sh scripts/install-cue-hook ) >/dev/null
echo "hello" > "$REPO5/README.md"
stage "$REPO5" README.md
( cd "$REPO5" && git commit -q -m "irrelevant change" ) \
    || fail "commit with no relevant staged files should succeed (hook no-op)"

# Test 6: hook blocks commit on a staged .cue file that fails cue vet.
REPO6="$SANDBOX/repo-bad-cue"
make_sandbox_repo "$REPO6"
( cd "$REPO6" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO6/docs/schemas/topicX"
echo "schema_version: \"1.0.0\"" > "$REPO6/docs/schemas/topicX/bad-broken.cue"
stage "$REPO6" docs/schemas/topicX/bad-broken.cue
exit_code=0
( cd "$REPO6" && git commit -q -m "broken cue" ) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "hook did not block commit on failing .cue"

# Test 7: hook lets commit through when staged .cue file passes cue vet.
REPO7="$SANDBOX/repo-good-cue"
make_sandbox_repo "$REPO7"
( cd "$REPO7" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO7/docs/schemas/topicY"
echo 'schema_version: "1.0.0"' > "$REPO7/docs/schemas/topicY/schema.cue"
stage "$REPO7" docs/schemas/topicY/schema.cue
( cd "$REPO7" && git commit -q -m "valid cue" ) || fail "hook blocked commit on valid .cue"

# Test 8: hook runs schema-evolution loop when a fixture is staged
# (under valid/ — same hook trigger applies to invalid/), and blocks on
# violation. Layout per D-2026-04-25-033: <topic>/fixtures/v<N>/{valid,invalid}/.
REPO8="$SANDBOX/repo-bad-fixture"
make_sandbox_repo "$REPO8"
( cd "$REPO8" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO8/docs/schemas/topicZ/fixtures/v1.0.0/valid"
echo '#TopicZ: {x: int}' > "$REPO8/docs/schemas/topicZ/schema.cue"
echo 'x: 1' > "$REPO8/docs/schemas/topicZ/fixtures/v1.0.0/valid/bad-fix.yaml"
( cd "$REPO8" && git add docs/schemas/topicZ/schema.cue ) # initial: stage schema separately so we can test fixture-only later
( cd "$REPO8" && git commit -q -m "add schema" ) || fail "schema-only commit blocked"
stage "$REPO8" docs/schemas/topicZ/fixtures/v1.0.0/valid/bad-fix.yaml
exit_code=0
( cd "$REPO8" && git commit -q -m "bad fixture" ) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "hook did not block commit on failing valid fixture"

# Test 9: hook lets commit through when fixture passes the loop.
REPO9="$SANDBOX/repo-good-fixture"
make_sandbox_repo "$REPO9"
( cd "$REPO9" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO9/docs/schemas/topicW/fixtures/v1.0.0/valid"
echo '#TopicW: {x: int}' > "$REPO9/docs/schemas/topicW/schema.cue"
echo 'x: 1' > "$REPO9/docs/schemas/topicW/fixtures/v1.0.0/valid/good.yaml"
stage "$REPO9" docs/schemas/topicW/schema.cue docs/schemas/topicW/fixtures/v1.0.0/valid/good.yaml
( cd "$REPO9" && git commit -q -m "valid schema + fixture" ) || fail "hook blocked commit on valid schema+fixture"

# Test 10: --no-verify bypasses the hook (developer escape hatch).
REPO10="$SANDBOX/repo-no-verify"
make_sandbox_repo "$REPO10"
( cd "$REPO10" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO10/docs/schemas/topicQ"
echo "schema_version: \"1.0.0\"" > "$REPO10/docs/schemas/topicQ/bad-broken.cue"
stage "$REPO10" docs/schemas/topicQ/bad-broken.cue
( cd "$REPO10" && git commit --no-verify -q -m "bypass hook" ) \
    || fail "--no-verify should bypass the hook"

# Test 11: changes outside docs/schemas/ that include unrelated .cue-named
# files should still be vetted (cue files anywhere are .cue files; the
# hook's gate is on the file extension, not on docs/schemas/ membership).
REPO11="$SANDBOX/repo-cue-outside-schemas"
make_sandbox_repo "$REPO11"
( cd "$REPO11" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO11/elsewhere"
echo "schema_version: \"1.0.0\"" > "$REPO11/elsewhere/bad-stray.cue"
stage "$REPO11" elsewhere/bad-stray.cue
exit_code=0
( cd "$REPO11" && git commit -q -m "stray cue" ) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "hook did not vet a .cue file outside docs/schemas/"

# Test 12: --allow-empty exercises the [ -z "$STAGED" ] early-exit branch
# in pre-commit-cue (git lets the hook run even with nothing staged when
# --allow-empty is passed, so the hook must handle it).
REPO12="$SANDBOX/repo-allow-empty"
make_sandbox_repo "$REPO12"
( cd "$REPO12" && sh scripts/install-cue-hook ) >/dev/null
# Need an initial commit before --allow-empty is meaningful; create one
# with a no-op file (then run --allow-empty against the resulting HEAD).
echo "init" > "$REPO12/seed"
stage "$REPO12" seed
( cd "$REPO12" && git commit -q -m "seed" )
( cd "$REPO12" && git commit --allow-empty -q -m "empty hook run" ) \
    || fail "--allow-empty should pass the empty-staged early-exit branch"

# Test 13: hook regex matches invalid/ paths — staging a correctly-
# invalid fixture (one that fails cue vet) lets the commit through
# (the schema-evolution loop sees it correctly rejected, exits 0).
REPO13="$SANDBOX/repo-invalid-correctly"
make_sandbox_repo "$REPO13"
( cd "$REPO13" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO13/docs/schemas/topicV/fixtures/v1.0.0/invalid"
echo '#TopicV: {x: int}' > "$REPO13/docs/schemas/topicV/schema.cue"
echo 'x: 1' > "$REPO13/docs/schemas/topicV/fixtures/v1.0.0/invalid/bad-shape.yaml"
stage "$REPO13" docs/schemas/topicV/schema.cue \
    docs/schemas/topicV/fixtures/v1.0.0/invalid/bad-shape.yaml
( cd "$REPO13" && git commit -q -m "schema + correctly-invalid fixture" ) \
    || fail "hook blocked commit on a correctly-invalid fixture (mock cue rejects bad-* paths, so loop should exit 0)"

# Test 14: hook regex matches invalid/ paths — staging an invalid fixture
# that *passes* cue vet (i.e. the schema didn't reject it) blocks the
# commit (the schema-evolution loop reports an inverted regression).
REPO14="$SANDBOX/repo-invalid-passes"
make_sandbox_repo "$REPO14"
( cd "$REPO14" && sh scripts/install-cue-hook ) >/dev/null
mkdir -p "$REPO14/docs/schemas/topicU/fixtures/v1.0.0/invalid"
echo '#TopicU: {x: int}' > "$REPO14/docs/schemas/topicU/schema.cue"
( cd "$REPO14" && git add docs/schemas/topicU/schema.cue )
( cd "$REPO14" && git commit -q -m "schema only" )
# Fixture under invalid/ with a non-bad- basename → mock cue passes →
# regression: the schema accepted a fixture declared invalid.
echo 'x: 1' > "$REPO14/docs/schemas/topicU/fixtures/v1.0.0/invalid/should-fail.yaml"
stage "$REPO14" docs/schemas/topicU/fixtures/v1.0.0/invalid/should-fail.yaml
exit_code=0
( cd "$REPO14" && git commit -q -m "invalid fixture passes" ) || exit_code=$?
[ "$exit_code" -ne 0 ] || fail "hook did not block commit on inverted regression (invalid fixture accepted by schema)"

echo "PASS: scripts/install-cue-hook + scripts/pre-commit-cue handle install + hook semantics per AC4"
