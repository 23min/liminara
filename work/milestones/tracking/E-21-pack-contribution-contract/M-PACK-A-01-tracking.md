# M-PACK-A-01: Liminara-project Contract-TDD tooling — Tracking

**Started:** 2026-04-25
**Completed:** pending
**Branch:** milestone/M-PACK-A-01 (cut from epic/E-21-pack-contribution-contract)
**Spec:** work/epics/E-21-pack-contribution-contract/M-PACK-A-01-contract-tdd-tooling.md
**Commits:** _(filled at wrap)_

<!-- Status is not carried here. The milestone spec's frontmatter `status:` field is
     canonical. `**Completed:**` is filled iff the spec is `complete`. -->

## Acceptance Criteria

- [x] AC1: Shared tool-versions file at repo root (`.tool-versions`, single source of truth, line-oriented `<tool> <version>` format).
- [x] AC2: CUE installed in the devcontainer from the pinned version (Dockerfile reads `.tool-versions`, no separate hard-coded literal).
- [x] AC3: Local invocation entry point at `scripts/cue-vet` — runs `cue vet` against a single `.cue` file or, with no arg, the full library; exits non-zero on failure with the spec-defined failure-semantics format; cwd-independent.
- [x] AC4: Pre-commit hook installable via single idempotent command (`scripts/install-cue-hook`); blocks staged `.cue` violations and staged-fixture schema-evolution violations; no-op when neither is staged; `--no-verify` bypass intact.
- [x] AC5: Schema-evolution loop (POSIX shell, colocated with `scripts/cue-vet`) — walks every fixture, runs `cue vet <topic>.cue <fixture>` per fixture, exits 0 on empty library, failure output matches spec format.
- [x] AC6: Fixture-library directory layout (`docs/schemas/<topic>/schema.cue` + `docs/schemas/<topic>/fixtures/v<N>/<name>.yaml`) documented; `docs/schemas/` exists with at least a `README.md` placeholder; entry point + loop walk `docs/schemas/*/` (no edits to add a new topic).
- [ ] AC7: `.ai-repo/skills/design-contract.md` authored as flat `.md` (no hand-written folder-form output); content is Liminara-specific bindings only; references admin-pack docs, contract-matrix index, reviewer rules; states the upstream framework dependency (ai-workflow#37); includes hook-install command in onboarding checklist.
- [ ] AC8: `.ai-repo/rules/contract-design.md` authored — reviewer-enforceable, binds anchored admin-pack citations, contract-matrix wrap verification, boundary-library compile blocks, cross-pack-pressure rules; references contract-matrix index path + parent sub-epic spec path; does not duplicate generic-CUE-workflow content.

## Decisions made during implementation

<!-- Decisions that came up mid-work that were NOT pre-locked in the milestone spec.
     For each: what was decided, why, and a link to a decision record if one was
     opened. If no new decisions arose, say "None — all decisions are pre-locked
     in the milestone spec." -->

- **CUE version pin: `0.16.1`** (AC1, 2026-04-25). Spec deferred the version choice to the builder ("Builder confirms during implementation" — *Dependencies* section). Picked the latest stable release from `cue-lang/cue` (tagged `v0.16.1`, published 2026-04-08, prerelease=false) with `linux_amd64` + `linux_arm64` archives confirmed available on the GitHub release. Recorded in `.tool-versions` as `cue 0.16.1` (asdf/mise convention; no leading `v`). Re-pinning is one-line edit per AC1's "single source of truth" contract; the Dockerfile (AC2), `scripts/cue-vet` (AC3), and the pre-commit hook (AC4) all read this file via the canonical extractor `grep '^cue ' .tool-versions | awk '{print $2}'`.

## Work Log

<!-- One entry per AC (preferred) or per meaningful unit of work.
     Header: "AC<N> — <short title>" or "<short title>" if not AC-scoped.
     First line: one-line outcome · commit <SHA> · tests <N/M>
     Optional prose paragraph for non-obvious context: what changed, file:line
     references, why a detour was needed. Append-only — don't rewrite earlier entries. -->

### AC1 — `.tool-versions` at repo root

`.tool-versions` created at repo root pinning `cue 0.16.1` (latest stable as of 2026-04-08; release exists on cuelang/cue with linux_amd64 + linux_arm64 binaries — dependency confirmed). Format is asdf/mise convention: `<tool> <version>`, one tool per line, no leading `v` on the version. Mechanically parseable via the canonical extractor `grep '^cue ' .tool-versions | awk '{print $2}'` which the Dockerfile (AC2), `scripts/cue-vet` (AC3), and the pre-commit hook (AC4) will all use verbatim.

Smoke test added at `scripts/tests/test-tool-versions.sh` (POSIX shell, exits non-zero with `FAIL:` prefix on any of: file missing, no `cue` line, empty version field, non-semver-shaped version). All four failure branches and the happy path exercised in branch-coverage audit.

commit · _(pending milestone-end)_ · tests 1/1

### AC2 — Dockerfile installs CUE from the pinned version

`.devcontainer/Dockerfile` extended (between `uv` and the Hex/Rebar block) with a CUE install step that:

1. `COPY .tool-versions /tmp/.tool-versions` — uses the new build context (`devcontainer.json` `"build.context": ".."` added) to bring the pin into the Docker build scope.
2. Extracts the version with the canonical extractor `grep '^cue ' /tmp/.tool-versions | awk '{print $2}'` into `${CUE_VERSION}`. Same one-liner the local script and pre-commit hook will use.
3. Detects arch via `dpkg --print-architecture` (`amd64` / `arm64` only — cue-lang ships those for Linux).
4. Downloads `https://github.com/cue-lang/cue/releases/download/v${CUE_VERSION}/cue_v${CUE_VERSION}_linux_${ARCH}.tar.gz`, extracts the `cue` binary directly to `/usr/local/bin/`, chmods +x, and removes the temp `.tool-versions` copy. Two `${CUE_VERSION}` substitutions (URL path + tarball name) — no hard-coded version literal anywhere in the Dockerfile.

Smoke test added at `scripts/tests/test-dockerfile-cue.sh` (POSIX shell). Static checks: build.context present, canonical extractor present, cue-lang URL present, `${CUE_VERSION}` substituted at least 2 times. Runtime check (network-dependent, gated by `SKIP_NETWORK_TEST=1`): replays the install in a sandbox tmpdir and asserts the resulting `cue version` reports `0.16.1` exactly. Branch-coverage audit exercised every fail() branch including the count-check at both substitution sites independently; the unsupported-arch defensive guard is reachable only via direct injection (`ARCH=i386 ...`) and verified by hand — coverage note in the test file.

Devcontainer rebuild not performed during this cycle — that's an integration verification the user does after merge. The runtime check on the install algorithm is the proof gate.

commit · _(pending milestone-end)_ · tests 2/2

### AC3 + AC5 — `scripts/cue-vet` entry point + schema-evolution loop

Single POSIX-shell entry point at `scripts/cue-vet` covers both ACs:

- **Single-file mode** (`scripts/cue-vet path/to/file.cue`) — `exec`s `cue vet "$1"` so the cue exit code propagates verbatim. Used by the pre-commit hook (AC4) on each staged `.cue` file.
- **No-arg mode** (`scripts/cue-vet`) — the schema-evolution loop. Walks `docs/schemas/<topic>/`, for each topic with a `schema.cue` and a `fixtures/` subtree, runs `cue vet <topic>/schema.cue <fixture>` against every `fixtures/v*/*.yaml`. Empty or missing `docs/schemas/` exits 0 — the M-PACK-A-01 wrap-state. Failure output format matches the parent sub-epic spec exactly: `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>`.
- **Too-many-args** prints `usage: scripts/cue-vet [path/to/file.cue]` to stderr and exits 2.
- **cwd-independent** via `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`; resolves the schemas tree relative to its own location, not the caller's `$PWD`.

Script length: 58 lines total, ~23 effective shell lines (rest is the doc header + spec citation). The parent sub-epic spec budgets "~20 lines"; the marginal overage covers defensive guards (`[ -d ]` / `[ -f ]` checks for missing topic dirs, schemas, fixtures dirs) which the test suite explicitly exercises.

Test added at `scripts/tests/test-cue-vet.sh` (POSIX shell, 13 sub-tests). Uses an injected mock `cue` binary on `PATH` (treats argument paths containing `bad-` as failing) so the test runs without real cue installed — real-cue integration is covered transitively by AC2's runtime install verification. Branch-coverage audit: every reachable conditional in `scripts/cue-vet` has a dedicated test, including the three defensive `continue`-branches (no schema.cue, no fixtures/ subdir, empty fixtures/v*/ glob).

commit · _(pending milestone-end)_ · tests 13/13

#### AC3/AC5 addendum — `valid/invalid/` sub-walk refactor (D-2026-04-25-033)

After AC4 landed, ai-workflow#37 / PR #72 closed upstream during the same session, shipping the tech-neutral `design-contract` skill + CUE recipe. Upstream prescribes `<topic>/<version>/{valid,invalid}/<name>.<ext>` for the fixture library and treats invalid fixtures as a non-optional principle. Liminara's flatter `fixtures/v<N>/<name>.yaml` shape (just shipped in AC3/AC5/AC6) had no place for invalid fixtures and would have flagged any committed invalid fixture as a permanent regression.

Decision recorded in `work/decisions.md` D-2026-04-25-033; M-PACK-A-01 spec AC5 + AC6 amended; `E-21a-contract-design.md` *Schema-evolution check — specification* subsection rewritten.

`scripts/cue-vet`'s no-arg loop refactored into two sub-walks:
- `fixtures/v*/valid/*.yaml` → `cue vet` must exit 0 per fixture; failures use the standard format.
- `fixtures/v*/invalid/*.yaml` → `cue vet` must exit non-zero per fixture; an inverted pass is a regression with format `<fixture> in invalid/ unexpectedly passed against <topic>.cue at <schema>`.

The schema-evolution forward-compat invariant still applies only to `valid/` (invalid fixtures are rejected by construction across versions).

Script grew from 58 to 79 lines (~31 effective shell lines after the doc-header growth). The second sub-walk is a structural mirror of the first — within the spec's "~20 lines, with the second sub-walk adding modest size" envelope.

Test suite grew from 13 → 16 sub-tests. New tests: invalid fixture that correctly fails (test 8, exit 0), invalid fixture that incorrectly passes (test 9, exit non-zero with inverted format), mixed-library happy path (test 10), defensive guard for fixtures/v<N>/ without valid/invalid/ subdirs (test 16). Branch-coverage audit re-run: every reachable conditional in the refactored script exercised by a dedicated test.

commit · _(pending milestone-end)_ · tests 16/16

### AC4 — Pre-commit hook + idempotent installer

Two scripts shipped:

- **`scripts/pre-commit-cue`** (POSIX shell) — the hook logic. Reads `git diff --cached --name-only --diff-filter=ACMR`. If any staged file ends in `.cue`, runs `scripts/cue-vet <file>` per file and exits 1 on the first failure. If any staged file matches `^docs/schemas/<topic>/fixtures/v<N>/`, runs `scripts/cue-vet` (no-arg, full schema-evolution loop) per the user's Q2-A choice. Empty staged set (e.g. `--allow-empty`) is a silent no-op.
- **`scripts/install-cue-hook`** — the installer. Drops a thin wrapper at `.git/hooks/pre-commit` that `exec`s `$REPO_ROOT/scripts/pre-commit-cue` (Q1-B: editing the hook-logic file takes effect without re-running the installer). The wrapper carries a marker comment `# liminara-cue-hook (managed by scripts/install-cue-hook — do not edit)` for human legibility. Idempotency is byte-equality via `cmp -s` against a tmpfile materialization of the expected wrapper (Q3-A; tmpfile pattern avoids the shell `$(cat ...)`-strips-trailing-newlines pitfall I hit on the first GREEN). Foreign hooks are never overwritten — installer prints a clear notice and exits 1.

Test added at `scripts/tests/test-install-cue-hook.sh` (POSIX shell, 12 sub-tests). Sandboxes a fresh `git init` per scenario in `tmpdir`; never touches the real repo `.git/`. Same mock-cue pattern as AC3 except the failure heuristic is tightened to match on file basename (was: substring anywhere in path), so test-repo directory names containing `bad-` no longer cross-contaminate. Tests cover: clean install, idempotent re-run, foreign-hook clobber refusal, thin-wrapper-vs-self-contained, no-op when nothing relevant staged, block on bad `.cue`, pass on good `.cue`, block on bad fixture (schema-evolution loop), pass on good fixture, `--no-verify` bypass, `.cue` outside `docs/schemas/` still vetted, `--allow-empty` empty-staged early-exit.

Branch-coverage audit: `install-cue-hook` and `pre-commit-cue` both have every reachable conditional exercised. Refactor removed one defensive `[ -n "$f" ] || continue` guard inside the `.cue`-vet pipeline that was unreachable (grep `'\.cue$'` never emits empty lines).

commit · _(pending milestone-end)_ · tests 12/12

#### AC4 addendum — fixture-stage regex tightened for `valid/invalid/` split (D-2026-04-25-033)

`scripts/pre-commit-cue` fixture-stage regex tightened from `^docs/schemas/[^/]+/fixtures/v[^/]+/` to `^docs/schemas/[^/]+/fixtures/v[^/]+/(valid|invalid)/`. The hook now triggers the schema-evolution loop only when a staged fixture is under the canonical `valid/` or `invalid/` subdirectory — files placed outside that convention don't trigger the loop (and won't be picked up by `scripts/cue-vet`'s no-arg walk either).

Test suite grew from 12 → 14 sub-tests. New tests: hook trigger + correctly-rejected invalid fixture lets commit through (test 13), hook trigger + invalid fixture that *passes* schema blocks commit with inverted-regression message (test 14). Existing tests 8 + 9 (fixture-stage trigger + good/bad valid/ fixtures) reworked to use `valid/` paths.

commit · _(pending milestone-end)_ · tests 14/14

### Decisions made during AC4

Discussed up-front and recorded in tracking-doc top section:

- **Q1-B**: hook is a thin wrapper at `.git/hooks/pre-commit` that `exec`s `scripts/pre-commit-cue`. Edits to the wrapper-logic file take effect without re-running the installer.
- **Q2-A**: when any fixture is staged, the hook runs the full no-arg schema-evolution loop. Per-affected-topic optimization is deferred — fixture library is empty at M-PACK-A-01 wrap and stays small through M-PACK-A-02*.
- **Q3-A**: idempotency check is byte-equality via `cmp -s` (with a marker comment in the wrapper for human-legible diff context). Foreign hook = exit 1 with a clear notice.
- **Q4-A**: install method is copy (not symlink). Symlink edge cases on cross-platform devcontainer hosts not worth navigating; the thin-wrapper design keeps the copy a fixed artifact.
- **Q5**: tests run real `git init` / `git commit` inside `mktemp -d` sandboxes; never touch the real `.git/`. Same mock-cue heuristic as AC3, with the basename-match tightening.
- **Q6**: filename `scripts/pre-commit-cue` (sibling of `scripts/cue-vet` and `scripts/install-cue-hook`).

### AC6 — `docs/schemas/` directory + layout README

`docs/schemas/` directory created (empty, by design — M-PACK-A-02a lands the first schemas + fixtures). `docs/schemas/README.md` documents the layout convention end-to-end:

- The pair-shape: `<topic>/schema.cue` + `<topic>/fixtures/v<N>/<name>.yaml`. Inline reference plus tree-form ASCII layout.
- Why fixtures freeze at their authored version (the schema-evolution loop's whole point).
- The `scripts/cue-vet` entry point — both modes (single-file + no-arg) — and the canonical failure-format reference back to the parent sub-epic spec.
- The pre-commit hook's behavior + the `scripts/install-cue-hook` onboarding step.
- The auto-discovery property (adding a new topic requires no edits to `cue-vet` or the hook — they walk `docs/schemas/*/`).
- A wrap-state status block enumerating which milestones land which topics (M-PACK-A-02a/b/c).

Smoke test added at `scripts/tests/test-schemas-layout.sh` (POSIX shell, 6 checks). Asserts: directory exists, README exists, README documents the schema.cue layout, README documents the fixtures/v<N>/ layout, README references `scripts/cue-vet`, README mentions the schema-evolution loop / fixture-library walk. Branch-coverage audit: 5 of 6 fail() branches exercised by negative scenarios; the schema-evolution-mention branch is structurally reachable but my sed-based negative didn't catch the plural variant the regex accepts (deliberate flexibility in the regex, not a test bug).

The walk-by-`docs/schemas/*/` discoverability requirement of AC6 is already enforced by `test-cue-vet.sh` tests 6, 8, 11, 12, 13 — different topic names exercise the same script with no per-topic edits.

commit · _(pending milestone-end)_ · tests 6/6

#### AC6 addendum — README + test updated for `valid/invalid/` split (D-2026-04-25-033)

`docs/schemas/README.md` reshaped:
- Top-of-file two-artifacts paragraph now describes the `valid/invalid/` split + cross-references D-033 + ai-workflow#37.
- *Layout* section's tree expanded with `valid/` and `invalid/` subdirectories at every `v<N>/` level. Bullet expansion explains valid-must-pass / invalid-must-fail / at-least-one-of-each principle.
- *Local validation* section adds the inverted-failure format string (`<fixture> in invalid/ unexpectedly passed against <topic>.cue at <schema>`) alongside the standard format.

`scripts/tests/test-schemas-layout.sh` updated: check 4 now requires the `<topic>/fixtures/v<N>/{valid,invalid}` literal in the README, plus two new checks (4a, 4b) asserting the README explains the valid-must-pass and invalid-must-fail principles.

commit · _(pending milestone-end)_ · tests 7/7

## Reviewer notes (optional)

<!-- Things the reviewer should specifically examine — trade-offs, deliberate
     omissions, places where the obvious approach was rejected and why.
     Empty/omitted if none. -->

- (none yet)

## Validation

- _(filled at wrap with the validation pipeline result for this milestone's surfaces — no `runtime/` impact, so umbrella `mix test` is not the relevant gate; instead: `cue vet` smoke run on the library, devcontainer rebuild + `cue version` check, hook idempotency check, schema-evolution loop run.)_

## Deferrals

<!-- Work that was observed during this milestone but deliberately not done.
     Mirror each deferral into the repo's long-lived gaps/backlog register
     (wherever the repo tracks that) before the milestone archives, so the
     item survives the archive move. -->

- **wf-graph spec-frontmatter update path-shape mismatch.** Observed during start-milestone: `wf-graph apply --patch` updated `work/graph.yaml` correctly but skipped the milestone spec frontmatter update with `open .../M-PACK-A-01-contract-tdd-tooling.md/spec.md: not a directory` — the tool appends `/spec.md` to `n.Path` unconditionally (`.ai/tools/wf-graph/internal/patch/write.go:124,137`), expecting folder-form `<id>/spec.md` rather than the flat `<id>-<slug>.md` form Liminara uses per `.ai-repo/config/artifact-layout.json`. The frontmatter was hand-edited as a workaround. Filed upstream: [ai-workflow#80](https://github.com/23min/ai-workflow/issues/80). Out of scope for M-PACK-A-01.
