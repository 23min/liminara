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
