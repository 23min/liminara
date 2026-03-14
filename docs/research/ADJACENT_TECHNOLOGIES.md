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
- [LanceDB](https://lancedb.com/) — embedded vector database, file-based
- [Qdrant](https://qdrant.tech/) — Rust-native, can run in-process
- [pgvector](https://github.com/pgvector/pgvector) — if Postgres is already present for Oban

---

## 9. Technology Synthesis — The Pattern

The best systems come from someone who recognized that a *combination* of existing ideas was new even if the pieces weren't:

| System | Components | What was new |
|--------|-----------|-------------|
| Git | Content addressing + DAG + SHA-1 | Revision control that actually works |
| Bitcoin | Hash chains + Merkle trees + proof of work | Distributed trustless consensus |
| MapReduce | Functional programming + distributed systems | Scalable batch processing |
| BEAM/OTP | Actors + supervision trees + hot code loading | Fault-tolerant telecom at scale |
| Nix | Content addressing + functional builds | Reproducible system configuration |
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

---

*See also:*
- *[02_Fresh_Analysis.md](../analysis/02_Fresh_Analysis.md) — landscape and competitive analysis*
- *[04_HashiCorp_Parallels.md](../analysis/04_HashiCorp_Parallels.md) — HashiCorp architectural parallels*
- *[05_Why_Replay.md](../analysis/05_Why_Replay.md) — the case for recorded decisions*
