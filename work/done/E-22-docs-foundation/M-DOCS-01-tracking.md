# M-DOCS-01: Framework Prep — Tracking

**Started:** 2026-04-24
**Completed:** 2026-04-24
**Branch:** `epic/E-22-docs-foundation` (Liminara-side); `feat/remove-specs-path-and-soften-contract-catalog-refs` inside `.ai/` submodule (framework-side, now merged and branch deleted).
**Spec:** `work/epics/E-22-docs-foundation/M-DOCS-01-framework-prep.md`
**Commits:**
- Framework: `0995171` on `feat/remove-specs-path-and-soften-contract-catalog-refs`, merged to `ai-workflow` `main` as `62510f1` via PR [ai-workflow#40](https://github.com/23min/ai-workflow/pull/40).
- Liminara-side close-out: (this commit — submodule bump + status flip + tracking updates; SHA landed post-commit).
- Planning (not a milestone commit): `cb6cc6b` — E-22 planning artifacts.

## Acceptance Criteria

- [x] AC1: Framework branch in `.ai/` submodule contains all specified edits (specsPath removal + contract-catalog phrase softening + migrate.sh deprecation check + CHANGELOG entry). → framework commit `0995171`, 9 files touched.
- [x] AC2: `bash tests/test-sync.sh` passes in the framework working tree. → 94/94 pass on the feature branch pre-merge.
- [x] AC3: Framework PR opened and merged against `ai-workflow` `main`. → PR [#40](https://github.com/23min/ai-workflow/pull/40) merged as `62510f1` (merge-commit strategy, feature branch deleted).
- [x] AC4: Liminara `.ai/` submodule pointer bumped to the merged framework commit. → `git submodule update --remote .ai` advanced the pointer from `87fd040` to `62510f1`.
- [x] AC5: `bash .ai/sync.sh` regeneration is clean; regenerated adapters no longer carry `01_CONTRACT_MATRIX.md` example references; `CLAUDE.md` Current Work section preserved. → sync reported 7 adapters regenerated, 39 unchanged; `CLAUDE.md` working-tree diff shows only the manually-authored Current Work edits (no source-content drift in the generated Project-Specific Rules section because `.ai/rules.md` and `.ai-repo/rules/liminara.md` were not touched by M-DOCS-01).
- [x] AC6: `bash .ai/migrate.sh` produces no advisory mentioning `specsPath` on Liminara's repo. → sync's embedded migrate-audit output shows only a single `§3.1e` advisory referencing `researchPath/architecturePath` only; no `§3.1e-deprecated` (we don't have `specsPath` set). Note: the `§3.1e` researchPath/architecturePath advisory will resolve in M-DOCS-02 Commit 3 when we add those two keys to `artifact-layout.json`.

## Decisions made during implementation

- (pending — all decisions pre-locked in M-DOCS-01 spec + ADR-0003 at milestone start)

## Deliberation log (pre-execution)

The deliberation that produced this milestone is recorded in full in the M-DOCS-02 tracking doc under *Deliberation log*. Key decisions relevant to M-DOCS-01 specifically:

- **`specsPath` removal over alternatives.** Keeping `specsPath` with value `docs/architecture/` was considered and rejected (would collide with curated architecture prose). Keeping it as `docs/specs/` was considered and rejected (re-introduces the three-senses-of-spec ambiguity ADR-0003 resolves). Subfolder `docs/architecture/specs/` was considered. Removing upstream won on the argument that the third class (research / architecture / specs) does not survive the truth discipline coherently. See [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md) sub-decision 6 + Alternatives for full reasoning.
- **Bundling the contract-catalog phrase softening into the same framework PR.** Both changes are independent in scope but bundled in cadence — both unblock M-DOCS-02. Splitting would add review overhead with no benefit.
- **Self-review of the framework PR is acceptable.** The framework author and Liminara author are the same person; merging without waiting on external review is consistent with the repo's existing workflow.

## Work Log

### Framework branch + edits (2026-04-24)

Framework PR opened · `ai-workflow#40` · framework commit `0995171` on branch `feat/remove-specs-path-and-soften-contract-catalog-refs`.

Nine framework files modified per the M-DOCS-01 spec's *Surfaces touched* list. `bash tests/test-sync.sh` reports all 94 pass. PR body cites Liminara's E-22 + ADR-0003 sub-decision 6 as the originating context; describes the breaking-change deprecation handling via `§3.1e-deprecated`.

### PR merge (2026-04-24)

PR #40 merged as `62510f1` (merge-commit strategy via `gh pr merge --merge --delete-branch`). Feature branch deleted from the remote as part of the merge.

### Liminara-side submodule bump + sync (2026-04-24)

- `git submodule update --remote .ai` advanced `.ai` pointer: `87fd040` → `62510f1`.
- `bash .ai/sync.sh` produced the expected output:
  - Framework SHA delta block printed the two-commit range.
  - Embedded migrate-audit output: single `§3.1e` advisory for unset `researchPath`/`architecturePath` (expected; resolved in M-DOCS-02 Commit 3). No `§3.1e-deprecated` fired (Liminara never had `specsPath` set).
  - Adapter regeneration: 7 files regenerated (planner agent; architect, doc-lint, workflow-audit skills in both copilot and claude forms), 39 unchanged. All regenerated adapter files are gitignored per the framework's track-vs-ignore convention — no staged diff expected beyond `.ai` pointer + `CLAUDE.md`.
- `CLAUDE.md` working-tree diff shows only the Current Work edits manually authored at milestone start; no source-content drift (confirmed by targeted diff on the Project-Specific Rules span).

Milestone complete. M-DOCS-02 now unblocked.

## Reviewer notes

- Verify `bash tests/test-sync.sh` in the framework working tree produces a pass before the PR is opened. The framework's own discipline treats this as load-bearing validation.
- Verify the `migrate.sh` deprecation check fires correctly when simulated against a consumer config that has `specsPath` set (not just Liminara's, which omits it).
- Verify the generated adapter regeneration diff in Liminara is limited to expected file paths (`CLAUDE.md`, `.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`, and the four skill SKILL.md files). Unexpected file changes indicate the framework PR touched more surface than planned.

## Validation

- **Framework side:** `bash tests/test-sync.sh` (run inside `.ai/` working tree) passes.
- **Liminara side:** After submodule bump + `bash .ai/sync.sh`:
  - `git diff --stat` shows only the expected regenerated files.
  - `bash .ai/migrate.sh` is clean for `specsPath` (may still advisory-fire for `researchPath` / `architecturePath` until M-DOCS-02 Commit 3; that is expected).

## Deferrals

- (none pre-execution; append during execution if any arise)
