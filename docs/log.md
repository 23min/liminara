# Doc Log

Chronological record of doc-lint runs and doc-garden sessions. Append-only. Entries are greppable with `grep "^## \[" docs/log.md`.

## [2026-04-26 14:39] doc-lint full | bootstrap

- Index regenerated: 86 docs, 1674 sections (first ever full pass; all entries fresh by definition)
- doc_health: 79 (freshness 1.00, ref_integrity 1.00, decision_currency 0.75, orphan_rate 0.83, coverage 0.20, conflict_rate 1.00)
- Findings: 23 total
  - 6 broken file-path references in narrative prose (research/architecture/history-tier; logged as low-priority for `doc-garden`)
  - 1 superseded-decision citation: `docs/decisions/0003-doc-tree-taxonomy.md` cites `D-2026-04-22-028` (superseder; reference is historical-contextual; **dismissed**)
  - 1 false-positive TODO in `docs/research/14_alternative_computation_models.md:165` (prose discussing TODO comments as a stigmergic signal; **dismissed**)
  - 15 orphan files (0 inbound links) — 14 are forward-thinking docs in `docs/domain_packs/` (8) and `docs/brainstorm/` (4) plus 2 housekeeping outliers; 1 (`docs/architecture/proposals/lifecycle-fsm-engine.md`) is a Liminara-authored framework RFC filed upstream as `ai-workflow#77`, intentionally without Liminara inbound links (**dismissed**)
  - Template drift on ADRs: 8-field template vs 3-field existing ADRs — expected (template evolved post-existing-ADRs via PR #72); next ADR will use new template
  - Index conflicts: 0
  - Contract drift / removed-feature docs: N/A (full mode, no change-set)
  - Uncovered contract surface: N/A (`contractSurfaces` not configured)
- Trigger: user-invoked after E-21 sub-epic → umbrella + peer-children migration commits 8dcff98..13dd451
- Bootstrap commit follows: `chore(docs): initialize doc-lint index + log + metrics`

## [2026-05-02 16:00] doc-lint full | queued (post-M-CONTRACT-02 merge)

Status: **queued, not yet executed.** Recorded here because M-CONTRACT-02 added substantial new content that the index does not yet reflect; running `doc-lint full` is a separate dedicated commit (per the skill's own "wrap-epic queues a post-archival doc-lint full" pattern, applied here at milestone-wrap scope).

- New documents added (post-2026-04-26 index):
  - 5 ADRs: `docs/decisions/0004-op-execution-spec.md`, `0005-port-wire-protocol.md`, `0006-replay-protocol.md`, `0007-pack-manifest.md`, `0008-pack-plan.md`
  - 5 CUE schemas + 52 fixtures: `docs/schemas/{op-execution-spec,wire-protocol,replay-protocol,manifest,plan}/schema.cue` + `fixtures/v1.0.0/{valid,invalid}/*.yaml`
  - 1 architecture proposal: `docs/architecture/proposals/dynamic-pipelining-via-contract-routing.md`
  - 1 contract-matrix update (5 new rows + 1 row updated): `docs/architecture/indexes/contract-matrix.md`
- Edits to existing documents (drift fixes flagged during M-CONTRACT-02 wrap-time audit):
  - `docs/liminara.md` — ExecutionSpec field-name drift (`kind:`/`op:` → `executor:`/`entrypoint:`); `may_warn` → `decisions.may_emit` + `warnings.may_emit`; `run_partial` added to terminal events; phase-numbered build plan retired in favour of pointer to `work/roadmap.md`; M-TRUTH-02 reframed post-merge
  - `docs/architecture/01_CORE.md` — same set of drift fixes
  - `docs/architecture/proposals/pipeline-scoped-run-context.md` — `kind:` field-name fix
  - `docs/analysis/11_Data_Model_Spec.md` — `node_*` event names + `run_partial` added
- Expected impact when full regen runs: index grows by ~58 entries (5 ADRs + 52 fixtures + 1 proposal); reverse indexes pick up new symbols (`Liminara.Pack`, `Liminara.ExecutionSpec`, `radar_summarize`, `bookkeeping`, etc.); `freshness` component will refresh; `coverage` will improve as the M-CONTRACT-02 schemas register `authoritative_for` claims.
- Trigger for actual execution: post-merge of `milestone/M-CONTRACT-02` to `epic/E-24-contract-design`, as a dedicated follow-up commit.
