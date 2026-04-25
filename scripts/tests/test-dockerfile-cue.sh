#!/bin/sh
# Smoke test for the devcontainer CUE install contract (M-PACK-A-01 AC2).
#
# Validates:
#   - .devcontainer/devcontainer.json's build.context includes the repo root
#     (so .tool-versions is in the Docker build context).
#   - .devcontainer/Dockerfile sources the CUE version from .tool-versions
#     using the canonical extractor (no hard-coded cue version literal).
#   - .devcontainer/Dockerfile installs cue from the cue-lang/cue release
#     archive matching that version.
#   - The install logic, replayed in a sandbox tmpdir, produces a working
#     `cue` binary whose `cue version` output reports the pinned version
#     exactly.
#
# Run from any cwd:  sh scripts/tests/test-dockerfile-cue.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKERFILE="$REPO_ROOT/.devcontainer/Dockerfile"
DEVCONTAINER_JSON="$REPO_ROOT/.devcontainer/devcontainer.json"
TOOL_VERSIONS="$REPO_ROOT/.tool-versions"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Pre-check: AC1's deliverable must already be in place (it gates AC2).
[ -f "$TOOL_VERSIONS" ] || fail ".tool-versions missing — AC1 prerequisite not satisfied"
PINNED_VERSION="$(grep '^cue ' "$TOOL_VERSIONS" | awk '{print $2}')"
[ -n "$PINNED_VERSION" ] || fail ".tool-versions has no cue line"

# 1. devcontainer.json sets the build context to a parent of .devcontainer/
#    so the Dockerfile can COPY .tool-versions. Accept "..", "../", or any
#    string ending in ".." (mechanical, no jq required — devcontainer.json
#    permits comments so jq-strict parsing is not guaranteed).
grep -qE '"context"[[:space:]]*:[[:space:]]*"\.\.[/]?"' "$DEVCONTAINER_JSON" \
    || fail "devcontainer.json missing build.context: \"..\" — Dockerfile cannot reach .tool-versions"

# 2. Dockerfile must use the canonical extractor pattern (same one-liner
#    scripts/cue-vet and the pre-commit hook will use, per AC1's design).
#    This implies the Dockerfile references .tool-versions; no separate
#    grep for that reference is needed.
grep -qE "grep .\\^cue . .*tool-versions.*\\| *awk .\\{print \\\$2\\}" "$DOCKERFILE" \
    || fail "Dockerfile does not use the canonical extractor 'grep ^cue .tool-versions | awk {print \$2}'"

# 3. Dockerfile must reference the cue-lang release URL pattern.
grep -q 'cue-lang/cue/releases/download' "$DOCKERFILE" \
    || fail "Dockerfile does not download cue from cue-lang/cue/releases"

# 4. Dockerfile must use \${CUE_VERSION} substitution at BOTH points where
#    the version literal would otherwise appear: in the release URL path
#    (download/v<VERSION>/) and in the tarball filename (cue_v<VERSION>_).
#    Two distinct substitutions, so this is an occurrence count (not line
#    count — both substitutions can sit on the same RUN line).
SUBST_COUNT="$(grep -oE '\$\{?CUE_VERSION\}?' "$DOCKERFILE" | wc -l | tr -d ' ')"
[ "$SUBST_COUNT" -ge 2 ] \
    || fail "Dockerfile uses \${CUE_VERSION} only $SUBST_COUNT time(s); should be at least 2 (URL path + tarball name) — a hard-coded version literal is likely present"

# 5. Runtime check — replay the install in a sandbox tmpdir and verify
#    `cue version` reports the pinned version. Skipped if the env has no
#    network (e.g. air-gapped CI); the static checks above remain
#    authoritative for the Dockerfile contract.
if [ "${SKIP_NETWORK_TEST:-0}" = "1" ]; then
    echo "SKIP runtime install test (SKIP_NETWORK_TEST=1)"
else
    ARCH="$(dpkg --print-architecture)"
    # Coverage note: the unsupported-arch fail() branch is a defensive guard.
    # In any devcontainer host, dpkg --print-architecture returns amd64 or
    # arm64 — Liminara's Dockerfile is bound to those two via the cue-lang
    # release artifacts. The branch is reachable only by direct injection
    # (ARCH=i386 sh scripts/tests/test-dockerfile-cue.sh) and is not
    # exercised in automated runs.
    case "$ARCH" in
        amd64|arm64) ;;
        *) fail "unsupported arch '$ARCH' — cue release tarballs are amd64 + arm64 only" ;;
    esac
    SANDBOX="$(mktemp -d)"
    trap 'rm -rf "$SANDBOX"' EXIT
    URL="https://github.com/cue-lang/cue/releases/download/v${PINNED_VERSION}/cue_v${PINNED_VERSION}_linux_${ARCH}.tar.gz"
    curl -fsSL "$URL" | tar -xz -C "$SANDBOX" cue \
        || fail "could not download/extract cue from $URL"
    chmod +x "$SANDBOX/cue"
    INSTALLED_VERSION="$("$SANDBOX/cue" version 2>&1 | awk '/^cue version/ {print $3}' | sed 's/^v//')"
    [ "$INSTALLED_VERSION" = "$PINNED_VERSION" ] \
        || fail "installed cue version '$INSTALLED_VERSION' does not match pinned '$PINNED_VERSION'"
fi

echo "PASS: Dockerfile installs cue $PINNED_VERSION from .tool-versions"
