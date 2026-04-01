# Beyond the DAG: Alternative Computation Models

**Date:** 2026-04-01
**Context:** The DAG is not the only way to orchestrate computation. Several fundamentally different models exist, and some are experiencing a revival in the LLM agent era. Understanding them matters most for Liminara's deferred "discovery mode" — where the execution path can't be predetermined. DAGs are the right model for known pipelines (Radar, House Compiler). The alternatives matter where DAGs break down.

**Companion doc:** See `dataflow_systems_and_liminara.md` for the DAG-based landscape (Pd, FAUST, vvvv, Max, agent orchestration frameworks) and Liminara's seven architectural gaps.

---

## Why Look Beyond DAGs?

Liminara's current architecture is a strict DAG. This is correct for pipeline-mode packs where the execution graph is known upfront. But three planned capabilities push against the DAG model:

1. **Discovery mode** — the Software Factory, where an agent decides what to do next. The plan is built incrementally. Currently modeled as `expand: true` nodes that add to the DAG, but this is a DAG-shaped approximation of a fundamentally non-DAG problem.
2. **Multi-agent coordination** — when multiple agents with unpredictable capabilities need to collaborate on a problem. Who does what? A DAG requires a central planner that assigns work. Some problems don't have a central planner.
3. **Data-driven control flow** — when the next step depends on what's been discovered so far, not on a pre-declared plan. Rules, hypotheses, and emerging patterns determine what runs next.

The models below are genuinely non-DAG and genuinely relevant to these problems.

---

## Blackboard Systems — The Strongest Alternative

### What it is

A shared data store (the "blackboard") that multiple independent "knowledge sources" (KS) read from and write to. No graph, no predetermined ordering. A control component selects which knowledge source to activate next based on the current state of the blackboard.

### How it works

Knowledge sources are opportunistic — each monitors the blackboard for patterns it can contribute to. When a KS sees data it can work with, it volunteers. The control component selects among competing volunteers. The process repeats until a solution emerges or no more progress can be made. The only coupling between knowledge sources is through the shared data.

### Origin

HEARSAY-II (1971–76) did speech recognition by having KSs at different levels — acoustic features, phonemes, syllables, words, phrases — all writing hypotheses to the blackboard. A word-level KS might see a partial phoneme sequence and post a word hypothesis, which a phrase-level KS then picks up. The system converges through cooperative, unorchestrated interaction.

### Modern revival for LLM agents

Blackboard systems are experiencing a genuine comeback. Two 2025 papers are directly relevant:

- *"LLM-Based Multi-Agent Blackboard System for Information Discovery in Data Science"* (arXiv:2510.01285): Agents post requests to a shared blackboard and subordinate agents volunteer based on capabilities. Outperformed both RAG and master-slave multi-agent paradigms by 13–57% on end-to-end task success.
- *"Exploring Advanced LLM Multi-Agent Systems Based on Blackboard Architecture"* (arXiv:2507.01701): Blackboard-based multi-agent systems with public/private areas, specialized agent roles (planners, critics, deciders), and dynamic agent selection. Outperformed competing approaches across six benchmarks while using fewer tokens.

### Why it outperforms graph-based agent coordination

Agents *self-select* based on capability rather than being assigned by a coordinator. This solves the problem where a central controller can't know what every agent is good at. New capabilities can be added without rewiring a graph.

### Relevance to Liminara

This is what "discovery mode" actually needs. The Software Factory agent looking at the current state of the work and deciding what to contribute is a blackboard pattern. The `expand: true` flag is a DAG-shaped approximation.

Liminara's artifact store is already half a blackboard — a content-addressed shared space where ops produce and consume artifacts. The difference is that Liminara pre-declares which ops consume which artifacts via the plan. A more blackboard-like model would let ops declare what *patterns* of artifacts they can work with, and the scheduler would match.

A hybrid is possible: blackboard coordination for agent selection, but decisions are still recorded for replay. The blackboard pattern solves *what runs next*; Liminara's event sourcing and decision recording solve *how to reproduce it*.

### Tradeoffs

- Debugging is difficult — execution order is emergent, not specified
- Control (who fires next?) is the hard problem — BB1 tried meta-level reasoning, GBB tried efficient pattern matching
- No built-in causal trace
- These are exactly the properties Liminara's event sourcing is designed to provide

---

## Tuple Spaces — The Coordination Insight

### What it is

A shared associative memory where processes communicate by writing tuples (`out`), reading without removing (`rd`), or atomically claiming them (`in`). Processes don't know about each other — they only know about data patterns they need. Linda (David Gelernter, Yale, 1985).

### How it works

A producer writes `out("task", 42, "pending")`. Any number of workers call `in("task", ?x, "pending")` — one atomically claims it. When done, it writes `out("result", 42, answer)`. A collector calls `in("result", ?id, ?val)` to gather results. No process knows the identity of any other process.

### Modern relevance

A February 2026 analysis by Otavio Carvalho ("Our AI Orchestration Frameworks Are Reinventing Linda") argues that modern AI agent tools are independently reinventing tuple space patterns:

| Agent framework pattern | Linda equivalent |
|---|---|
| Task creation | `out` (write tuple to space) |
| Task claiming | `in` (atomically remove matching tuple) |
| Status checking | `rd` (read without removing) |
| Capability filtering | Template matching |

The tuple space literature already solved problems these tools are still struggling with — atomic claiming (race conditions), polling inefficiency (Linda had blocking `in`), context decay, and flat architecture (Linda evolved to scoped spaces by 1989).

### Is Erlang/ETS a tuple space?

Partially. An `espace` library implements Linda's operations on ETS. ETS provides the shared store with pattern matching (`ets:match/2`). But Erlang's native model is message-passing between *identified* processes — in Linda, you never address a process, you address a data pattern. The philosophical gap matters: Erlang couples processes by PID or name; tuple spaces couple by data schema only.

### Relevance to Liminara

Erlang's ETS + `:pg` is already half a tuple space. The artifact store is a content-addressed shared space. Ops produce artifacts (= `out`), other ops consume them by hash (= `rd`). The difference is pre-declared wiring (the plan specifies which op consumes which output) vs. pattern-based matching (ops declare what artifact patterns they accept, scheduler matches).

A tuple-space lens on the artifact store could inform discovery mode design. Instead of `Plan.node(:summarize, :rank_and_summarize, docs: ref(:dedup))`, discovery-mode ops could declare: "I accept any artifact of type `radar.docs.v1`." The scheduler matches available artifacts to op input patterns. This is more flexible than `expand: true` and more structured than a raw blackboard.

### Tradeoffs

- No built-in notion of causality or ordering — coordination without a dependency chain
- Debugging is hard — execution trace is implicit
- The space can become a bottleneck and single point of failure

---

## Rule Engines — Data-Driven Control Flow

### What it is

A "working memory" of facts, a set of IF-THEN rules (productions), and an inference engine that repeatedly matches rules against facts and fires the best match. The Rete algorithm (Charles Forgy, 1974) makes matching efficient by building a discrimination network.

### How it works

The recognize-act cycle: (1) Match — find all rules whose conditions are satisfied by current facts. (2) Conflict resolution — pick one rule (by priority, recency, specificity). (3) Act — execute the rule's action, modifying working memory. (4) Repeat until no rules match.

### How it differs from a DAG scheduler

A DAG scheduler knows the full dependency graph before execution begins. A production system does not — the next rule to fire depends on what facts exist *right now*, which depends on what previous rules produced. The execution path is discovered at runtime. This is essentially what "discovery mode" means in Liminara's terminology.

### Modern state

- **Drools** (Red Hat) is production-grade, widely used in enterprise — insurance underwriting, healthcare clinical decision support, compliance checking. Uses ReteOO, an object-oriented Rete variant.
- **Soar** (University of Michigan) is a cognitive architecture in continuous development since the 1980s. Recent work (2025) translates natural language into Soar production rules, bridging LLMs and symbolic reasoning.
- **CLIPS** is still maintained and used in embedded and aerospace applications.

### Relevance to Liminara

Less direct than blackboards, but the pattern of "rules that fire based on current state" offers an alternative way to think about discovery mode. Instead of an agent expanding the DAG, a set of rules could automatically determine what ops to run based on what artifacts exist in the store.

The Soar + LLM integration is a concrete example of bridging symbolic rules with neural capabilities — relevant if Liminara's discovery mode needs to combine structured planning with LLM flexibility.

### Tradeoffs

- "Rule storms" (cascading firings) are notoriously hard to debug
- Performance degrades with large rule sets without Rete optimization
- Opaque relationships between rules make behavior hard to predict

---

## Petri Nets — More Expressive Than DAGs

### What it is

A bipartite graph of "places" (holding tokens) and "transitions" (consuming and producing tokens). Transitions fire nondeterministically when their input places have sufficient tokens. Unlike DAGs, Petri nets can have cycles, model concurrency, synchronization, and resource contention. The standard formal model for workflow analysis (45th International Conference on Petri Nets, Geneva, 2024).

### How it differs from a DAG

A Petri net transition fires when all input places have tokens — like a DAG node becoming ready. But tokens are consumed and produced, creating resource dynamics. A place can accumulate multiple tokens (buffering). Transitions can feed back into earlier places (cycles). This models producer-consumer patterns, mutual exclusion, and bounded buffers that DAGs cannot represent.

### Relevance to Liminara

Liminara's scheduler already resembles a Petri net execution engine — "find ready nodes" is essentially "find enabled transitions." The difference: Liminara's tokens (artifacts) are immutable and content-addressed, while Petri net tokens are anonymous and consumed.

If Liminara ever needs resource-aware scheduling (bounded pools, mutual exclusion), Petri net theory provides the formal framework. BPMN workflow semantics are defined via Petri nets — relevant if Liminara integrates with business process tools.

---

## Stigmergy — Indirect Coordination

### What it is

Agents modify a shared environment; other agents respond to those modifications. No direct communication. Named by Pierre-Paul Grassé (1959) from studying termite construction. Ant pheromone trails are the canonical example.

### Modern software examples

Open source development is stigmergic — developers leave TODO comments, failing tests, open issues, and incomplete features. Other developers respond to these environmental signals without central task assignment. Robot swarm coordination (2024, Communications Engineering) uses automatically designed digital pheromone trails.

### Relevance to Liminara

Limited for core orchestration (wrong tradeoffs for reproducibility), but a Liminara run's event stream could be viewed as environmental signals — downstream observers react to what upstream ops have done. The concept is a useful lens for thinking about how the observation layer influences human decision-making at gates.

---

## Chemical Abstract Machine / Gamma — Computation as Reactions

### What it is

Data elements are "molecules" in a "solution" (multiset). Reaction rules fire when molecules meet conditions. No sequencing — reactions happen concurrently and nondeterministically until quiescence. Berry and Boudol (1990). Extended by Banâtre's Gamma language and Păun's P systems (membrane computing, 1998).

### Concrete example

To find primes from 2 to 100: put all integers in the solution. Rule: if molecule `a > b` and `a mod b == 0`, remove `a`. Molecules randomly interact. When no reactions fire, the remaining molecules are the primes. No loop, no graph.

### Relevance to Liminara

Minimal. The chemical model's core property — maximal implicit parallelism — is elegant but provides no causal trace, no reproducibility, no auditability. These are the exact properties Liminara exists to provide. Interesting as theory; wrong for this domain.

---

## Constraint Solvers / Declarative Models

### What it is

Declare constraints (what must be true), the solver finds solutions. No execution graph from the programmer's perspective. SAT/SMT solvers, Prolog, Datalog, miniKanren.

### Relevance to Liminara

Constraint solving is relevant as an *op type* — a SAT solver or Prolog engine can be an agent inside Liminara's DAG. But it's not an alternative orchestration model. You still need to know when to invoke the solver, what constraints to feed it, and what to do with the output. That's the DAG's job.

---

## Assessment

| Model | Genuinely non-DAG? | Practical today? | Relevant to Liminara? | When? |
|---|---|---|---|---|
| Blackboard systems | Yes | Yes (LLM multi-agent revival) | **High** — discovery mode | Phase 7+ (Software Factory) |
| Tuple spaces | Yes | Yes (patterns being reinvented) | **High** — coordination pattern | Phase 7+ (discovery mode design) |
| Rule engines | Yes | Yes (Drools, Soar) | **Medium** — data-driven control | Research input |
| Petri nets | Yes | Yes (workflow formalism) | **Medium** — resource-aware scheduling | If pools need formal grounding |
| Stigmergy | Yes | Niche (swarms, OSS) | Low | Conceptual input |
| Chemical/CHAM | Yes | No (academic) | Low — no auditability | Not applicable |
| Constraint solvers | Partly | Yes (SAT/SMT everywhere) | Medium — as an op type | Any phase |

**DAGs are the right model for known pipelines.** Radar, House Compiler — pre-declared pipelines where the graph is known upfront. DAGs give dependency tracking, caching, reproducibility, observability. Nothing on this list does those things better.

**The alternatives matter where DAGs break down** — when the execution path can't be predetermined. The blackboard pattern in particular is worth studying before building discovery mode, because it solves agent self-organization more naturally than "a DAG that grows itself." The tuple space literature offers coordination patterns that modern agent frameworks are independently (and imperfectly) reinventing.

**For shipping Radar:** the DAG model is exactly right. **For designing discovery mode:** read the blackboard and tuple space papers first.
