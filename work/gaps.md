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
**Relates to:** E-19, E-24 ADR-CONTENT-01 (briefing contract)
**Severity:** UI gap — runtime-level degraded signals from these paths continue to surface via the observation layer (M-WARN-02), but the rendered HTML briefing does not yet reflect them.
**Items:**
- `radar_dedup` safe-default surfacing: `radar_dedup` operates on items before clustering; its degraded signal would need an item-level degraded flag that propagates through `Cluster` / `Rank` into `ComposeBriefing`. That is a briefing-contract schema decision (surface degraded items as a section? tag clusters containing degraded items?) and crosses into E-24 ADR-CONTENT-01 territory.
- Fetch-error partial-ingestion surfacing: source-level concern; the briefing already has a `source_health` section showing errors. Extending that to a top-level banner would require deciding how per-source errors compose with per-cluster placeholder summaries in the same banner — another UX + schema decision.
- Both extensions were deferred from M-WARN-03 because they cost >1h and the spec explicitly said to defer in that case. Consider re-opening when E-24 ADR-CONTENT-01 codifies the briefing contract, or earlier if operator feedback calls for them.

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
**Relates to:** E-24 (ADR authoring), `epic.md:202` comparables citation, future contract-facing contributors
**Severity:** Low — most of the useful comparable context is already embedded inline in per-ADR content requirements (Findings 8, 13, 14, 15, 17). The standalone doc's main value is helping *multiple* reviewers / contributors converge on a shared mental model; for single-author + occasional-reviewer current state, the inline context is sufficient.
**Context:** E-21's parent epic cites Argo / Flyte / Kubeflow / GitHub Actions / N8N / Zapier / Windmill as data-contract workflow comparables but no standalone comparison doc exists. Each E-24 ADR that picks a design (manifest format, schema evolution pattern, replay semantics, content-type identifier shape, trigger restart semantics, secret observability) now carries a design-space shortlist inline — ADR-EVOLUTION-01's {P1 strict major match / P2 multi-historical-schema / P3 unify-or-fail / P4 pack-declared range}; ADR-TRIGGER-01's fire-and-forget decision with E-14 escalation named; ADR-FSSCOPE-01's two-surface model vs Landlock; ADR-SECRETS-01's Vault / Key Vault / Doppler delivery adapters + runtime-mediated-proxy deferral; cross-version replay's Bazel / Flyte / Nix-Guix / Dagger / Argo industry-name landscape. Collectively these inline shortlists do most of what a standalone comparables doc would do; the remaining gap is a single-glance landing page for orientation.
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

## `liminara_widgets` extraction — in-tree for E-26; extract when a second consumer arrives
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 24)
**Relates to:** E-26 M-DX-02 (`liminara_widgets` lands in-tree), future submodule + Hex release
**Severity:** Low — in-tree indefinitely is fine for the current deployment; the discipline is forward-compatibility with extraction, not immediate extraction.
**Context:** `liminara_widgets` ships in E-26 M-DX-02 as five generic A2UI widgets (`data_grid`, `json_viewer`, `dag_map` embedder, `content_card`, `banner`) with zero Liminara domain types by design. The library is **structurally reusable** by any A2UI consumer, but no external consumer exists today. Name chosen (`liminara_widgets` not `liminara_ui`): honest about being a widget library; doesn't mislead readers into expecting `%Run{}`/`%Artifact{}`-aware components (which a `liminara_ui` name would imply); doesn't collide with `ex_a2ui` naming the way `liminara_a2ui` would.
**MVP decision:** keep in-tree inside the Liminara umbrella (`runtime/apps/liminara_widgets/` or equivalent). Reasons:
- No external consumers today → extracting now is speculative investment.
- `boundary` hex lib (ADR-BOUNDARY-01, lands in M-RUNTIME-01) enforces the zero-domain-types rule structurally via compile-time checks; the type-hygiene guarantee doesn't require submodule isolation.
- In-tree keeps E-26 M-DX-02's scope smaller — no separate Hex release cadence, no separate CI, no separate v0.1 → v1.0 maturity arc.
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
**Relates to:** E-24 ADR-REPLAY-01 (scope trimmed — pack-version skew removed), E-25 M-RUNTIME-02 (provenance recording lands), E-17 Container Executor (natural home for hermetic replay), future VSME / DPP compliance epics
**Severity:** Low today — Radar is one continuous version; single-operator deployments don't need cross-version replay. Rises to Medium when first pack ships a major-version bump mid-lifecycle, or when a regulator asks for byte-exact historical replay.
**Context:** Today Liminara replays a run against whatever pack version is currently loaded. Works because the pack version at replay time matches the pack version at run-production time (one continuous Radar). When packs evolve mid-lifecycle (admin-pack ships v2.0; old runs from v1.5 exist in the event log), "what does replay mean?" becomes a real question. E-21 deliberately does not pick a policy — no pack has surfaced concrete pressure, and hermetic replay is expensive to bolt onto `:inline` + `:port` executors.
**The provenance layer ships in E-25** (M-RUNTIME-02): each run's initial event records `pack_version` + `git_commit_hash`. This is cheap and unlocks audit workflows — "which code produced this run" is a recorded fact — without requiring the runtime to execute old code. **Provenance is separate from replayability**: most compliance disputes are resolved by reading the old code's source (by git hash), not by re-executing it in production.
**Design space (not decided; revisit when pressure surfaces):**
1. **Single-version-with-provenance (current plan, post-E-21).** Runtime loads one pack version; replay uses that version; `pack_version` + `git_commit_hash` in events support "read the source" audit. Simplest. Matches the ship-when-you-need-it E-21 scope.
2. **Compatibility-range replay.** Pack declares `replay_compat_range: "^1.0"` in manifest. Runtime loads one version; replay refuses if loaded version is outside the run's recorded compat range. Cheap to implement. Trust-based — compat is a policy claim, not a mechanical guarantee (unlike CUE schema unification, which *is* mechanical). Reasonable if a pack ships a breaking v2.0 but wants intra-1.x replays to work.
3. **Hermetic replay / version-pinned execution.** Runtime can load arbitrary historical pack versions on demand; replay fetches exactly the version pinned in the run's events and executes against it. Bit-exact reproducibility. Industry names: "hermetic replay" (Bazel), "version-pinned execution" (Flyte), "content-addressable code loading" (Nix/Guix). **Cost:** BEAM can't host two versions of the same module in one node; Python can't share an interpreter across package versions. Real implementations (Flyte, Dagger, Argo) use **container-level isolation** — each run's pinned image is retrieved and replayed in a container. This is the natural home in E-17 (Container Executor + pluggable storage). Bolting it into `:inline` + `:port` executors is a multi-process-per-version engineering dead end.
**The "prove it" era possibility.** When hermetic replay becomes real (E-17 container territory or later), a run's events could additionally store a **container image hash** alongside `pack_version` + `git_commit_hash`. The image is stored in a registry (pack-scoped or runtime-scoped content-addressed cache); replay retrieves it by hash and executes there. This is how Flyte / Dagger / Argo ship replay today. For Liminara this is a future capability, tracked here so the eventual E-17 planner sees the design connection. Not scoped now; not in E-21.
**Trigger for revisit:** (a) first pack ships a major-version bump mid-lifecycle and needs cross-version replay, (b) first regulator / auditor requires byte-exact historical execution (not just historical-source inspection), or (c) E-17 container work picks up and bundles hermetic replay as a natural capability.
**Explicit non-goal:** Building multi-version BEAM / multi-version Python hot-loading inside the existing `:inline` + `:port` executors. This is the wrong place for it; wait for containers.

## Secret-management maturity — pluggable SecretSource adapters + secret-observability hardening
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 15)
**Relates to:** E-25 M-RUNTIME-03 (`SecretSource` behaviour + `EnvVar` adapter + `Secrets.Registry` + scrub + `:suspected_secret_leak` warning); ADR-SECRETS-01; future E-14 / production-deployment territory
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

## Radar generated `pack.yaml` shim — planned entry, activates on M-RUNTIME-02 merge
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 6)
**Relates to:** E-25 M-RUNTIME-02 (shim lands), E-27 M-RADX-02 (shim removed), `docs/governance/shim-policy.md`
**Severity:** N/A — this is a declared shim under policy, not a silent drift. Recorded here so the shim's survival across multiple milestones (B-01 → B-02 → B-03 → C-01..03 → early D-01) is visible.
**Status:** **Planned.** This entry is promoted to active when M-RUNTIME-02 merges and the shim file actually lives in-tree. Before that, the shim exists only as a spec commitment.
**Context:** E-25 M-RUNTIME-02 lands a generated `pack.yaml` for Radar in-tree so `PackLoader` can load Radar through the generic code path without a big-bang extraction. The file adapts Radar's current shape to the ADR-MANIFEST-01 schema; it preserves semantics (Radar's execution is identical), so it qualifies under the shim policy's allowed-exception rule. Full shim record in `work/epics/E-21-pack-contribution-contract/E-25-runtime-pack-infrastructure.md` → "Compatibility shims" section.
**Items (survival-tracking only; the fix is E-27 M-RADX-02):**
- Shim file carries the required SHIM header comment (enforced at M-RUNTIME-02 PR review)
- Shim is not referenced as an authoritative manifest anywhere — it is `PackLoader` input only
- Any change to Radar's shape during E-25/c regenerates the shim (or updates the hand-authored version) but does not add new shim files
**Removal trigger:** E-27 M-RADX-02 replaces the in-tree generated manifest with `radar-pack`'s own authored canonical `pack.yaml`; the shim file is deleted in that same milestone.

## E-24 CI alignment — repo-wide CI pipeline + `cue vet` + schema-evolution as unbypassable gates
**Discovered:** 2026-04-23 (E-21 ultrareview — Finding 5)
**Relates to:** E-24 M-CONTRACT-01 (local + pre-commit `cue vet`), `.devcontainer/Dockerfile`, future shared `tool-versions` file
**Severity:** Medium — E-24 ships local + pre-commit enforcement in the interim; pre-commit is bypassable via `--no-verify`, so invalid CUE can land on a branch. Reviewer checklist covers the gap during PR review, but unbypassable CI enforcement is the real fix.
**Context:** `.github/workflows/` is currently empty. E-24 deliberately does not take on "stand up repo-wide CI" as scope — that's a broader initiative (would also need to pick up Elixir tests, Python tests, dag-map tests, format/credo/dialyzer, etc.). The design decision at E-24 is that **the shared tool-versions file is the pinning mechanism CI will reuse verbatim**, so when CI eventually lands there is no drift between local and CI versions.
**Items:**
- Stand up a GitHub Actions pipeline that reads CUE version from the shared tool-versions file (same file the devcontainer reads) and runs `cue vet` + schema-evolution compat check on every PR. Cannot be bypassed.
- Evaluate Option-A-style alignment (run CI jobs inside the devcontainer image, published to ghcr.io) as a future evolution — builds on the tool-versions file without changing its role.
- Extend the CI pipeline to cover other validation pipelines mentioned in CLAUDE.md (Elixir `mix format` / `credo` / `dialyzer` / `test`, Python `ruff` / `ty` / `pytest`, dag-map `npm test`) — likely a separate CI epic rather than part of E-24.
- When CI lands, the interim reviewer-checklist duty in E-24's risks table is removed (it exists only because pre-commit is bypassable).
**Trigger:** when repo-wide CI becomes a priority — could be triggered by pre-commit bypass actually biting, by a second contributor joining, or by a production deployment milestone needing a build gate. Not urgent while the repo has a single committer.

## `warning_payload/1` and helpers duplicated byte-identically across `Run` and `Run.Server`
**Discovered:** 2026-04-26 (M-CONTRACT-02 ADR-WIRE-01 authoring; subagent flagged the duplication while reading `Liminara.Executor.Port`'s warning shape source-of-truth)
**Relates to:** E-19 (Warnings & Degraded Outcomes), `runtime/apps/liminara_core/lib/liminara/run.ex`, `runtime/apps/liminara_core/lib/liminara/run/server.ex`, ADR-WIRE-01 (cites these as the wire-shape divergence point), ADR-OPSPEC-01 (cites `Liminara.Warning` as source-of-truth)
**Severity:** Medium — DRY violation, not a correctness bug today (both copies are byte-identical), but a latent regression vector. The next person who needs to change the wire shape (e.g. add a field to `Warning`, or alter the stringification rule) has two places to remember to change. The original M-WARN-04 fix (D-2026-04-20-026) addressed `bug_005` by changing the on-the-wire shape to string-keyed JSON; if either copy had been missed at fix time, the bug would have re-emerged on whichever path used the unfixed copy.
**Context:** The duplicated functions are `warning_payload/1`, `stringify_warning_map/1`, `stringify_warning_value/2`, `enforce_warning_contract/2`, and `warning_contract_may_emit?/1`. Locations: `run.ex:710-738` and `run/server.ex:1192-1214` (verified byte-identical with the same load-bearing `bug_005` comment block above each copy). The duplication likely originated in the E-19 warning-epic work where the same payload-shaping logic was needed in both modules — `Run` for replay-path event emission (`run.ex:508`, `:587`) and `Run.Server` for live-path emission (`server.ex:682`, `:908`) — and was copy-pasted instead of extracted to a shared helper. The two paths exist for a real reason (replay and live broadcast are deliberately decoupled), but the *payload shape* is a single contract that should live in one place.
**Items:**
- Extract the five duplicated functions to a single private helper module (e.g. `Liminara.Run.WarningPayload`) that both `Run` and `Run.Server` call into. Or hoist them onto `Liminara.Warning` itself (the struct knows its own wire shape) — this is more idiomatic Elixir and would also let the SDK + admin-pack proxy bind to the same helper rather than re-implement the stringification rule.
- Decide between the two extraction targets — the trade-off is whether `Warning` should carry on-the-wire-shape concerns (couples the struct to the JSON contract) or whether a separate WirePayload module owns it (one more module, but cleaner separation). ADR-WIRE-01 cites this as the wire-shape divergence point; whichever target is picked, the ADR's *Reference implementation* should re-cite the new location after extraction.
- Confirm the comment block referring to `bug_005` survives extraction — it documents the load-bearing reason for the stringification step, and losing that comment risks a future "why is this here?" refactor undoing the fix.
**Trigger:** address as a small follow-up patch when next touching either `run.ex` or `run/server.ex` for warning-shape work. Not urgent (zero behavioral risk while both copies stay byte-identical), but should not be deferred indefinitely — the longer it lives, the higher the chance someone modifies one copy and silently breaks the other.

## Dynamic pipelining shape — content-routed dispatch via contract matching
**Discovered:** 2026-05-02 (Q&A round on ADR-PLAN-01 Q8; user surfaced the contract-routing direction as a structurally cleaner alternative to predicate-flag conditionals)
**Relates to:** D-2026-05-02-039 (the design-direction record), ADR-PLAN-01 (PLAN-01 v1.0.0 ships strict static-DAG-only, deferring all conditional shape), ADR-OPSPEC-01 (the contract grammar `contracts.{inputs,outputs}: {[string]: _}` is too loose to express value-pattern constraints), ADR-MULTIPLAN-01 (M-CONTRACT-04, the natural pairing point), `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md` §9 (the `enabled: input.use_llm` example that exposed the gap), Petri-net deadlock-analysis literature, BPMN content-based-routing patterns.
**Severity:** Architectural deferral — not blocking any current pack (Radar's static plan suffices) but the load-bearing capability gap that admin-pack §9's `enabled:` shape and beyond will pressure-test. Cost of leaving deferred: admin-pack at E-22 either avoids conditional plans entirely (constrains pack design) or pushes the v1.x evolution path itself (adds scope to E-22). Cost of admitting now: designing without a working consumer, exactly the over-commit lock-to-used (D-2026-04-26-036 convention 4) was authored against.
**Context:** Liminara's deterministic-replay discipline forbids wall-clock timeouts (they make replay non-deterministic). The standard escape hatches that other dataflow runtimes use for starvation handling — "wait T seconds, then give up," "retry with exponential backoff," "race a fallback path" — are unavailable. The right answer per D-2026-05-02-039 is **load-time coverage proof**: PackLoader proves statically that every possible runtime state has a defined fate, via Petri-net-style reachability analysis. If coverage holds, starvation is impossible at runtime. This forces the design to a stronger shape than runtime-timeout-driven dataflow languages. The bill of materials below is sized at ~3-5 milestones of work depending on scope split (single `ADR-DYNAMIC-PIPELINE-01` vs. multi-ADR breakdown).
**Items:**
- **Contract grammar extension.** Extend ADR-OPSPEC-01's `contracts.{inputs,outputs}: {[string]: _}` to admit value-pattern constraints. Shape options: refinement types (predicate constraints on existing types), JSON-Schema-like predicates, tagged discriminator unions (sum types with discriminator field), or CUE-style constraints embedded in the contract definitions. Pick one at design time; not pre-committed in D-039.
- **Runtime contract matcher.** Pure function on artifact bytes ("does artifact X match contract Y?"). Smaller than CEL/JSONPath but non-trivial. Deterministic on replay because it's a pure function of content-addressed inputs.
- **Candidate-consumers plan shape.** Extend ref-binding to admit "any matching consumer" or `candidates: [{op, when_contract}]`. Today's `{ref: <node_id>}` stays as the static binding shape; new shape is additive.
- **Dead-letter as catch-all consumer.** No-match becomes a defined routing decision, not a runtime surprise. Pack authors register a dead-letter consumer (or runtime provides default).
- **Slot multiplicity per input slot.** Singular (function-call model: one matching artifact; ambiguity-error or first-wins on multi-match) vs. collection (stream-join model: list of matching artifacts). Right answer depends on use case (palette + structure → singular; merge-all-clusters → collection).
- **Slot optionality per input slot.** Required / optional-with-default / optional-with-skip. Determines consumer fate when an upstream slot can't be filled.
- **Cascade rules for upstream-dead-letter / upstream-skipped events.** When an upstream node terminates without a routable output, downstream consumers get deterministic fates by slot optionality. Required-slot starvation cascades dead-letter; optional-with-default fires with default; optional-with-skip cascades skip (transitively).
- **Reachability tracking at runtime.** Per-node state machine: `expected-to-fire | fired | dead-lettered | skipped`. State transitions driven by upstream output events; consumer transitions to terminal state when all upstream states are terminal. Replay reproduces transitions trivially (deterministic function of artifact bytes + recorded contracts).
- **Load-time coverage proof.** PackLoader proves statically that every possible upstream-state combination for every node maps to a defined cascade outcome. Petri-net-style reachability analysis against the contract grammar. **If coverage proof passes, starvation is impossible at runtime — every node terminates in a defined state, no deadlocks, ever.** This is the load-bearing reason to do the work.
- **Decision-record interaction.** A dispatch decision is deterministic on artifact bytes (not a `Decision` in Liminara's nondeterministic-choice sense). A predicate referencing a recorded `Decision` (e.g. LLM classifier output) is deterministic *given the recorded decision*. Surface design: does dispatch produce its own audit event? Does it land in the event log alongside artifact-emit events?
- **Failure-mode taxonomy.** Distinguish "structural mismatch" (output shape doesn't match any consumer's input shape — a real contract violation) from "value-no-match" (output is well-shaped but no consumer's value-pattern claims it — a routing-no-match). Different semantics, different operator surfaces.
- **Cross-pack op references and routing.** v1.0.0 PLAN-01 is single-pack-only. Contract routing across pack boundaries is a future question (does pack A's output route to pack B's consumer?). Likely deferred to its own pass.
**Trigger:** scope and design at M-CONTRACT-04 alongside ADR-MULTIPLAN-01 (the two ADRs are natural pairs — multi-plan and dynamic-routing both relax "one static DAG"). The eventual ADR provisionally lands as `ADR-DYNAMIC-PIPELINE-01` (or scope-extension of MULTIPLAN-01; the milestone scoping picks one). Admin-pack at E-22 is the binding pressure-test consumer; if E-22 lands before M-CONTRACT-04, admin-pack must defer conditional usage or push the v1.x evolution path itself.

## Worked-example abbreviated-subset drift detection (wf-doc-lint extension)
**Discovered:** 2026-05-02 (M-CONTRACT-02 wrap-time verification audit; B-finding from the worked-example/fixture parity sweep)
**Relates to:** M-CONTRACT-02 spec *Design Notes* "Worked-example fixture parity" rule (now amended to admit explicit-abbreviation-with-link as a valid pattern), `docs/decisions/0007-pack-manifest.md`, `docs/decisions/0008-pack-plan.md`, `.claude/skills/wf-doc-lint/SKILL.md`, the contract-design reviewer rule.
**Severity:** Low — no current correctness issue; latent drift risk in ADRs that use the explicit-abbreviation pattern. The verbatim-fixture pattern (used by OPSPEC-01, WIRE-01, REPLAY-01) is drift-proof; the abbreviation pattern (used by MANIFEST-01, PLAN-01) is drift-permissive at the subset level.
**Context:** The M-CONTRACT-02 milestone spec's *Worked-example fixture parity* rule originally required ADRs to reproduce the cited fixture verbatim. After audit, MANIFEST-01 (152-line excerpt of 372-line fixture) and PLAN-01 (65-line excerpt of 179-line fixture) ship explicitly-abbreviated worked-examples — a reasoned authoring choice (full-fixture inline reduces ADR readability past ~100 YAML lines). The spec is amended to admit the abbreviation pattern when (a) the abbreviation is stated in prose, (b) what's covered is described, (c) the full fixture is linked. **What the abbreviation pattern doesn't catch:** drift between the abbreviated subset and the corresponding portion of the canonical fixture. cue-vet doesn't catch it because the ADR-body-embedded YAML isn't a registered fixture — it's prose-embedded text. The verbatim form is byte-equality-checkable against the fixture; the abbreviation form requires per-field reasoning about which fixture portion the excerpt represents.
**Items:**
- **Extend `.claude/skills/wf-doc-lint/SKILL.md`** with a check that walks every ADR under `docs/decisions/` looking for ` ```yaml ` fenced blocks. For each block:
  - Parse as YAML; report syntax errors.
  - If the ADR carries `contract.schema:` frontmatter pointing at a CUE schema, run `cue vet <schema> -` (stdin) on the parsed YAML. Report `cue vet` errors. **This catches structural drift** — if the abbreviated YAML uses a field name that the schema rejects, the lint fails.
  - This is a weaker check than fixture-equality (it doesn't catch subset-mismatch drift between the excerpt and the canonical fixture) but is cheap and catches the common case.
- **Optional stronger check:** parse the ADR body's worked-example YAML AND the cited `contract.worked_example:` fixture; verify the ADR's YAML is a *prefix* or *structural sub-tree* of the fixture (every node-id/op/field that appears in the ADR must appear identically in the fixture). This catches subset-vs-full-fixture drift but requires shape-aware comparison logic per topic.
- **CI integration:** add the new check to `wrap-milestone`'s pre-wrap gate so abbreviated-worked-example drift is caught at PR-review time, not after merge.
**Trigger:** address as part of the next `wf-doc-lint` enhancement pass, or when the next big-fixture ADR (any cohort with a fixture > 100 lines) lands and adopts the abbreviation pattern. Not blocking M-CONTRACT-02 wrap; the spec amendment acknowledges the gap explicitly.

## Soft-wrap normalization mode for wf-doc-lint (integrate scripts/reflow-md.py + scripts/detect-hardwrap-md.py)
**Discovered:** 2026-05-02 (M-CONTRACT-02 wrap-time docs cleanup; reflow tooling promoted from `/tmp/` to `scripts/` after a documents-drift sweep produced 13 hard-wrapped findings)
**Relates to:** `scripts/reflow-md.py`, `scripts/detect-hardwrap-md.py`, `.claude/skills/wf-doc-lint/SKILL.md`, the *Worked-example fixture parity* spec amendment in `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md` (Design Notes), the doc-tree convention in `docs/governance/`.
**Severity:** Low — no current correctness issue; the standalone tools are sufficient for periodic manual sweeps. Latent issue: drift creeps in over time as new content is authored in hard-wrap form (especially when contributors paste from email / external editors), and there's no automated nag to keep the convention.
**Context:** Liminara's docs convention is one paragraph per line for narrative prose under `docs/`. Hard-wrapped paragraphs (each line ~65 chars, common in older ADRs and inherited content) cause noisy diffs (whole-paragraph re-wraps for one-word edits) and hide structural changes inside reformatting churn. M-CONTRACT-02 wrap-time audit surfaced 13 hard-wrapped files; a one-off reflow sweep brought them to convention. Tools live at:
- `scripts/reflow-md.py` — collapse hard-wrapped paragraphs into one line; preserves YAML frontmatter, fenced code, headings, tables, lists, blockquotes, HRs.
- `scripts/detect-hardwrap-md.py` — classify candidate files (hard-wrapped / soft-wrapped / ambiguous / too-tiny). Companion to reflow.

The `wf-doc-lint` skill (`.claude/skills/wf-doc-lint/SKILL.md`) is the natural long-term home for these checks — it already owns "structural correctness of narrative documentation" and writes findings to `docs/log.md` + `metrics.json`. A `soft_wrap_compliance` component in the `doc_health` metric would surface drift on every full lint run.
**Items:**
- **Add a `soft_wrap_compliance` check to `wf-doc-lint full`.** Walk `docs/` (excluding `history/`, `archive/`, `releases/`, `badges/`, `index.md`); run `scripts/detect-hardwrap-md.py` against each candidate; report findings under a new heading in the lint output (alongside *Orphan Files*, *Documentation TODOs*, etc.).
- **Consider a `soft_wrap_compliance` component in the `doc_health` metric** (sibling to `freshness`, `reference_integrity`, etc.). Weight: small — drift here is real but recoverable, not load-bearing on contract correctness. Initial weight ~0.05; subtract from another component if total weights are at 1.00.
- **Wire `wf-doc-lint scoped` to flag added-or-modified docs that violate convention** before merge. The wrap-milestone check picks this up at AC-pass time.
- **Decide on convention scope.** Today `docs/architecture/proposals/` and `docs/architecture/01_CORE.md` were already soft-wrapped (different convention surface); the M-CONTRACT-02 sweep extended the convention to ADRs, governance, and schema READMEs. Future-pass: confirm `docs/research/`, `docs/analysis/`, `docs/public/`, `docs/domain_packs/` adoption (most are already soft-wrapped per the post-sweep classifier output, but a deliberate per-area decision would be cleaner than relying on the heuristic's classification).
- **False-positive handling.** `detect-hardwrap-md.py`'s heuristic flags short-paragraph + bullet-heavy files (e.g., `docs/governance/shim-policy.md`, `docs/architecture/02_PLAN.md`) as hard-wrapped. Reflow on these is a no-op (correctly), but the lint output noise is real. The `wf-doc-lint` integration should either tighten the heuristic (e.g., require a minimum count of long-prose-paragraph lines before flagging) or add a per-doc opt-out signal.
- **YAML-frontmatter pass-through is load-bearing.** The first version of the reflow tool elided this and broke 5 ADRs' frontmatter on a sweep; the recovery cost was non-trivial. The wf-doc-lint integration must inherit the frontmatter-aware version (`scripts/reflow-md.py` as shipped), not re-implement.
**Trigger:** integrate during the next `wf-doc-lint` enhancement pass. Until then, the standalone tools are the manual-sweep mechanism; commit the next manual sweep alongside the lint-skill enhancement.

## Resolved

Closed gap entries kept for history. Move new resolutions here rather than deleting.

### wf-graph apply skips spec frontmatter for flat-layout repos
**Discovered:** 2026-04-25 (M-CONTRACT-01 start-milestone, status flip via `wf-graph apply --patch`)
**Resolved:** 2026-04-26 (framework bump `.ai` → `3fce1cb` consumed PR #81)
**Relates to:** `.ai/tools/wf-graph/internal/patch/write.go`, `.ai-repo/config/artifact-layout.json`
**Filed upstream:** [ai-workflow#80](https://github.com/23min/ai-workflow/issues/80) (closed by PR #81)
**Fix:** Upstream introduced a `resolveSpecPath` helper that branches on the `.md` suffix in the node's `path` field. Folder-layout (`path` is a directory containing `spec.md`) and flat-layout (`path` already names a `.md` file) both work correctly. Liminara consumed the fix transparently when the framework submodule advanced to `9df1dc1+`.

### wf-graph diff-roadmap misses letter-suffixed epic IDs
**Discovered:** 2026-04-25 (M-CONTRACT-01 wrap, post-wrap graph audit)
**Resolved:** 2026-04-26 (framework bump consumed PR #98)
**Relates to:** `wf-graph diff-roadmap` prose-side ID extraction; previous false-positive on E-11b and (now-retired) E-21a/b/c/d
**Filed upstream:** [ai-workflow#88](https://github.com/23min/ai-workflow/issues/88) (closed by PR #98)
**Fix:** Upstream introduced a parallel `idPatternDepGraph` regex that accepts `E-\d+[a-z]?` for the dep-graph extractor (the conservative `\bE-\d+\b` on the line-by-line RoadmapRow scanner stays put to avoid spawning ghost-node findings on letter-suffixed prose mentions without folder backing). E-11b now resolves cleanly. Liminara's E-21 sub-epics retired before the fix landed (per D-2026-04-26-034), so the legacy concern is moot — the surviving consumer of the fix is E-11b.

### Framework `.ai/` sync to upstream HEAD pending — pulls PR #72 deliverables on-disk
**Discovered:** 2026-04-25 (M-CONTRACT-01 AC7+AC8 authoring; upstream PR #72 closed mid-milestone)
**Resolved:** 2026-04-26 (multiple framework syncs this session pulled `.ai/` to HEAD)
**Relates to:** [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37) / PR #72, `.ai-repo/skills/design-contract.md`, `.ai-repo/rules/contract-design.md`, D-2026-04-25-033
**Fix:** `.ai/skills/design-contract.md`, `.ai/docs/recipes/design-contract-cue.md`, `.ai/templates/adr.md` `contract:` frontmatter fields, and `.claude/skills/design-contract/SKILL.md` are all on-disk after the routine bumps. M-CONTRACT-02 authors will use the `contract:` frontmatter when authoring their first ADRs.

### Workflow-audit: roadmap-scope and roadmap-presence drift not detected
**Discovered:** 2026-04-23 (PackRegistry / E-22 admin-pack sequencing review)
**Resolved:** 2026-04-26 (framework `workflow-audit` skill rewritten upstream — landed in the multi-bump window covered by `.ai` → `3fce1cb`)
**Relates to:** `.ai/skills/workflow-audit.md` Section 7 (ROADMAP.md Currency), framework repo `23min/ai-workflow`
**Fix:** The framework's `workflow-audit` skill now ships **§7.2 capability-overlap drift** (extracts back-ticked / bolded / CamelCase tokens from each open row's scope, flags any token appearing in >1 row) and **§7.3 referenced-epic-absence drift** (greps `epicIdPattern` across `epicRootPath/*/`, decisions, gaps, CLAUDE.md; diffs against roadmap rows; flags any ID referenced ≥3× without a row). Both were exactly the checks the gap requested. Both skipped this session's audit cleanly with zero findings — the post-migration roadmap is clean. Companion `contract-matrix` check (§7.4) is also present, advisory-only.

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
