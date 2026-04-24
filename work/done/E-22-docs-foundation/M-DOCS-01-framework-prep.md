---
id: M-DOCS-01-framework-prep
epic: E-22-docs-foundation
status: complete
depends_on:
completed: 2026-04-24
---

# M-DOCS-01: Framework Prep — Remove `specsPath`, Soften Contract-Catalog References

## Goal

Land an upstream PR on the `ai-workflow` framework that (a) removes the `specsPath` config key and its three-class architect-output split, and (b) softens hard-coded `01_CONTRACT_MATRIX.md` example references in framework skill docs to a generic "contract catalog" phrase. Then bump the `.ai/` submodule pointer in Liminara and regenerate adapters so the doc-tree reorg in M-DOCS-02 lands against an aligned framework.

## Context

ADR-0003 articulates the bind-me / inform-me taxonomy and identifies two framework-side issues that block clean execution of the Liminara reorg:

1. **`specsPath` is not inert.** The framework's three-way split of architect-skill output (research / architecture / specs) does not survive the truth discipline — there is no coherent "decided-but-not-architecture" tier. As long as `specsPath` exists as a config key, every consumer either configures it (committing to a placement that doesn't fit) or leaves it unset (triggering `migrate.sh §3.1e` advisory noise).

2. **Hard-coded `01_CONTRACT_MATRIX.md` references in framework skill docs** (`doc-lint.md`, `workflow-audit.md`, `migrate-contract-surfaces.md`) name a specific filename as the example contract catalog. When Liminara renames its matrix file (M-DOCS-02), the framework's example references silently drift. Softening the references to a generic phrase — and using the existing "or similar" detection clause in `workflow-audit` — removes the cosmetic drift entirely.

Both changes are framework-side only. Liminara consumes the result by bumping its `.ai/` submodule pointer and re-running `bash .ai/sync.sh`.

## Acceptance Criteria

1. **Framework branch** in the `.ai/` submodule (e.g. `feat/remove-specs-path-and-soften-contract-catalog-refs`) contains:
   - `specsPath` removed from `paths.md` (the Path config table) and from `sync.sh` (the `SPECS_PATH` shell variable, the case branch in the `artifact-layout.json` parser, and any default-fallback assignment).
   - The `architect.md` skill collapsed from three output classes (research / architecture / specs) to two (research / architecture). The `Specs` line in the file-placement section is removed; downstream guidance updated to route what was previously "specs" to either `architecturePath` (decided design intent) or `researchPath` (exploration).
   - The `planner.md` agent's reference to `specsPath` (currently in the architect-skill invocation paragraph) updated to omit the key and reflect the two-class shape.
   - `migrate.sh §3.1e` reworked: the existing "researchPath/architecturePath/specsPath not in artifact-layout.json" advisory is replaced by (a) an unchanged advisory for `researchPath` and `architecturePath` only, and (b) a new check that warns if a consumer's `artifact-layout.json` *has* `specsPath` set, telling them to remove the key.
   - `doc-lint.md`, `workflow-audit.md`, and `migrate-contract-surfaces.md` updated so that example references to `01_CONTRACT_MATRIX.md` use a generic phrase ("the contract catalog file" or equivalent). The "or similar" detection clause in `workflow-audit.md §7.4` is preserved or strengthened.
   - `CHANGELOG.md` entry added under the next version, describing the `specsPath` removal as a breaking change for any consumer who set the key, with the deprecation-check pointer to `migrate.sh`.

2. **Framework validation passes.** `bash tests/test-sync.sh` (run from the framework working tree) completes successfully. If it fails, the failure is fixed in the same branch before the PR is opened.

3. **Framework PR opened and merged.** PR is opened against `ai-workflow` `main` via `gh pr create`, references this milestone (`E-22-docs-foundation/M-DOCS-01`) and ADR-0003 in the body, and is reviewed (effectively self-reviewed; flag if there is any external reviewer cadence to wait on) and merged.

4. **Liminara `.ai/` submodule pointer bumped** to the merged framework commit. `git submodule update --remote .ai` (or equivalent) advances the pointer; the submodule update is committed.

5. **`bash .ai/sync.sh` regeneration is clean.** After the submodule bump, running sync produces deterministic output:
   - `CLAUDE.md` regenerates with no diff in the *Current Work* section.
   - `.claude/rules/ai-framework.md` and `.github/copilot-instructions.md` regenerate to reflect the framework's softened contract-catalog phrase.
   - `.claude/skills/wf-doc-lint/SKILL.md`, `.claude/skills/wf-workflow-audit/SKILL.md`, `.github/skills/doc-lint/SKILL.md`, `.github/skills/workflow-audit/SKILL.md` no longer carry `01_CONTRACT_MATRIX.md` example references.
   The submodule bump and the regenerated adapter diffs are committed together.

6. **`migrate.sh` advisory state matches the new framework.** Running `bash .ai/migrate.sh` against Liminara's repo (which omits `specsPath`) produces no advisory mentioning `specsPath`. (If `researchPath` and `architecturePath` are still unset at this milestone's close, the §3.1e advisory may continue to fire for those keys; that is expected and resolved in M-DOCS-02 Commit 3.)

## Constraints

- **Single framework PR.** Both changes (`specsPath` removal and contract-catalog phrase softening) ship in the same PR. Splitting them adds review overhead with no benefit; the changes are independent in scope but bundled in cadence (both unblock M-DOCS-02).
- **No consumer-repo changes outside Liminara.** Other consumers of the framework (if any) handle their own submodule bumps when their cadence permits. The deprecation check in `migrate.sh` is the contract for downstream notification.
- **Framework discipline** (per `.ai/CLAUDE.md`): if `tests/test-sync.sh` regresses, fix the underlying issue in the framework PR rather than working around it. Do not skip hooks or bypass the changelog.
- **No Liminara doc-tree changes in this milestone.** Moving files, creating `docs/governance/`, prefixing `docs/research/` — all M-DOCS-02. M-DOCS-01 is purely framework prep + adapter sync.

## Design Notes

- Full reasoning for the `specsPath` removal lives in [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md) (sub-decision 6 + Alternatives section).
- The `workflow-audit` detection mechanism is the reason the contract-catalog phrase softening matters. The skill detects the matrix via "a file named `01_CONTRACT_MATRIX.md` (or similar) under `architecturePath`." Liminara's renamed `contract-matrix.md` under `docs/architecture/indexes/` is *under architecturePath*, so the location requirement holds; the filename match relies on the "or similar" clause. Softening the framework's example reference removes the cosmetic mismatch in adapter files; the skill's behavior is unchanged.
- The deprecation check pattern (warn if consumer set a removed key) follows the framework's own convention for breaking changes, per `.ai/CLAUDE.md` Path config defaults guidance.

## Contract matrix changes

None — this milestone modifies the framework source already covered by the existing "AI workflow and repo guardrails" row in `docs/architecture/contracts/01_CONTRACT_MATRIX.md`. The row's live-source paths (`.ai/rules.md`, `.ai/paths.md`, `.ai-repo/rules/liminara.md`) are unchanged; their contents are modified, which is the row's intended steady-state behavior. No row additions, updates, or retirements.

## Surfaces touched

Framework (`.ai/` submodule):
- `paths.md`
- `sync.sh`
- `agents/planner.md`
- `skills/architect.md`
- `skills/doc-lint.md`
- `skills/workflow-audit.md`
- `docs/migrate-contract-surfaces.md`
- `migrate.sh`
- `CHANGELOG.md`
- `tests/test-sync.sh` (validation only — no edits expected)

Liminara (post-PR-merge):
- `.ai` submodule pointer (in Liminara's `.gitmodules`-tracked state)
- `CLAUDE.md` (regenerated)
- `.claude/rules/ai-framework.md` (regenerated)
- `.github/copilot-instructions.md` (regenerated)
- `.claude/skills/wf-doc-lint/SKILL.md` (regenerated)
- `.claude/skills/wf-workflow-audit/SKILL.md` (regenerated)
- `.github/skills/doc-lint/SKILL.md` (regenerated)
- `.github/skills/workflow-audit/SKILL.md` (regenerated)

## Out of Scope

- Liminara doc-tree reorg (M-DOCS-02).
- Any framework changes beyond `specsPath` removal and contract-catalog phrase softening (e.g., further skill refactoring, additional path-config keys, template changes). Those are separate framework initiatives.
- Other consumer repositories' adoption of the framework version bump.
- Removing or modifying `researchPath` / `architecturePath` in the framework (both stay; only `specsPath` is removed).
- Updating `docs/decisions/` ADRs that reference framework defaults (none currently do for `specsPath`; if any are found during execution, they get updated as part of the framework PR or noted in `work/gaps.md`).

## Dependencies

- **ADR-0003** ratified (status `proposed` is sufficient for this milestone to start; `accepted` flip happens at epic close).
- `.ai/` submodule has push access to `https://github.com/23min/ai-workflow.git` (verified during pre-flight: `git remote -v` shows fetch + push remotes).
- Working tree of `.ai/` is clean at milestone start.

## References

- [ADR-0003 — Adopt bind-me/inform-me doc-tree taxonomy](../../../docs/decisions/0003-doc-tree-taxonomy.md) — sub-decision 6 (`specsPath` omission) and Alternatives section.
- [E-22 epic spec](epic.md) — milestone sequencing and overall goal.
- [M-DOCS-02 spec](M-DOCS-02-doc-tree-taxonomy.md) — the milestone this one unblocks.
- `.ai/CLAUDE.md` — framework's own contributor conventions (changelog discipline, test-sync validation, breaking-change handling).
- `.ai/paths.md` and `.ai/skills/architect.md` — current state of `specsPath` in the framework.
