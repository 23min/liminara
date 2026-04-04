---
title: Radar Pack CEP Framing and Two-Layer Design
doc_type: architecture-history
truth_class: historical
status: archived
owner: history
archived_on: 2026-04-04
snapshot_date: 2026-04-04
superseded_by:
  - work/epics/E-11-radar/epic.md
  - docs/architecture/08_EXECUTION_TRUTH_PLAN.md
---

# Radar Pack: CEP Framing and Two-Layer Design

Notes from analysis of prior art (Nummesh concept, Complex Event Processing literature). Should inform Radar epic scoping when drafted.

---

## The insight

The current plan describes Radar as a linear pipeline:

> fetch → normalize → dedup → rank+summarize → deliver

CEP (Complex Event Processing) reframes this as **two layers with different execution characteristics**. The plan already mentions "two-layer architecture: continuous collection + triggered analysis" — this note makes the distinction concrete and identifies the design questions each layer raises.

---

## Layer 1: Continuous collection (CEP-style)

**Pipeline:** fetch → normalize → dedup-against-history → store in vector index

**Characteristics:**
- Runs frequently (hourly, or on webhook/feed triggers)
- Each run is cheap — mostly cache hits, no LLM calls
- **Cross-run stateful**: must know what previous runs already collected
- Accumulates into a shared corpus (LanceDB vector index)

**CEP concepts that apply:**
- **Windowing**: what time range counts as "already seen"? Fixed window (last 7 days)? Sliding? Per-source?
- **Correlation**: same event reported by multiple sources — detect and merge
- **Temporal ordering**: late-arriving items (RSS feed backdated, API pagination quirks)
- **Dedup**: not just within a single run, but against the accumulated history

**Novel runtime question:** How does one run read artifacts from previous runs? The cache layer handles memoization (same inputs → same outputs), but dedup-against-history is a different pattern — it's "check whether this content already exists in the corpus regardless of which run produced it." This might be:
- A Pack-level concern (the dedup Op queries LanceDB directly)
- A runtime feature (cross-run artifact queries)
- A convention (a well-known artifact namespace that persists across runs)

This should be decided during epic scoping, not deferred to implementation.

**Fits the "activatable runs" pattern:** Layer 1 runs are short-lived processes that wake up, check for new items, store them, and stop. Oban is the natural trigger.

---

## Layer 2: Triggered analysis (LLM-heavy)

**Pipeline:** query corpus → rank by relevance/novelty → summarize with LLM → deliver briefing

**Characteristics:**
- Runs less often (daily, or on-demand)
- Expensive (LLM calls dominate cost)
- **Stateless within the run**: reads from what Layer 1 accumulated, produces a briefing
- Normal pipeline DAG — no cross-run state needed

**This is the straightforward case.** The Phase 2-3 runtime already supports this perfectly. The novel challenges are LLM decision recording and cost tracking, which are core runtime features.

---

## Scoping recommendation

Split the Radar epic (or structure its milestones) around this two-layer boundary:

| Concern | Layer 1: Collection | Layer 2: Analysis |
|---------|-------------------|-------------------|
| Frequency | Hourly+ | Daily / on-demand |
| Cost | Low (HTTP, hashing) | High (LLM calls) |
| State | Cross-run (corpus) | Single-run |
| Novel challenge | Cross-run dedup, windowing | LLM decision recording |
| Runtime dependency | Oban (Phase 6), cross-run queries | Core runtime (Phase 2-3) |
| Caching | Source-level (HTTP ETags, hashes) | Op-level (standard cache) |

**Risk of treating them as one pipeline:** either oversimplify collection (losing windowing, cross-run dedup) or overcomplicate analysis (making it stateful when it doesn't need to be).

**Note on Phase ordering:** The plan currently has Radar (Phase 5) before Oban (Phase 6). Layer 2 can run without Oban (manual trigger). Layer 1 needs Oban for scheduled execution. This suggests the Radar epic should start with Layer 2 (analysis pipeline, manually triggered) and add Layer 1 (collection with scheduling) after or alongside Oban integration.

---

## Source

Analysis derived from Nummesh concept notes (CEP references, StreamBase) cross-referenced with Liminara's architecture. See also `docs/history/architecture/02_PLAN.md §Phase 5` and `docs/analysis/10_Synthesis.md §6`.
