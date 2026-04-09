# Gaps

Discovered work items deferred for later.

## Python op isolation — E-12 epic needed
**Discovered:** 2026-04-02 (M-RAD-03, live run exposed VIRTUAL_ENV leakage)
**Relates to:** D-2026-04-02-011, E-10 Port Executor
**Severity:** Architectural gap — not blocking Radar dev (all ops are ours) but blocks production use and untrusted ops
**Items:**
- Clean env whitelist in Executor.Port (layer 1) — quick fix, could be a patch
- Audit hooks in liminara_op_runner.py (layer 2) — catches Python-level violations
- Landlock integration (layer 3) — kernel-enforced, needs sandbox module
- Op capability declarations in Pack behaviour (needs_network, needs_filesystem, allowed_paths)
- Sandbox config recorded in run events (provenance)
- Documentation of isolation model in docs/architecture/
- Evaluate: simple Python ops (normalize, rank, summarize) as Elixir :inline candidates

## Multi-decision replay is broken — RESOLVED in M-RAD-06
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Resolved:** 2026-04-03 (M-RAD-06 commit e9fe49a)
**Fix:** Decision.Store stores list per node_id, Run.Server replays stored output_hashes, full Radar replay test validates end-to-end

## Rank op violates determinism model — RESOLVED in M-RAD-03
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Resolved:** 2026-04-03 (M-RAD-03 commit fd5b4c9)
**Fix:** `reference_time` passed as explicit plan input; rank op raises on missing (no wall-clock fallback)

## M-RAD-03 tracking ahead of implementation — RESOLVED in M-RAD-03
**Discovered:** 2026-04-02 (OpenAI review)
**Resolved:** 2026-04-03 (M-RAD-03 scope amendment + tracking doc update)
**Fix:** Known limitations documented in spec and tracking doc; placeholders accepted for v1

## E-12 sandbox spec contradiction — RESOLVED in epic spec
**Discovered:** 2026-04-02 (OpenAI review)
**Resolved:** 2026-04-03 (E-12 epic spec rewrite)
**Relates to:** E-12 Op Sandbox epic, D-019 (sandbox split)
**Fix:** Success criteria now distinguish bootstrap code/dependency reads from runtime access restrictions. Startup may read declared bootstrap paths; runtime access remains limited to declared runtime paths, with undeclared host paths and other ops' working dirs blocked.

## dag-map: interactive features for live execution visualization
**Discovered:** 2026-04-02 (M-RAD-03 planning)
**Relates to:** M-RAD-04, D-2026-04-02-010
**Items:**
- `onNodeClick(id)` callback API — replace raw DOM `querySelectorAll` pattern
- `onNodeHover(id, rect)` callback API — enable consumer-positioned tooltips
- Selected node highlighting — visual treatment (thicker stroke / glow) via CSS class
- Execution state theme classes — add `running`, `completed`, `failed` to all 6 themes (alongside existing `pending`)
- Mental map preservation — don't reposition existing nodes on incremental re-render (complex, needed for smooth live updates)
- Node state animations — breathing effect for running nodes (nice-to-have, on dag-map roadmap as "someday")

## Borrowable patterns from Camunda
**Discovered:** 2026-04-06 (Camunda platform analysis)
**Relates to:** ADJACENT_TECHNOLOGIES.md §11
**Severity:** Future inspiration — not blocking any current work
**Items:**
- **Connector protocol for side_effecting ops** — standardized interface for ops that wrap external systems (email, Slack, webhooks, APIs). Not Camunda's specific connectors, but the pattern of a common protocol for integration ops. Maps to `side_effecting` determinism class.
- **Run inspection tooling** — Camunda's Operate shows where a process instance is, what's blocked, and why. Liminara's observation layer (A2UI) already has the data; surfacing "where is this run stuck and why?" as a first-class view would be high value. No instance mutation (that conflicts with immutability).
- **Process mining over historical runs** — Camunda's Optimize analyzes completed process instances for bottlenecks and deviations. Liminara's JSONL event logs are already pm4py-compatible (see ADJACENT_TECHNOLOGIES.md §2). A tool or future pack that runs statistical analysis over historical runs to find slow ops, common failure patterns, and plan deviations.
- **Agentic subprocess pattern** — Camunda models LLM agents as ad-hoc subprocesses where the LLM dynamically picks which tasks to run. In Liminara terms: a `recordable` op whose decision is "which sub-DAG to execute." The decision gets recorded, so replay works. Worth considering for packs where the plan itself is nondeterministic (e.g., serendipity exploration in Radar).

## Remaining execution-spec compatibility bridge outside Radar
**Discovered:** 2026-04-05 (M-TRUTH-03 wrap)
**Relates to:** E-20 Execution Truth, M-TRUTH-03
**Severity:** Cleanup follow-on — not blocking E-19, but keeps one legacy runtime bridge alive outside migrated Radar paths
**Items:**
- Remove `Liminara.Op.derive_execution_spec/1` after non-Radar test/support modules stop exporting legacy callback-derived specs
- Current known users: `runtime/apps/liminara_core/test/support/test_port_ops.ex` and `runtime/apps/liminara_core/test/liminara/executor/dispatch_test.exs`

## DAG bench: weight calibration — RESOLVED in calibration patch
**Discovered:** 2026-04-07 (M-DAGBENCH-02 end-to-end smoke)
**Resolved:** 2026-04-07 (calibration chore commit, same day)
**Relates to:** E-DAGBENCH-layout-evolution, M-DAGBENCH-02 AC6
**Root cause (in retrospect):** Two independent cliffs in the energy terms, plus the resulting weight vector:
- `E_envelope` returned a hard `1e6` DEGENERATE_PENALTY on zero-width or zero-height layouts.
- `E_repel_nn` and `E_repel_ne` used `(threshold/d - 1)^2`, a `1/d` singularity that the epsilon floor turned into ~1e15 spikes whenever dag-map placed two nodes at the same coordinate (which it does on several Tier A fixtures).
- These two cliffs made the scalar fitness dominated by one or the other, and the regression guard caught any individual whose coincidences or degenerate geometry differed from best-ever.
**Fix:**
- `E_envelope` now floors width and height at 1 px before computing the log-ratio. Zero-dimension layouts get a bounded ~10-40 range penalty instead of a 1e6 spike.
- `E_repel_nn` and `E_repel_ne` now use `((threshold - d) / threshold)^2`, bounded at 1 per pair. Total per-term is bounded by `n*(n-1)/2` or `n*segments`.
- `bench/config/default-weights.json` re-baselined so every active term contributes ~10 units at defaults (stretch 0.05, bend 40, envelope 1.3, channel 0.006, repel_nn 100, repel_ne 40; crossings 20 and monotone 20 stay inactive on the baseline corpus but are ready to fire).
- M-DAGBENCH-02 integration test tightened from `≤` to strict `<` baseline. Passes on first try.
**Smoke result:** 5-generation seeded run on the full corpus: mean fitness drops from 11419 to 1787 (84% improvement) and best from 1002 to 787.

