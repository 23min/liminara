# Domain Pack: Population Simulation Pack

**Status:** Draft
**Last updated:** 2026-03-22
**Pack ID:** `population_sim`

---

## 1. Purpose and value

Provide an agent-based simulation framework for modest to large populations (starting with ~1,000 individuals), with durable epochs, snapshots, and replay.

This pack is the bridge between "agent" metaphors and interests in flow systems, bottlenecks, emergent social dynamics, and inverse modeling.

### Market validation

In March 2026, **MiroFish** — an LLM-backed social simulation system built by a 20-year-old in 10 days — hit #1 on GitHub global trending and attracted a $4.1M investment within 24 hours. A single developer integrated it with a Polymarket trading bot, simulated 2,847 digital humans per trade, and reported real profit over 338 trades. The commercial use cases — financial sentiment prediction, PR crisis testing (simulate public reaction before a press release), policy impact modeling, market research — are viable at the ~1,000 agent scale. This is not a far-horizon problem. It is being solved now, with meaningful gaps that Liminara's architecture directly addresses.

### Fit with the core runtime

Simulation is expressed as epoch Ops: simulate K steps → snapshot → metrics. BEAM-native is possible for modest sizes; external compute remains an option for larger scale (see §7).

### Non-goals

- Compete with mature ABM suites in all features.
- Require process-per-individual; support sharded execution as well.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is "agentic"). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Source Document + Knowledge Graph (`IR0a`)

When agents are grounded in a document (a policy draft, financial report, news article), GraphRAG extracts entities, relationships, and semantic clusters into a knowledge graph. Agent personalities, stances, and social connections derive from this graph's structure. This is the pattern MiroFish uses: the same graph that powers retrieval also powers world-building.

**Artifact(s):**
- `sim.source_document.v1` (optional)
- `sim.knowledge_graph.v1` (optional, derived from source document)

### Sim Spec (`IR0b`)

Population config, environment topology, rules, seeds, epoch length, snapshot cadence, environment type (e.g. broadcast/social, spatial, economic). References the knowledge graph if present.

**Artifact(s):**
- `sim.spec.v1`

### Behavior Programs (`IR1`)

Behavior definitions per agent type (DSL text → checked AST → optional compiled form). May be authored manually or LLM-generated from the knowledge graph.

**Artifact(s):**
- `sim.behavior_dsl.v1`
- `sim.behavior_checked.v1`
- `sim.behavior_compiled.v1`

### World State Snapshot (`IR2`)

State at a point in time (epoch boundary). Content-addressed — same hash means cryptographically identical state. This enables verified identical starting conditions for forked runs (see §9).

**Artifact(s):**
- `sim.world_state.v1`

### Epoch Results (`IR3`)

State delta, events, and metrics for an epoch. Each agent's decisions within an epoch are recorded as `decision.llm_output.v1` entries (for LLM-backed agents). This is the mechanism that enables hallucination provenance tracing (see §10).

**Artifact(s):**
- `sim.epoch_result.v1`
- `sim.metrics.v1`

### Run Report (`IR4`)

Charts, summaries, anomaly detection, consensus analysis.

**Artifact(s):**
- `sim.report_md.v1`
- `sim.report_pdf.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`sim.extract_knowledge_graph`** — *Recordable*, *no side-effects*
  - Extract entities, relationships, and semantic clusters from source document via GraphRAG. Record LLM extraction decisions.
  - Inputs: `sim.source_document.v1`
  - Outputs: `sim.knowledge_graph.v1`
- **`sim.compile_behavior`** — *Pure deterministic*, *no side-effects*
  - Parse/validate behavior DSL into checked form (optionally compile).
  - Inputs: `sim.behavior_dsl.v1`
  - Outputs: `sim.behavior_checked.v1`, `sim.behavior_compiled.v1`
- **`sim.init_world`** — *Nondeterministic but recordable*, *no side-effects*
  - Initialize world state from spec (and optionally knowledge graph); record seed.
  - Inputs: `sim.spec.v1`, `sim.knowledge_graph.v1` (optional)
  - Outputs: `sim.world_state.v1`
- **`sim.run_epoch`** — *Pure deterministic*, *no side-effects*
  - Advance simulation for K ticks with explicit ordering policy; output next world state and epoch metrics. LLM-backed agent decisions within the epoch are recorded as decision records.
  - Inputs: `sim.world_state.v1`, `sim.behavior_checked.v1`
  - Outputs: `sim.world_state.v1`, `sim.epoch_result.v1`, `sim.metrics.v1`
- **`sim.inject_event`** — *Gate*, *no side-effects*
  - Pause simulation to inject a world event (e.g. "policy X announced", "market drops 10%"). The event is recorded as a decision and the simulation resumes with it in scope. This is the operator-facing "God's Eye View" mechanism. See §8.
  - Inputs: `sim.world_state.v1`
  - Outputs: `sim.world_state.v1` (with injected event applied)
- **`sim.render_report`** — *Pure deterministic*, *no side-effects*
  - Render report artifacts.
  - Inputs: `sim.metrics.v1`
  - Outputs: `sim.report_md.v1`, `sim.report_pdf.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Seeds and initialization choices**: Random seeds and sampled initial distributions.
  - Stored as: `decision.seed.v1`
  - Used for: Exact replay.
- **Knowledge graph extraction**: LLM extraction decisions from source documents.
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay; auditing how the agent population was derived.
- **Behavior authoring (if LLM-generated)**: LLM-generated DSL programs for agent behaviors.
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay and safety review.
- **Per-agent LLM decisions within epochs**: Each LLM-backed agent decision (opinion update, post generation, stance shift).
  - Stored as: `decision.llm_output.v1`
  - Used for: Hallucination provenance tracing (see §10), exact replay.
- **Injected world events**: Operator-injected events mid-simulation via `sim.inject_event`.
  - Stored as: `decision.world_event.v1`
  - Used for: Distinguishing operator-injected scenarios from emergent dynamics; replay.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- World inspector (state slices, agent population filters).
- Metrics dashboards (time-series, opinion distribution evolution).
- Epoch playback (snapshots, step-through).
- Behavior program viewer (DSL + AST).
- Hallucination provenance explorer: trace any belief in the current population back through its epoch chain to its origin — original document, self-generated, or absorbed from another agent.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- BEAM-native execution for modest size (~1,000 agents); switchable to sharded processes.
- **OASIS** (Open Agent Social Interaction Simulations, by CAMEL-AI) is the recommended external executor for larger scale. It handles: time engine (agent activation scheduling), recommendation system (algorithmic content surfacing between agents), environment server (posts, likes, follows, opinion shifts), and scalable LLM inference across GPUs (batching agent decisions for throughput). OASIS demonstrably scales to 500,000–1,000,000 agents. Liminara orchestrates epochs; OASIS executes them.

The separation of concerns: Liminara handles epoch boundaries, artifact management, decision recording, caching, replay, observation, and provenance. OASIS handles the raw compute inside each epoch.

---

## 8. Variable injection — the "God's Eye View"

A key capability in social and policy simulations is injecting world events mid-run: "Fed cuts rates by 50bps," "CEO resigns," "competitor launches at half the price." The entire population recalibrates. These are controlled experiments that cannot be run in reality.

In Liminara, this is modeled as a gate (`sim.inject_event`). The simulation pauses, the operator inputs the event, it is recorded as `decision.world_event.v1`, and execution resumes with the event in scope. This gives the injection three properties that ad-hoc variable injection lacks:

1. **Recorded**: the injected event is part of the run's event log
2. **Replayable**: inject the same event on replay, get the same downstream population behavior
3. **Distinguishable**: operator-injected events are separable from emergent dynamics in the logs — you always know what was a scenario parameter vs. what emerged

---

## 9. Forked runs and dual-environment testing

Running the same agent population through two different environment configurations — broadcast/social vs. threaded/deliberative, or fast-cascade vs. slow-deliberation — is a natural experiment on social dynamics. MiroFish does this by running a Twitter-like and Reddit-like environment simultaneously for every simulation.

In Liminara, this is a forked run: two runs sharing the same initial `sim.world_state.v1` artifact (same content hash — *cryptographically verified identical starting conditions*). They diverge only at the environment configuration parameter.

Divergent results reveal which findings are robust across interaction topologies and which are artifacts of the specific social structure. `diff(run_A.decisions, run_B.decisions)` shows exactly where the populations diverged.

---

## 10. The hallucination convergence problem — and Liminara's structural answer

### The problem

In LLM-backed multi-agent simulations, hallucination cascades are a first-order failure mode:

1. Agent A hallucinates a fact
2. Agent A's post enters the shared environment
3. Agents B, C, D absorb it into their memory
4. They propagate it in their own posts
5. 50 rounds later, the entire population makes decisions based on information that never existed

This is the **Woozle Effect** — named from multi-agent debate research — applied at simulation scale. In multi-agent discussions, over 10–20% of agents get misled per round, and this proportion compounds exponentially. The critical consequence: *opinion convergence and hallucination convergence look identical from the outside*. You cannot distinguish genuine emergent consensus from a cascade of fabricated facts by observing the final population state alone.

This is widely recognized as "the single most important unsolved problem in multi-agent simulation engineering" (Agent Native, March 2026). The proposed mitigation — memory provenance tracking, where every fact carries metadata about its origin — is described but not widely implemented.

One commenter made a deeper point: hallucination propagation may not always be a bug. If the goal is to simulate how *misinformation* spreads through a real population, then hallucination cascade is the phenomenon being modeled. The question becomes whether it was intentional or accidental — which requires provenance to answer.

### Liminara's structural answer

Liminara's content-addressed artifact graph *is* memory provenance tracking — not as a feature to add, but as a structural consequence of the architecture.

Every LLM-backed agent decision within an epoch is recorded as `decision.llm_output.v1`. Each `sim.epoch_result.v1` is a content-addressed artifact. Each `sim.world_state.v1` has a provenance chain through all epoch results that produced it.

If Agent A hallucinates in epoch 5, that hallucination is a recorded decision. The epoch 5 result artifact contains it. Every subsequent world state that incorporated epoch 5's results has a provenance chain that passes through that artifact. The question "which agents' current beliefs have a provenance chain that includes this specific hallucinated decision?" becomes a traversal of the artifact graph — answerable, auditable, and replayable.

This enables:
- **Tracing hallucination spread**: reconstruct the exact propagation path of a specific hallucination through the population, round by round
- **Measuring cascade depth**: how many agents were downstream of a given origin at each epoch boundary
- **Distinguishing injected vs. emergent**: `decision.world_event.v1` (operator-injected, intentional) vs. `decision.llm_output.v1` (agent-generated, potentially hallucinated) are separate record types
- **Post-hoc analysis**: a simulation that has already completed can be re-analyzed for hallucination provenance without re-running

The observation layer (A2UI / LiveView) can surface this as a hallucination provenance explorer: select any current belief in the population, trace it to its origin, see which agents it passed through and at which epochs.

### Benchmark against reality

Liminara's simulation/live duality makes it possible to measure how well a simulation predicted reality:

1. Run a historical simulation: inject real-world events from a past period as recorded decisions
2. Compare the simulation's predicted opinion distribution to what actually happened
3. `diff(simulation.decisions, actual.decisions)` shows exactly where the model diverged from reality

This directly addresses the "no benchmarks against real-world outcomes" limitation of current simulation systems like MiroFish.

---

## 11. MVP plan (incremental, testable)

- Define sim spec + world state schema (with optional knowledge graph input).
- Implement epoch runner with deterministic ordering.
- Support 1–2 simple behavior primitives (move, consume, emit event).
- Add `sim.inject_event` gate for mid-simulation variable injection.
- Basic A2UI metrics + epoch playback.
- Hallucination provenance explorer in the observation layer (traces decision records through artifact graph).

---

## 12. Should / shouldn't

### Should

- Avoid per-agent mailbox explosions; prefer epoch-level aggregation.
- Keep behavior DSL safe (bounded evaluation).
- Record every LLM-backed agent decision as `decision.llm_output.v1` — this is the foundation of provenance tracing.
- Treat injected world events (`sim.inject_event`) as gates so they are recorded and distinguishable from emergent dynamics.

### Shouldn't

- Don't rely on Elixir eval_string for behavior programs.
- Don't conflate operator-injected events with hallucination-origin facts in the provenance model.

---

## 13. Risks and mitigations

- **Risk:** Performance ceiling
  - **Why it matters:** Process-per-agent can hit overhead when many are runnable each tick.
  - **Mitigation:** Shard agents; event-driven sims; OASIS as external executor for large scale.
- **Risk:** Nondeterminism via concurrency
  - **Why it matters:** Scheduling differences can change outcomes.
  - **Mitigation:** Explicit tick ordering and RNG; single-threaded epoch loop or deterministic shard merge.
- **Risk:** Hallucination cascade corrupts simulation results
  - **Why it matters:** Opinion convergence and hallucination convergence look identical from the outside; results become uninterpretable.
  - **Mitigation:** Record all LLM agent decisions as `decision.llm_output.v1`; use artifact provenance graph to trace cascade origin and spread. The observation layer can surface this as a first-class inspector.
- **Risk:** Cost at scale
  - **Why it matters:** 1,000 agents × 100 rounds can cost hundreds of dollars per run at current LLM pricing.
  - **Mitigation:** Hybrid rule-based / LLM-backed agent architecture — pure rule-based ops for routine behavior, `recordable` LLM ops reserved for opinion-forming moments. Caching of `pure` epoch ops means unchanged world states never re-execute.

---

## Appendix: Related work and reference implementations

- [MiroFish](https://github.com/mirofish) — LLM-backed social simulation, March 2026. Built in 10 days, #1 GitHub trending, $4.1M backing. Demonstrates commercial viability of the ~1,000 agent scale. Key gaps it has that Liminara addresses: no hallucination provenance, no exact replay, no simulation/live benchmarking. Full analysis: `docs/research/mirofish_population_simulation.md`.
- [OASIS](https://github.com/camel-ai/oasis) — Open Agent Social Interaction Simulations by CAMEL-AI. The simulation engine underlying MiroFish. Scales to 1M agents. Recommended external executor for large-scale runs in this pack.
- [Mesa](https://mesa.readthedocs.io/) — Python ABM framework.
- [NetLogo](https://www.netlogo.org/) — Widely used ABM platform.
- [GAMA](https://gama-platform.org/) — Open-source spatial ABM environment.
- [AnyLogic](https://www.anylogic.com/) — Commercial multimethod simulation.
