---
id: E-11b-radar-serendipity
phase: 7
status: not started
depends_on: E-16-dynamic-dags
---

# E-11b: Radar Serendipity

## Goal

Extend the completed Radar pack with selective, replayable discovery: start from the most novel items, search for related coverage and counterpoints, follow useful links, merge relevant discoveries back into the briefing pipeline, and recommend promising new sources for human review.

## Context

E-11 Radar Pack is complete. D-2026-04-02-020 deferred serendipity until after VSME because it depends on dynamic DAG support (`E-16`). The roadmap already tracks this as `E-11b Radar Serendipity`; this epic gives that deferred work a real home so E-11 can stay closed.

This is not broad crawling. Serendipity is a budget-capped exploration pass seeded by the most novel or outlier items from core Radar. Query generation, relevance judgments, and source-evaluation calls must remain recorded decisions so exploration is replayable and auditable.

## Scope

### In Scope

- M-RAD-05 serendipity exploration as a follow-on to completed core Radar
- Selective exploration from top novel items and outliers
- Related-coverage search, counterpoint search, and outbound link following
- Relevance evaluation for discovered items before merge-back into the main pipeline
- New-source recommendations for human review
- Budget caps and cost tracking for exploration
- Dynamic DAG integration in `Radar.plan/1` once `E-16` lands

### Out of Scope

- Changes to E-11 completion criteria or reopening the core Radar epic
- Automated source config updates
- Multi-hop crawling
- Image or video analysis
- Real-time exploration outside the batch run

## Constraints

- Depends on `E-16 Dynamic DAGs` per D-2026-04-02-020
- Assumes completed core Radar pipeline from E-11 (including M-RAD-06 replay correctness)
- Query generation, relevance checks, and source evaluation must remain recorded decisions
- Search and fetch work must be budget-capped and allowed to stop gracefully with partial results
- Human curation remains the gate for adding permanent sources

## Success Criteria

- [ ] `E-11 Radar Pack` remains closed, with serendipity tracked only in this follow-on epic
- [ ] M-RAD-05 selects novel or outlier items for exploration rather than exploring the whole corpus
- [ ] Exploration can search related coverage, find counterpoints, and follow outbound links
- [ ] Relevant discoveries are merged back into the briefing pipeline before clustering
- [ ] Candidate new sources are surfaced as human-reviewed recommendations, not auto-added config
- [ ] Replay uses recorded decisions for judgments while keeping side-effecting fetch/search behavior explicit
- [ ] Exploration respects per-run budget caps and returns partial results gracefully when caps are hit

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-RAD-05 | Serendipity exploration | Select novel items, search related coverage and counterpoints, follow links, merge relevant discoveries, and recommend new sources for human review | E-16 + E-11 | not started |

## References

- Roadmap: `work/roadmap.md`
- Decision D-2026-04-02-020: dynamic DAGs and serendipity deferment after VSME
- Milestone spec: `work/epics/E-11b-radar-serendipity/M-RAD-05-serendipity.md`
- Completed core Radar epic: `work/epics/E-11-radar/epic.md`