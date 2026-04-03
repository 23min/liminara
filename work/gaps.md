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

