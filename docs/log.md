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

**Resolved by:** post-merge full-lint run on 2026-05-03 08:54 (entry below).

## [2026-05-03 08:54] doc-lint full | on-demand

- Index regenerated: 102 docs, 806 sections (delta vs prior file: +6 docs, +39 sections; net of +7 newly indexed entries — 5 ADRs (`0004-op-execution-spec.md`..`0008-pack-plan.md`) + 2 architecture proposals (`dynamic-pipelining-via-contract-routing.md`, `pipeline-scoped-run-context.md`) — minus the self-referential `docs/index.md` row the bootstrap pass had emitted; the bootstrap log's "1674 sections" was a recording error vs the file's actual 767, so the live delta cited here is against the file content)
- doc_health: 79 (freshness 1.00, ref_integrity 1.00, decision_currency 1.00, orphan_rate 0.94, coverage 0.00, conflict_rate 1.00); same headline as bootstrap 79 — internal: orphan_rate +0.11 (15 → 6), decision_currency +0.25 (treating five new ADRs' historical-contextual D-2026-04-22-028 mentions as not-active citations, consistent with the bootstrap's *dismissed* finding), coverage -0.20 (taken on the strict literal formula `(authoritative_for_count / total) × (sections_indexed / sections_present)`; with zero `authoritative_for` claims the first factor zeros the product. The bootstrap recorded 0.20 via a non-literal interpretation; this run sets the methodology to literal so future runs are reproducible. The lever for moving `coverage` upward is `doc-garden verify` declaring `authoritative_for` topics on principal docs.)
- Findings: 12 total
  - 0 fix-now
  - 6 logged as gaps (orphan files; see below)
  - 6 dismissed (5 D-2026-04-22-028 historical-contextual mentions in `docs/decisions/0004`..`0008` — same dismissal pattern as the bootstrap entry; 1 prose-discussion-of-TODO false positive in `docs/research/14_alternative_computation_models.md:165` — same dismissal pattern as the bootstrap entry)
  - Orphan files (6): `docs/analysis/13_Compliance_Positioning.md`, `docs/brainstorm/00_README.md`, `docs/brainstorm/01_Architecture_Requirements_Brief.md`, `docs/brainstorm/02_Umbrella.md`, `docs/brainstorm/03_Core_Runtime.md`, `docs/public/site-restructure.md`. The viz triplet (`VISION_CIRCUIT.md`, `VISION_SCORE.md`, `VISION_TERRAIN.md`) and the `docs/architecture/proposals/lifecycle-fsm-engine.md` RFC the bootstrap had flagged are now linked from `07_TIDEPOOL_VISION.md` / from external `ai-workflow#77`; the public/foundations + public/compliance pages the bootstrap had flagged are now linked from `docs/public/site-restructure.md` (which itself becomes a new orphan — it's the publishing-side index that should exist or get a backlink from a top-level proliminal artifact).
  - Code-reference drift: 0 (the prior index carried no populated `references` field; the spot-check on the 5 new ADRs' `contract.reference_implementation` citations and the contract-matrix's 31 cited live-source paths verified all 31 paths exist; line numbers verified within ±1 except `crash_recovery_test.exs:111` which points to the line *immediately preceding* the named test and `runtime/python/src/ops/radar_summarize.py:42` which points to a line inside `execute()` rather than its `def`. Both are "approximate but unambiguous" and not wrap-blocking.)
  - Superseded decisions: 5 historical-contextual mentions of D-2026-04-22-028 in ADRs 0004-0008 (each notes "now superseded by D-030 on filename, retained for the `working_id:` convention"). All five are framed as the historical record, not as currently-binding citations — same dismissal class as the bootstrap's single finding.
  - Contract drift: 0 — M-CONTRACT-02 spec declared 5 rows added (manifest, plan-as-data, op-execution-spec, replay-protocol, wire-protocol) and 1 row updated (warning + degraded-success). All 5 rows present in `docs/architecture/indexes/contract-matrix.md` (under the labels "Pack manifest contract", "Plan-as-data contract", "Op execution spec", "Replay protocol", "Port wire protocol" — naming variation acknowledged in the spec itself: "the row's *what the contract is* role is the binding part, the row label is editorial"). Warning row's `Approved next` column updated to cite the merged ADR-OPSPEC-01 path. All cited live-source paths exist.
  - Removed-feature docs: 0 — N/A in full mode (no specific change-set focus; sanity check passes).
  - Uncovered contract surface: N/A (`contractSurfaces` not configured in `.ai-repo/config/artifact-layout.json`).
  - Documentation TODOs: 1 false-positive (research prose discussing TODO comments as a stigmergic signal) — dismissed.
  - Template drift: 0 — the 5 new ADRs match the 8-field `.ai/templates/adr.md` shape exactly (frontmatter `id`, `working_id`, `title`, `status`, `date`, `decided_by`, `supersedes`, `superseded_by`, `contract.{schema, fixtures, worked_example, reference_implementation, schema_version}`). The bootstrap's "8-field-template-vs-3-field-existing" finding is now resolved at the new-ADR level; the three pre-existing ADRs (0001, 0002, 0003) still use the 3-field shape and are treated as historical (no retroactive rewrite).
  - Index conflicts: 0 (no docs declare `authoritative_for:` yet — `coverage` will lift only when `doc-garden verify` populates these).
  - Candidates for new documentation: none surfaced this pass (no symbols / decisions referenced that lack an authoritative doc; the new ADRs are themselves the authoritative docs for the schemas they ratify).
- Trigger: post-M-CONTRACT-02 merge to `epic/E-24-contract-design` (commit `b1ffb24`)
- Resolves the queued `[2026-05-02 16:00]` placeholder entry above.
