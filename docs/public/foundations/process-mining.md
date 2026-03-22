# Process Mining — Pipeline Self-Analysis and Discovery

**What if the runtime could analyze its own execution patterns — and discover things the pack author didn't anticipate?**

Research | [pm4py](https://pm4py.fit.fraunhofer.de/), Petri net discovery, conformance checking, meta-circular analysis, FlowTime feedback loop

---

## The scenario

Katarina's team has been running the Radar pack for three months — 100 runs across 12 weeks of intelligence collection and analysis. The pipeline works. Briefings ship on time. But Katarina has questions the briefings can't answer:

Which sources consistently produce content that survives the relevance filter? Are there execution patterns the pack author didn't design for — paths through the DAG that emerge from the interaction between caching, LLM decisions, and source availability? One source seems to cause retries every Tuesday morning. Is that a real pattern or a coincidence?

The data to answer these questions already exists. Every Radar run produced an event log — timestamped, with op names, durations, artifact hashes, decision outcomes. One hundred JSONL files. Liminara's own execution history is, structurally, exactly the kind of event log that process mining consumes.

The system can analyze itself.

---

## The pipeline

```
PHASE 1: INGEST AND DISCOVER
══════════════════════════════════════════════════════════════════

event logs ──→ parse_logs ──→ normalize ──→ discover_model ──→ conformance_check
(100 JSONL      (pinned_env)   (recordable)   (pinned_env)       (pure)
 from Radar                     │               │                  │
 runs)                          │               │                  │
                                │               │                  │
                                │  case notion:  │  discovered:     │  deviations:
                                │  one run =     │  Petri net with  │  15% of runs show
                                │  one case      │  12 places,      │  unexpected retry
                                │                │  18 transitions  │  on source fetch
                                │  DECISION      │                  │  for source #7
                                │  RECORDED      │  matches the     │  (HN API)
                                │                │  intended plan   │
                                │                │  — mostly        │  4% show a
                                │                │                  │  classification
                                │                │                  │  re-run after
                                │                │                  │  synthesis
                                │                │                  │  (not in the plan)


PHASE 2: ANALYZE AND BRIDGE
══════════════════════════════════════════════════════════════════

                    ┌──→ variant_analysis ──→ bottleneck_stats ──→ report
                    │     (pure)               (pure)               (pure)
conformance_check ──┤
                    │
                    └──→ export_to_flowtime ──→ flowtime_simulate ──→ compare
                          (pure)                 (pure)                (pure)
                                                  │
                                                  │  FlowTime models the
                                                  │  Radar pipeline as a
                                                  │  flow system:
                                                  │
                                                  │  "If source #7 retry
                                                  │   rate drops from 15%
                                                  │   to 2%, pipeline
                                                  │   duration decreases
                                                  │   by 8 minutes (12%)"
```

**Phase 1 — Ingest and Discover:**

- `parse_logs` (pinned_env — depends on pm4py version): Read 100 Radar event log files. Each event has: timestamp, op name, run ID, artifact hashes, duration, outcome. Convert to XES format for pm4py ingestion. Total: ~14,000 events across 100 cases (runs). Executor: Python `:port` running pm4py 2.7.
- `normalize` (recordable): Define the case notion — what constitutes a "case" in the event log. For Radar runs, each run is a case. But the choice isn't always obvious. For a pipeline with sub-runs or fan-out, you might define cases differently. This is a modeling decision, and it affects everything downstream. Decision recorded: "case = run_id, activities = op completions, timestamps = event timestamps."
- `discover_model` (pinned_env — depends on algorithm choice and pm4py version): Run the inductive miner on the normalized log. Produces a Petri net: 12 places, 18 transitions, representing the discovered execution pattern across all 100 runs. The net shows the *actual* execution paths, not the *intended* plan.
- `conformance_check` (pure): Compare the discovered Petri net against the intended Radar plan (the designed DAG). Alignment-based conformance. Result: 81% of runs perfectly conform. 15% show an additional retry transition on `fetch_source` for source #7 (HN API). 4% show a `classify` re-execution after `synthesize` — a path the pack author didn't design.

**Phase 2 — Analyze and Bridge:**

- `variant_analysis` (pure): Group the 100 runs by execution path. Variant 1 (81 runs): the happy path. Variant 2 (15 runs): includes HN retry. Variant 3 (4 runs): includes post-synthesis reclassification. Compute frequency, duration distribution, cost per variant.
- `bottleneck_stats` (pure): Per-op duration statistics across all runs. `classify` is the most variable: mean 23s, P95 48s, P99 112s (LLM latency variance). `fetch_source` for HN: mean 2.1s, but 15% of cases show 45s+ (timeout + retry). `embed` is the most stable: mean 1.8s, stddev 0.2s.
- `export_to_flowtime` (pure): Convert the discovered Petri net into a FlowTime model definition. Places become queues. Transitions become services with processing time distributions derived from the bottleneck stats. Routing probabilities from variant frequencies: 81% happy path, 15% retry path, 4% reclassification path.
- `flowtime_simulate` (pure): FlowTime simulates the Radar pipeline as a flow system. What-if: "If we fix the HN API retry issue (drop retry rate from 15% to 2%), how much faster does the pipeline run?" Answer: average run duration decreases from 67 minutes to 59 minutes (-12%). "If we add a second LLM for classification (parallel, not sequential), P95 classification time drops from 48s to 28s."
- `report` (pure): Render findings — discovered model visualization, conformance deviations, bottleneck heatmap, what-if comparison from FlowTime.

---

## The unexpected reclassification pattern

The conformance check found that 4% of runs include a `classify` step *after* `synthesize` — a path that doesn't exist in the designed Radar plan. What's going on?

Tracing those 4 runs in detail:

```
Run #34:  ... → classify → cluster → synthesize → classify → synthesize → briefing
                                                   ^^^^^^^^
                                                   not in the plan

Decision record for Run #34, synthesize (first attempt):
  "Synthesis flagged inconsistency: document sha256:a1b2 was classified as
   'regulatory' but cluster analysis placed it with 'technology' documents.
   Re-running classification with updated context."

Decision record for Run #34, classify (second pass):
  "Reclassified sha256:a1b2 from 'regulatory' to 'technology/regulatory-adjacent'
   based on cluster context. Confidence improved from 0.61 to 0.84."
```

The pack has an implicit feedback loop: when synthesis detects an inconsistency, it triggers reclassification. The pack author didn't explicitly design this — it emerged from the LLM's synthesis step detecting problems and the pipeline's error handling allowing re-execution. Process mining made it visible. Is it a bug or a feature? That's a question for the pack author — but now they know it's happening, in exactly which runs, and with what effect on output quality.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Which sources consistently produce relevant content?" | Variant analysis + per-source statistics: source #3 (Riksdagen API) appears in 94% of briefings. Source #11 (niche RSS feed) appears in 12% and has never survived the relevance filter in the last 40 runs. |
| "Is the Tuesday retry pattern on HN real?" | Bottleneck stats with time-of-week overlay: yes. HN API response times spike Tuesday 08:00-09:00 CET (Monday evening US traffic). 11 of 15 retry cases fall in this window. |
| "What would it cost to fix the retry issue?" | The FlowTime simulation shows 12% duration improvement. The fix is infrastructure (longer timeout, pre-fetch on Monday evening). No pipeline logic change needed. Process mining quantified the impact; FlowTime simulated the improvement. |
| "Are there other emergent patterns we haven't noticed?" | The discovered Petri net *is* the answer. Compare it against the intended plan — every deviation is a pattern the designer didn't anticipate. Currently: the reclassification loop (4%) and the retry path (15%). As more runs accumulate, new patterns may emerge. |
| "How does our pipeline compare to last month?" | Run discovery on two subsets: runs 1-50 (month 1-2) vs. runs 51-100 (month 2-3). Compare the Petri nets. Structural differences show how the pipeline's behavior has evolved — perhaps the reclassification pattern only started after a model update. |

---

## Before and after

**Today:** Katarina knows the pipeline works because briefings arrive. She doesn't know *how* it works in practice — which paths are common, which sources pull their weight, whether there are patterns she should worry about. When something takes longer than expected, she checks logs manually. The logs are verbose and tell her what happened in one run, not what happens across runs. The relationship between source reliability and pipeline duration is invisible.

**With process mining:** 100 event logs become a discovered process model — a map of actual behavior, not intended behavior. Conformance checking shows exactly where reality deviates from design: 15% retry rate on one source, 4% emergent reclassification loop. Bottleneck statistics quantify which ops are stable and which are variable. The FlowTime bridge turns the discovered model into a simulation — so "what if we fix this?" has a quantified answer, not a guess.

The meta-circular quality matters: Liminara's own execution is the dataset. The system doesn't just run pipelines — it can learn from how it runs them. The pack author gets feedback they never had before: not "does the pipeline work?" but "how does the pipeline actually behave, and what patterns have emerged that I didn't design?"

---

*The Process Mining pack validates meta-circular analysis (the runtime analyzing its own execution), the process mining to FlowTime feedback loop (discovered model becomes simulation input), and Python-based `:port` executors (pm4py). It also demonstrates a pattern where packs compose — Process Mining consumes artifacts that other packs (Radar, or any pipeline) produce as a natural byproduct of execution. Looking for process mining practitioners and teams interested in pipeline observability. [Contact ->]*
