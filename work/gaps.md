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

## Multi-decision replay is broken — Phase 5a priority
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Relates to:** E-11c Replay & Determinism Integrity
**Severity:** Critical — violates the core replay contract
**Items:**
- Decision.Store stores one file per `node_id` — multiple decisions for the same node overwrite each other
- Run.Server `handle_replay_inject/2` loads one decision per node and extracts `output.response` — doesn't match multi-cluster summarize decisions
- radar_summarize.py produces multiple decisions (one per cluster) in a single op execution
- Fix: Decision.Store must support storing/loading a list of decisions per node_id
- Fix: Run.Server replay must reconstruct multi-output results from the decision list
- Validation: end-to-end replay test — run full Radar pipeline, replay, assert identical outputs

## Rank op violates determinism model — Phase 5a priority
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Relates to:** E-11c Replay & Determinism Integrity
**Severity:** Critical — cache hits are semantically unsafe
**Items:**
- radar_rank.py calls `datetime.now(timezone.utc)` but op is declared `:pure`
- Same inputs cached at 6am produce different results at 6pm
- Fix: pass reference timestamp as explicit plan input (makes the op genuinely pure)
- Alternative: change to `:pinned_env` with time as environment input (less clean)

## M-RAD-03 tracking ahead of implementation — Phase 5a priority
**Discovered:** 2026-04-02 (OpenAI review)
**Relates to:** M-RAD-03 tracking doc, D-014 (status labels)
**Severity:** Medium — tracking doc claims ACs done but implementation has known shortcuts
**Items:**
- `historical_centroid` is `{:literal, Jason.encode!([])}` — empty list, not real historical data
- `run_id` is `{:literal, "placeholder"}` — not actual run ID
- Source diversity scoring gives same bonus to every item in a cluster (cluster-level, not per-item cross-source coverage as spec describes)
- Fix: mark these as known shortcuts in tracking doc, not completed ACs
- Fix: address in Phase 5b when M-RAD-03 is properly finished

## E-12 sandbox spec contradiction — fix before E-12 starts
**Discovered:** 2026-04-02 (OpenAI review)
**Relates to:** E-12 Op Sandbox epic, D-019 (sandbox split)
**Severity:** Medium — spec blocks startup or silently expands trust boundary
**Items:**
- Success criteria say Python ops cannot read op source directory or shared venv
- Technical design applies Landlock before importing the op module
- But the runner needs to read both op module and dependencies to boot
- Fix: distinguish between code/dependency read access (allowed during import) and mutable runtime access (restricted during execution)
- Must be resolved in E-12 epic spec before implementation begins

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

