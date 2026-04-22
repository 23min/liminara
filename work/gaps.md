# Gaps

Discovered work items deferred for later.

## Dependabot: security vulnerabilities in Python dependencies — plan under a security epic
**Discovered:** 2026-04-22 (push to `main` after `.ai` framework bump; GitHub surfaced 2 open dependabot alerts)
**Relates to:** `runtime/python/uv.lock`, `integrations/python/uv.lock`, future security epic
**Severity:** High + Medium (one each) — runtime scope for both, no exploit in current usage pattern (see notes) but worth addressing together rather than one-off
**Items:**
- **GHSA-vfmq-68hx-4jfw / CVE-2026-41066 — `lxml` XXE via `iterparse()` / `ETCompatXMLParser()` defaults** (severity: high)
  - Location: `runtime/python/uv.lock`
  - Vulnerable range: `< 6.1.0`; fix: upgrade to `>= 6.1.0`
  - Alert: https://github.com/23min/liminara/security/dependabot/2
  - Usage note: verify whether we call `iterparse`/`ETCompatXMLParser` on untrusted XML; if only trusted inputs, exposure is limited but the upgrade is still the right fix
- **GHSA-fv5p-p927-qmxr — `langchain-text-splitters` SSRF redirect bypass in `HTMLHeaderTextSplitter.split_text_from_url`** (severity: medium)
  - Location: `integrations/python/uv.lock`
  - Vulnerable range: `< 1.1.2`; fix: upgrade to `>= 1.1.2`
  - Alert: https://github.com/23min/liminara/security/dependabot/1
  - Usage note: only exploitable if we actually call `HTMLHeaderTextSplitter.split_text_from_url` on user-supplied URLs; confirm whether we do
**Trigger:** plan a security epic covering dependabot bulk-resolution, SBOM tracking, and a cadence for future alerts. Do not address as one-off patches unless a critical CVE lands that can't wait.

## Milestone/tracking template drift — consolidate at next milestone start
**Discovered:** 2026-04-21 (post-framework-update doc-gardening pass)
**Relates to:** `.ai/templates/`, `work/_templates/`
**Severity:** Low — real specs work fine; templates just aren't helpful starting points anymore
**Context:** Neither template set matches current practice. Framework templates (`.ai/templates/milestone-spec.md`, `tracking-doc.md`) are structurally close but lack YAML frontmatter, `depends_on`, and Constraints/Decisions/Design sections that real E-19/E-20 specs use. Repo templates (`work/_templates/milestone.md`, `milestone-log.md`) use a status vocabulary (`draft|ready|active|review|done`) that nobody adopted and an obsolete "test-agent / impl-agent / review" TDD sequence that's since moved into the `wf-tdd-cycle` skill. `work/_templates/milestone-log.md` has zero usage.
**Items:**
- Delete `work/_templates/milestone.md` and `work/_templates/milestone-log.md`
- Create `.ai-repo/templates/milestone-spec.md` and `.ai-repo/templates/tracking-doc.md` as repo overrides — start from the framework versions, add YAML frontmatter (`id`, `epic`, `status: draft|approved|in-progress|complete`, `depends_on`), plus Constraints / Decisions / Design sections
- Keep `work/_templates/ADR.md` and `work/_templates/epic.md` until we have evidence they need updating (only 2 ADRs in the repo — low signal)
**Trigger:** do this at the start of the next milestone (likely E-21a) — write the spec first, retrofit the template from it rather than designing speculatively
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

## Radar LanceDB path drifts into `_build` — RESOLVED in explicit Radar path config
**Discovered:** 2026-04-08 (container persistence review)
**Resolved:** 2026-04-08 (explicit `:liminara_radar, :lancedb_path` in dev/test/prod plus required config lookup)
**Relates to:** D-2026-04-01-009, D-2026-04-08-024, M-RAD-01 persistent storage paths
**Fix:** Radar no longer falls back to a build-output-derived LanceDB path. The pack now requires an explicit configured `lancedb_path`, with dev defaulting to `runtime/data/radar/lancedb`, test using an explicit tmp path, and prod defaulting to `/var/lib/liminara/radar/lancedb`.

## Pack-owned durable path contract needs implementation follow-through
**Discovered:** 2026-04-08 (follow-up from LanceDB path review)
**Relates to:** D-2026-04-08-024, deployment planning
**Severity:** Implementation gap — the contract is now defined, but existing runtime and pack paths still need alignment
**Items:**
- Audit existing pack and UI/runtime fallbacks that still derive durable locations from `System.tmp_dir!/0`, `Application.app_dir/2`, or `_build`
- Migrate Radar LanceDB to the decided durable path contract and decide whether to preserve or discard existing local drift data
- Ensure recorded plans and runtime metadata surface resolved durable pack paths consistently when those paths materially affect execution
- Make any future pack-specific durable directory explicit in both dev and deployment config from day one

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

## Port executor: no process pooling (cold-start per invocation)
**Discovered:** 2026-04-16 (E-21 planning — op lifecycle review)
**Relates to:** E-21 Pack Contribution Contract, future ML-heavy packs
**Severity:** Not blocking near-term packs (Radar, admin-pack, VSME) whose ops are dominated by I/O or subprocess work; **blocking** for future packs that load local ML models or heavy native libraries per invocation
**Context:** `Liminara.Executor.Port.run/3` spawns a fresh Python process (`uv run python -u runner.py`) on every op invocation, sends one request, receives one response, closes the port. Startup cost is roughly 150-300 ms on typical hardware. For I/O- or compute-bound ops this is negligible; for ops that must load a model into memory before first use, it becomes prohibitive (2-second startup on a 1-second op is 67% overhead; across 100 invocations that is minutes of pure cold-start waste).
**Items:**
- Add a persistent-worker pool to `Liminara.Executor.Port`: N long-lived Python processes keyed by op module, each holding the runner loop open and accepting many requests over the same port. Round-robin or least-busy dispatch.
- Prewarm on runtime boot so the first pack invocation does not pay first-run cost.
- Eviction policy (LRU kill on memory pressure).
- Health-check + restart on unhealthy signals.
- Transparent to pack authors — pack manifest and wire protocol are unchanged; this is internal runtime work.
- The same pattern extends to future `:container`, `:wasm`, and `:remote` executors, which have much larger cold-start costs and **must** be designed around persistent workers from day one (codified in E-21's ADR-EXECUTOR-01).

## Remaining execution-spec compatibility bridge outside Radar
**Discovered:** 2026-04-05 (M-TRUTH-03 wrap)
**Relates to:** E-20 Execution Truth, M-TRUTH-03
**Severity:** Cleanup follow-on — not blocking E-19, but keeps one legacy runtime bridge alive outside migrated Radar paths
**Items:**
- Remove `Liminara.Op.derive_execution_spec/1` after non-Radar test/support modules stop exporting legacy callback-derived specs
- Current known users: `runtime/apps/liminara_core/test/support/test_port_ops.ex` and `runtime/apps/liminara_core/test/liminara/executor/dispatch_test.exs`

## Radar briefing HTML — `radar_dedup` safe-default and fetch-error surfacing
**Discovered:** 2026-04-20 (M-WARN-03 wrap)
**Relates to:** E-19, E-21a ADR-CONTENT-01 (briefing contract)
**Severity:** UI gap — runtime-level degraded signals from these paths continue to surface via the observation layer (M-WARN-02), but the rendered HTML briefing does not yet reflect them.
**Items:**
- `radar_dedup` safe-default surfacing: `radar_dedup` operates on items before clustering; its degraded signal would need an item-level degraded flag that propagates through `Cluster` / `Rank` into `ComposeBriefing`. That is a briefing-contract schema decision (surface degraded items as a section? tag clusters containing degraded items?) and crosses into E-21a ADR-CONTENT-01 territory.
- Fetch-error partial-ingestion surfacing: source-level concern; the briefing already has a `source_health` section showing errors. Extending that to a top-level banner would require deciding how per-source errors compose with per-cluster placeholder summaries in the same banner — another UX + schema decision.
- Both extensions were deferred from M-WARN-03 because they cost >1h and the spec explicitly said to defer in that case. Consider re-opening when E-21a ADR-CONTENT-01 codifies the briefing contract, or earlier if operator feedback calls for them.

## ADR-007 Phases 2 & 3 — cache-aware and replay-aware visual states
**Discovered:** 2026-03-23 (ADR-007 body); formally logged 2026-04-22 (F-M6 promotion)
**Relates to:** ADR-007, Observation layer, future cache + replay integration
**Severity:** UX polish — Phase 1 (dim pending nodes) shipped in M-OBS-05a and is sufficient for day-to-day DAG legibility. Phases 2-3 would disambiguate "not yet reached" from "has a cached result" and "will replay" from "will discover" — useful when cache + replay become visually important.
**Context:** ADR-007 was promoted from draft → accepted on 2026-04-22 (F-M6). Phase 1 is in production. Phases 2 and 3 were explicitly deferred in the ADR body to "Phase 5: Radar or later"; captured here so planners don't have to read the ADR to see the deferred work.
**Items:**
- Phase 2 — cache-aware states: `Observation.Server` queries the artifact cache for each pending node; view gains `cache_available: true`; dag-map renders a distinct visual (dotted outline or badge). Requires a cache-lookup API in `Observation.Server`.
- Phase 3 — replay-aware states: `Decision Store` queried for each recordable/side-effecting node; view gains `replay_available: true`; visual distinction for "will replay" vs "will discover." Requires a Decision-Store lookup API in `Observation.Server`.
- Revisit trigger: when replay/cache integration work is scheduled, or earlier if operator feedback demands it.

