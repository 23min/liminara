# MiroFish and the Population Simulation Pack

**Date:** 2026-03-22
**Source:** ["MiroFish: Swarm-Intelligence with 1M Agents That Can Predict Everything"](https://agentnativedev.medium.com/mirofish-swarm-intelligence-with-1m-agents-that-can-predict-everything-114296323663), Agent Native, March 2026
**Context:** Positioned against Liminara's Population Simulation pack (`07_Population_Simulation.md`). MiroFish is a concrete, deployed instance of the exact problem space the pack targets. This analysis examines what MiroFish does, where the pack spec already covers it, where MiroFish goes further, and — the most important finding — where Liminara's architecture solves MiroFish's stated #1 unsolved problem.

---

## What the Article Is Saying

A 20-year-old undergraduate in Beijing named Guo Hangjiang vibe-coded **MiroFish** in 10 days. It hit #1 on GitHub global trending above OpenAI, Google, and Microsoft repositories. Within 24 hours of a rough demo, Chen Tianqiao — the former richest person in China — committed $4.1 million to incubate it. Brian Roemmele ran 500,000 AI agents in a single simulation. A developer integrated it with a Polymarket trading bot, simulated 2,847 digital humans before every trade, and reported $4,266 profit over 338 trades.

MiroFish is not a task-orchestration system. It **spawns thousands of autonomous agents with unique personalities, memories, and social connections, drops them into a simulated world, and watches emergent behavior unfold**. The underlying simulation infrastructure is OASIS (Open Agent Social Interaction Simulations) by CAMEL-AI, which scales to one million agents with 23 different social actions: following, commenting, reposting, liking, muting, searching.

### Architecture

**Document ingestion and knowledge graph construction.** The system uses GraphRAG to extract entities, relationships, and semantic clusters from an input document — a policy draft, financial report, news article. In the original implementation this knowledge graph lives in Zep Cloud; the offline fork replaces it with local Neo4j (data stays on your hardware, critical for pre-publication confidential documents).

**Agent generation.** Based on the knowledge graph, the system automatically generates agent personas. Each agent receives: a unique biography and personality type, a distinct stance derived from the document's entities, long-term memory (Zep / Neo4j), and behavioral logic (persuadability, posting frequency, leader/follower role). The personas are *grounded in the document* — this is GraphRAG applied to world-building.

**Dual-platform parallel simulation.** MiroFish runs two environments simultaneously: a Twitter-like (rapid opinion cascading via short posts and retweets) and a Reddit-like (threaded discussion, upvote/downvote dynamics). Running both is essentially a built-in A/B test on social dynamics for every simulation.

**OASIS framework internals:**
- *Time Engine* — activates agents based on schedules and simulated time progression
- *Recommendation System* — determines which content surfaces to which agents, mimicking algorithmic feeds
- *Environment Server* — tracks all posts, comments, likes, follows, and opinion shifts
- *Scalable Inferencer* — distributes LLM inference across available GPUs, batching agent decisions for throughput

**God's Eye View: variable injection.** At any point during a simulation you can inject new variables: "Fed cuts rates by 50bps," "CEO resigns effective immediately," "Competitor launches at half the price." The entire world recalibrates in real time. You're running controlled experiments that cannot be run in reality.

**Report generation.** A dedicated ReportAgent analyzes simulation outcomes and compiles human-readable forecasts. You can also enter the simulated world directly — querying individual agents about their reasoning, examining specific conversation threads that emerged organically.

### Why now

The article identifies three catalysts that made this possible in 2026 when it would have been a multi-team, multi-quarter project two years ago:

1. **LLMs made agents behaviorally rich.** Classical ABMs use rule-based if-then-else logic. An agent's "trust threshold" determines whether it adopts a neighbor's opinion. It works for macro patterns but individual behaviors feel robotic. LLM-backed agents reason about context, generate natural language, form nuanced opinions. The behavioral surface area exploded.

2. **GraphRAG made knowledge grounding tractable.** Extracting entities and relationships from a document and using that graph as the substrate for generating agent personalities and stances is a new and transferable pattern.

3. **Simulation infrastructure matured.** OASIS is now an open-source dependency. What previously required a whole team is now an import.

### The core failure mode: The Woozle Effect

The article's most important technical observation:

1. Agent A hallucinates a fact during generation
2. Agent A posts this hallucinated fact to the simulated social platform
3. Agents B, C, and D read the post and incorporate it into their memory
4. They share it in their own posts and comments
5. 50 simulation rounds later, the entire population makes decisions based on information that never existed

This is the **Woozle Effect** — named from multi-agent debate systems — applied at simulation scale. In multi-agent discussions, over 10–20% of agents get misled per round through discussion, and this proportion continuously increases as the initial hallucination level rises. The effect compounds exponentially.

The core tension: *the same mechanism that makes multi-agent simulation powerful — agents influencing each other's beliefs — is the same mechanism that propagates hallucinations. You can't have one without risking the other.*

By the time you're analyzing simulation outputs, you can't distinguish between emergent consensus (the thing you're trying to measure) and hallucination cascade (the thing corrupting your measurements). The article calls this "the single most important unsolved problem in multi-agent simulation engineering."

The proposed mitigation is **memory provenance tracking**: every fact in an agent's memory should carry metadata about its source — was it extracted from the original document, generated by the agent itself, or absorbed from another agent's output?

### Stated limitations

- No published benchmarks against real-world outcomes
- Hallucination propagation is unsolved at scale
- LLM bias becomes simulation bias (model gaps feel like comprehensive coverage at scale)
- Cost at scale prohibitive: 1,000 agents × 100 rounds can cost hundreds of dollars per run
- Simulated humans are not real humans; the map is not the territory

---

## Liminara's Population Simulation Pack — What Already Exists

The pack spec (`07_Population_Simulation.md`) defines exactly this problem domain: agent-based simulation with durable epochs, snapshots, and replay. The IR pipeline maps cleanly:

| MiroFish | Liminara pack |
|---|---|
| Document + knowledge graph | `sim.spec.v1` (IR0), behavior programs (IR1) |
| World state | `sim.world_state.v1` (IR2) |
| Simulation round | `sim.run_epoch` op → `sim.epoch_result.v1` + `sim.metrics.v1` (IR3) |
| Report generation | `sim.render_report` op → `sim.report_md.v1` + `sim.report_pdf.v1` (IR4) |
| Random seed | `decision.seed.v1` |
| LLM-generated agent behavior | `decision.llm_output.v1` |

The op determinism classification is already correct: `sim.init_world` is `recordable` (seed recorded), `sim.run_epoch` is `pure` (given same world state + behavior + seed, same output). `sim.compile_behavior` is `pure`. The spec already identifies the concurrency risk: "Scheduling differences can change outcomes — mitigate with explicit tick ordering and RNG, single-threaded epoch loop or deterministic shard merge."

The pack spec currently targets "modest to large populations (~1,000 individuals)" and is classified as far-horizon. MiroFish changes the picture on both counts, as discussed below.

---

## Where MiroFish Goes Further Than the Current Spec

**GraphRAG as agent generation substrate.** The current pack spec doesn't specify how agent populations are generated. MiroFish's approach — extract a knowledge graph from a document, derive agent personalities and stances from the graph's structure — is a concrete and transferable pattern. This makes `sim.spec.v1` richer: the spec should include the source document and knowledge graph as first-class inputs, not just configuration parameters. The knowledge graph IS an artifact (content-addressed), and the agent population derives deterministically from it.

**Algorithmic recommendation system as part of the environment.** The current spec has no concept of an information-surfacing layer. OASIS's recommendation system — determining which content each agent sees based on simulated algorithmic feeds — significantly changes the dynamics. What an agent believes depends not just on what others post, but on what the algorithm shows them. This is a critical environmental parameter for social simulations that the pack spec should acknowledge.

**Dual-environment testing.** Running the same agent population through two different interaction topologies simultaneously (Twitter-like vs Reddit-like) is not in the current spec. It's a powerful design pattern — the divergence between the two topologies reveals which findings are robust and which are artifacts of the specific social structure.

**Variable injection mid-simulation.** The "God's Eye View" — injecting world events mid-run — is not explicitly modeled in the spec. As discussed below, this maps cleanly to gates in Liminara. But the spec should name this capability.

**Scale ambition.** The spec targets ~1,000 individuals to start. OASIS demonstrably scales to 500,000–1,000,000 agents. The limiting factor for Liminara's pack isn't the epoch runner — it's the external compute substrate. OASIS is the answer to this: it *is* the external executor the spec mentions as an option for larger scale.

---

## The Most Important Insight: Liminara Solves MiroFish's #1 Unsolved Problem

The article identifies memory provenance tracking as the solution to hallucination cascade, and says nobody has implemented it cost-effectively at scale. **Liminara's architecture is memory provenance tracking, by design, for free.**

Here is what provenance tracking looks like in Liminara's population simulation:

- Each `sim.run_epoch` op is a `pure` op. Its inputs are `sim.world_state.v1` (the population state) and `sim.behavior_checked.v1` (the behavior programs). Its outputs include `sim.epoch_result.v1`.
- Every LLM call *within* an epoch — every agent's decision, every generated post, every opinion update — is a `decision.llm_output.v1`. These are recorded by the `recordable` ops inside the epoch runner.
- Each agent's memory update is a state transition from one `sim.world_state.v1` to the next, mediated by `sim.epoch_result.v1`.
- All of these are content-addressed artifacts. Every artifact knows what produced it and what it was derived from.

The consequence: if Agent A hallucinates in epoch 5, that hallucination is a recorded decision. The `sim.epoch_result.v1` for epoch 5 is a content-addressed artifact that contains it. Every subsequent `sim.world_state.v1` that incorporated epoch 5's results has a provenance chain that passes through that artifact. You can query: *which agents' current belief states have a provenance chain that includes this specific hallucinated decision record?*

That is not just provenance tracking — it is **auditable hallucination propagation tracing**. You can reconstruct the exact spread path of a specific hallucination through the population, round by round, agent by agent, with cryptographic certainty. MiroFish cannot do this. The article says nobody can do this. Liminara's architecture does it as a structural consequence of content-addressed artifacts and decision records.

---

## Simulation/Live Duality Becomes Very Concrete Here

The archived `docs/history/architecture/02_PLAN.md` recognizes simulation/live duality as an existing architectural capability:

> *"Simulation mode: All nondeterministic ops use synthetic data or inject stored decisions. Live mode: Ops are gated by real-world events. Decision records enable comparing the two: diff(simulation.decisions, live.decisions) shows exactly where reality diverged from the plan."*

For the population simulation pack, this resolves MiroFish's "no benchmarks against real-world outcomes" limitation directly. The workflow:

1. Run a historical simulation: inject real-world events from a past period as recorded decisions
2. Run the simulation forward with those injected decisions
3. Compare the simulation's predicted opinion distribution to what actually happened in that period
4. `diff(simulation.decisions, actual.decisions)` shows exactly where the model's behavior diverged from reality — which events the model under-weighted, which opinion dynamics it failed to capture

This is the benchmarking methodology MiroFish lacks. It requires exact replay — which requires decision records — which Liminara has and MiroFish doesn't.

---

## Variable Injection as a Gate

MiroFish's "God's Eye View" variable injection is a gate in Liminara. When a world event is injected mid-simulation — "Fed cuts rates 50bps" — in Liminara this is:

```
sim.run_epoch returns {:gate, "inject world event"}
→ Run pauses
→ Operator inputs: "Fed cuts rates 50bps"
→ Decision recorded as decision.world_event.v1
→ Run resumes with injected event in scope
```

The injected event is now: recorded (part of the event log), replayable (inject the same event on replay, get the same downstream behavior), and auditable (any observer can see that the rate cut was injected at epoch N, not emergent from the simulation).

This is important for distinguishing intentional scenario testing ("what if the Fed cuts rates?") from emergent dynamics. MiroFish has no such distinction — injected variables and emergent opinion shifts look identical in the logs.

There's also a deeper point here connected to the comment Jeff LaCoursiere made in the article: "adoption of false facts looks the same from the outside as adoption of true facts — isn't that exactly what happens in real life?" He's right that misinformation propagation is a valid simulation target, not just a bug. Liminara's gate mechanism makes this distinction explicit: *intentional* misinformation injection (a gate decision, recorded) vs *unintentional* hallucination cascade (traceable through the provenance graph). You can study both, and you know which is which.

---

## OASIS as the External Executor

The pack spec notes: "BEAM-native execution for modest size; switchable to sharded processes. Optional external simulator executor for larger scale."

OASIS is that external executor. The separation of concerns is clean:

- **Liminara orchestrates**: epoch boundaries, artifact management, decision recording, caching, replay, observation, provenance
- **OASIS executes**: agent activation scheduling, recommendation system, LLM inference distribution across GPUs, batching for throughput

The epoch boundary is the handoff point. Liminara calls `sim.run_epoch`, passing in the world state artifact and behavior programs. The op executor (OASIS) runs K ticks of simulation — activating agents, routing content through the recommendation system, batching LLM calls — and returns the next world state artifact and epoch metrics. Liminara records everything at the epoch boundary. OASIS can scale to a million agents inside a single epoch; Liminara doesn't need to know.

This is a clean and implementable architecture that doesn't exist in MiroFish: it collapses orchestration, execution, provenance, and observation into a single stack that has none of them modularized.

---

## Dual-Environment Testing in Liminara Terms

Running the same agent population through Twitter-like and Reddit-like environments simultaneously is a forked run in Liminara. Both runs start from the same `sim.world_state.v1` artifact (same content hash — cryptographically verified to be identical starting conditions). They diverge at the environment configuration parameter. The comparison is `diff(run_twitter.decisions, run_reddit.decisions)`.

Findings that appear in both runs are robust to interaction topology. Findings that appear in only one are artifacts of the specific environment structure. This is precisely what the article describes as the analytical value of dual-environment testing — and Liminara provides the infrastructure to do it rigorously, with verified identical starting conditions and full decision records for each branch.

---

## Priority Reassessment

The Population Simulation pack is currently classified as far-horizon. MiroFish hitting #1 on GitHub globally, $4.1M investment in 24 hours, and a developer generating real Polymarket profit are strong market signals that this problem space has immediate commercial viability. The use cases with near-term value:

- **Financial prediction**: Simulate market sentiment before trades (the Polymarket use case)
- **PR crisis testing**: Simulate public reaction to a press release before publication — the document is confidential, so data sovereignty (Liminara's local-first architecture) is critical
- **Policy impact simulation**: Simulate how a policy change will propagate through a population before implementing it
- **Market research**: Replace expensive human panels with simulated populations grounded in demographic data

None of these require a million agents. The ~1,000 agent starting target from the pack spec is commercially viable for all of them. The far-horizon classification may be overly conservative given what MiroFish has demonstrated is buildable by one person in 10 days.

---

## What Liminara Would Uniquely Offer Over MiroFish

| Problem | MiroFish | Liminara population_sim pack |
|---|---|---|
| Hallucination cascade detection | Unsolved ("single most important unsolved problem") | Provenance tracing through content-addressed artifact graph — by design |
| Exact replay | No | Yes — seeds + LLM outputs recorded as decisions |
| Benchmarking against reality | No methodology | Simulation/live diff: inject historical events, compare prediction to outcome |
| Verified identical starting conditions for A/B tests | No | Yes — content-addressed world state artifact, same hash = same state |
| Compliance-grade audit trail | No — data stays local but no audit trail | Yes — tamper-evident event log, recorded decisions, EU AI Act-aligned |
| Variable injection traceability | No — injected events and emergent dynamics indistinguishable in logs | Yes — injected events are gate decisions, recorded and separable from emergent behavior |
| Cost-aware caching | No | Yes — `pure` epoch ops are cached by input hash; unchanged world states never re-execute |

---

## Additions to the Pack Spec

The pack spec at `07_Population_Simulation.md` should be updated to reflect:

1. **GraphRAG as agent generation substrate**: source document + knowledge graph as first-class IR artifacts. `sim.spec.v1` should reference these.
2. **Recommendation system parameter**: which content-surfacing model is used (algorithmic feed, random, network-proximity) should be a named configuration parameter, not an implicit default.
3. **Variable injection via gates**: explicitly model mid-simulation event injection as a gate mechanism.
4. **OASIS as external executor option**: name OASIS (CAMEL-AI) as the concrete external executor for large-scale runs.
5. **Dual-environment testing pattern**: name the forked-run pattern explicitly as a first-class design pattern for this pack.

---

## Verdict

MiroFish is a concrete, deployed, commercially validated instantiation of the Population Simulation pack's target problem. It validates that the problem space is real, that the timing is now (not far-horizon), and that a single developer can build the core in 10 days on top of OASIS. Its limitations are exactly what Liminara's architecture addresses by design: hallucination provenance, exact replay, simulation/live benchmarking, and compliance-grade auditability.

The most striking finding: the article identifies memory provenance tracking as the unsolved core problem, and Liminara's content-addressed artifact graph *is* memory provenance tracking — not as a feature to add, but as a structural consequence of the architecture. A population simulation running on Liminara would be MiroFish with its most critical failure mode solved.

---

*See also:*
- *[07_Population_Simulation.md](../domain_packs/07_Population_Simulation.md) — the pack spec*
- *[ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) §2 — Petri nets and process mining (formal models for agent-based simulation)*
- *[02_Fresh_Analysis.md](../analysis/02_Fresh_Analysis.md) — landscape and competitive analysis*
- *[05_Why_Replay.md](../analysis/05_Why_Replay.md) — the case for recorded decisions*
