# Adjacent Technologies and Intellectual Ancestors

**Date:** 2026-03-14
**Context:** Research gathered during architecture exploration. Covers historical systems that anticipated Liminara's design, formal models that illuminate it, and adjacent technologies worth tracking. Not a list of things to build — a collection of lenses for thinking clearly.

---

## 1. The Memex and Its Lineage

### Vannevar Bush — "As We May Think" (1945)

Bush directed the US Office of Scientific Research and Development during WWII, overseeing 6,000 scientists. Drowning in scientific literature, he published a visionary essay in *The Atlantic* describing a hypothetical device called the **Memex** — a desk that stored a researcher's entire library and, crucially, let them create **associative trails** through it.

The key insight was cognitive: human memory works by association, not by index or hierarchy. Traditional filing systems fight this. The Memex would support it. Trails — the same associative jumps a thinking mind makes — could be saved as artifacts, shared with colleagues, published alongside papers as "here is how I thought through this."

What Bush couldn't have: LLMs to traverse trails automatically, content-addressed storage, vector embeddings, cheap global networks.

**The Memex connection to Liminara:** The Radar pack is the Memex finally buildable. The corpus is content-addressed (every document has a stable identity). The trail through the corpus is a Liminara run (the DAG of ops). The decisions along the trail are recorded — why did the LLM find *this* connection interesting? That judgment is preserved. The trail is replayable and forkable — a colleague can take a Radar run, fork it at the "which connections to explore" decision, and explore an alternative path.

Sources:
- Vannevar Bush, ["As We May Think"](https://www.theatlantic.com/magazine/archive/1945/07/as-we-may-think/303881/), *The Atlantic*, July 1945
- [Memex — Wikipedia](https://en.wikipedia.org/wiki/Memex)
- [The forgotten 80-year-old machine that shaped the internet](https://theconversation.com/the-forgotten-80-year-old-machine-that-shaped-the-internet-and-could-help-us-survive-ai-260839), *The Conversation*, 2025

### Douglas Engelbart — "Augmenting Human Intellect" (1962) and the 1968 Demo

Engelbart read Bush's essay in a Red Cross library in the Philippines in 1945 and spent his career trying to build it. His 1962 framework paper defined augmentation not as adding more information but as augmenting the *process of thinking*. He wanted to capture the **structure of thought** — not just the conclusion, but the reasoning path.

His 1968 NLS (oN-Line System) demonstration — the "Mother of All Demos" — introduced in 90 minutes: the mouse, hypertext, collaborative real-time editing, video conferencing, and windowed interfaces. NLS had a "journal" — an append-only record of all work, with deep linking to specific document states.

**Connection to Liminara:** Decision records are Engelbart's journal. The event log is the append-only record of how work was done. The observation layer shows the structure of the computation — not just the output, but the reasoning path that produced it.

Sources:
- Douglas Engelbart, ["Augmenting Human Intellect: A Conceptual Framework"](https://www.dougengelbart.org/content/view/138), SRI, 1962
- [The Mother of All Demos](https://www.youtube.com/watch?v=yJDv-zdhzMY), December 9, 1968

### Ted Nelson — Xanadu (1960s–present)

Nelson coined "hypertext" and "hypermedia" and spent 54 years trying to build Xanadu — a system with true two-way links and **transclusion** (embedding content by reference, not copy). Every piece of text has a permanent address. If document A transcluded paragraph 3 of document B, you'd see the living content of B — changes propagate, and B can see who referenced it.

The web implemented one-way links and broke the vision. Content-addressed artifacts in Liminara are Xanadu-style permanent addressing. The provenance graph (which runs consumed this artifact?) is a two-way link. Transclusion is an op that references an input artifact by hash rather than copying — changes to the input produce a cache miss downstream, equivalent to the transcluded content updating.

Sources:
- [Project Xanadu](https://xanadu.com/)
- [Ted Nelson on Transclusion](https://www.youtube.com/watch?v=En_2T7KH6RA)

---

## 2. Petri Nets and Process Mining

### Petri Nets

Invented by Carl Adam Petri in 1962. A bipartite graph with **places** (circles, holding tokens), **transitions** (rectangles, consuming/producing tokens), and directed arcs. A Petri net models concurrent, distributed computation — tokens flow through places, transitions fire when their input places have enough tokens.

A DAG of Liminara ops is a special case of a **workflow net** — a well-studied Petri net subclass where every token flows from a source place to a sink place. Petri net theory gives formal tools for reasoning about:
- **Deadlock-freedom** (soundness): every execution can complete
- **Liveness**: every transition can eventually fire
- **Reachability**: can the system reach a given state?

For Liminara's scheduler: the ready-node detection loop is correct if and only if the underlying workflow net is sound. This can be formally verified without building the system.

**Colored Petri Nets (CPNs):** tokens carry typed data. A CPN models typed artifact flow directly — tokens are artifacts, transitions are ops. This is the formal model underlying Liminara's DAG.

Sources:
- Carl Adam Petri, ["Kommunikation mit Automaten"](https://petri.de/kommunikation-mit-automaten/), 1962 (German)
- [CPN Tools](https://cpntools.org/) — formal modeling tool
- Wil van der Aalst, *Process Mining: Data Science in Action*, Springer, 2016

### Process Mining — The Stunning Reverse

Process mining **discovers Petri nets from event logs**. The Alpha algorithm, Inductive Miner, and Heuristics Miner take an event log (case ID, activity, timestamp) and output a Petri net that describes the process that generated those events.

**Liminara produces exactly the kind of event log process mining consumes.**

Run a Liminara pack a hundred times. Feed the event logs into pm4py. Get back a formal Petri net of your actual process — including rare paths, bottlenecks, and deviations from the intended DAG. "Reverse engineering your own pipeline automatically from its execution traces." The runtime discovers what the pack actually does, not what the plan says it should do.

Key tools:
- [ProM](https://processmining.org) — academic framework, 250+ plugins, TU/e (Eindhoven)
- [pm4py](https://pm4py.fit.fraunhofer.de) — Python library, production-ready
- DISCO — commercial process mining for business analysts

The field is led by Wil van der Aalst at RWTH Aachen (previously TU/e). His work on **conformance checking** is particularly relevant: given a reference Petri net (the intended process) and an event log (what actually happened), compute the deviation. For Liminara: compare the intended pack plan against actual execution traces. Find runs where ops were retried, reordered, or failed — automatically.

**Future Pack idea:** `ProcessMining.Pack` — takes a collection of Liminara run event logs as input, runs pm4py's Inductive Miner, outputs a discovered process model as an artifact. Compelling demo: "here is what Liminara learned about itself from watching its own runs."

Sources:
- [Process Mining and Petri Net Synthesis](https://www.researchgate.net/publication/221586291_Process_Mining_and_Petri_Net_Synthesis)
- [pm4py library](https://pm4py.fit.fraunhofer.de/)
- [Petri Nets for Workflow Anomaly Detection in Microservice Architectures](https://link.springer.com/chapter/10.1007/978-3-031-94634-9_11), PETRI NETS 2025

---

## 3. Spaces

"A space is a place where things happen, distance, connections, interactions." The concept of a structured space — with topology, metric, or order — appears throughout mathematics and applied to Liminara's domain.

### Latent Space
The high-dimensional vector space where ML embeddings live. Documents, proteins, chemical compounds, musical pieces, house designs — embedded into vectors where geometric distance = semantic similarity. The Radar pack navigates latent space to find connections. The vector index is a materialized sample of latent space.

### Phase Space (Physics)
All possible states of a dynamical system, as a geometric space. In Liminara: a run's phase space is all possible execution traces given all possible decision combinations. The full decision tree IS the discrete phase space. Replay + forking is phase space navigation — moving through the space of possible executions efficiently.

### Design Space
The set of all possible designs, with a topology defined by similarity or adjacency. The house compiler navigates design space: each decision (roof pitch, material, room layout) is a step through design space. Replay + branching makes design space exploration cheap — fork at a decision, explore a branch, compare results.

### Fitness Landscape (Evolutionary Biology)
A function mapping each point in design space to a fitness value. Evolutionary algorithms are hill-climbing algorithms in fitness landscapes. The GA sandbox navigates fitness landscapes. An interesting property: fitness landscapes can have many local maxima — evolutionary algorithms explore them stochastically, and decision recording lets you return to any explored point.

### Semantic / Concept Space
The continuous space of ideas, where proximity = conceptual relatedness. The Radar's cross-domain connection finding is: find pairs of points from different regions of concept space that are closer than expected. These unexpected proximities are serendipitous connections — the core value of the Radar pack.

### Configuration Space (Robotics)
All possible robot joint configurations. Motion planning is finding a path through configuration space from start to goal avoiding obstacles. The house compiler's constraint satisfaction is structurally isomorphic: find a point in design space satisfying structural, thermal, and regulatory constraints.

### Information Space
A formalization of all possible information states. Wurman (inventor of TED) described information architecture as navigating information space. Liminara's DAG is a structured path through information space: input information → transformations → output information, with every intermediate state preserved as an artifact.

---

## 4. Content Addressing — The Intellectual Family

Liminara's artifact store belongs to a family of systems built around the same insight: *identify by content, not location*.

### Git
Every object (blob, tree, commit) addressed by SHA-1 hash. Git's object store IS Liminara's artifact store. Git for files; Liminara for computation. The key difference: Git doesn't know what the blobs *mean* — Liminara knows the op that produced each artifact, the inputs it took, and the decisions it recorded.

### Nix/NixOS
Reproducible builds via total input-addressing: every build input (source, compiler, flags, dependencies) is hashed into a derivation. Same inputs = same output, guaranteed. Nix's limitation: it can only handle deterministic builds. **Liminara's extension:** also record nondeterministic choices (decisions), making irreducible nondeterminism reproducible. This is a strictly more general mechanism.

Sources:
- [Nix thesis: Eelco Dolstra, "The Purely Functional Software Deployment Model"](https://edolstra.github.io/pubs/phd-thesis.pdf), 2006

### IPFS (InterPlanetary File System)
Distributed content-addressed storage. Every piece of content addressed by its CID (Content Identifier, a multihash). Liminara's artifact store is a local IPFS. If Liminara ever distributes, IPFS is the natural storage substrate — artifacts on IPFS have permanent addresses that work across nodes.

### Bazel (Google)
Two-layer architecture: **CAS** (Content-Addressable Storage, blob store) + **Action Cache** (maps `hash(command + input_hashes + environment)` to output hashes). This separation — what is stored (CAS) from how to find it (action cache) — is the cleanest architecture for Liminara's artifact store. Bazel handles billions of actions at Google.

Sources:
- [Bazel Remote Execution API](https://github.com/bazelbuild/remote-apis)
- [AiiDA — provenance in computational materials science](https://aiida.net/), running since 2015 with millions of calculation nodes in production

---

## 5. Hash Chains, Merkle Trees, and Tamper-Evidence

### Hash Chains
A sequence where each element contains `hash(previous_element)`. To tamper with entry N, you must recompute all subsequent hashes — detectable because the final hash changes. This is the core data structure underlying both blockchain and Certificate Transparency.

**For Liminara's event log:** each appended event includes `hash(previous_event)`. The final event's hash is the "run seal" — a single value cryptographically committing to the entire run history. Store the seal in a database or a public transparency log. Auditors verify the seal matches. This gives Article 12 tamper-resistance with negligible overhead.

### Merkle Trees
A tree of hashes where each non-leaf node is `hash(left_child || right_child)`. The root commits to all leaves. A **Merkle proof** demonstrates that a specific leaf is in the tree without revealing other leaves — an efficient, privacy-preserving membership proof.

For Liminara: a Merkle root over a run's artifact set enables efficient provenance proofs. "Prove that artifact X is in run Y's provenance" without revealing other artifacts in the run. Used in Git (for tree objects), Bitcoin (for transactions), IPFS (for content), and Certificate Transparency.

### Certificate Transparency (Google, 2013)
A global, publicly auditable, hash-chained log of every TLS certificate ever issued. Anyone can verify the log hasn't been tampered with. No distributed consensus needed — just append-only logs auditable by anyone.

**This is the architecture Liminara's event log could adopt for EU AI Act compliance:** not a blockchain (private, expensive), but a hash-chained log verifiable by any auditor. Architecturally elegant, legally defensible.

Sources:
- [Certificate Transparency — RFC 9162](https://www.rfc-editor.org/rfc/rfc9162)
- [Google Certificate Transparency](https://certificate.transparency.dev/)

### Zero-Knowledge Proofs (ZKPs)
Prove that a computation was performed correctly without revealing the inputs. Future angle for privacy-preserving AI compliance: prove to an auditor that your pipeline processed data correctly and produced a compliant output, without revealing the underlying data. Relevant when EU AI Act compliance requirements conflict with data privacy obligations.

---

## 6. Formal Models Illuminating Liminara

### Category Theory
A DAG of typed ops with artifact types is a **category**: artifact types are objects, ops are morphisms, composition is pipeline chaining. Category theory gives a formal framework for reasoning about composition and type safety. Op type signatures (`inputs: [:a, :b], outputs: [:c]`) are morphism signatures. A pack plan is a morphism composition.

Practically: when Elixir's type system matures, typed op compositions can be verified at compile time using categorical semantics.

### Datalog
A logic programming language for recursive relational queries. Standard SQL cannot efficiently compute transitive closure ("find all ancestors of artifact X"). Datalog can. For Liminara's provenance queries — "find all artifacts in the provenance chain of this briefing, transitively" — Datalog semantics are the right model. The Datomic database (Rich Hickey) uses Datalog as its query language precisely for this reason.

### Process Calculi (CSP, π-calculus)
Formal languages for concurrent communicating systems. **CSP** (Communicating Sequential Processes, Hoare, 1978) is the direct ancestor of the BEAM's message-passing model. Liminara ops communicating through Run.Server via messages is CSP composition. The **π-calculus** (Milner, 1992) extends CSP with dynamic process creation — analogous to discovery mode where new ops are created at runtime.

### Functional Reactive Programming (FRP)
Time-varying values as first-class citizens. A run's state is a signal — a function of all events seen so far. The observation layer is FRP: events arrive over time, and the UI is a pure function of the event stream. Elm's architecture, React's unidirectional data flow, and Phoenix LiveView's assigns are all FRP-influenced.

### CRDTs (Conflict-free Replicated Data Types)
Data structures that can be merged without conflicts, enabling distributed systems without coordination. If Liminara ever runs on multiple nodes, CRDTs for the artifact metadata index would allow nodes to merge knowledge without a central coordinator. The event log is already CRDT-friendly: append-only, and appends from multiple nodes can be merged by Lamport timestamp ordering.

---

## 7. Rich Hickey's Relevant Ideas

Rich Hickey (creator of Clojure) articulated several principles directly relevant to Liminara:

**"Values, not places"** — complexity comes from mutable state at addresses. Immutable values with stable identities make reasoning tractable. Liminara's content-addressed artifacts are this philosophy applied to computation: artifacts are values (immutable), identified by hash (stable), not by location (not mutable).

**"The Database as a Value"** (2012 talk) — a database where you can ask "what did this database look like at time T?" The event log gives Liminara this property for every run.

**Datomic** — an event-sourced, append-only database. The event log is a mini-Datomic for runs. Datomic uses Datalog for queries, stores facts as immutable assertions, and treats time as a first-class dimension. The architectural parallel to Liminara's event log + ETS projection is direct.

Sources:
- Rich Hickey, ["The Value of Values"](https://www.youtube.com/watch?v=-6BsiVyC1kM), JaxConf, 2012
- Rich Hickey, ["Deconstructing the Database"](https://www.youtube.com/watch?v=Cym4TZwTCNU), 2012
- Rich Hickey, ["Simple Made Easy"](https://www.youtube.com/watch?v=SxdOUGdseq4), Strange Loop, 2011

---

## 8. Vector Databases in the Radar Pipeline

The Radar pack's core capabilities — semantic deduplication, cross-domain connection finding, serendipity detection, historical search — all require vector embeddings and similarity search.

**How this maps to Liminara's model:**
- **Embedding** is a `pure` op (or `pinned_env` with model version): `(document) → vector`. Same document + same model = same embedding. Cacheable, content-addressed.
- **The vector index** is a Pack-managed reference artifact: a versioned dataset registered via `init/0`, updated by collection runs. Each version is a content-addressed artifact. Analysis runs reference a specific version — the index at a point in time.
- **Index update** is a `side_effecting` op producing a new index artifact: `(old_index_artifact, new_documents) → new_index_artifact`. The new index has a new hash; downstream ops see a cache miss.
- **Semantic search** is a `pure` op: `(query_vector, index_artifact) → [(doc_hash, similarity_score)]`.

**LanceDB** is particularly well-suited for v1: file-based (like SQLite for vectors), embeddable as a library, content-addressable at the file level. The vector index file IS the artifact.

Sources:
- [zvec](https://github.com/alibaba/zvec) — Alibaba's embedded vector database with Elixir NIF bindings (`{:zvec, "~> 0.2.0"}`). In-process, no server, dirty-scheduler-safe. The strongest candidate for Liminara's "zero external dependencies" philosophy. Full analysis: [zvec.md](zvec.md)
- [LanceDB](https://lancedb.com/) — embedded vector database, file-based
- [Qdrant](https://qdrant.tech/) — Rust-native, can run in-process
- [pgvector](https://github.com/pgvector/pgvector) — if Postgres is already present for Oban

---

## 9. CUE — Lattice-Based Configuration and Constraint Unification

CUE (Configure, Unify, Execute) is a data validation language where **types and values live in a single lattice**. Every CUE value — from abstract types (`int`) to concrete data (`42`) — is placed in a partially ordered set with a unique meet (greatest lower bound, `&`) and join (least upper bound, `|`). Merging any two CUE values is always unambiguous and order-independent. Created by Marcel van Lohuizen after 15 years on Google's internal configuration language (GCL).

The key insight: data, schemas, constraints, and policy are all the same kind of thing — values in a lattice. No separate validation layer.

**Connection to Liminara:** CUE's lattice is to *valid states* what Liminara's DAG is to *execution order*. Both are drawn as directed acyclic graphs — every lattice has a Hasse diagram that is a DAG — but they model different things. Liminara's DAG says "do A then B." CUE's lattice says "the result must satisfy A and B simultaneously."

The deepest fit is LodeTime's IR2 pass (architecture rule checking): codebase state as a CUE value, architecture rules as CUE constraints, unification = compliance checking, `_|_` (bottom) = violation with exact location and reason. Multi-stakeholder policy composition (security + platform + compliance teams defining constraints independently) is CUE's core use case.

Nearer-term applications: pack manifest validation (static composition checking before runtime), run configuration with layered constraints (pack defaults + user overrides + security policy), and decision space schemas for recordable ops.

**Caveat:** CUE adds real value when multiple independent sources of constraints must compose safely. Liminara doesn't have that problem yet in practice. LodeTime will.

Full analysis: [cue_language.md](cue_language.md)

Sources:
- [CUE Language](https://cuelang.org/)
- [The Logic of CUE](https://cuelang.org/docs/concept/the-logic-of-cue/)

---

## 10. Reactor — Saga Orchestration for Elixir

[Reactor](https://hexdocs.pm/reactor/) (v1.0, from the [Ash project](https://github.com/ash-project/reactor)) is a **dynamic, concurrent, dependency-resolving saga orchestrator** for Elixir. It lets you define complex workflows as steps with declared arguments, automatically resolves those declarations into a DAG, executes steps concurrently where dependencies allow, and supports saga-style compensation (undo) when a step fails.

```elixir
# Reactor DSL — declarative steps with automatic dependency resolution
defmodule CreateOrder do
  use Reactor

  input :customer_id
  input :items

  step :validate_inventory do
    argument :items, input(:items)
    run fn %{items: items} -> InventoryService.check(items) end
  end

  step :charge_payment do
    argument :customer_id, input(:customer_id)
    argument :items, result(:validate_inventory)
    run fn args -> PaymentService.charge(args.customer_id, args.items) end
    undo fn args, _result -> PaymentService.refund(args.customer_id) end
  end
end
```

Key features: composition (nested sub-reactors), control flow (`switch`, `map`, `group`, `around`), middleware with lifecycle hooks and telemetry, configurable retry with backoff, Mermaid diagram generation for visualization, and deep Ash Framework integration for resource actions.

**Connection to Liminara:** Reactor and Liminara share the DAG-of-steps execution model — both build a directed acyclic graph from declared dependencies and execute concurrently where possible. The overlap ends at the purpose:

| Dimension | Reactor | Liminara |
|-----------|---------|----------|
| **Core concern** | Reliability — execute or roll back | Reproducibility — execute and replay |
| **DAG** | Ephemeral, in-memory during execution | Persisted as an artifact, replayable |
| **Nondeterminism** | Not addressed — steps just run | Central concept — every choice captured as a Decision |
| **Failure model** | Saga compensation (undo what was done) | Append-only event log (record what happened) |
| **Determinism classes** | No concept | `pure`, `pinned_env`, `recordable`, `side_effecting` |
| **Audit trail** | Telemetry/middleware hooks | Hash-chained JSONL event log, tamper-detectable |

Reactor is a **workflow reliability** tool (distributed operations either all succeed or all roll back). Liminara is a **workflow reproducibility** tool (any run can be replayed and audited exactly). They have opposite philosophies about failure: Reactor erases it (compensate), Liminara preserves it (record).

**Could Reactor serve as Liminara's execution engine?** Probably not cleanly. Reactor's DAG is ephemeral while Liminara's is a persisted artifact. Reactor has no hooks for "record this nondeterministic choice" at the decision boundary. Its undo model conflicts with append-only event logs. Liminara needs to intercept every op boundary for decision recording, which would fight Reactor's execution model.

**Where the concept could be borrowed:** If Liminara ever needs compensation for `side_effecting` ops (e.g., an email was sent but a downstream op failed), the saga pattern is the right tool. This could be modeled as a `compensate` callback on ops with determinism class `side_effecting`, without adopting Reactor as a dependency.

Sources:
- [Reactor 1.0 Released — Elixir Forum](https://elixirforum.com/t/reactor-1-0-released-saga-orchestration-for-elixir/74083)
- [Reactor in the Elixir Ecosystem — hexdocs](https://hexdocs.pm/reactor/ecosystem.html)
- [Complex Workflows in Elixir with Reactor (+ AI Agents)](https://www.youtube.com/watch?v=0Dvn039qD8I) — talk building a travel booking system, then turning it into an AI agent via Ash AI

---

## 11. Camunda — BPMN Process Orchestration

[Camunda](https://camunda.com/) is a BPMN-based process orchestration platform built on **Zeebe**, a distributed, event-driven workflow engine. It executes BPMN/DMN models natively, uses event sourcing with append-only logs, and provides operational tooling (Operate for instance inspection, Optimize for process mining, Tasklist for human task management). Deployed as SaaS or self-managed clusters.

Camunda 8 introduced "agentic orchestration" — LLM agents modeled as BPMN ad-hoc subprocesses that dynamically select which tools (BPMN tasks) to invoke. Supports Anthropic, Amazon Bedrock, and OpenAI-compatible APIs.

**Connection to Liminara:** Camunda and Liminara share vocabulary (orchestration, AI, audit trails) but solve fundamentally different problems with incompatible architectures.

| Dimension | Camunda | Liminara |
|-----------|---------|----------|
| **Core abstraction** | BPMN state machine (graph with loops, branches, human gates) | DAG of ops producing content-addressed artifacts |
| **Execution model** | Job workers consume tasks from Zeebe broker | Elixir/OTP supervisors execute ops, Python via ports |
| **Nondeterminism** | Acknowledged but uncontrolled — LLM picks paths, results not recorded for replay | First-class concept — every choice captured as a Decision record |
| **Artifacts** | No content-addressing; data flows through process variables | Immutable, SHA-256 addressed blobs |
| **Replay** | Re-run a process (new execution, potentially different result) | Replay with recorded decisions = identical output, guaranteed |
| **Loops** | Native BPMN support for cycles, retries, waiting states | DAG is acyclic by definition |
| **Deployment** | Zeebe cluster + Elasticsearch + Operate + Tasklist + Optimize | Single Elixir app, zero external dependencies |

**Where Camunda is stronger:** Human workflow routing (approvals, escalations, timeouts, compensation). Visual process design for non-technical users. Enterprise connector ecosystem (100+ integrations). Operational tooling for running instances — inspect, repair, modify. Process mining over historical executions.

**Where Liminara is stronger:** Reproducibility (replay with identical output). Content-addressed caching (same inputs + same decisions = skip computation). Determinism classification as a type system for side effects. Compliance provenance for EU AI Act Article 12. Operational simplicity (no cluster, no external DB).

**They are not competitors.** Camunda answers "how do I get work done across people and systems?" Liminara answers "how do I prove this computation produced this result, and reproduce it?" They could coexist — Camunda orchestrating a business process that calls Liminara for computation steps requiring provenance.

**Borrowable ideas:** See `work/gaps.md` for specific patterns worth adopting (connectors, run inspection, process mining, agentic subprocesses).

Sources:
- [Camunda Platform](https://camunda.com/platform/)
- [Zeebe Architecture](https://docs.camunda.io/docs/components/zeebe/zeebe-overview/)
- [Camunda Agentic Orchestration](https://camunda.com/solutions/agentic-orchestration/)
- [AI Agents Documentation](https://docs.camunda.io/docs/components/agentic-orchestration/ai-agents/)

---

## 12. Luna / Enso — Visual Data-Flow Programming

[Luna](https://medium.com/@enso_org/luna-the-future-of-computing-aaf4f76303ef) was a 2017-era programming language built on the thesis that **"the graph IS the code"** — a data-flow DAG and a functional textual source are dual representations of the same program, convertible either direction. The design goal was cognitive: reduce programming's mental overhead by making the DAG itself the primary artifact rather than a debugging aid. Stack was Haskell + GHCJS + React.

The project rebranded to [Enso](https://ensoanalytics.com/) and today ships as a visual data-preparation / workflow-automation platform positioned as an Alteryx replacement for FP&A, accounting, tax, and sales-ops teams. Same DAG substrate, narrowed to a vertical SaaS market; no AI/LLM story, no formal reproducibility or audit claims beyond "automatic version history."

**Connection to Liminara:** Luna is a genuine ancestor in the *"DAG as first-class computational substrate"* lineage — nodes as typed transformations, edges as data, composition as the unit of meaning. dag-map's visualization ambitions descend from the same tradition Luna championed (graph-as-primary-surface, not as after-the-fact diagram).

| Dimension | Luna (2017) | Enso (today) | Liminara |
|-----------|-------------|--------------|----------|
| **Core thesis** | "The graph IS the code" — programming ergonomics | Visual data prep for business analysts | Reproducible nondeterministic computation |
| **DAG role** | Authoring surface (dual with text) | Workflow authoring for non-engineers | Execution plan + persisted artifact |
| **Nondeterminism** | Not addressed — pure functional model | Not addressed | First-class — captured as Decision records |
| **Reproducibility** | Not a stated concern | "Version history" (workflow source only) | Replay with recorded decisions = identical output |
| **Content addressing** | No | No | SHA-256 artifacts, hash-chained event log |
| **Target user** | General programmers | FP&A / sales ops | Pack authors building auditable AI workflows |

**Where Liminara picks up what Luna dropped.** Luna's 2017 manifesto has no mention of nondeterminism, caching, replay, or reproducibility — its DAG was a pure-functional thing where those questions didn't arise. Enso's current product gestures at version history but makes no reproducibility or audit claims, and has no AI/LLM surface. Liminara's entire thesis lives in that gap: a DAG where *some nodes are inherently nondeterministic* (LLM calls, human approvals, stochastic selection), and the runtime's job is to record every such choice so the run can be replayed exactly. That's the layer Luna never built and Enso walked away from.

**The useful framing:**
- **Luna (2017):** "DAGs make programming ergonomic" — a language/IDE thesis, pre-LLM.
- **Enso (today):** "DAGs make data prep accessible" — a vertical SaaS.
- **Liminara:** "DAGs + decision records make AI-era computation reproducible" — a runtime thesis that only makes sense *because* the new primitives (LLM, human-in-the-loop) are nondeterministic.

Shared substrate, different problem. Acknowledging Luna sharpens Liminara's claim about what's actually new: not the DAG, but the recorded choice at each nondeterministic node.

Sources:
- [Luna — The Future of Computing](https://medium.com/@enso_org/luna-the-future-of-computing-aaf4f76303ef), Enso Org, 2017
- [Enso Analytics](https://ensoanalytics.com/) — current product

---

## 13. Technology Synthesis — The Pattern

The best systems come from someone who recognized that a *combination* of existing ideas was new even if the pieces weren't:

| System | Components | What was new |
|--------|-----------|-------------|
| Git | Content addressing + DAG + SHA-1 | Revision control that actually works |
| Bitcoin | Hash chains + Merkle trees + proof of work | Distributed trustless consensus |
| MapReduce | Functional programming + distributed systems | Scalable batch processing |
| BEAM/OTP | Actors + supervision trees + hot code loading | Fault-tolerant telecom at scale |
| Nix | Content addressing + functional builds | Reproducible system configuration |
| Camunda | BPMN + event sourcing + Zeebe + agentic subprocesses | Enterprise process orchestration with AI agents |
| Liminara | Content-addressed artifacts + decision recording + event sourcing + OTP + determinism classes | Reproducible nondeterministic computation |

The collection approach: gather interesting technologies, let them sit together, notice which combinations are novel and useful.

**Candidate additions to Liminara's intellectual collection:**
- Merkle proofs — efficient, privacy-preserving provenance attestation
- Hash-chained event logs — tamper-evidence without blockchain overhead
- Process mining — discover process models from execution traces
- Datalog — recursive provenance queries
- CRDTs — eventual consistency for future distribution
- W3C PROV — standard provenance vocabulary for interoperability
- Certificate Transparency architecture — publicly auditable AI audit logs
- CUE — lattice-based constraint composition for pack manifests and architecture rules
- Saga compensation — borrow the pattern for `side_effecting` ops without adopting a framework dependency (see §10)

---

*See also:*
- *[02_Fresh_Analysis.md](../analysis/02_Fresh_Analysis.md) — landscape and competitive analysis*
- *[04_HashiCorp_Parallels.md](../analysis/04_HashiCorp_Parallels.md) — HashiCorp architectural parallels*
- *[05_Why_Replay.md](../analysis/05_Why_Replay.md) — the case for recorded decisions*
