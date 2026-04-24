---
id: E-22-docs-foundation
status: in-progress
depends_on:
---

# E-22: Doc-tree Foundation

## Goal

Articulate the bind-me / inform-me register distinction in Liminara's `docs/` tree and move misclassified artifacts to coherent homes, so that E-21's downstream contract artifacts (ADRs, CUE schemas, fixtures, policies) land at paths that accurately describe their class rather than inheriting the legacy `docs/architecture/contracts/` grouping.

## Context

A small prompt — `migrate.sh §3.1e` flagging three unset path fields in `.ai-repo/config/artifact-layout.json` — surfaced three interconnected issues in the current doc tree:

- The word "spec" is used for three different artifact types (milestone scope, design intent, Nygard ratification) without a shared location discipline.
- `docs/architecture/contracts/` is a misnamed grouping that bundles policies, indexes, and future schemas under a single label and buries them under `architecture/`, which per the truth discipline should hold only live or decided-next design prose.
- The repo has no articulated distinction between artifacts the AI must *obey* when doing work and artifacts the AI *reads for context* when iterating on design. The distinction exists implicitly (shim policy binds authoring, `cue vet` will bind schemas, the truth model binds truth-source adjudication) but the directory structure does not express it.

E-21 (Pack Contribution Contract) is about to generate roughly 14 ADRs, 14 CUE schemas, multiple fixture sets, and several policy docs. Fixing the structure now — before E-21 produces downstream artifacts that inherit the legacy layout — is substantially cheaper than rerouting them afterward.

Full reasoning, including the taxonomy and all alternatives considered, lives in [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md). This epic is the execution of that decision.

## Scope

### In Scope

- **Framework-side changes** (via PR on the `ai-workflow` submodule): remove `specsPath` from paths/skills/sync/migrate; soften `01_CONTRACT_MATRIX.md` example references in framework skill docs to a generic "contract catalog" phrase.
- **Liminara-side doc-tree reorg**:
  - Move `00_TRUTH_MODEL.md` and `02_SHIM_POLICY.md` from `docs/architecture/contracts/` to `docs/governance/` (with filename normalization to kebab-case).
  - Rename and move `01_CONTRACT_MATRIX.md` to `docs/architecture/indexes/contract-matrix.md`.
  - Remove the empty `docs/architecture/contracts/` directory.
  - Create `docs/governance/README.md` with a discovery table + redirect stub for moved files.
  - Move the two PDFs in `docs/research/` to `docs/research/literature/`.
  - Prefix every `.md` file in `docs/research/` with `NN_<lower_case>.md` per git-creation date, alphabetical within same-commit batches.
- **Rule-text articulation** in `.ai-repo/rules/liminara.md`:
  - New *Doc-tree boundaries* section naming the bind-me / inform-me registers, enumerating the classes in each, and articulating the distinction between `.ai-repo/rules/` (process discipline) and `docs/governance/` (artifact governance).
  - New *Author-sequenced thinking convention* section formalizing `NN_<descriptor>.md` (with descriptor-case rules per directory).
  - Updates to the *Contract matrix discipline* section (path pointer) and the *Project structure* list.
- **Reference sweeps** across all live files that mention the old paths (approximately 14 live files, 40 references). Regenerated adapters (`CLAUDE.md`, `.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`) pick up rule-text changes via `bash .ai/sync.sh`.
- **E-21 semantic adjustments**: drop the planned separate `pack-contract-index.md` (the renamed matrix is the index); update schema/fixture path references in E-21a/b/c/d planning prose to the co-located shape; propagate the governance directory name.
- **Two decision-log entries** (`D-2026-04-24-031` ratifying the reorg; `D-2026-04-24-032` recording the `specsPath` omission rationale).
- **Deletion of the working proposal doc** `work/proposals/docs-layout-reorg.md` (superseded by this epic, ADR-0003, and the two milestone specs).

### Out of Scope

- Bulk-renaming the existing `NN_UPPERCASE.md` files in `docs/architecture/` (the convention is intentional and load-bearing for the author's sequenced thinking; only `docs/research/` gets the retroactive prefix).
- Sweeping frozen surfaces (`work/done/`, `work/agent-history/`, prior `work/decisions.md` entries D-001 through D-030). Per D-2026-04-22-028, session records are not rewritten.
- Any content edits to the moved files beyond path self-references (the files relocate; their prose stays).
- Creation of CUE schemas, fixtures, or the schema-evolution policy document (E-21 deliverables; this epic only establishes where they will land).
- Framework refactoring beyond `specsPath` removal and contract-catalog phrase softening (deeper framework changes are out of scope).
- PDF content review or filename normalization (the two existing PDFs move to `docs/research/literature/` with their current filenames intact).

## Constraints

- **Milestone sequencing**: M-DOCS-01 (framework prep) must merge and the `.ai/` submodule pointer must be bumped in Liminara before M-DOCS-02 (the doc-tree reorg) begins. Rationale: Liminara's `artifact-layout.json` deliberately omits `specsPath`; the framework must stop requiring it first.
- **Frozen-surface policy is non-negotiable**: no rewrites of `work/done/`, `work/agent-history/`, or prior decisions entries. Redirect bridging happens once, in `docs/governance/README.md`.
- **Contract matrix stays under `architecturePath`** so the `workflow-audit` skill's detection pattern (`01_CONTRACT_MATRIX.md` or similar under architecturePath) continues to resolve. After M-DOCS-01, the framework's softened phrase makes the filename less load-bearing; the location requirement stands.
- **Existing `NN_UPPERCASE.md` files in `docs/architecture/` are preserved** verbatim. The convention is retained, only formalized.
- **No new epics or milestones are created beyond M-DOCS-01 and M-DOCS-02.** If further structural work surfaces during execution, it is captured as a new entry in `work/gaps.md`, not folded into this epic.

## Success Criteria

- [ ] Every live reference to `docs/architecture/contracts/*` resolves to a new path (grep returns zero hits in live files).
- [ ] `docs/governance/` contains `truth-model.md`, `shim-policy.md`, and `README.md` (with redirect stub).
- [ ] `docs/architecture/indexes/contract-matrix.md` exists; `docs/architecture/contracts/` does not.
- [ ] Every `.md` file in `docs/research/` is prefixed `NN_<lower_case>.md`; the two PDFs live in `docs/research/literature/`.
- [ ] `.ai-repo/rules/liminara.md` contains the *Doc-tree boundaries* and *Author-sequenced thinking convention* sections; `bash .ai/sync.sh` produces matching adapter output with no diff beyond expected rule-text propagation.
- [ ] `migrate.sh` no longer flags `specsPath` as a missing key (framework PR merged; submodule pointer bumped).
- [ ] E-21a/b/c/d planning prose reflects the reorg (no references to `docs/architecture/contracts/*`; no planned separate `pack-contract-index.md`; schema+fixture path shape matches the co-located form).
- [ ] ADR-0003 status flips from `proposed` to `accepted`.
- [ ] `work/proposals/` no longer contains `docs-layout-reorg.md`.

## Open Questions

All blocker and significant questions were deliberated during ADR-0003 drafting and resolved before this epic was opened. The deliberation trail lives in `work/milestones/tracking/E-22-docs-foundation/M-DOCS-02-tracking.md`; no open questions remain at epic-entry time.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Framework PR review takes longer than expected, blocking M-DOCS-02 start. | Medium | PR scope is deliberately small (one config key removal + phrase softening); author is also effectively the reviewer; no external dependencies. |
| Reference sweep in M-DOCS-02 Commit 1 misses a file. | Low–Medium | Grep-validation gate after the sweep: `grep -rln "docs/architecture/contracts" --exclude-dir=work/done --exclude-dir=work/agent-history` must return empty for live files before moving on to Commit 2. |
| `docs/research/` files have subtle cross-references broken by NN_ renumbering. | Low | Commit 5's sweep walks the same grep pattern across markdown files; same validation gate. |
| External links to old `docs/architecture/contracts/*` paths 404. | Low (repo is not public) | Redirect stub in `docs/governance/README.md` bridges frozen-record followers; optional cleanup later if 404s never become an issue. |
| Generated framework adapters (`.claude/skills/wf-doc-lint/SKILL.md` and siblings) carry old references between M-DOCS-01 PR merge and the next sync. | Low (cosmetic) | Adapters regenerate from framework source on `sync.sh`; the softened phrase lands once M-DOCS-01 resyncs post-merge. |

## Milestones

- [M-DOCS-01-framework-prep](M-DOCS-01-framework-prep.md) — Framework-side PR removing `specsPath` and softening contract-catalog phrase references, plus Liminara-side submodule bump and adapter regeneration. · depends on: —
- [M-DOCS-02-doc-tree-taxonomy](M-DOCS-02-doc-tree-taxonomy.md) — Five-commit doc-tree reorg: file moves, rule-text articulation, config updates, E-21 semantic adjustments, and `docs/research/` NN_ renumbering. · depends on: M-DOCS-01-framework-prep

## References

- [ADR-0003 — Adopt bind-me/inform-me doc-tree taxonomy](../../../docs/decisions/0003-doc-tree-taxonomy.md) — full reasoning, alternatives considered, consequences.
- `D-2026-04-22-028` in `work/decisions.md` — frozen-surface policy precedent this epic builds on.
- `.ai-repo/rules/liminara.md` — target of the rule-text articulation.
- `.ai/` submodule (ai-workflow repo) — target of M-DOCS-01's framework PR.
- `work/epics/E-21-pack-contribution-contract/` — the epic whose downstream artifacts this reorg pre-routes; E-21a/b/c/d sub-epics receive semantic adjustments in M-DOCS-02 Commit 4.
