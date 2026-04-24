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
**Status:** superseded by D-2026-04-22-027
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

## D-2026-04-20-025: `run_partial` is a first-class terminal event type
**Status:** active
**Context:** M-WARN-04 merged_bug_001 — pre-fix, `Run.Server.finish_run/2` emitted the same `"run_failed"` event for both `:failed` and `:partial` terminal statuses. Every consumer that derived degraded from event type (ViewModel, RunsLive.Show, RunsLive.Index) collapsed `:partial`-with-warnings to `:failed` and dropped the degraded signal, creating a cross-layer disagreement between the CLI's `Run.Result.degraded` (correct) and every web/observation surface (wrong).
**Decision:** Add `"run_partial"` as a distinct terminal event type alongside `"run_completed"` and `"run_failed"`. Event type is a 1:1 mirror of `Run.Result.status` (`:success` → `run_completed`, `:partial` → `run_partial`, `:failed` → `run_failed`). Every consumer switching on event type grows a matching `run_partial` clause. No payload-field discriminator.
**Consequences:** Every runtime/observation/web consumer is explicit about which terminal state it's handling — no downstream heuristic re-derivation. E-21a ADR-OPSPEC-01 will codify `run_partial` alongside `run_completed` / `run_failed` in the canonical event taxonomy. Any tool that reads persisted event logs must recognise all three terminal types; `result_from_event_log/1` and `rebuild_from_events/2` already do.

## D-2026-04-20-026: No backward-compat shims for in-flight contract fixes
**Status:** active
**Context:** M-WARN-04 landed four contract-tightening bugfixes (string-keyed warning payloads on the wire, new terminal event type, direct-assign warning_count, per-node warnings on the fallback path). Each fix made some pre-existing test fixture or helper non-compliant with the new spec. The tempting alternative was to add defensive accept-both clauses in production code (e.g. `Map.get(payload, "warnings") || Map.get(payload, :warnings)`) so legacy fixtures kept passing.
**Decision:** Production code does not carry fallback clauses to tolerate legacy fixture shapes. When a fixture becomes non-compliant with a new spec, the fixture is migrated to match the spec. Applies to all of M-WARN-04's fixes and, by precedent, to future in-flight contract work. Recorded explicitly as a rule rather than an ad-hoc preference because the user reaffirmed it multiple times through the epic.
**Consequences:** Production code stays honest about what it accepts — no accept-both paths that pretend to enforce a contract while silently accepting its violation. Test helpers that construct protocol-shaped maps carry the full burden of spec compliance; when the spec changes, the helpers change. Persisted on-disk event logs under `runs/` in old shape are treated as disposable test artefacts. E-21a contract work should apply the same rule: no shim layer between authored packs and the runtime.

## D-2026-04-08-024: Pack data paths and Python environments must be explicit
**Status:** active
**Context:** D-009 defined explicit persistent paths for the core artifact and run stores, but it did not define a full runtime-wide contract for pack-owned durable state. That gap already surfaced in practice: Radar semantic history drifted into `_build` instead of a declared data directory. In parallel, Python ops are a first-class runtime capability, but the repo had no explicit rule for whether Python should be ambiently available everywhere or managed through owned environments. The devcontainer installed Python and `uv`, but only bootstrapped `integrations/python/`, not the runtime Python op environment.
**Decision:** Durable pack-owned state must be explicitly configured in both development and deployment. In development, the default shape is `runtime/data/<pack>/...`. In deployment, the default shape is `/var/lib/liminara/<pack>/...` unless an operator provides another explicit persistent root. Durable pack state may not silently fall back to `System.tmp_dir!/0`, build output, or tool caches. Today, durable pack paths are modeled as explicit pack-owned config keys; a future runtime-owned persistent root may derive them, but hidden inference is not the contract. Python remains available in the devcontainer as a platform capability, but there is no ambient repo-wide Python environment contract. `runtime/python/` is the standard runtime-managed Python environment for Python ops and is bootstrapped via Astral `uv`. `integrations/python/` remains its own explicit `uv`-managed environment for the SDK and integration surface.
**Consequences:** Pack and runtime code must declare durable paths instead of deriving them from app directories, tmp, or build output. Recorded plans should surface resolved durable pack paths when they materially affect execution. Additional Python environments must have explicit ownership and documentation instead of quietly becoming shared repo state. The devcontainer bootstrap now prepares both the runtime Python op environment and the integration/SDK Python environment.

## D-2026-04-22-027: PackRegistry promotion trigger swap — admin-pack (E-22), not VSME
**Status:** active
**Supersedes:** D-2026-04-02-018
**Context:** D-018 pinned the PackRegistry promotion trigger to VSME on the reasoning that two real packs needing runtime-level instance management would be the right forcing function. Since then, E-21 (Pack Contribution Contract) was scoped with admin-pack (E-22) as the second-pack validator and pulled PackRegistry forward to land with the pack-contract work. `work/roadmap.md` Phase 5c calls this out explicitly as a D-012 exception ("PackRegistry generalization needs separate justification" → admin-pack is that justification). Leaving D-018 `active` while the actual trigger has moved creates a silent disagreement between the decisions log and the roadmap.
**Decision:** PackRegistry promotes to a runtime-level registry in E-21b (M-PACK-B-01), validated by admin-pack (E-22) as the second real pack. VSME is no longer the PackRegistry forcing function; it becomes the first compliance pack built on top of the pack-contract surface that E-21 + admin-pack have already landed.
**Consequences:** No change to shipped code — this decision ratifies the sequencing already documented in `work/roadmap.md:93-94` and E-21's parent epic. D-018's underlying insight (ship the narrower abstraction until two packs force it) still holds; the two packs are now Radar + admin-pack, not Radar + VSME. Future decisions that reference D-018 as a justification should reference D-027 instead. Caught by ultrareview F-M2.

## D-2026-04-22-028: ADR numbering is monotonic `ADR-NNNN`, assigned at write time
**Status:** superseded by D-2026-04-23-030
**Context:** Framework bump on 2026-04-22 (`.ai` at `9ef0b5e`, PR #19) locked the canonical ADR filename convention to `ADR-NNNN-<slug>.md` under `docs/decisions/`, with `N` monotonic across the whole repo (no keyword-scoped sub-sequences). Pre-bump, the repo had `ADR-001` and `ADR-007` (gap in sequence because earlier planning assumed keyword-scoped allocation). E-21 specs introduce 14 keyword-scoped placeholder IDs — `ADR-REPLAY-01`, `ADR-MANIFEST-01`, `ADR-WIRE-01`, etc. — for ADRs that have not been written yet.
**Decision:** `ADR-007` is renamed to `ADR-002` as part of the 2026-04-22 framework bump (only two ADRs exist, so a clean renumber is cheap). Going forward, each new ADR claims the next free `ADR-NNNN` at the moment it is written. E-21's keyword-scoped placeholders (`ADR-REPLAY-01`, `ADR-MANIFEST-01`, `ADR-LA-01`, `ADR-PLAN-01`, `ADR-WIRE-01`, `ADR-OPSPEC-01`, `ADR-TRIGGER-01`, `ADR-FILEWATCH-01`, `ADR-FSSCOPE-01`, `ADR-SECRETS-01`, `ADR-EXECUTOR-01`, `ADR-REGISTRY-01`, `ADR-SURFACE-01`, `ADR-MULTIPLAN-01`, `ADR-CONTENT-01`) remain in E-21 planning docs as working titles. When each is actually authored, it takes the next monotonic `ADR-NNNN` and its frontmatter includes the original keyword name as a cross-reference.
**Consequences:** No mass-renumber of E-21 placeholders now — would be bookkeeping theatre on 14 ADRs that don't yet exist, and would force a write order that may not match development reality. Authors of new ADRs must grep `docs/decisions/` for the next free number before claiming it. Agent-history entries (e.g. `work/agent-history/E-21-ultrareview-docs-drift/`) that reference the pre-rename `ADR-007` are not rewritten — they're frozen session records and accurate at time of writing. **Superseded 2026-04-23:** this decision misread the framework — the framework locks the **ID** shape to `ADR-\d{4}` (4-digit zero-padded) and the **filename** to `NNNN-<slug>.md` on disk (no `ADR-` prefix). See D-2026-04-23-030 for the corrected reading and the rename action.

## D-2026-04-22-029: Sub-epic pattern retired after E-21
**Status:** active
**Context:** E-21 (Pack Contribution Contract) is structured as an umbrella epic composed of four sub-epics (E-21a through E-21d), each with its own spec file, `parent: E-21-pack-contribution-contract` frontmatter, and `composed_of:` listing on the umbrella. This predates the 2026-04-22 framework bump, which codifies a flat epic shape (`id`, `status`, `depends_on`, `completed`) with milestones as the next-level-down unit. The umbrella pattern (`parent`, `composed_of`, `phase` frontmatter fields) is not in the framework `epic-spec.md` template and not prescribed anywhere in `.ai-repo/`.
**Decision:** Sub-epics are an anti-pattern in Liminara going forward. After E-21, new epics use the flat framework shape: a single `epic.md` per epic directory, milestones as the unit of decomposition. The `parent`, `composed_of`, and `phase` frontmatter fields are not added to any template and will not appear in new epic specs. E-21 is grandfathered — its existing sub-epic structure and extra frontmatter fields remain as-is; it is not retrofitted to the flat shape. The `status: planning` value on E-21 (and any other pre-bump epic that used it) is collapsed to `status: draft` at the 2026-04-22 template adoption, since `planning` is not in the framework vocabulary (`draft | approved | in-progress | complete`) and we treat it as a synonym for `draft`.
**Consequences:** Readers of E-21 see legacy fields that are not in any template — this decision is the explicit "do not copy this pattern" signal. Future epics that feel like they want sub-epics should instead be either (a) one epic with more milestones, or (b) several sibling epics with a sequencing note in `work/roadmap.md`. The `.ai-repo/templates/` directory stays empty (no overrides created) because the only divergences from the framework templates — sub-epic fields and the `planning` status — are being retired, not formalised.

## D-2026-04-23-030: ADR filename is `NNNN-<slug>.md`, ID is `ADR-NNNN` (4-digit zero-padded) — supersedes D-028
**Status:** active
**Supersedes:** D-2026-04-22-028
**Context:** Framework bump on 2026-04-23 (`.ai` at `87fd040`) re-ran `migrate.sh` and surfaced §adr-convention drift on the two existing ADRs (`ADR-001-failure-recovery-strategy.md`, `ADR-002-visual-execution-states.md`). Investigation against the framework sources shows D-028 misread the 2026-04-22 framework change: `.ai/paths.md:23` and `:45` specify the filename shape as `NNNN-<slug>.md` (no `ADR-` prefix on disk); `.ai/rules.md:67` and `.ai/paths.md:43-44` specify the **ID** shape as `ADR-\d{4}` (4-digit zero-padded, stored in frontmatter and used for cross-references). The two conventions are intentionally separate: the directory `docs/decisions/` already scopes what these files are, so the filename carries only the sequence number plus slug, while the `ADR-` prefix lives on the ID for unambiguous prose references like "see ADR-0002." The pattern matches the `adr-tools` / `log4brains` / ThoughtWorks ecosystem standard (Nygard's 2011 post prescribes the decision-record structure but not a filename pattern; `adr-tools` is where `NNNN-<slug>.md` comes from).
**Decision:** The two existing ADRs are renamed on 2026-04-23 as part of the framework bump to `87fd040`:
- `docs/decisions/ADR-001-failure-recovery-strategy.md` → `docs/decisions/0001-failure-recovery-strategy.md`, frontmatter `id: ADR-001` → `id: ADR-0001`, title heading updated.
- `docs/decisions/ADR-002-visual-execution-states.md` → `docs/decisions/0002-visual-execution-states.md`, frontmatter `id: ADR-002` → `id: ADR-0002`, `renamed_from: ADR-007` → `renamed_from: [ADR-007, ADR-002]`, title heading updated.
Inbound references in live docs (`work/gaps.md`, `work/done/E-09-observation-layer/epic.md`) are updated to the new filename and 4-digit ID. Frozen session records under `work/agent-history/` are **not** rewritten — they remain accurate at time of writing (same principle D-028 applied to the 2026-04-22 renumber). E-21's 14 keyword-scoped placeholder IDs (`ADR-REPLAY-01`, `ADR-MANIFEST-01`, etc.) are not yet files under `docs/decisions/` and so are not affected by the filename convention; each claims the next free `ADR-\d{4}` when actually authored.
**Consequences:** `migrate.sh §adr-convention` stops flagging the two existing ADRs. The `renamed_from` chain on `ADR-0002` preserves full history (`ADR-007` → `ADR-002` → `ADR-0002`). Going forward: new ADR filenames are `NNNN-<slug>.md`; frontmatter `id:` is `ADR-NNNN` (4-digit). Authors grep `docs/decisions/*.md` for the next free number before claiming it. D-028's misread of "the framework locks `ADR-NNNN-<slug>.md` as the filename" is explicitly retracted; the framework locks filename and ID as two separate shapes.

