# First Analysis: Honest Review of the Liminara Core Runtime

**Date:** 2026-03-02
**Reviewer:** Claude (requested adversarial review)
**Scope:** Core runtime viability, spec quality, risks, and hardening recommendations
**Inputs:** All 17 documents in `agent_runtime_specs/`

---

## Executive Summary

The Liminara specs describe a genuinely interesting system: a durable, observable execution substrate for heterogeneous workloads, built on Elixir/OTP. The core idea — force all work through artifact-producing IR passes with decision records for nondeterminism — is sound and would be valuable if built.

**However, there are real concerns:**

1. **The specs are AI-generated** and show characteristic patterns of that: consistency without depth, plausible-sounding but untested claims, and hidden complexity swept under abstractions.
2. **The scope is extreme** for a solo developer. 13 domain packs, a custom runtime, a custom artifact store, and distributed execution.
3. **Key hard problems are acknowledged but not solved.** The specs name the right risks but the mitigations are often just labels ("use allowlists", "pin environments") without designs.
4. **The build-vs-buy analysis is too generous to "build."** Temporal + a thin artifact layer would get you 70% of the value with 20% of the effort.
5. **A2UI is a good fit but still early.** The protocol (v0.8, Google) is real and well-designed for this use case, but it's in public preview and still evolving. Have a fallback plan.

**Verdict:** The *concept* is viable. The *scope* will kill it. The path to something real requires ruthless reduction and honest acknowledgment of what's actually hard.

6. **The house compiler conversation validates the core model.** A deep design conversation about using Liminara for timber-frame house compilation (SketchUp → structural analysis → manufacturing outputs) confirms the IR pipeline model isn't just metaphorical — it's a literal compiler. This also reveals gaps: convergence protocols for coupled agents, binary artifact handling, regulatory transition logic, and pack-managed reference data. See `docs/research/house_compiler_context.md`.

---

## 1. A2UI: Good Choice, but Understand the Maturity

### The situation

A2UI (Agent-to-UI) is a **real Google project** ([github.com/google/A2UI](https://github.com/google/A2UI), [a2ui.org](https://a2ui.org/)) with 11k+ stars and active development. The v0.8 specification exists and is well-designed for exactly this use case: declarative, streaming UI messages from agent backends to clients, with native widget rendering.

### Why it's a good fit

- **Declarative, no code injection** — agents send JSON component descriptions, not executable code
- **LLM-optimized** — flat JSON structure designed for incremental generation by transformers
- **Framework-agnostic** — works across React, Flutter, Angular, native mobile
- **Progressive rendering** — UIs stream and build in real-time, which maps well to run progress

### The risk

A2UI is at v0.8 "Public Preview." The spec is evolving. You are betting on an early-stage protocol.

### What to do

- Use A2UI as the primary UI protocol — it's the right abstraction
- But build your internal event model (run events, gate events, artifact events) as a clean intermediate layer that A2UI renders *from*
- If A2UI changes or stalls, you can swap the rendering layer without redesigning the event model
- Consider Phoenix Channels as the transport layer for A2UI messages in the Elixir stack

---

## 2. The Specs Are AI-Generated (and It Shows)

### Evidence

- **Structural uniformity.** All 13 pack specs follow an identical template (sections 1-10, same headings, same phrasing). Real specs evolve differently per domain.
- **Plausible but untested claims.** Statements like "compiler passes model naturally maps to agent fleets" are asserted but never demonstrated with a concrete example of how an agent fleet episode becomes a DAG.
- **Boilerplate mitigations.** Risk sections across packs repeat the same phrases: "strict allowlists", "pin environments", "audit logs". These are labels, not designs.
- **No contradictions or tension.** Real architecture documents have tradeoffs that create friction between requirements. These specs are suspiciously harmonious.
- **Well-researched citations.** The appendix references are all real and relevant — the pattern of an LLM doing a good job of looking well-researched.

### Why this matters

AI-generated specs are excellent for *exploration* — they help you map the space quickly. But they're dangerous if treated as *validated designs*, because:
- They confidently describe things that haven't been thought through
- They hide complexity behind consistent abstraction layers
- They don't capture the hard-won insight that comes from actual prototyping

### What to do

Treat these specs as **brainstorming output, not architecture.** Use them as a map, but verify every claim by building. The walking skeleton approach in the roadmap is the right instinct — lean into it harder.

---

## 3. Scope Analysis: Why This Could Die

### What a solo developer is signing up for

The core runtime alone requires:
- DAG scheduler with dependency tracking, retries, timeouts, cancellation
- Content-addressed artifact store with metadata index
- Append-only event log with replay capability
- Executor abstraction (ports, containers, remote workers, Wasm)
- Policy/gate system for HITL
- Multi-tenancy with isolation
- Budget enforcement
- Observation UI / event streaming
- Pack registration and schema management

This is roughly equivalent to building a simplified Temporal + a simplified MLflow + a custom UI — in Elixir, by yourself.

### The pack explosion

13 domain packs are described. Even if you only build 3 (the recommended toy packs), each one requires:
- Schema definitions for 4-6 artifact types
- Op implementations with correct determinism contracts
- Executor integration
- UI views

### The honest timeline

For a solo developer working full-time:
- Walking skeleton (runs, ops, artifacts, one executor): 2-4 months
- First toy pack (Report Compiler): 1-2 months
- Observation UI (basic run viewer): 1-2 months
- Radar prototype: 2-4 months

That's 6-12 months before you have something you can use daily. This is feasible but requires extreme discipline to avoid scope creep.

### What to do

1. **Cut multi-tenancy from v0.** You're a solo dev. You are the only tenant. Add it later if the system proves valuable.
2. **Cut distributed execution from v0.** Run single-node. Distributed Erlang is a trap — it's easy to start but hard to get right.
3. **Cut 10 of the 13 packs from your planning horizon.** Actively refuse to think about Population Simulation or Evolutionary Factory until Radar is running.
4. **Set a time box.** If the walking skeleton doesn't work in 3 months, reconsider the build-vs-buy decision.

---

## 4. Build vs Buy: The Case Against Building

### What Temporal gives you for free

- Durable execution with event sourcing and replay
- Workflow state machines with crash recovery
- Activity retries with backoff
- Timeouts, heartbeats, cancellation
- Signal/query for human-in-the-loop
- Multi-tenancy (Temporal Cloud) or self-hosted
- SDKs in Go, Java, Python, TypeScript, .NET
- Battle-tested at scale (Uber, Netflix, Snap, Stripe)

### What you'd still need to build on top of Temporal

- Content-addressed artifact store (Temporal doesn't do this)
- Decision record capture (custom activity wrapper)
- Pack registration and schema management
- The observation UI
- Domain-specific ops

### The Elixir SDK problem

There is no official Temporal Elixir SDK. There are community efforts but they are immature. This is the strongest argument for building custom — if you're committed to Elixir.

### Alternatives worth considering

**Dagster** is the closest existing system to what Liminara describes:
- Asset-based (artifacts map to assets)
- Strong lineage/provenance
- Good UI for debugging pipelines
- Python ecosystem
- Software-defined assets are similar to "ops producing artifacts"

The tradeoff: it's Python, not Elixir. You'd lose the BEAM advantages for the control plane. But you'd gain an ecosystem, a community, and years of battle-testing.

### My honest assessment

If the goal is to **build products** (Radar, a house compiler, etc.), use Dagster or Temporal+Python and build domain logic. You'll ship faster.

If the goal is to **build a platform** because the platform itself is the intellectual project, build custom in Elixir. But be honest that the platform is the product, not the packs.

---

## 5. Core Design Issues (Assuming You Build)

### 5.1 The DAG model is underspecified for agent workloads

The specs claim "agent fleets and compiler passes are just different ways to generate DAG-shaped work." This is true in a trivially abstract sense but hides a real tension:

**Compiler pipelines** are:
- Mostly static DAGs (known shape before execution)
- Short-lived (minutes to hours)
- Deterministic except for explicit LLM steps

**Agent fleets** are:
- Open-ended (the agent decides what to do next based on observations)
- Long-lived (days, weeks, indefinitely)
- Fundamentally reactive (stimulus → response, not plan → execute)

The spec bridges this with "dynamic expansion" — an agent episode becomes a run that dynamically expands its DAG. But this means the DAG is being *constructed during execution*, which makes the scheduler, the UI, the replay logic, and the budget enforcement all significantly more complex than for static DAGs.

**Recommendation:** Define two run modes explicitly:
1. **Pipeline mode**: DAG is known at plan time, with optional fan-out nodes. This is the compiler use case.
2. **Episode mode**: DAG is constructed step-by-step by the executing logic. This is the agent use case.

Don't pretend they're the same thing. They share infrastructure but have different scheduling, display, and replay semantics.

### 5.2 Replay semantics have unsolved edge cases

The three replay modes (exact, verify, selective refresh) are well-conceived but have real implementation complexity:

**Exact replay with LLM decisions:**
- You store the LLM response as a decision record and inject it on replay. Fine.
- But what if the LLM call included tool use? The tool calls themselves may have been nondeterministic.
- The spec says "store tool-call traces" but doesn't specify the granularity. Do you replay at the level of "LLM call → response" or "LLM call → tool call 1 → tool result 1 → tool call 2 → tool result 2 → final response"?

**Selective refresh with graph changes:**
- If you change one op's implementation and want to refresh downstream, what if the downstream graph was dynamically expanded based on the *output* of the changed op?
- The new output might produce a different expansion (different number of URLs, different candidates). Now you can't just re-run downstream — the graph shape is different.

**Verify replay with floating-point:**
- "Deterministic with pinned environment" doesn't guarantee bitwise-identical floats across different CPU architectures or compiler versions. The structural check ops in the house compiler will hit this.

**The user's key insight on replay:** "Once the non-deterministic parts (GA optimization, LLM decisions etc) have been made, then we get a DAG. On the 'replay' we just replay the decisions, we don't have to 'discover' them." This is the right mental model — discovery mode builds the DAG by making nondeterministic choices, and replay mode executes a recorded graph by injecting stored decisions. The distinction between "discovery" and "replay" is cleaner than the spec's three replay modes and should probably be the primary framing.

**Recommendation:** Start with only exact replay (inject all decisions) and pipeline-mode DAGs. Add verify replay once you have test cases that exercise it. Defer selective refresh until you understand the graph-change problem concretely.

### 5.2.1 Convergence protocol (missing from spec)

The house compiler conversation revealed a gap: when agent outputs are **coupled** (structural sizing affects thermal performance, which affects structural sizing), the pipeline isn't a simple DAG — it's an iterative loop.

For timber-frame houses, the coupling is weak enough that 2-3 iterations converge. But the spec has no mechanism for this. The runtime needs either:
- **Explicit loop nodes** in the DAG (a "converge" node that re-runs a subgraph until outputs stabilize)
- **Fixed-point detection** (compare artifact hashes between iterations; stop when stable)
- **Constraint propagation** as a pre-pass (analytically derive bounds before running the expensive pipeline)

This matters beyond house compilation — any pack with interacting agents (e.g., the software factory where test results affect code generation) will hit the same pattern.

### 5.3 The artifact store will become a bottleneck

Every intermediate is an artifact. For the GA Sandbox with 100 candidates per generation across 50 generations, that's 5,000+ fitness artifacts plus population snapshots plus decision records per run. For Radar with 200 sources, each producing snapshots, normalized docs, extracted items... you're at thousands of artifacts per daily run.

**Storage:** Manageable (most artifacts are small JSON/text). But the metadata index in Postgres will grow fast, and queries like "find all artifacts in the provenance chain of this briefing" become expensive without careful indexing.

**Performance:** Content-addressing means hashing every artifact on write. For large binary artifacts (PDFs, NC files, repo snapshots), this adds latency. Streaming hashing helps but adds complexity.

**Garbage collection:** This is the hard part. When can you delete an artifact? It might be:
- Referenced by a run that's still "interesting"
- Used as a cache hit for a future run
- Part of a provenance chain someone is debugging

Without a clear GC policy with reference counting or reachability analysis, the store grows without bound.

**Recommendation:**
- Start with local filesystem + SQLite, not S3 + Postgres. You can migrate later. Premature infrastructure choices are a classic solo-dev killer.
- Implement a simple retention policy: keep last N runs, keep all starred/bookmarked runs, delete the rest. Don't build a general GC system until you need one.
- Consider lazy hashing: hash on first read/compare, not on every write. Many artifacts will never be compared.

### 5.4 The executor contract is too thin

The spec defines:
```
execute_op(op_name, op_version, inputs, env, budget) -> outputs + logs + events
heartbeat(run_id, node_id)
cancel(run_id, node_id)
```

This doesn't cover:
- **Artifact materialization.** How does the executor get the input artifacts? Are they passed inline (expensive for large artifacts)? Via a shared filesystem? Via an artifact store API? The answer differs for BEAM local vs container vs remote worker.
- **Streaming outputs.** Some ops (LLM calls, simulations) produce partial results over time. The contract only has final outputs.
- **Resource negotiation.** The budget is passed but there's no protocol for the executor to report resource usage or negotiate limits.
- **Schema validation.** Who validates that the output artifacts match the declared schema? The executor? The runtime? Both?

**Recommendation:** Design the executor contract around artifact handles, not raw data:
- The runtime provides `artifact_store_url` and `artifact_ids` as inputs
- The executor fetches what it needs, produces output artifacts, and registers them
- The runtime validates schemas and links provenance

### 5.5 Multi-tenancy is premature

The spec describes tenant isolation for artifacts, runs, secrets, workspaces, and quotas. This is at least 3-6 months of additional work on top of the core:
- Row-level security in Postgres
- Secret management with per-tenant encryption
- Workspace isolation (filesystem namespacing or containers)
- Quota enforcement at the scheduler level

For a solo developer building a platform they'll use themselves, this is wasted effort.

**Recommendation:** Hardcode a single tenant. Use `tenant_id = "default"` everywhere so the data model is future-compatible, but don't build any isolation logic until you have a second user.

---

## 6. What the Specs Get Right

To be fair, several things are genuinely well-designed:

### 6.1 The determinism classification

The four-class system (pure, pinned-env, recordable, side-effecting) is clean and practical. It's more nuanced than most workflow systems, which treat everything as either deterministic or not. The "recordable" class for LLM outputs is the right abstraction.

### 6.2 The control plane / compute plane split

Keeping the BEAM as orchestrator-only and pushing compute to ports/containers is the correct call. It avoids the biggest Elixir footgun (heavy compute destroying scheduler fairness) while preserving the genuine benefits of OTP supervision and process isolation. The house compiler makes this concrete: geometry kernels (opencascade-rs via Rustler NIF), structural solvers, and PDF renderers all belong outside BEAM, but OTP supervision of those processes is exactly the right orchestration model.

### 6.3 The incremental roadmap

Toy packs → Radar → Software Factory → House Compiler is the right order. It validates the most important core features first (artifact handling, determinism, scheduling) before hitting the hard domain problems.

### 6.4 Snapshotting external inputs

The principle of "snapshot first, then process" is underappreciated in most agent frameworks. It's what makes replay possible and is a genuine differentiator from most workflow tools.

### 6.5 Decision records as a first-class concept

Treating LLM nondeterminism as something to be captured and managed — not just tolerated — is a good architectural instinct. Most agent frameworks treat LLM calls as opaque function calls. Making them auditable and replayable adds real value.

### 6.6 The "agent" abstraction is genuinely general

The house compiler conversation confirms that the agent model isn't just about LLMs. An "agent" in Liminara is any supervised, message-passing capability provider — LLM calls, Eurocode 5 calculations, geometry kernels, geographic database lookups, human approval gates, and GA optimizers all share the same supervision, artifact production, and decision recording infrastructure. The runtime doesn't care what's inside the agent; it cares about the contract. This generality is a real strength, not overengineering.

### 6.7 "Discovery mode" vs "replay mode" is a clean framing

The user articulated the replay model more clearly than the spec: discovery mode builds a DAG by making nondeterministic choices; replay mode executes a recorded DAG by injecting stored decisions. This is a simpler and more intuitive framing than the spec's three-mode taxonomy, and should probably be adopted as the primary mental model.

---

## 6.8 Validation strategy: omvärldsbevakning first, with a house spike

The ChatGPT conversation arrived at a smart validation sequencing:

1. Build omvärldsbevakning first — it forces you to build scheduling, ingestion, retries, dedup, caching, delivery, and audit trail. Low-stakes if something goes wrong.
2. But make it "compiler-shaped" — IR stages, immutable input snapshots, reproducible outputs. Don't let it become a text-only special case.
3. Add a tiny house spike early — a trivial pipeline (parameters → member list → PDF + BOM) to verify the core can handle binary artifacts and non-LLM agents.
4. Then build the house compiler for real on the validated runtime.

This avoids the trap of building a generic platform that accidentally only works for one workload shape.

---

## 7. Hardening Recommendations

If you proceed with building the core, here's what I'd change:

### 7.1 Define the pack contract as a behaviour/protocol

The spec says packs provide schemas, ops, graph builders, and A2UI views. But it doesn't define a concrete Elixir interface. Define it:

```elixir
defmodule Liminara.Pack do
  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback op_defs() :: [Liminara.OpDef.t()]
  @callback schema_defs() :: [Liminara.SchemaDef.t()]
  @callback plan(input :: term(), config :: map()) :: Liminara.PlanDAG.t()
end
```

This makes the pack boundary real, testable, and enforceable.

### 7.2 Build the walking skeleton against a concrete scenario

Don't build "generic runs, ops, artifacts." Build the Report Compiler first and extract the core from that. Let the first real pack drive the core API. You'll discover what's actually needed vs. what's speculative.

### 7.3 Use Oban for job processing instead of rolling your own

Oban is a mature Elixir job processing library backed by Postgres. It gives you:
- Durable job scheduling
- Retries with backoff
- Unique jobs (idempotency)
- Job dependencies (via Oban Pro)
- Telemetry integration

The DAG scheduler can be a thin layer on top of Oban, not a from-scratch GenServer state machine. This dramatically reduces the "walking skeleton" timeline.

### 7.4 Use event sourcing for runs, not just an event log

The spec mentions an "append-only event log" but treats it as a side output. Instead, make it the **source of truth**:
- Run state is derived from events, not stored separately
- The "run_nodes" table is a projection, not a mutable record
- This gives you replay for free — replay is just re-projecting events

This aligns with Temporal's approach and with Commanded/EventStore in the Elixir ecosystem.

### 7.5 Design the internal event model separately from A2UI rendering

A2UI is a good rendering protocol, but your internal events should be a clean intermediate layer:
- `run.started`, `run.completed`, `run.failed`
- `node.pending`, `node.running`, `node.succeeded`, `node.failed`, `node.gated`
- `artifact.produced`, `artifact.cached`
- `gate.requested`, `gate.resolved`
- `decision.recorded`

These internal events are published on Phoenix PubSub. A2UI rendering is a *consumer* of these events, translating them into declarative UI components. This separation means:
- You can test the event model without a UI
- You can swap A2UI for another renderer if needed
- The event log remains the source of truth, not the UI messages

---

## 8. The One-Page Version (What To Actually Do)

1. **Acknowledge the specs are a brainstorm**, not a validated design. Treat them as a map, not a blueprint.
2. **Design an internal event model** that A2UI renders from. Keep the event layer clean and testable independent of the UI protocol.
3. **Cut scope ruthlessly.** No multi-tenancy, no distributed execution, no Wasm executor, no 10 of the 13 packs.
4. **Decide: platform or product?** If product, consider Dagster/Temporal. If platform, commit to the timeline.
5. **Build the Report Compiler first** and extract the core from it. Not the other way around.
6. **Use Oban + event sourcing** to avoid reinventing durable execution.
7. **Time-box the walking skeleton** to 3 months. If it's not working, reconsider.
8. **Write tests, not more specs.** The next document should be an ExUnit test file, not another markdown file.

---

## Appendix: Document-by-document notes

| Document | Quality | Key Issue |
|----------|---------|-----------|
| `00_UMBRELLA.md` | Good | Honest build-vs-buy section; good A2UI choice |
| `01_CORE_RUNTIME.md` | Good | Underspecified executor contract; data model is reasonable |
| `ARCHITECTURE_REQUIREMENTS_BRIEF.md` | Good | Original brief; well-structured but high-level |
| `radar.omvarldsbevakning.md` | Good | Best pack spec; concrete IR pipeline; real risks |
| `software_factory.md` | Adequate | Security risks named but not designed for |
| `house_compiler.md` | Good | Geometry correctness is the real risk; the IR pipeline is well-designed. Detailed analysis in `docs/research/house_compiler_context.md` |
| `agent_fleets.md` | Weak | Doesn't reconcile fleet semantics with DAG model |
| `toy.report_compiler.md` | Good | Right choice for first validation |
| `toy.ruleset_lab.md` | Good | Clean domain; good for testing rules-as-data |
| `toy.ga_sandbox.md` | Adequate | Storage explosion risk acknowledged but not solved |
| `flowtime.integration.md` | Adequate | Assumes FlowTime exists and is Elixir-native |
| `lodetime.dev_pack.md` | Adequate | Tooling sprawl is the real problem |
| `process_mining.md` | Adequate | Delegates to PM4Py; pack is a thin wrapper |
| `population_sim.md` | Weak | Performance model is unclear; BEAM limitations |
| `behavior_dsl.md` | Adequate | Scope explosion risk is real |
| `evolutionary_factory.md` | Weak | Depends on multiple other packs existing first |

---

*See also: [docs/research/](../research/) for supporting research on alternatives and specific technical topics.*
