# Decisions

Shared decision log. Active decisions that guide implementation choices.

## D-2026-04-01-001: A2UI as secondary observation UI
**Status:** active
**Context:** Needed lightweight mobile-friendly observation alongside Phoenix LiveView
**Decision:** Use ex_a2ui (A2UI v0.9) as a secondary renderer; LiveView remains primary
**Consequences:** A2UI provider maps Observation.Server state to components; debug renderer works for dev; production needs a proper Lit/React renderer

## D-2026-04-01-002: dag-map lineGap defaults to 0 for auto-discovered routes
**Status:** active
**Context:** v0.3 lineGap feature caused squiggly bezier curves on auto-discovered routes
**Decision:** lineGap defaults to 0 for auto-discovered routes; non-zero only for consumer-provided routes
**Consequences:** Metro-map aesthetic preserved; parallel line separation available when routes are explicit

## D-2026-04-01-003: Python ops via :port for Radar pack
**Status:** active
**Context:** Python ecosystem (feedparser, trafilatura, sentence-transformers) is vastly richer for web scraping and NLP
**Decision:** Radar ops execute as Python processes via Elixir :port; Elixir handles orchestration
**Consequences:** Need Python toolchain in deployment; uv for package management; ops communicate via JSON over stdio

## D-2026-04-01-004: Compliance packs sequence after Radar
**Status:** active
**Context:** VSME, DPP, EUDR all have enforcement deadlines 2026-2027
**Decision:** Radar first (validates Pack pattern + LLM decisions), then VSME (validates compliance pattern), then DPP/EUDR
**Consequences:** EIC Accelerator pitch by Sep 2026 needs Radar running; compliance packs follow

## D-2026-04-01-005: Port executor uses raw Erlang Ports, not libraries
**Status:** active
**Context:** Need Python op execution for Radar. Evaluated ErlPort (abandoned), Porcelain (leaks), Rambo (stale), Pythonx (GIL kills concurrency), MuonTrap (not for bidirectional JSON). OTP documentation and community converge on raw Ports.
**Decision:** Use `Port.open/2` with `{packet, 4}` length-framed JSON. Zero Elixir dependencies. Spawn-per-call for V1; upgrade to NimblePool long-running workers for V2 when spawn overhead matters. Include correlation IDs from day 1.
**Consequences:** No library risk. Protocol is future-proof (V2 is internal swap). Python side uses a generic dispatcher (`liminara_op_runner.py`).

## D-2026-04-01-006: Local embeddings via model2vec, not API
**Status:** active
**Context:** Evaluated API options (Voyage AI, Jina, Gemini, Cohere) and local options (model2vec, fastembed, sentence-transformers). Local avoids API keys and costs. model2vec (potion-base-8M) is 152MB installed, no PyTorch, no ONNX, 6.6ms for 100 items. Quality sufficient for news dedup (threshold ~0.35 cleanly separates duplicates).
**Decision:** Use model2vec with `minishlab/potion-base-8M` (256 dims). Swappable via EmbeddingProvider protocol — can upgrade to fastembed or Voyage AI if quality insufficient.
**Consequences:** Zero API cost for embeddings. Works offline. Dedup thresholds lower than transformer models (0.55 dup / 0.35 ambiguous vs 0.92/0.7). Model auto-downloads on first run (~59MB).

## D-2026-04-01-007: Tavily as primary search provider for serendipity
**Status:** active
**Context:** Evaluated 8 search APIs. Bing dead, Google CSE sunsetting 2027. Tavily: 1,000 free queries/month, no CC, AI-agent optimized, returns LLM-ready content. Exa.ai (neural search) is a complement option for later.
**Decision:** Tavily as primary search provider. Swappable via SearchProvider protocol. Exa.ai deferred to future enhancement.
**Consequences:** Free at our volume (~450 queries/month). Search call is a recordable op — provider is captured in decision record.

## D-2026-04-01-009: Persistent storage paths, not tmp
**Status:** active
**Context:** Default storage falls back to `System.tmp_dir!()` — data lost on reboot/container restart. Radar needs cumulative LanceDB history and persistent run artifacts.
**Decision:** Configure explicit paths in dev config: `runtime/data/store/` (artifacts), `runtime/data/runs/` (events/decisions/plans). LanceDB at `runtime/data/radar/lancedb/`. Gitignore `runtime/data/`. Tests continue using `tmp_dir`.
**Consequences:** Data persists across dev sessions. Production paths (`/var/lib/liminara/`) configured when deployment epic arrives.

## D-2026-04-02-011: Layered sandbox for Python ops, not containers
**Status:** active
**Context:** Python ops via :port inherit all host env vars and have full filesystem access. One op can modify another op's source code or shared venv. For a reproducibility runtime, this is an integrity gap. Evaluated containers (500ms+ startup, too heavy for 5-line functions), WASM/Pyodide (can't run numpy/scikit-learn), RestrictedPython (no C extensions), V8/Deno (can't run CPython). No one in the orchestration world (Dagster, Prefect, Airflow, Temporal) does lightweight sandboxing — they either trust the process or use containers.
**Decision:** Layered kernel-level sandboxing without containers:
- Layer 1: Clean env via Erlang Port `{:env, ...}` whitelist (0ms)
- Layer 2: Python audit hooks (`sys.addaudithook`) — intercept open/subprocess/socket at Python level, irreversible (0ms)
- Layer 3: Landlock LSM — kernel-enforced filesystem + TCP restriction per-process, no root needed (3ms)
- Layer 4 (optional): seccomp-BPF — block fork/execve/ptrace syscalls (1ms)
- Layer 5 (optional): bubblewrap — mount/PID/net namespaces when available (5ms)

Total overhead: ~4ms typical. Verified Landlock working on kernel 6.12 (ABI v6).
Ops declare isolation capabilities in `execution_spec/0.isolation` using the canonical fields `env_vars`, `network`, `bootstrap_read_paths`, `runtime_read_paths`, and `runtime_write_paths`.
Sandbox config recorded in run events for provenance.
**Consequences:** Novel approach — no other Python orchestrator does this. Requires E-12 epic (Op Sandbox & Provenance). Devcontainer has Landlock limitation on fakeowner mounts — audit hooks cover that gap. Production (ext4/xfs) gets full Landlock enforcement. Simple Python ops that don't need the ecosystem should prefer Elixir :inline (no sandbox overhead needed).

## D-2026-04-02-010: DAG visualization — dag-map vs Liminara UI responsibilities
**Status:** active
**Context:** Radar pipeline needs live execution visualization: updated node states during runs, tooltips for op metadata, side panel for runtime info (timing, artifacts, decisions). dag-map is a generic DAG visualization library (submodule); Liminara has domain-specific needs. Need clear ownership boundary.
**Decision:** dag-map provides hooks and visual vocabulary; Liminara owns data and orchestration.

**dag-map should provide (generic library features):**
- `onNodeClick(id)` / `onNodeHover(id, rect)` callback API (replaces raw DOM queries)
- Selected node highlighting (stroke/glow via CSS class toggle)
- Execution state classes in all themes (`running`, `completed`, `failed`, `pending` — pending already exists)
- Mental map preservation on re-render (don't move existing nodes when re-laying out)

**Liminara owns (application-specific):**
- Side panel / detail drawer (LiveView component) — click a node → show op name, determinism class, duration, input/output artifact hashes, decision records
- WebSocket-driven updates — LiveView subscribes to Run.Server events, updates node states, triggers re-render
- Tooltip content — what metadata to show is domain logic
- When to re-render — on node_started, node_completed, node_failed events

**Consequences:** dag-map evolves toward an interactive DAG toolkit (not just static renderer). Liminara doesn't fork dag-map for domain features. M-RAD-04 (Web UI) is the integration point. dag-map improvements can be tracked as issues on the dag-map repo.

## D-2026-04-01-008: GenServer scheduler, not system cron
**Status:** active
**Context:** Need daily run trigger for Radar. Options: system cron (simple, invisible), GenServer + :timer (portable, testable, visible), Oban (Phase 6).
**Decision:** GenServer scheduler supervised by OTP. Configurable daily trigger. Prepares the path for Oban migration in Phase 6 — the run-triggering logic becomes the Oban worker's `perform/1` body.
**Consequences:** Portable across macOS/devcontainer/production. Testable in ExUnit. Visible in observation UI. No persistence — recalculates next run on restart.

## D-2026-04-02-012: Radar hardening moves before VSME, scoped to proven Radar needs
**Status:** active
**Context:** Earlier analysis favored getting to VSME sooner, but M-RAD-03 and production planning surfaced real Radar pack friction: replay/correctness integrity, scheduling/recovery concerns, execution hardening, and limited deployment needs. The question is no longer whether hardening should happen before VSME; it should. The risk is letting that hardening expand into generic platform work too early.
**Decision:** Insert a Radar hardening phase before VSME, but scope it strictly to capabilities Radar has already proven it needs in production. Hardening is allowed to include correctness fixes, recovery/resume semantics, scheduling, persistence, limited instance/config management, and targeted execution hardening. Broad platform abstractions are not automatic prerequisites.
**Consequences:** Radar gets the production slice it has earned. VSME remains the next pack after that slice, not after a generalized runtime program. PackRegistry generalization, broad Postgres metadata separation, heartbeats, and richer multi-instance UI need separate justification.

## D-2026-04-02-013: Near-term sequence is Radar correctness -> Radar hardening -> VSME -> platform generalization
**Status:** active
**Context:** The roadmap needs an explicit sequencing rule that reflects current constraints and avoids oscillating between "ship the next pack immediately" and "finish the generic platform first."
**Decision:** Use the following near-term sequence for planning and roadmap rewrites:
1. Radar correctness
2. Radar hardening
3. VSME
4. Platform generalization
**Consequences:** Replay and determinism integrity come first. Radar hardening happens before VSME, but only in a bounded slice. VSME remains the next pack after Radar. Generalized runtime work should be pulled by concrete evidence from hardened Radar operation and, ideally, cross-pack needs.

## D-2026-04-02-014: Internal strategy docs distinguish validated today, decided next, and directional thesis
**Status:** active
**Context:** Internal analysis and positioning docs use strong forward-looking language. That is useful, but it can blur three different things: what the runtime already does, what the team has decided to do next, and what remains a directional belief about the future.
**Decision:** Internal architecture, positioning, and roadmap-adjacent documents should explicitly label material as one of:
- Validated today
- Decided next
- Directional thesis
**Consequences:** Strong internal language can remain ambitious without confusing future planning agents. This reduces the chance that aspiration is mistaken for current runtime capability or that milestone tracking drifts ahead of the actual contract.

## D-2026-04-02-015: Unified execution spec replaces callback sprawl
**Status:** active
**Context:** The op execution contract is fragmenting across separate callbacks: `determinism/0`, `executor/0`, future `sandbox_capabilities/0` (E-12), future `resources/0` (scale roadmap), and later CUE contracts. If each lands as a standalone callback, every op module gets revised multiple times. OpenAI review flagged this as a medium-severity structural risk.
**Decision:** Design one `execution_spec/0` struct with sections (identity, determinism, execution, isolation, contracts) before E-12 starts. The determinism section owns `class`, `cache_policy`, and `replay_policy`. E-12 implements its sandbox work against the `isolation` section of this spec. Existing callbacks become derived views where possible; if bootability requires a compatibility shim, it must be explicit, bounded, and removal-tracked. Future concerns (resources, CUE contracts) populate their sections when built.
**Consequences:** Build forward, not refactor. Each new concern adds to the spec rather than adding a new top-level callback. Design pass needed before E-12 implementation begins. Lightweight design work, not a whole epic.

## D-2026-04-02-016: Postgres deferred to platform generalization
**Status:** active
**Context:** D-009 established persistent filesystem paths (`runtime/data/`). Radar v1 runs on a single VM with one operator and 3-5 topics. Filesystem persistence is sufficient for this deployment. Postgres adds queryability and concurrent access safety, but these are not proven needs yet.
**Decision:** Defer Postgres to Phase 7 (platform generalization). Filesystem persistence serves Radar v1 and VSME. Postgres earns its place when rich querying, multi-user access, or Oban (which depends on Postgres) are needed.
**Consequences:** Simpler deployment for Radar v1 (no database). Observation UI works against flat files. Migration path: when Postgres is added, event logs and artifact metadata migrate from filesystem to database with content-addressed hashes preserved.

## D-2026-04-02-017: Oban deferred to platform generalization, GenServer scheduler for Radar v1
**Status:** active (reinforces D-008)
**Context:** D-008 already decided GenServer scheduler first, Oban later. The roadmap had drifted by placing Oban in Phase 6. Oban depends on Postgres (now deferred). GenServer scheduler is the M-RAD-04 deliverable.
**Decision:** GenServer scheduler for Radar v1. Oban moves to Phase 7 alongside Postgres. The run-triggering logic is designed as the future Oban worker's `perform/1` body — clean migration path.
**Consequences:** Consistent with D-008. No Postgres dependency for Radar v1. Scheduler recalculates next run time on restart (no persistence needed for schedule state).

## D-2026-04-02-018: Lightweight topic config for Radar v1, not full PackRegistry
**Status:** active
**Context:** Multi-topic isolation is a real Radar v1 need (company radar, disease research, person tracking). Full PackRegistry with runtime-level instance management is a general abstraction. OpenAI review argued PackRegistry is a "second-operator problem." User confirmed multi-topic is needed but agreed that the general abstraction can wait.
**Decision:** Radar v1 uses lightweight topic config: YAML/JSON config listing topics with sources, focus, schedule, and paths. Pack namespaces its own file paths by topic ID. Scheduler iterates topics. Observation UI filters by topic ID. When VSME arrives and also needs instances, the pattern promotes to runtime-level PackRegistry with two real examples to design against.
**Consequences:** Real isolation without premature abstraction. Topic config keys become instance IDs later. Migration path is clean.

## D-2026-04-02-019: Sandbox split — Layer 1 is correctness, Layers 2-3 are hardening
**Status:** active
**Context:** E-12 sandbox epic has 3 layers: (1) clean env whitelist, (2) Python audit hooks, (3) Landlock. Layer 1 fixes a reproducibility bug (VIRTUAL_ENV leakage discovered in M-RAD-03) — this is a correctness concern. Layers 2-3 are security hardening for production deployment.
**Decision:** Layer 1 (~20 lines in Executor.Port) moves to Phase 5a (Radar Correctness). Layers 2-3 plus capability declarations and provenance recording remain in Phase 5c (Radar Hardening).
**Consequences:** Reproducibility fix lands with other correctness work. Full sandbox lands before production deployment. E-12 epic scope is unchanged, but split across two roadmap stages.

## D-2026-04-02-020: Dynamic DAGs, container executor, time-travel UI move after VSME
**Status:** active
**Context:** These were in Phase 7 (between hardening and VSME), which contradicts D-013's sequence. VSME's DAG is static (~25 nodes, known at plan time). VSME's ops use `:port` executor (same as Radar). Time-travel UI is developer polish, not a pack prerequisite.
**Decision:** All three move to platform generalization (after VSME). Dynamic DAGs are needed for M-RAD-05 serendipity and House Compiler, not for VSME. Container executor and pluggable storage are needed for cloud deployment, not for single-VM VSME. Time-travel UI is valuable but not blocking.
**Consequences:** Direct path from hardening to VSME with no runtime capability work in between. M-RAD-05 serendipity remains deferred until dynamic DAGs land.

## D-2026-04-02-021: Op heartbeats demoted to demand-driven
**Status:** active
**Context:** Radar's longest ops are LLM summarize calls (~30s). Port executor already has configurable timeouts. Heartbeats distinguish "hung" from "slow but working" — valuable for ops running minutes/hours (GPU training, heavy geometry), not for 30-second LLM calls.
**Decision:** Demote heartbeats to demand-driven. Trigger: when ops legitimately run for minutes/hours.
**Consequences:** Timeout handling is sufficient for Radar and VSME. Heartbeats earn their place with House Compiler or ML training packs.

## D-2026-04-04-022: Architecture truth is split into live, decided-next, and historical sources
**Status:** active
**Context:** Architecture, roadmap, and execution-truth work were drifting because current behavior, approved next-state design, and historical snapshots were living side by side as if they had the same authority. That makes it too easy for agents or humans to cite stale documents as current contract.
**Decision:** Adopt an explicit truth hierarchy:
- `docs/architecture/` contains only live or decided-next material
- `docs/history/` stores superseded architecture docs and snapshots
- `work/roadmap.md` is the only current sequencing source
- compatibility shims are banned by default and allowed only as documented temporary exceptions with removal triggers
- AI instruction changes land in `.ai-repo/` and are propagated by `./.ai/sync.sh`, not by hand-editing generated files
**Consequences:** Architecture docs now carry frontmatter describing truth class and ownership. Historical material keeps chronology without pretending to be current. Completion status and semantic quality stay separate. Migration glue becomes visible, bounded, and reviewable.

## D-2026-04-05-023: Radar run identity is runtime-owned; dedup remains single-op side-effecting with recorded replay
**Status:** active
**Context:** M-TRUTH-03 needs Radar to stop fabricating runtime identity in the pack. Before this slice, `Radar.plan/1` injected synthetic `run_id` literals into both `dedup` and `compose_briefing`, `ComposeBriefing` consumed that plan-time value directly, and `Dedup` both mutated LanceDB history and stamped persisted rows while still advertising `:pure` semantics.
**Decision:** Runtime `ExecutionContext` is the sole source of Radar run identity. `ComposeBriefing` is migrated to an explicit context-aware execution spec and reads `run_id` from the runtime context, not plan inputs. While Radar dedup still remains one op that both classifies items and mutates LanceDB history, it is now classified truthfully as `:side_effecting` with `cache_policy: :none` and `replay_policy: :replay_recorded`, and it consumes runtime context for persisted `run_id` and `started_at` instead of plan-synthesized values.
**Consequences:** Radar plans no longer fabricate a value named `run_id`. Replay keeps rendered briefings identical because context-aware composition reuses the stored source execution context rather than inventing a replay-time replacement. Dedup no longer claims pure/cacheable semantics, and replay avoids re-running LanceDB writes while still supplying recorded outputs downstream.

## D-2026-04-08-024: DAG bench relaxes the hard-determinism contract
**Status:** active
**Context:** M-DAGBENCH-02 inherited Liminara's hard reproducibility contract verbatim: "two runs with the same seed + config produce byte-identical snapshots." Liminara proper is a runtime for reproducible nondeterministic computation — every recorded decision must replay exactly. The dag-map bench is a different kind of thing: a developer-iteration tool that searches for good layout parameters via GA + human pairwise votes. Strict byte-identical reproducibility is nice to have but not load-bearing. What matters for the bench is *convergence*: if you rerun with a different seed, you should land in a similar-quality region of the elite set, even if the specific genomes differ.
**Decision:** The bench GA relaxes the "byte-identical across runs" contract to a "convergence within tolerance" contract. Specifically:
- Existing byte-identical tests are rewritten as "two runs with the same seed reach comparable final fitness within a documented tolerance" tests.
- Seeded PRNG stays in place for debugging, but is not load-bearing for test assertions.
- The `Math.random()`-free hygiene checks stay as unit tests (they're cheap and catch a real class of bug) but their purpose is "no implicit randomness" not "strict reproducibility."
- M-03 features (vote-count temporal decay in the BT refit, fork-per-generation PRNG in the runner) can use either vote-count OR wall-clock decay — the previous determinism-driven preference for vote-count is lifted, though vote-count remains the recommendation for *interpretability*.
- End-to-end determinism ACs in the M-03 spec become "end-to-end convergence" ACs.
**Consequences:** The bench is free to use wall-clock reads, nondeterministic operators (e.g., timing-sensitive work queues), and future LLM voter integrations without breaking test contracts. The test suite still catches regressions by asserting final-fitness convergence, not exact byte equality. This decision does NOT relax Liminara's runtime determinism contract — Liminara runtime code continues to record every nondeterministic decision for exact replay. The relaxation applies only to `dag-map/bench/`, which is a gitignored developer tool.

## D-2026-04-08-025: DAG bench energy function scope is metro-map DAGs only
**Status:** active
**Context:** dag-map exports three layout engines: `layoutMetro` (transit-map aesthetic, small circle stations, grid placement), `layoutFlow` (process-mining style, dot + info card, obstacle-aware routing), and `layoutHasse` (lattice diagrams). The bench's 8 energy terms (stretch, bend, crossings, monotone, envelope, channel, repel_nn, repel_ne) were designed around metro semantics: stations are points, polylines are straight lines between route waypoints, edges don't route around obstacles. When we considered rewriting `bend` / `repel_ne` for "card-avoidance" routing (Celonis-style), we realized that aesthetic belongs to `layoutFlow`, not `layoutMetro` — and the bench currently only evaluates `layoutMetro` output.
**Decision:** The bench's scope is **metro-map DAG layouts only**. Specifically:
- The evaluator calls `layoutMetro(dag, opts)` and scores its output. `layoutFlow` and `layoutHasse` are out of scope.
- `routing_primitive` is hardcoded to `'bezier'` in the evaluator's DEFAULT_RENDER (see also D-2026-04-08-026).
- `bend` is kept in the energy function because it legitimately measures smooth passage of routes through stations — the concept is correct for metro-map aesthetic.
- Card-aware evaluation (label boxes as obstacles, `edge_through_card` term) is explicitly deferred to a future milestone that targets `layoutFlow`, if we ever scope it.
- Flow-layout GA evaluation becomes M-DAGBENCH-05 (tentative) or later, after M-03 and M-04.
**Consequences:** The M-03 Tinder UI is optimizing for metro-map taste, not process-map taste. This is a narrower target but matches dag-map's primary aesthetic and the fixtures we actually have. The bench's ceiling for improvement is bounded by what `layoutMetro` can produce — escaping the station-on-grid constraint would be a change to `layoutMetro` in the dag-map codebase (same owner's repo), not a bench change.

## D-2026-04-08-026: DAG bench genome is 8 Tier 1 fields, Tier 2 removed
**Status:** active
**Context:** Empirical sensitivity analysis on 2026-04-08 (`bench/scripts/sensitivity.js`) measured the scalar fitness delta of mutating each Tier 1 field by ±1σ across the full 34-fixture corpus. 7 of the 15 original Tier 1 fields produced zero delta: `render.trunkY` (the surprise — translation-invariant in every energy term), `render.progressivePower`, `render.cornerRadius` (both SVG-curve-only, don't affect polyline geometry), and the 4 `lane.weight_*` fields (wired into `toEvaluatorGenome` output but never consumed by the evaluator). Tier 2 was also effectively dead: `routing_primitive` was the only field the evaluator read, and with the bench scope locked to bezier (D-2026-04-08-025) it became a constant; `route_extraction` and `convergence_style` were never consumed.
**Decision:**
- Tier 1 shrinks to 8 live fields: `render.layerSpacing`, `render.mainSpacing`, `render.subSpacing`, `render.scale`, `energy.stretch_ideal_factor`, `energy.repel_threshold_px`, `energy.channel_min_separation_px`, `energy.envelope_target_ratio`.
- Tier 2 is removed entirely. The genome is `{tier1}` only.
- `routing_primitive` is locked to bezier via the evaluator's DEFAULT_RENDER.
- The "island per routing primitive" semantics are renamed to "random subpopulations with ring-topology introgression migration" (D-2026-04-08-027). The plumbing stays the same; the partitioning criterion changes.
**Consequences:** Mutation budget is no longer wasted on dials that cannot move the fitness. The GA's effective search space is the 8 live fields. The default weights vector still calibrates cleanly against the 8-field genome (re-verified via `scripts/sensitivity.js` after the cleanup). If a future milestone reintroduces multiple routing primitives, Tier 2 comes back together with the island-per-primitive semantics. The dead `trunkY` option in dag-map's own `layoutMetro` is a quiet API wart worth cleaning up in the dag-map codebase as a follow-on chore.

## D-2026-04-08-027: DAG bench islands use ring-topology introgression migration
**Status:** active
**Context:** M-DAGBENCH-02 built an island model with "one population per routing primitive" semantics — a Tier 2 mutation that flipped `routing_primitive` migrated the individual to the matching island. When Tier 2 was removed (D-2026-04-08-026), that mechanism lost its partitioning criterion and the island infrastructure became a single-population wrapper. The user asked whether there was a way to preserve long-lived lineages with occasional cross-pollination, like Neanderthal × Sapiens interbreeding.
**Decision:** The bench uses a standard **island model GA with low migration rate, ring topology**, biologically equivalent to *allopatric speciation with introgression*:
- **Islands are random subpopulations** (default 3), assigned at initialisation. Islands are no longer defined by any genome content.
- **Ring topology**: island i sends migrants to island (i+1) mod N. Each event moves gene material one hop around the ring.
- **Migration every `migrationInterval` generations** (default 10), chosen to give each island several generations of isolated evolution between contact events.
- **Migration rate** is a fraction of the population per event (default 0.05 = 1 individual per 20-sized population). Migrants are picked via tournament selection (best individuals migrate) and placed in the target island with their `island` field rewritten.
- **No replacement policy** — migrants are appended; population counts stay constant across islands because every island loses one migrant out and gains one migrant in per event.
- **Single-generation migration only**: migrants that land on a new island don't migrate again in the same event. A migrant in island j+1 has to wait for the next migration event before potentially moving on.
- **Config is optional**: if `migrationInterval` is 0, null, or missing, migration never fires. This preserves backward compatibility with existing test configurations.
**Consequences:** The bench now supports long-lived lineage structure (each island evolves mostly on its own) with rare cross-pollination (introgression every N generations). This is standard EA literature territory — "coarse-grained parallel GA with sparse migration" — and preserves diversity better than a single flat population would. The migration code is ~80 lines in `bench/ga/migration.mjs`. If a future milestone wants different topologies (full mesh, star, random), the primitive is in place.

## D-2026-04-08-028: LLM voter deferred to a future bench milestone
**Status:** active
**Context:** During M-03 spec drafting, we considered adding LLM-based pairwise voting as either (a) a replacement for the human voter, (b) a synthetic voter that pre-warms the BT refit before the human session starts, or (c) a curator that ranks elites and emits derived pairwise votes.
**Decision:** LLM voting is deferred to a future milestone (tentative M-DAGBENCH-05 or later), after M-03 (human voting + BT refit) and M-04 (external corpora) have landed. Reasons:
- Adding LLM voting during M-03 would blur the debuggability of the refit loop.
- Cost and latency are non-trivial (~500-2000 ms per LLM call, ~$20-100 per long run).
- The LLM's aesthetic priors are themselves suspect and would need calibration against the project owner's taste — which is exactly what the Tinder UI already does for the human voter. Stacking two BT refits compounds that calibration problem.
- Liminara's decision-recording infrastructure (where recorded nondeterministic decisions replay for free) would be the right home for LLM verdicts, but the bench doesn't use that infrastructure and wiring it in is a scope expansion.
**Consequences:** M-03 is human-only. Adding LLM votes later is architecturally cheap — the BT refit doesn't care where votes come from, it just consumes pairwise preferences. An LLM voter process would POST to the same `/vote` endpoint the UI uses, with `voter: "llm-<model>"` in the vote record.

