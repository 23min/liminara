# Gaps

Discovered work items deferred for later.

## wf-graph apply skips spec frontmatter for flat-layout repos (filed upstream)
**Discovered:** 2026-04-25 (M-PACK-A-01 start-milestone, status flip via `wf-graph apply --patch`)
**Relates to:** `.ai/tools/wf-graph/internal/patch/write.go:124,137`, `.ai-repo/config/artifact-layout.json`
**Severity:** Low — graph.yaml updates correctly; only the spec-frontmatter side of the atomicity contract is broken. Hand-edit is a one-line workaround.
**Filed upstream:** [ai-workflow#80](https://github.com/23min/ai-workflow/issues/80)
**Items:**
- Tool unconditionally appends `/spec.md` to the node's `path` field, expecting folder-form `<id>/spec.md` shape. Liminara uses flat `<id>-<slug>.md` per `milestoneSpecPathTemplate` in `.ai-repo/config/artifact-layout.json`.
- Workaround: hand-edit the spec frontmatter after `wf-graph apply --patch` succeeds for graph.yaml. Use case is rare (only at milestone status flips during start/wrap).
**Trigger:** consume the upstream fix when ai-workflow#80 lands and the framework `.ai/` is synced. No Liminara-side action needed in the meantime.

## wf-graph diff-roadmap misses letter-suffixed epic IDs (filed upstream)
**Discovered:** 2026-04-25 (M-PACK-A-01 wrap, post-wrap graph audit)
**Relates to:** `wf-graph diff-roadmap` prose-side ID extraction; `work/roadmap.md` line 133 references E-11b but the tool's regex stops at `E-\d+` and doesn't match the letter suffix
**Severity:** Low — false-positive `graph_only` reports for any epic ID with a letter suffix (E-11b today; legacy E-21a/b/c/d also affected). No real drift; the tool is just under-recognizing. Workaround is manual prose-vs-graph verification.
**Filed upstream:** [ai-workflow#88](https://github.com/23min/ai-workflow/issues/88)
**Items:**
- Suggested upstream fix: extend regex from `E-\d+` to `E-\d+[a-z]?` (or `E-\d+\w*` for multi-character suffixes).
- Liminara has D-2026-04-22-029 retiring sub-epics as a pattern after E-21, but legacy E-11b + grandfathered E-21a/b/c/d still need correct diff handling until the umbrella shape retires.
**Trigger:** consume the upstream fix when ai-workflow#88 lands and the framework `.ai/` is synced. No Liminara-side action needed in the meantime.

## Framework `.ai/` sync to upstream HEAD pending — pulls PR #72 deliverables on-disk
**Discovered:** 2026-04-25 (M-PACK-A-01 AC7+AC8 authoring; upstream PR #72 closed mid-milestone)
**Relates to:** [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37) / PR #72, `.ai-repo/skills/design-contract.md` (AC7), `.ai-repo/rules/contract-design.md` (AC8), `work/decisions.md` D-2026-04-25-033
**Severity:** Low — milestone deliverables stand alone; the upstream files are forward-references that will exist on-disk after the next routine framework sync.
**Items:**
- `.ai/skills/design-contract.md` (tech-neutral skill body) — referenced by AC7 overlay + AC8 reviewer rule
- `.ai/docs/recipes/design-contract-cue.md` (CUE recipe) — referenced by AC7 overlay
- `.ai/templates/adr.md` (additive `contract:` frontmatter block: schema, fixtures, worked_example, reference_implementation, schema_version) — needed by M-PACK-A-02a's first ADRs
- `.claude/skills/design-contract/SKILL.md` (generated folder-form output) — produced by `./.ai/sync.sh` after the framework pull
**Trigger:** routine framework sync. M-PACK-A-02a authors should verify the four files exist on-disk before drafting their first ADR; if not, run `bash .ai/sync.sh` (and pull the framework submodule first).

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

## Op sandbox: layered isolation not implemented
**Discovered:** 2026-04-02 (M-RAD-03, live run exposed VIRTUAL_ENV leakage)
**Relates to:** D-2026-04-02-011, E-10 Port Executor, E-12 Op Sandbox
**Severity:** Architectural gap — not blocking Radar dev (all ops are ours) but blocks production use and untrusted ops
**Items:**
- Clean env whitelist in Executor.Port (layer 1) — quick fix, could be a patch
- Audit hooks in liminara_op_runner.py (layer 2) — catches Python-level violations
- Landlock integration (layer 3) — kernel-enforced, needs sandbox module
- Op capability declarations in Pack behaviour (needs_network, needs_filesystem, allowed_paths)
- Sandbox config recorded in run events (provenance)
- Documentation of isolation model in docs/architecture/
- Evaluate: simple Python ops (normalize, rank, summarize) as Elixir :inline candidates

## Pack-owned durable path contract needs implementation follow-through
**Discovered:** 2026-04-08 (follow-up from LanceDB path review)
**Relates to:** D-2026-04-08-024, deployment planning
**Severity:** Implementation gap — the contract is now defined, but existing runtime and pack paths still need alignment
**Items:**
- Audit existing pack and UI/runtime fallbacks that still derive durable locations from `System.tmp_dir!/0`, `Application.app_dir/2`, or `_build`
- Migrate Radar LanceDB to the decided durable path contract and decide whether to preserve or discard existing local drift data
- Ensure recorded plans and runtime metadata surface resolved durable pack paths consistently when those paths materially affect execution
- Make any future pack-specific durable directory explicit in both dev and deployment config from day one

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
**Relates to:** 01_adjacent_technologies.md §11
**Severity:** Future inspiration — not blocking any current work
**Items:**
- **Connector protocol for side_effecting ops** — standardized interface for ops that wrap external systems (email, Slack, webhooks, APIs). Not Camunda's specific connectors, but the pattern of a common protocol for integration ops. Maps to `side_effecting` determinism class.
- **Run inspection tooling** — Camunda's Operate shows where a process instance is, what's blocked, and why. Liminara's observation layer (A2UI) already has the data; surfacing "where is this run stuck and why?" as a first-class view would be high value. No instance mutation (that conflicts with immutability).
- **Process mining over historical runs** — Camunda's Optimize analyzes completed process instances for bottlenecks and deviations. Liminara's JSONL event logs are already pm4py-compatible (see 01_adjacent_technologies.md §2). A tool or future pack that runs statistical analysis over historical runs to find slow ops, common failure patterns, and plan deviations.
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

## ADR-0002 Phases 2 & 3 — cache-aware and replay-aware visual states
**Discovered:** 2026-03-23 (ADR-0002 body); formally logged 2026-04-22 (F-M6 promotion)
**Relates to:** ADR-0002 (originally ADR-007, renumbered to ADR-002 on 2026-04-22, zero-padded to ADR-0002 on 2026-04-23 per framework `ADR-\d{4}` / `NNNN-<slug>.md` convention), Observation layer, future cache + replay integration
**Severity:** UX polish — Phase 1 (dim pending nodes) shipped in M-OBS-05a and is sufficient for day-to-day DAG legibility. Phases 2-3 would disambiguate "not yet reached" from "has a cached result" and "will replay" from "will discover" — useful when cache + replay become visually important.
**Context:** ADR-0002 was promoted from draft → accepted on 2026-04-22 (F-M6). Phase 1 is in production. Phases 2 and 3 were explicitly deferred in the ADR body to "Phase 5: Radar or later"; captured here so planners don't have to read the ADR to see the deferred work.
**Items:**
- Phase 2 — cache-aware states: `Observation.Server` queries the artifact cache for each pending node; view gains `cache_available: true`; dag-map renders a distinct visual (dotted outline or badge). Requires a cache-lookup API in `Observation.Server`.
- Phase 3 — replay-aware states: `Decision Store` queried for each recordable/side-effecting node; view gains `replay_available: true`; visual distinction for "will replay" vs "will discover." Requires a Decision-Store lookup API in `Observation.Server`.
- Revisit trigger: when replay/cache integration work is scheduled, or earlier if operator feedback demands it.

## Pack-contract comparables audit — standalone landing page; deferred until pressure emerges
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 27)
**Relates to:** E-21a (ADR authoring), `epic.md:202` comparables citation, future contract-facing contributors
**Severity:** Low — most of the useful comparable context is already embedded inline in per-ADR content requirements (Findings 8, 13, 14, 15, 17). The standalone doc's main value is helping *multiple* reviewers / contributors converge on a shared mental model; for single-author + occasional-reviewer current state, the inline context is sufficient.
**Context:** E-21's parent epic cites Argo / Flyte / Kubeflow / GitHub Actions / N8N / Zapier / Windmill as data-contract workflow comparables but no standalone comparison doc exists. Each E-21a ADR that picks a design (manifest format, schema evolution pattern, replay semantics, content-type identifier shape, trigger restart semantics, secret observability) now carries a design-space shortlist inline — ADR-EVOLUTION-01's {P1 strict major match / P2 multi-historical-schema / P3 unify-or-fail / P4 pack-declared range}; ADR-TRIGGER-01's fire-and-forget decision with E-14 escalation named; ADR-FSSCOPE-01's two-surface model vs Landlock; ADR-SECRETS-01's Vault / Key Vault / Doppler delivery adapters + runtime-mediated-proxy deferral; cross-version replay's Bazel / Flyte / Nix-Guix / Dagger / Argo industry-name landscape. Collectively these inline shortlists do most of what a standalone comparables doc would do; the remaining gap is a single-glance landing page for orientation.
**What a standalone comparables pass would produce (~1 day if done):**
- `docs/analysis/pack-contract-comparables.md`: 3 comparables (Argo / Flyte / Temporal) × 6 axes (contract shape / task declaration style / versioning model / replay semantics / multi-language support / pack registration). ~500 lines.
- Scope to decisions that could realistically be revisited (manifest format, schema evolution, replay, versioning); skip baked-in decisions (CUE, Elixir runtime, content-addressed artifacts).
- Each ADR cites relevant rows where Liminara diverges / matches.
**Trigger for revisit:** any one of —
1. Reviewers or contributors ask "how does this compare to X?" more than twice across different ADRs, signaling a recurring orientation gap the inline shortlists aren't closing.
2. A second contract-facing contributor joins (non-author review cadence means shared mental model matters more).
3. A specific design choice in an ADR authoring cycle surfaces uncertainty that an explicit comparable would resolve.
4. An external adopter (someone building on Liminara's contract) asks about comparability for interop reasons.
**Explicit non-goal:** Speculative comparables research before a trigger fires. The inline shortlists in Findings 8 / 13 / 14 / 15 / 17 retire most of the risk; build the standalone doc when pressure calls for it.

## `liminara_widgets` extraction — in-tree for E-21c; extract when a second consumer arrives
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 24)
**Relates to:** E-21c M-PACK-C-02 (`liminara_widgets` lands in-tree), future submodule + Hex release
**Severity:** Low — in-tree indefinitely is fine for the current deployment; the discipline is forward-compatibility with extraction, not immediate extraction.
**Context:** `liminara_widgets` ships in E-21c M-PACK-C-02 as five generic A2UI widgets (`data_grid`, `json_viewer`, `dag_map` embedder, `content_card`, `banner`) with zero Liminara domain types by design. The library is **structurally reusable** by any A2UI consumer, but no external consumer exists today. Name chosen (`liminara_widgets` not `liminara_ui`): honest about being a widget library; doesn't mislead readers into expecting `%Run{}`/`%Artifact{}`-aware components (which a `liminara_ui` name would imply); doesn't collide with `ex_a2ui` naming the way `liminara_a2ui` would.
**MVP decision:** keep in-tree inside the Liminara umbrella (`runtime/apps/liminara_widgets/` or equivalent). Reasons:
- No external consumers today → extracting now is speculative investment.
- `boundary` hex lib (ADR-BOUNDARY-01, lands in M-PACK-B-01a) enforces the zero-domain-types rule structurally via compile-time checks; the type-hygiene guarantee doesn't require submodule isolation.
- In-tree keeps E-21c M-PACK-C-02's scope smaller — no separate Hex release cadence, no separate CI, no separate v0.1 → v1.0 maturity arc.
**Forward-compatibility discipline** (what makes the extraction cheap when it happens):
- Module docs written Hex-style (each public module documented; examples tested).
- Public API surface stable enough that extraction is a git-filter-branch, not a rewrite.
- No `liminara_core` / `liminara_observation` / `liminara_web` imports — already enforced by `boundary`.
- JS bundle builds independently (no Liminara-specific build-time injections).
**Extraction triggers (named; any one suffices):**
1. Second live consumer emerges — a Liminara-adjacent project wants to use the widgets without cloning Liminara (your own future side project, an `ex_a2ui` community widget-catalog contribution, a VSME / House Compiler shared visualization layer that spans packs).
2. Hex community asks — someone outside Liminara requests widget-library publication.
3. Widget library grows past ~15 widgets — at that size the library is probably doing enough to stand alone.
**Extraction work (when triggered):** cut submodule at `github.com/23min/liminara_widgets` (or a rename to `a2ui_widgets` / `ex_a2ui_widgets` if shedding the Liminara brand is desired at extraction time), `git filter-branch` to preserve history, Hex release v0.1.0, Liminara `mix.exs` consumes the Hex version. Estimated ~1 day once a trigger lands.
**Explicit non-goal:** Extracting before a trigger arrives. No speculative submodule + Hex release "because it might be useful someday."

## Cross-version pack replay semantics — design space, not decided
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 17)
**Relates to:** E-21a ADR-REPLAY-01 (scope trimmed — pack-version skew removed), E-21b M-PACK-B-01b (provenance recording lands), E-17 Container Executor (natural home for hermetic replay), future VSME / DPP compliance epics
**Severity:** Low today — Radar is one continuous version; single-operator deployments don't need cross-version replay. Rises to Medium when first pack ships a major-version bump mid-lifecycle, or when a regulator asks for byte-exact historical replay.
**Context:** Today Liminara replays a run against whatever pack version is currently loaded. Works because the pack version at replay time matches the pack version at run-production time (one continuous Radar). When packs evolve mid-lifecycle (admin-pack ships v2.0; old runs from v1.5 exist in the event log), "what does replay mean?" becomes a real question. E-21 deliberately does not pick a policy — no pack has surfaced concrete pressure, and hermetic replay is expensive to bolt onto `:inline` + `:port` executors.
**The provenance layer ships in E-21b** (M-PACK-B-01b): each run's initial event records `pack_version` + `git_commit_hash`. This is cheap and unlocks audit workflows — "which code produced this run" is a recorded fact — without requiring the runtime to execute old code. **Provenance is separate from replayability**: most compliance disputes are resolved by reading the old code's source (by git hash), not by re-executing it in production.
**Design space (not decided; revisit when pressure surfaces):**
1. **Single-version-with-provenance (current plan, post-E-21).** Runtime loads one pack version; replay uses that version; `pack_version` + `git_commit_hash` in events support "read the source" audit. Simplest. Matches the ship-when-you-need-it E-21 scope.
2. **Compatibility-range replay.** Pack declares `replay_compat_range: "^1.0"` in manifest. Runtime loads one version; replay refuses if loaded version is outside the run's recorded compat range. Cheap to implement. Trust-based — compat is a policy claim, not a mechanical guarantee (unlike CUE schema unification, which *is* mechanical). Reasonable if a pack ships a breaking v2.0 but wants intra-1.x replays to work.
3. **Hermetic replay / version-pinned execution.** Runtime can load arbitrary historical pack versions on demand; replay fetches exactly the version pinned in the run's events and executes against it. Bit-exact reproducibility. Industry names: "hermetic replay" (Bazel), "version-pinned execution" (Flyte), "content-addressable code loading" (Nix/Guix). **Cost:** BEAM can't host two versions of the same module in one node; Python can't share an interpreter across package versions. Real implementations (Flyte, Dagger, Argo) use **container-level isolation** — each run's pinned image is retrieved and replayed in a container. This is the natural home in E-17 (Container Executor + pluggable storage). Bolting it into `:inline` + `:port` executors is a multi-process-per-version engineering dead end.
**The "prove it" era possibility.** When hermetic replay becomes real (E-17 container territory or later), a run's events could additionally store a **container image hash** alongside `pack_version` + `git_commit_hash`. The image is stored in a registry (pack-scoped or runtime-scoped content-addressed cache); replay retrieves it by hash and executes there. This is how Flyte / Dagger / Argo ship replay today. For Liminara this is a future capability, tracked here so the eventual E-17 planner sees the design connection. Not scoped now; not in E-21.
**Trigger for revisit:** (a) first pack ships a major-version bump mid-lifecycle and needs cross-version replay, (b) first regulator / auditor requires byte-exact historical execution (not just historical-source inspection), or (c) E-17 container work picks up and bundles hermetic replay as a natural capability.
**Explicit non-goal:** Building multi-version BEAM / multi-version Python hot-loading inside the existing `:inline` + `:port` executors. This is the wrong place for it; wait for containers.

## Secret-management maturity — pluggable SecretSource adapters + secret-observability hardening
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 15)
**Relates to:** E-21b M-PACK-B-02 (`SecretSource` behaviour + `EnvVar` adapter + `Secrets.Registry` + scrub + `:suspected_secret_leak` warning); ADR-SECRETS-01; future E-14 / production-deployment territory
**Severity:** Medium — MVP covers Boundary 1 reliably and Boundary 2 best-effort; richer hardening is demand-driven when deployment needs grow
**Context:** Secret management has three distinct concerns and Liminara's E-21 MVP addresses the middle one:
1. **Secret source / storage (where plaintext lives, who can read, audit).** *Industrial-strength solved problem.* HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, Doppler, 1Password Connect. Liminara does **not** build a bespoke vault.
2. **Secret delivery (how resolved secrets reach ops).** *Liminara MVP: `SecretSource` behaviour + `EnvVar` adapter.* Future adapters (`SecretSource.Vault`, `SecretSource.AzureKeyVault`, `SecretSource.Doppler`, etc.) plug into the same behaviour demand-driven.
3. **Secret observability (preventing accidental disclosure once secrets are in play).** *Liminara MVP: Boundary 1 runtime-internal scrub (reliable) + Boundary 2 pack-code discipline (best-effort signal via `:suspected_secret_leak` warning).* Runtime-mediated capability proxies (HTTP / SMTP / subprocess that resolve opaque handles at send time) are deferred.

**Items (all demand-driven, none blocking E-21):**
- `SecretSource.Vault` adapter — authenticate via agent / token / JWT-auth; cache leases; token-refresh lifecycle. Trigger: first multi-operator deployment, or first deployment requiring short-lived secrets.
- `SecretSource.AzureKeyVault` adapter — Azure AD auth; regional endpoints. Trigger: first Azure-hosted deployment.
- `SecretSource.Doppler` adapter (or equivalent developer-centric vault). Trigger: first deployment where `.env` files are unacceptable.
- Secret rotation API — runtime calls `SecretSource.refresh/1` on a schedule; ops invoked after rotation get the new value. Trigger: first secret that rotates faster than the runtime's restart cadence.
- Per-secret audit log — `Liminara.Secrets.Registry` emits structured events for every `fetch` and every `scrub_match`. Trigger: first deployment requiring compliance audit trails.
- Runtime-mediated capability proxies (Approach D from Finding 15) — pack code gets opaque handles; a `SecretProxy.HTTP / SMTP / ...` resolves at send time so plaintext never enters pack code. Trigger: first pack needing true Boundary-2 guarantee rather than best-effort signal. Large scope; not justified for single-operator deployments.
- Encrypted-at-rest secret storage for deployment config — today deployment config holds secret names; operator stores plaintext in `.env` or equivalent. Trigger: first shared deployment.
- Break-glass / emergency revocation — a way to revoke a compromised secret without redeploying the runtime. Trigger: first security incident.

**Non-goal:** Building a bespoke Liminara-branded secret vault. Vault / Key Vault / Doppler solve the storage problem well; Liminara integrates with them via `SecretSource` adapters, not reinvents them.

**Trigger for revisit:** (a) any deployment with more than one operator, or (b) any pack requiring short-lived / rotating secrets, or (c) admin-pack real-data deployment exposing a concrete need the MVP can't meet.

## Radar generated `pack.yaml` shim — planned entry, activates on M-PACK-B-01b merge
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 6)
**Relates to:** E-21b M-PACK-B-01b (shim lands), E-21d M-PACK-D-01b (shim removed), `docs/governance/shim-policy.md`
**Severity:** N/A — this is a declared shim under policy, not a silent drift. Recorded here so the shim's survival across multiple milestones (B-01 → B-02 → B-03 → C-01..03 → early D-01) is visible.
**Status:** **Planned.** This entry is promoted to active when M-PACK-B-01b merges and the shim file actually lives in-tree. Before that, the shim exists only as a spec commitment.
**Context:** E-21b M-PACK-B-01b lands a generated `pack.yaml` for Radar in-tree so `PackLoader` can load Radar through the generic code path without a big-bang extraction. The file adapts Radar's current shape to the ADR-MANIFEST-01 schema; it preserves semantics (Radar's execution is identical), so it qualifies under the shim policy's allowed-exception rule. Full shim record in `work/epics/E-21-pack-contribution-contract/E-21b-runtime-pack-infrastructure.md` → "Compatibility shims" section.
**Items (survival-tracking only; the fix is E-21d M-PACK-D-01b):**
- Shim file carries the required SHIM header comment (enforced at M-PACK-B-01b PR review)
- Shim is not referenced as an authoritative manifest anywhere — it is `PackLoader` input only
- Any change to Radar's shape during E-21b/c regenerates the shim (or updates the hand-authored version) but does not add new shim files
**Removal trigger:** E-21d M-PACK-D-01b replaces the in-tree generated manifest with `radar-pack`'s own authored canonical `pack.yaml`; the shim file is deleted in that same milestone.

## E-21a CI alignment — repo-wide CI pipeline + `cue vet` + schema-evolution as unbypassable gates
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 5)
**Relates to:** E-21a M-PACK-A-01 (local + pre-commit `cue vet`), `.devcontainer/Dockerfile`, future shared `tool-versions` file
**Severity:** Medium — E-21a ships local + pre-commit enforcement in the interim; pre-commit is bypassable via `--no-verify`, so invalid CUE can land on a branch. Reviewer checklist covers the gap during PR review, but unbypassable CI enforcement is the real fix.
**Context:** `.github/workflows/` is currently empty. E-21a deliberately does not take on "stand up repo-wide CI" as scope — that's a broader initiative (would also need to pick up Elixir tests, Python tests, dag-map tests, format/credo/dialyzer, etc.). The design decision at E-21a is that **the shared tool-versions file is the pinning mechanism CI will reuse verbatim**, so when CI eventually lands there is no drift between local and CI versions.
**Items:**
- Stand up a GitHub Actions pipeline that reads CUE version from the shared tool-versions file (same file the devcontainer reads) and runs `cue vet` + schema-evolution compat check on every PR. Cannot be bypassed.
- Evaluate Option-A-style alignment (run CI jobs inside the devcontainer image, published to ghcr.io) as a future evolution — builds on the tool-versions file without changing its role.
- Extend the CI pipeline to cover other validation pipelines mentioned in CLAUDE.md (Elixir `mix format` / `credo` / `dialyzer` / `test`, Python `ruff` / `ty` / `pytest`, dag-map `npm test`) — likely a separate CI epic rather than part of E-21a.
- When CI lands, the interim reviewer-checklist duty in E-21a's risks table is removed (it exists only because pre-commit is bypassable).
**Trigger:** when repo-wide CI becomes a priority — could be triggered by pre-commit bypass actually biting, by a second contributor joining, or by a production deployment milestone needing a build gate. Not urgent while the repo has a single committer.

## Workflow-audit: roadmap-scope and roadmap-presence drift not detected
**Discovered:** 2026-04-23 (PackRegistry / E-22 admin-pack sequencing review)
**Relates to:** `.ai/skills/workflow-audit.md` Section 7 (ROADMAP.md Currency), framework repo `23min/ai-workflow`
**Severity:** Medium — workflow-audit is the skill that's supposed to catch exactly this, and it didn't. Two real drifts (E-15 PackRegistry row overlapping E-21b scope; E-22 missing from the roadmap entirely despite being cited across E-21 specs + D-027) lived silently because the audit's roadmap checks don't cover scope-overlap or cross-surface reference completeness.
**Context:** Section 7 of `workflow-audit` currently checks (a) in-progress items appear in roadmap, (b) completed epics have a shipped entry, (c) released epics are marked released, (d) roadmap entries don't reference deleted epic folders. It does not check whether an epic referenced across other surfaces (specs, decisions, tracking) actually has a roadmap row, nor whether two roadmap rows describe the same capability/primitive. Both were the load-bearing checks in this case.
**Items:**
- Add a Section 7 check: *referenced-epic-must-appear-on-roadmap* — for every epic ID referenced in `work/epics/*/`, `work/decisions.md`, and CLAUDE.md Current Work, verify a roadmap row exists for that ID. Mechanically checkable by grepping `E-\d{2}[a-z]?` across those surfaces and diffing against roadmap rows.
- Add a Section 7 check: *capability-overlap detection* — flag cases where a named capability/primitive (e.g. `PackRegistry`, `TriggerManager`, `SurfaceRenderer`) appears in the scope of more than one active roadmap row. Mechanically checkable by extracting bolded/back-ticked capability names from each row and reporting names that appear in >1 open row.
- Consider a companion check against the contract matrix (`docs/architecture/indexes/contract-matrix.md`) for repos that maintain one — runtime-level capabilities in the matrix should map to exactly one active epic row.
**Trigger:** file as an issue on `23min/ai-workflow`; address when the framework opens a workflow-audit milestone. This is framework-level work, not Liminara-local — no workaround needed beyond manual review at epic planning time.

## Resolved

Closed gap entries kept for history. Move new resolutions here rather than deleting.

### Milestone/tracking template drift — consolidate at next milestone start
**Discovered:** 2026-04-21 (post-framework-update doc-gardening pass)
**Resolved:** 2026-04-22 (framework bump `.ai` → `9ef0b5e` adopted as-is; all of `work/_templates/` deleted)
**Relates to:** `.ai/templates/`, `work/_templates/` (removed), D-2026-04-22-029
**Severity:** Low — real specs work fine; templates just aren't helpful starting points anymore
**Context:** Neither template set matched current practice when this gap was logged. The 2026-04-22 framework bump shipped updated templates (`.ai/templates/{adr,epic-spec,milestone-spec,tracking-doc}.md`) that include YAML frontmatter with `id`/`epic`/`status: draft|approved|in-progress|complete`/`depends_on`, plus Constraints / Design Notes / Surfaces touched sections — closing the concrete lacks this gap named. Side-by-side comparison with real E-19/E-20 specs showed framework templates now cover the core shape; Liminara extras (Milestone Boundary, Tests, TDD Sequence, Downstream Consumers, Technical Notes) are additive author choices per spec, not structural requirements — they don't need to live in a template.
**Resolution:** Framework templates adopted as-is. `.ai-repo/templates/` intentionally left empty — the only divergences worth codifying would have been sub-epic frontmatter fields (`parent`, `composed_of`, `phase`) and the `planning` status value, both retired by D-2026-04-22-029. All four files under `work/_templates/` deleted:
- `work/_templates/ADR.md` — deleted in `dcf9311` alongside the framework bump
- `work/_templates/epic.md`, `work/_templates/milestone.md`, `work/_templates/milestone-log.md` — deleted in the template-adoption commit
E-21 files had `status: planning` bumped to `status: draft` in the same commit (per D-029).

### Radar LanceDB path drifts into `_build`
**Discovered:** 2026-04-08 (container persistence review)
**Resolved:** 2026-04-08 (explicit `:liminara_radar, :lancedb_path` in dev/test/prod plus required config lookup)
**Relates to:** D-2026-04-01-009, D-2026-04-08-024, M-RAD-01 persistent storage paths
**Fix:** Radar no longer falls back to a build-output-derived LanceDB path. The pack now requires an explicit configured `lancedb_path`, with dev defaulting to `runtime/data/radar/lancedb`, test using an explicit tmp path, and prod defaulting to `/var/lib/liminara/radar/lancedb`.

### Multi-decision replay is broken
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Resolved:** 2026-04-03 (M-RAD-06 commit e9fe49a)
**Fix:** Decision.Store stores list per node_id, Run.Server replays stored output_hashes, full Radar replay test validates end-to-end.

### Rank op violates determinism model
**Discovered:** 2026-04-02 (OpenAI review of M-RAD-03 implementation)
**Resolved:** 2026-04-03 (M-RAD-03 commit fd5b4c9)
**Fix:** `reference_time` passed as explicit plan input; rank op raises on missing (no wall-clock fallback).

### M-RAD-03 tracking ahead of implementation
**Discovered:** 2026-04-02 (OpenAI review)
**Resolved:** 2026-04-03 (M-RAD-03 scope amendment + tracking doc update)
**Fix:** Known limitations documented in spec and tracking doc; placeholders accepted for v1.

### E-12 sandbox spec contradiction
**Discovered:** 2026-04-02 (OpenAI review)
**Resolved:** 2026-04-03 (E-12 epic spec rewrite)
**Relates to:** E-12 Op Sandbox epic, D-019 (sandbox split)
**Fix:** Success criteria now distinguish bootstrap code/dependency reads from runtime access restrictions. Startup may read declared bootstrap paths; runtime access remains limited to declared runtime paths, with undeclared host paths and other ops' working dirs blocked.
