# RFC: Pipeline-scoped run contexts (workspace-bearing runs)

## Status

Draft / proposal. Filed during M-CONTRACT-02 (foundational contracts) authoring on 2026-05-02 to capture an architectural shape that pressure-tests the foundational five (manifest, plan, op-spec, replay, wire) and to surface the design space *before* contract decisions accidentally close it off. **No implementation work is proposed for the current epic (E-24).** The decision points marked in §11 are the things M-CONTRACT-02 should be aware of; everything else is post-Radar.

## Summary

The current Liminara executor taxonomy (`:inline`, `:task`, `:port`, `:nif`, `:container`) is uniformly **per-op**. Every executor invocation is op-scoped: provision, run, capture artifacts, tear down. This works cleanly for compiler-shaped pipelines (House Compiler, Process Mining, FlowTime) where each op is a near-pure function over content-addressed inputs.

It does **not** model agentic-coding-shaped pipelines well. In those, the pipeline runs *inside* a long-lived environment — the repo is cloned once, a work branch is created once, an LLM op proposes an edit, a write op mutates the working tree, a test op runs against the mutated tree, the LLM reads the failures, another edit, another test run. The substrate is a stateful workspace, not a sequence of pure functions. The Software Factory pack draft (`docs/domain_packs/03_Software_Factory.md`) implicitly assumes this shape but does not name it; the runtime architecture (`docs/architecture/01_CORE.md`) does not provide a primitive for it.

This RFC names the gap, sketches two implementation paths (Lite and Full), maps which packs need which, identifies the architectural amendments required, and proposes a sequencing that defers the decision until forced — but keeps both paths open from M-CONTRACT-02 onward.

The two paths in one sentence each:

- **Path A — Lite (single runtime + run context).** Add `run_context` as a first-class plan-level primitive. The runtime provisions a long-lived environment (container/VM) at run start; ops execute *inside it* via a thin in-VM agent. One event log, one artifact store, one replay model, with the model's "ops are pure functions over artifacts" invariant explicitly weakened to allow workspace-as-mutable-substrate.
- **Path B — Full (recursive Liminara-on-Liminara).** Outer Liminara provisions the VM, an inner Liminara runs the actual pipeline inside it. The outer treats the inner run as a single recordable unit (event log + artifacts exfiltrated as outputs). Two event logs, two replay layers, but each layer keeps its "pure functions" invariant intact at its own level.

The proposal's recommendation: **build Path A when Software Factory ships; keep Path B in the back pocket as a meta-architecture pattern; ensure M-CONTRACT-02's schemas don't preclude either.**

---

## Background — the two shapes

### Op-scoped containers (today)

The executor at `docs/architecture/01_CORE.md:464-471` is per-op. An op declares `execution: %{executor: :container, entrypoint: ..., timeout_ms: ...}`; the runtime provisions a fresh container for *that op invocation*, runs the op's entrypoint, captures declared output artifacts back into the artifact store, tears the container down. State between ops flows exclusively through the artifact store. Replay is clean because no state leaks across op boundaries.

This is the right shape for:
- **House Compiler** (`docs/domain_packs/02_House_Compiler.md`) — each compiler pass is a near-pure function: SketchUp model → semantic IR → structural check → PDF render → NC code. Stateful workspace would be a liability.
- **Process Mining** (`docs/domain_packs/05_Process_Mining.md`) — event log → cleaned log → discovered model → reports. Same compiler shape.
- **FlowTime Integration** (`docs/domain_packs/04_FlowTime_Integration.md`) — spec → model → run → telemetry.
- **Population Simulation** (`docs/domain_packs/07_Population_Simulation.md`) — heavy compute via `:port` / `:container`, but each op is a function over snapshots.
- **Radar** (`docs/domain_packs/01_Radar.md`) — fetcher → snapshot → extractor → cluster → briefing. Compiler-shaped.

For these packs, the current architecture is exactly right. **This RFC does not propose changing it.**

### Pipeline-scoped containers (the gap)

Some workloads do not decompose into compiler passes. Their unit of work is *a session against a workspace*, where the workspace mutates continuously and ops are commands inside the session, not functions over independently-addressed artifacts.

The canonical example is agentic software development:

```
[run start]
  clone repo at ref          (provision workspace)
  create branch agent/<id>   (mutate workspace)
  loop:
    LLM: read code, propose diff   (recordable)
    apply diff to working tree     (mutates workspace)
    run linter                     (reads workspace)
    run tests                      (reads workspace)
    LLM: read failures, decide next move (recordable)
  open PR                          (side-effecting)
[run end]
  tear down workspace
```

If you try to model this as op-scoped containers, the artifact store has to materialize the entire repo state after every edit, then re-instantiate it as a fresh container for the next op. For a 2GB repo and 30-step LLM iteration loop, that's 60GB of artifact churn for a single ticket — and it's the wrong abstraction, because the LLM's working memory of "the repo" is a *live mutating filesystem*, not a sequence of independently-content-addressable snapshots.

Other workloads with similar shape:
- **Agent Fleets** (`docs/domain_packs/06_Agent_Fleets.md`) — long-lived episodes where an agent operates against an evolving environment. Each episode could be pipeline-scoped.
- **Behavior DSL** (`docs/domain_packs/08_Behavior_DSL.md`) — depending on the implementation, behaviors operating against simulated environments may want pipeline scope.
- **Toy Ruleset Lab** (`docs/domain_packs/12_Toy_Ruleset_Lab.md`) — exploratory rule iteration sessions.

The pattern: when a pack's natural unit of work is "a session against a workspace" rather than "a function over artifacts," it wants pipeline scope.

---

## Path A — Lite (single runtime, run-context primitive)

### Conceptual model

The plan declares a `run_context` at the plan level (peer of nodes/edges). The runtime provisions the context once at run start; it lives until run termination. Ops in the plan can be marked as executing *inside* that context.

Schematic plan structure:

```yaml
plan:
  id: "sf.fix-ticket-1234"
  run_context:
    kind: container               # or :vm, :devcontainer
    image: "ghcr.io/foo/dev:abc"
    workspace:
      source: { kind: git_clone, repo: "...", ref: "main" }
      mount_at: /workspace
      mode: rw
    network: restricted           # or :none, :unrestricted
    secrets: [ "github_token" ]
    teardown_on: [ success, failure, timeout ]
  nodes:
    - id: plan_changes
      op: sf.plan_changes
      executor: in_context        # NEW: dispatch into run context
      determinism: recordable
    - id: apply_diff
      op: sf.apply_patch
      executor: in_context
      determinism: pure_in_context  # NEW class — see §"Replay semantics"
    - id: run_tests
      op: sf.run_tests
      executor: in_context
      determinism: pinned_env
    ...
```

### In-context agent protocol

The runtime ships a thin agent into the run context (image-baked or fetched at provisioning). The agent listens on a unix socket / port for op invocations from the outer runtime. Protocol surface (sketch — exact contract is post-M-CONTRACT-02 work):

```
INVOKE  { op_module, op_function, inputs: [...artifacts or workspace_paths], env: {...} }
        → STARTED { invocation_id }
EVENT   { invocation_id, kind: :stdout|:stderr|:progress, payload }
RESULT  { invocation_id, exit_code, outputs: [...declared artifacts], error?, duration_ms }
HEARTBEAT { invocation_id, last_progress_at }
```

Outer runtime's Run.Server treats each `INVOKE`/`RESULT` round trip exactly like any other op execution from its event log's perspective. `node_started` / `node_completed` events get emitted normally. The agent is just another executor backend — equivalent in role to a `:port` or `:nif` executor today, but with a long-lived peer process instead of a per-op spawn.

### Replay semantics

This is where the Lite path explicitly weakens the pure-functions invariant, and the weakening must be acknowledged not smuggled.

Two new determinism distinctions are needed:

- **`pure_in_context`** — deterministic given the same workspace state at op start. Its inputs are not fully content-addressed (workspace paths are by-reference, not by-hash). Replay requires re-executing in a workspace whose history (the prior chain of in-context ops) matches.
- **`recordable_in_context`** — same as `recordable` (LLM call etc.), with the same workspace caveat: the LLM's input includes whatever it reads from the workspace at call time, and what it reads depends on prior in-context ops' edits.

Replay strategy: the run's event log records the *sequence* of in-context op invocations and their declared outputs. To replay, the runtime re-provisions the run context (same image + same source ref), then re-executes the sequence of in-context ops in order, injecting recorded decisions for `recordable` ops. The final workspace state should be deterministically reproducible, modulo:
- Image drift (mitigated by image hash pinning).
- Filesystem operations that depend on time/UID/path-randomness (pack discipline issue, not runtime issue).
- Side-effecting ops outside the workspace (network calls, etc. — these are explicitly side-effecting, no replay).

Cache semantics weaken too: in-context ops cannot be cached the way op-scoped pure ops can, because their input includes workspace state that's not independently hashable. Caching becomes per-run, not cross-run.

### What persists in the artifact store

Even though the workspace is mutable mid-run, the artifact store still records the audit-load-bearing pieces:

- **Inputs to recordable ops** (the prompts, the workspace excerpt the LLM read at that moment).
- **Outputs of recordable ops** (the LLM's response — full content, content-addressed).
- **Diffs** (each apply_patch op records the diff it applied as a content-addressed artifact).
- **Test/lint reports** (the structured output of test runs).
- **Final commit / PR metadata** (the side-effecting op's receipt).

What does *not* persist in the artifact store: intermediate working-tree states between ops. They're not independently re-derivable from the artifact store alone — they're re-derivable from the *sequence of recorded ops* applied to the initial workspace.

This is a real semantic shift from current Liminara. It should be documented as such (proposed: a new ADR, ADR-RUN-CONTEXT-01, defining the run-context primitive and the replay weakening; and a paragraph in `docs/governance/` if a governance file is established for runtime semantics).

### Lifecycle

- **Provision.** At run start, runtime takes the plan's `run_context`, provisions container/VM, mounts workspace per spec, injects scoped secrets, starts the in-context agent. Emits `run_context_provisioned` event.
- **Execute.** Run.Server dispatches in-context ops to the agent over the protocol. Each invocation produces normal node events.
- **Gate.** Human gates work as today — they're independent of executor; the gate UI surfaces, the gate's decision is recorded, the run unblocks. Gates can read run-context state (e.g., "show me the current diff") via a read-only protocol on the agent.
- **Teardown.** On terminal state (success/failure/abandonment/timeout), the runtime drains pending events, archives the agent's logs, tears down the run context. Emits `run_context_torn_down`.
- **Crash recovery.** If the daemon crashes mid-run, the run context is by default abandoned (the in-VM agent exits when its parent socket closes; the workspace is GC'd). A future enhancement could persist enough state to re-attach — but that's a real complication and probably v2.

---

## Path B — Full (recursive Liminara-on-Liminara)

### Conceptual model

The outer Liminara provisions a VM and starts an inner Liminara inside it. The inner Liminara runs the actual pipeline (with whatever op-scoped or pipeline-scoped semantics it wants — it can itself use Path A if it likes). The outer runtime treats the inner run as a single recordable op:

```yaml
plan:                  # outer plan
  nodes:
    - id: agentic_run
      op: meta.run_inner_liminara
      executor: container
      determinism: recordable
      execution:
        image: ghcr.io/foo/dev-with-liminara:abc
        inner_pack: software_factory
        inner_plan_inputs: { task_spec: ... }
      outputs:
        - inner_event_log     # full inner run's event log, exfiltrated
        - inner_decisions     # all decision records from the inner run
        - inner_artifacts     # everything the inner pipeline produced
        - delivery_receipt    # final commit/PR
```

From the outer runtime's perspective, the agentic-coding workflow is one op. From the inner runtime's perspective, it's a full Liminara run with its own DAG, event log, artifact store, replay model.

### Why this is structurally elegant

The composition rule is fractal: a Liminara run is a sub-DAG; a sub-DAG can be implemented as a Liminara run; therefore a Liminara run can host a Liminara run. The "ops are pure functions over content-addressed artifacts" invariant is preserved at each layer independently. The outer's invariant: `meta.run_inner_liminara` is a pure-ish function that takes (image, inner pack, inner plan inputs) and produces (event log, decisions, artifacts). The inner's invariant: whatever its plan declares, with full Liminara semantics, against a workspace that lives only in the inner's process world.

### Two replay modes

- **Outer-only replay** — re-provision VM, re-run inner pipeline live. Inner LLM calls may pick differently; outer outputs may differ. Useful for "what would the agent do today against the same spec?"
- **Inner-replay** — re-provision VM, re-run inner pipeline with all inner decisions injected. Deterministic up to image hash. Useful for audit ("show me exactly what the agent did, in full detail, reproducibly").

The user picks which mode at replay time; the choice is recorded as part of replay metadata.

### Bootstrap

How does the inner Liminara get into the VM?

- **Image-baked** (default). The container image includes a Liminara binary (or a self-extracting installer) at a known path. The outer runtime's provisioning step starts it as the entrypoint with a one-shot config. Image management is a real cost — Liminara version drift between outer and inner becomes a pinning question.
- **Mounted from outer** (alternative). The outer runtime exposes its own Liminara binary as a read-only mount into the VM. Pro: no image management. Con: blurs the isolation boundary (the VM has read access to the outer's binary; in some threat models that's fine, in others it's a leak).
- **Network-fetched** (rejected for default). The VM downloads a pinned Liminara binary at provision time. Pro: simple. Con: requires VM network access, breaks airgapped deployment, adds provisioning latency.

Image-baked is the default-good answer. Mounted is acceptable for trusted-environment deployments.

### Two event logs

The outer event log records the outer DAG's execution as today. The single op `meta.run_inner_liminara` produces a `node_completed` event whose payload includes a pointer to the *inner* run's event log artifact. Audit UI gets a "drill into inner run" affordance: clicking the inner-run node opens that run's full DAG view, event timeline, decisions, artifacts — all rendered as a normal Liminara run, just sourced from the artifact store rather than live.

### Why the strong arguments are real

- **Security boundary.** Prompt injection in repo content can't reach outer runtime state. Outer secrets, other tenants' runs, the outer artifact store — all isolated by VM boundary plus by the recursive runtime's internal isolation. This is a genuinely strong argument for multi-tenant SaaS posture.
- **Runtime independence.** The inner runtime can be a different Liminara version, or — at the limit — a non-Liminara runtime that satisfies the same exec-and-harvest contract. This is a real seam for future flexibility.
- **Per-layer audit clarity.** "What did the platform do?" → outer log. "What did the agent do inside its sandbox?" → inner log. They don't intermix.
- **Per-tenant policy.** Each VM can run a different inner pack version, different policy config, different LLM provider — without affecting other tenants.

### Why the costs are real

- **Resource overhead.** A full Liminara process tree per ticket: Run.Server, artifact store, event log, A2UI provider. For a 5-LLM-call ticket, that's ~10× more process state than the actual workload needs.
- **Bootstrap complexity.** Image-baked Liminara means image management discipline, Liminara version pinning per image, upgrade paths.
- **Two pack manifests.** The outer pack declares "VM provisioning + inner-run dispatch + harvest"; the inner pack declares the actual work. Or one manifest with explicit outer/inner sections — design choice, neither is obviously right.
- **Cross-layer plumbing.** Gates raised in the inner pipeline have to surface in the outer UI (or in the inner UI, accessed through the outer's drill-down). Decisions on inner gates have to flow inward. This is doable but it's plumbing.
- **The hard question.** What does the outer Liminara contribute that's load-bearing? Sandboxing + lifecycle + gate routing — but a thin orchestrator could do all of those without being a full Liminara. The recursion is intellectually satisfying but for v1 it pays for elegance the use case may not need.

---

## Comparison matrix

| Dimension | Op-scoped (today) | Path A (Lite) | Path B (Full) |
|---|---|---|---|
| **Workspace mutability** | None — artifact-only | Mutable workspace per-run | Mutable workspace per-run, isolated by VM |
| **Replay invariant** | Pure functions over hashes | Pure functions over (initial workspace + op sequence) | Pure at each layer; composed fractally |
| **Event logs** | One | One | Two (outer + inner per run) |
| **Cache scope** | Cross-run (CAS) | Per-run only for in-context ops | Cross-run at outer; per-run at inner |
| **Security boundary** | Per-op container | Per-run container/VM | Per-run VM + recursive runtime isolation |
| **Resource overhead** | Per-op spawn | Per-run spawn + thin agent | Per-run spawn + full inner runtime |
| **Bootstrap** | Image only | Image + agent binary | Image + Liminara binary |
| **UI surface** | Single DAG view | Single DAG view + workspace browser | Outer DAG + drill-into-inner |
| **Suits**                    | Compiler-shaped packs | Workspace-shaped packs (1 layer) | Multi-tenant platform / runtime independence |
| **Implementation cost (relative)** | (in place) | ~2 milestones | ~5–8 milestones |

---

## Pack-by-pack analysis

| Pack | Today's executor fit | Pipeline-scoped need? | Recommended path |
|---|---|---|---|
| **Radar** (`01_Radar.md`) | `:inline` + `:port` ok | No — pure compiler shape | Op-scoped (no change) |
| **House Compiler** (`02_House_Compiler.md`) | `:port` + `:container` + `:nif` ok | No — compiler passes are pure | Op-scoped (no change) |
| **Software Factory** (`03_Software_Factory.md`) | Insufficient | **Yes — workspace is the substrate** | **Path A (Lite)** |
| **FlowTime** (`04_FlowTime_Integration.md`) | `:port` + `:container` ok | No | Op-scoped (no change) |
| **Process Mining** (`05_Process_Mining.md`) | `:container` + `:port` ok | No | Op-scoped (no change) |
| **Agent Fleets** (`06_Agent_Fleets.md`) | Mostly ok | **Maybe — per-episode** | Path A per episode (defer until Fleet pack ships) |
| **Population Sim** (`07_Population_Simulation.md`) | `:port` + `:container` ok | No | Op-scoped (no change) |
| **Behavior DSL** (`08_Behavior_DSL.md`) | TBD | Possibly | Decide at pack design time |
| **Evolutionary Factory** (`09_Evolutionary_Factory.md`) | `:port` ok | No — GA inner loops are pure | Op-scoped (no change) |
| **LodeTime Dev Pack** (`10_LodeTime_Dev_Pack.md`) | TBD | Possibly | Decide at pack design time |
| **Toy Report Compiler** (`11_Toy_Report_Compiler.md`) | `:inline` ok | No | Op-scoped (no change) |
| **Toy Ruleset Lab** (`12_Toy_Ruleset_Lab.md`) | `:inline` + `:port` ok | Possibly — exploratory iteration | Decide at pack design time |
| **Toy GA Sandbox** (`13_Toy_GA_Sandbox.md`) | `:inline` ok | No | Op-scoped (no change) |

The pattern: **one pack today** definitively needs Pipeline-scoped (Software Factory). One or two more *might* (Agent Fleets, Behavior DSL, Toy Ruleset Lab). Full Liminara-on-Liminara has zero confirmed packs — its use case is platform-shape (Liminara-as-multi-tenant-SaaS), which is post-product-market-fit territory.

---

## Current architecture — what's in place, what precludes

### Already in place

- **Executor taxonomy.** `:inline`, `:task`, `:port`, `:nif`, `:container` (`01_CORE.md:464-471`). Adding a new executor backend (`in_context`) is a precedented extension, not a model break.
- **Determinism classes.** `pure`, `pinned_env`, `recordable`, `side_effecting` (`01_CORE.md:478-494`). Adding `pure_in_context` / `recordable_in_context` is a precedented extension.
- **Decision records.** Universal recording mechanism (`01_CORE.md:63, 187`). The `decision.gate_approval.v1` pattern (Software Factory §5) shows decisions don't have to be LLM-only — human gates and any nondeterministic op fit. In-context LLM decisions fit the same model.
- **Gate vocabulary.** `gate_requested` / `gate_resolved` events, `decision.gate_approval.v1` artifact (`01_CORE.md:218-219, 432-436`). Gates are executor-agnostic — they work the same whether the gated op is op-scoped or pipeline-scoped.
- **A2UI surfaces.** Already drafted for Software Factory: workspace browser, patchset/diff review, test log viewer, PR publishing gate (`03_Software_Factory.md` §6). These are exactly the surfaces Path A needs. Inner-run drill-down for Path B would be additional UX work.
- **Process isolation per run.** `01_CORE.md:401, 450` — each run is an isolated supervision subtree. Adding a long-lived run context is just a peer process under the run's supervisor.

### What precludes Pipeline-scoped today

- **No plan-level context concept.** The plan today is `nodes + edges`. Adding a `run_context` block is a new top-level field — not a destructive change, but a schema-level addition that needs to land in ADR-PLAN-01 (M-CONTRACT-02) or be left explicitly room-shaped.
- **Executor is per-op-invocation.** The runtime today provisions per-op. Adding `in_context` as an executor that dispatches to a long-lived peer requires Run.Server changes plus the agent protocol.
- **Cache key assumes content-addressed inputs.** `cache_key = hash(op_name, op_version, hash(input_artifacts), env_hash?)` (`01_CORE.md:480`). In-context ops can't fully participate without breaking this — needs an explicit "no cross-run cache for in-context ops" rule.
- **Workspace as artifact assumption.** The `sf.repo_snapshot.v1` artifact in the Software Factory draft (§4) implies the repo *is* a content-addressed artifact. For 2GB repos that's untenable; for in-context execution it's wrong-shape (the workspace mutates). The pack draft would need amendment to acknowledge "initial workspace state is a snapshot artifact; subsequent state is the agent's filesystem."

### What precludes Recursive (Path B) today

Everything Path A precludes, plus:

- **No nested-run concept.** A run today is a top-level entity. The artifact store, event log, and Run.Server are not currently designed to host a child run as one of their own ops' outputs. Adding that is a Run.Server-level change.
- **No exec-and-harvest contract.** The outer-to-inner dispatch needs a stable protocol: how the outer hands inner-pack + inner-plan inputs to the inner runtime, how the inner reports completion, how artifacts get exfiltrated as content-addressed blobs back into the outer's CAS, how the inner's event log lands as an outer artifact. None of this exists.
- **No inner-run UI surfacing.** The A2UI provider would need a "drill into nested run" affordance, served by re-rendering an archived run's state from artifact-store data. Substantial UI work.

---

## Required amendments per path

### For M-CONTRACT-02 (now)

Neither path requires changes inside M-CONTRACT-02. What M-CONTRACT-02 *should* do is leave room:

- **ADR-MANIFEST-01.** No change needed — the manifest is per-pack metadata, not per-plan. Pipeline-scoped is a plan-level concern, not a manifest concern.
- **ADR-PLAN-01.** **Action: leave a `run_context` field as optional and forward-compatible.** Either declare it as a reserved-for-future field in the CUE schema (with a `// reserved` comment) or omit it entirely while ensuring the schema's `close()` discipline doesn't reject plans that include unknown top-level fields in a not-yet-pinned-down manner. The cleanest form is probably an explicit `run_context?: #RunContext | null` field with `#RunContext` defined as a placeholder type that can be elaborated post-RFC.
- **ADR-OPSPEC-01.** **Action: ensure executor and determinism enums are open to extension.** Don't enumerate `:inline | :task | :port | :nif | :container` as a closed CUE disjunction without a clear extensibility story; same for determinism classes.
- **ADR-REPLAY-01.** **Action: ensure the replay protocol's invariants don't bake in "every op input is fully content-addressed."** If the replay protocol asserts content-addressing of all inputs, it'll need to be amended later for in-context ops. A more general "replay re-derives the same outputs from the same recorded sequence" framing leaves room.
- **ADR-WIRE-01.** No change needed — wire protocol is for `:port` execution; in-context is a different executor backend with its own protocol.

These amendments are cheap if done now and expensive if discovered later. They are **the only M-CONTRACT-02 implications of this RFC.**

### For Path A (when implemented)

New ADRs, drafted at the time Path A is built (likely around when Software Factory pack is constructed):

- **ADR-RUN-CONTEXT-01.** Defines the `run_context` plan-level primitive: lifecycle (provision/execute/teardown), supported kinds (container/VM/devcontainer), workspace specification, secret scoping, network policy, teardown triggers. Names the replay-invariant weakening explicitly.
- **ADR-IN-CONTEXT-EXECUTOR-01.** Defines the `in_context` executor backend: how Run.Server dispatches to a long-lived peer agent, the agent protocol, error handling, agent crash recovery.
- **ADR-WORKSPACE-01.** Defines the workspace abstraction: how the run-context's workspace is provisioned (git_clone, local_path, fresh, named volume), mount semantics, ownership/UID, GC policy. Companion to ADR-FSSCOPE-01 from E-21 (which defines per-op fsscope) but at the run-context layer.
- **ADR-IN-CONTEXT-DETERMINISM-01.** Defines `pure_in_context` and `recordable_in_context` determinism classes and their cache/replay semantics.

Schema/contract changes to existing ADRs:

- **ADR-PLAN-01 amendment.** Elaborate the `#RunContext` type from placeholder to concrete schema.
- **ADR-OPSPEC-01 amendment.** Add `in_context` to the executor enum; add the two new determinism classes.
- **ADR-REPLAY-01 amendment.** Document the in-context replay weakening; specify the "replay re-executes recorded op sequence in re-provisioned context" path.

Pack-side changes:

- **Software Factory pack draft.** Amend §3 (IR pipeline) to acknowledge initial workspace as snapshot artifact + subsequent state as in-context filesystem. Amend §4 (op catalog) to mark workspace-mutating ops as `executor: :in_context`. Amend §7 (executor requirements) to specify pipeline-scoped sandboxed workspace, not per-op.

### For Path B (if/when adopted)

Everything Path A requires, plus:

- **ADR-NESTED-RUNS-01.** Defines the recursive-run pattern: outer run hosting inner run as a single op, exfiltration of inner event log + decisions + artifacts as outer's outputs, isolation guarantees.
- **ADR-EXEC-AND-HARVEST-01.** Defines the protocol between outer runtime and inner runtime: provisioning, plan submission, completion signaling, artifact transfer.
- **ADR-NESTED-REPLAY-01.** Defines outer-only-replay vs inner-replay modes and how the user selects between them.
- **ADR-NESTED-OBSERVABILITY-01.** Defines how the A2UI surface drills into archived inner-run state.
- **A `meta.*` pack** — a meta-runtime pack with ops like `meta.run_inner_liminara`, `meta.harvest_inner_run`. Lives at the same architectural layer as the runtime itself.
- **Bootstrap discipline.** Image-baked Liminara binary management; inner-runtime version pinning per image; upgrade paths.
- **Substantial UI work.** Drill-into-inner; cross-layer gate routing; outer/inner event log reconciliation views.

---

## Sequencing — when to do what

Stages, with rough phase/epic alignment:

1. **Now (M-CONTRACT-02, Phase 5c).** Apply the M-CONTRACT-02 amendments listed above (cheap insurance, ~half a day's work, ~no scope expansion). Add a `work/decisions.md` entry referencing this RFC and the deferred decision. Do not implement.

2. **Through Phase 5c–7 (Radar extraction + platform hardening).** No work required. Software Factory is post-Radar; the decision can stay deferred.

3. **Software Factory authoring (post-Radar, likely Phase 7+).** Decision point: do we build Path A now, or hold? If holding, Software Factory pack ships in a degraded form (op-scoped, expensive, slow agentic loops) — possibly fine for an MVP demo but not for real use. **Most likely:** build Path A as part of Software Factory pack construction. Estimated 2–3 milestones for the runtime work + Software Factory's own milestones for pack construction.

4. **Path B trigger evaluation (post-Software-Factory, ongoing).** As Liminara matures toward platform/SaaS posture, evaluate whether Path B becomes worth the cost. Triggers in §11.

### Sequencing summary

| Stage | When | What |
|---|---|---|
| RFC filed | 2026-05-02 | This document |
| M-CONTRACT-02 amendments | This milestone | Forward-compat schema room for `run_context`, open enums |
| `work/decisions.md` entry | This milestone | Defer-until-Software-Factory decision recorded |
| Hold | Phase 5c–7 | No further work |
| Path A implementation | Software Factory build (Phase 7+) | ADR-RUN-CONTEXT-01 + agent + executor + pack amendments |
| Path B trigger eval | Ongoing post-A | Reassess if multi-tenant or runtime-independence triggers fire |
| Path B implementation | If triggered | New ADR cluster, meta-pack, recursive runtime |

---

## Decision points / triggers

Explicit triggers that flip the recommendation:

### Triggers to start Path A (Lite)

- Software Factory pack moves from Draft to active build, **or**
- Agent Fleets pack moves to active build with per-episode workspace requirement, **or**
- Any pack identifies stateful workspace as load-bearing for its primary use case.

### Triggers to start Path B (Full) — any of:

- **Multi-tenant SaaS commitment.** Liminara becomes a hosted product with multiple customers running their own pipelines on shared infrastructure. The recursive isolation boundary becomes load-bearing.
- **Runtime independence requirement.** A real product requirement emerges to support non-Liminara inner runtimes (compatibility layer, customer-supplied runtime, third-party pack ecosystem with different runtime needs).
- **Compliance / audit pressure.** A regulated customer requires per-layer audit clarity beyond what Path A's single event log can provide. (Concrete shape: SOC 2 Type II auditor wants "platform actions" and "tenant agent actions" in independently-attestable logs.)
- **Cross-layer policy enforcement.** Need to express "platform may do X but tenant pack may not" in a way that survives prompt injection in the tenant's pack content. Path A's single-runtime model has weaker guarantees here.

### Triggers to *keep* Path B in the back pocket (don't build, don't preclude)

- Liminara stays single-tenant or small-team posture.
- Pack ecosystem stays first-party or trusted-third-party.
- Audit requirements stay at the per-run granularity.

The default is "build A when forced, keep B as latent."

---

## Open questions

The proposal does not pretend to resolve these:

- **Workspace volume strategy.** For Path A, is the workspace a docker-managed volume, a bind-mount of a host directory, a tmpfs, or a CoW filesystem snapshot? Each has trade-offs (durability, performance, GC discipline, host coupling).
- **Crash recovery for long-running runs.** If the daemon restarts mid-Software-Factory-run with 20 minutes of in-context work in flight, do we re-attach to the live container or abort? Probably abort for v1; re-attach is a real engineering project.
- **Agent protocol versioning.** As the agent protocol evolves, how does an outer runtime running version N talk to an in-context agent running version N-1? Same forward-compat discipline as wire protocol.
- **Concurrency within a run context.** Can multiple in-context ops execute concurrently against the same workspace? Probably yes for read-only ops, no for write ops, with a workspace-level lock or a CRDT-style merge story for parallel writes. v1 should pick the simple answer (serialize all in-context ops); v2 can complicate.
- **The pack-author DX for in-context ops.** Writing an op that runs in-context vs op-scoped should be ergonomically similar. SDK design (E-26) needs to know about both shapes when it lands.
- **Inner-runtime version skew (Path B).** If the outer is Liminara N and the inner is Liminara N-2, what guarantees do we make? Image-baked pinning gives us "the inner runs whatever the image was built with"; the question is what compatibility surface the outer needs to maintain across inner versions.
- **Cost in resources.** A single Liminara Run.Server is light, but how light? Path B's "spin a full Liminara per ticket" — is that 50MB of resident memory or 500MB? Empirical question that informs whether the recursion overhead is real or imagined.

---

## References

- `docs/architecture/01_CORE.md` — current runtime architecture, especially:
  - `:464-471` executor taxonomy
  - `:478-494` determinism classes and cache semantics
  - `:218-219, 432-436` gate vocabulary
  - `:401, 450` per-run process isolation
- `docs/domain_packs/03_Software_Factory.md` — drafted pack that implicitly assumes pipeline-scoped semantics
- `docs/domain_packs/02_House_Compiler.md` — pack that explicitly stays op-scoped
- `docs/domain_packs/06_Agent_Fleets.md` — pack with per-episode pipeline-scoped potential
- `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md` — current milestone whose contracts must leave room for both paths
- `.ai-repo/rules/liminara.md` — *Contract matrix discipline* section (relevant when ADR-RUN-CONTEXT-01 lands and produces matrix rows)
- Companion in spirit: `docs/architecture/proposals/lifecycle-fsm-engine.md` — same "name the structural gap before building" register

---

## Recommendation

1. **In M-CONTRACT-02:** apply the schema-room amendments listed in §"For M-CONTRACT-02 (now)". Add the deferred-decision entry to `work/decisions.md`. No implementation work in this milestone.
2. **Through Phase 7:** hold. Don't pre-build either path.
3. **At Software Factory build time:** build Path A. Author ADR-RUN-CONTEXT-01 and its companions. Amend Software Factory pack draft to reflect actual semantics.
4. **Path B:** keep latent. Re-evaluate annually or when one of the §11 triggers fires.

The cost of the M-CONTRACT-02 amendments is low (forward-compat schema room) and the cost of *not* doing them is high (re-opening foundational contracts later to add fields the new shape needs). That asymmetry is the core argument for filing this RFC during M-CONTRACT-02 even though no implementation work is proposed for the milestone.
