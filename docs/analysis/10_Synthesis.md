# Liminara: Strategic Synthesis

**Date:** 2026-03-14
**Context:** Distillation of all analysis and discussion sessions into settled decisions and open questions. Supersedes discussion notes; complements 02_Fresh_Analysis.md with decisions made.

---

## 1. What Liminara Is — The Final Definition

**Liminara is a general-purpose supervised computation runtime with recorded nondeterminism.**

More precisely: a system that makes any computation — regardless of domain — reproducible, auditable, and inspectable by treating nondeterministic choices as first-class recorded decisions rather than uncontrolled events.

"Make for processes with choices." The build system model (Make, Bazel, Nix), extended to handle irreducible nondeterminism that those systems cannot capture: LLM responses, human judgments, stochastic algorithms, creative synthesis.

### What "general-purpose" means

The five concepts (Artifact, Op, Decision, Run, Pack) are completely domain-agnostic. Artifact is an immutable blob. Op is a typed function with a determinism class. Decision is a recorded nondeterministic choice. Run is an event log + a plan. Pack is a plugin providing ops and a plan function.

These concepts apply equally to:
- AI/LLM workflow orchestration (Radar)
- Computational engineering (house compiler)
- Flow modeling (FlowTime integration)
- Scientific workflows (bioinformatics, materials science)
- Any domain where nondeterminism needs to be tracked

**"Knowledge work" is the beachhead market, not the definition.** The house compiler (non-LLM, geometry/structural/manufacturing) is the deliberate proof of generality — it should be the second pack precisely because it breaks the "LLM orchestrator" framing.

### The core differentiator

The combination nobody else has:
1. **Content-addressed artifacts** (like Git/Bazel/Nix) — "have I computed this exact thing before?"
2. **Decision records** (like a lab notebook) — "what did the LLM say, what did the human approve?"
3. **Determinism classes** (like a type system for side effects) — "is this op safe to cache? safe to replay?"

Neither Temporal, Dagster, Apache Burr, LangGraph, nor any other tool in the space has all three. This combination is the architectural moat.

Sources: [02_Fresh_Analysis.md](02_Fresh_Analysis.md), [04_HashiCorp_Parallels.md](04_HashiCorp_Parallels.md), [01_First_Analysis.md](01_First_Analysis.md)

---

## 2. DAG as the Execution Model — Settled

The execution model is a **DAG (directed acyclic graph)**. This is a settled decision.

### Why not a state machine?

Apache Burr (DAGWorks/Hamilton team) chose a state machine model for AI agents precisely because agents *loop* — they observe, reason, act, repeat. State machines handle cycles ergonomically. But they sacrifice:

- **Content-addressed caching** — stable cache keys require stable node identity, which cycles break
- **Deterministic replay** — "which cycle iteration are we on?" has no clean answer in a state machine
- **Provenance tracing** — shared mutable state makes backward tracing hard
- **Parallelism** — independent DAG nodes fire simultaneously; shared state creates implicit dependencies

### The synthesis

Any state machine can be **unrolled** into a DAG — this is a standard result in formal methods. A state machine running for N transitions produces a DAG execution trace with N nodes. The state machine is a compact *template* for possible executions; the unrolled trace is the actual *instance*.

Liminara's model:
- The **execution trace** is always a DAG, regardless of how it was generated
- Discovery mode produces a DAG that *grows during execution* — new nodes added as `expand` ops fire
- An op can internally implement state machine logic (loops, retries) — the runtime sees only "op started, op completed, outputs produced"
- The event log IS the unrolled execution trace

The DAG is not a limitation — it is the property that enables content-addressing, replay, and provenance. The state machine is an implementation detail of individual ops, not a runtime concern.

### Formal backing

A Liminara plan is a **workflow net** — a well-studied subclass of Petri nets. Petri net theory provides formal tools for verifying the scheduler: deadlock-freedom, liveness, reachability. The scheduler's "find ready nodes, dispatch, collect, repeat" loop is sound if and only if the underlying workflow net is sound.

Sources: [ADJACENT_TECHNOLOGIES.md](../research/ADJACENT_TECHNOLOGIES.md), [02_Fresh_Analysis.md](02_Fresh_Analysis.md)

---

## 3. Platform Emergence Model — Settled

The platform is not designed upfront. It emerges from building real domain packs.

### The pattern (with historical precedent)

Rails from Basecamp. React from Facebook's newsfeed. Terraform from HashiCorp's own infra needs. The platform emerges from the friction of building real things.

### Liminara's emergence path

1. **Report Compiler** (test fixture) — proves the plumbing. Exercises every core concept in miniature. Necessary but not sufficient to convince anyone.
2. **Radar** (first real pack) — used daily by the builder. Proves the runtime works for LLM workflows. First stress test against reality.
3. **House Compiler** (second real pack, different domain entirely) — the proof of generality. If the same five concepts work for *both* LLM text pipelines *and* geometry/structural/manufacturing pipelines with binary artifacts and non-LLM compute, the platform has genuinely emerged.

After step 3: an external party could take the platform and build their own pack. The abstraction is validated.

### What's being sold

The house compiler is the *product* — what generates revenue. The Radar is a *demonstration* of capability and a daily-use tool. The platform is the *enabler* of future packs and customer customizations. These are complementary, not competing.

The platform itself is not productized until after the house compiler validates it in a second domain. At that point, the Pack contract is proven, the core is hardened, and external packs become a real possibility.

---

## 4. Licensing — Decided

**Apache 2.0 for the core runtime.**

Rationale:
- Maximum community adoption — no copyleft concerns for corporate users
- EU funding compatible — EIC Accelerator and Vinnova strongly prefer open source
- Includes explicit patent grant — protects users and contributors
- Does not constrain domain packs — House Compiler, Radar → proprietary/commercial

The commercial moat is the domain packs and domain expertise, not the runtime code. The runtime being open source accelerates adoption; the domain packs being proprietary preserve commercial value.

**What to avoid:**
- BSL: destroyed HashiCorp's community trust overnight when switched. Avoid.
- AGPL: scares off enterprise users; most compliance-oriented buyers won't touch it.
- No license changes after community forms: this is the lesson from HashiCorp → IBM. Decide now, commit.

Sources: [04_HashiCorp_Parallels.md](04_HashiCorp_Parallels.md)

---

## 5. EU AI Act Positioning — Settled

**Framing:** "General-purpose provenance runtime. Compliance is a consequence of the architecture, not the product."

Liminara itself is **minimal risk** under the EU AI Act (it's infrastructure tooling). Its architecture (event sourcing, content-addressing, decision records) naturally satisfies Article 12 requirements — but this is a selling point in pitches, not the reason to build or buy Liminara. The actual value is reproducibility, replay, caching, and decision recording.

### Article 12 mapping

Article 12 requires automatic, tamper-resistant logging for all high-risk AI systems, with traceability from outputs to inputs, model versions, and governing policies. Minimum 6-month retention. Enforcement deadline: **2 August 2026** (5 months away as of this writing).

| Article 12 requirement | Liminara feature |
|------------------------|-----------------|
| Automatic event recording | Append-only event log per run |
| Tamper-resistant logs | Content-addressed artifacts + hash-chained events (planned) |
| Trace outputs to inputs | DAG of artifacts with content-addressed edges |
| Record model versions | Decision records capture model IDs, prompts, token usage |
| Identify nondeterminism | Determinism classes flag which ops are nondeterministic |
| 6-month retention | Filesystem event files, retained by policy |

**Planned addition for compliance:** hash-chained event log — each event includes `hash(previous_event)`. The final event's hash is the "run seal," cryptographically committing to the entire run history. This gives tamper-evidence without blockchain overhead. See [Certificate Transparency](../research/ADJACENT_TECHNOLOGIES.md#certificate-transparency) for the reference architecture.

### Positioning for funding applications

> "Liminara is a provenance engine for nondeterministic computation — it makes AI-driven workflows reproducible, auditable, and cacheable by recording every nondeterministic choice. Its architecture (content-addressed artifacts, decision records, determinism classes) naturally satisfies EU AI Act Article 12 requirements for automatic, tamper-resistant logging — compliance is a built-in consequence, not a bolt-on."

Sources: [03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md)

---

## 6. Radar Architecture — Clarified

Radar is a **research intelligence system**, not just an omvärldsbevakning newsletter generator. Key properties:
- **Continuous background process** — not a one-shot batch job
- **Discovers new sources** — directed crawler behavior, dynamically expanding the source set
- **Finds connections across adjacent fields** — cross-domain semantic proximity
- **Serendipity detection** — unexpected proximity between current corpus and distant sources
- **Historical search** — "has this problem been solved before?"

### Two-layer architecture

**Collection layer** — continuous, persistent, side-effecting. Ops: crawl, fetch, normalize, embed, update index. Runs on Liminara in discovery mode — new sources are found and added as new nodes. Produces a growing artifact corpus and vector index.

**Analysis layer** — triggered (scheduled or on-demand), pipeline mode. Takes an immutable snapshot of the current corpus as input. Produces a briefing artifact. Fully replayable and cacheable.

This separation keeps the analysis layer clean and testable while the collection layer handles the messy reality of the open web.

### Vector database integration

The vector index is a **Pack-managed reference artifact** — a versioned dataset registered via `Pack.init/0` and updated by collection runs. Each version is content-addressed.

- `embed_document` → `pure` op (pinned to model version): cacheable, stable
- `semantic_dedup` → `pure` op querying the current index
- `cross_domain_search` → `pure` op finding cross-domain nearest neighbors
- `index_update` → `side_effecting` op producing a new index artifact
- `synthesize` → `recordable` op (LLM): decision recorded

**Preferred vector store for v1:** [LanceDB](https://lancedb.com/) — file-based, embeddable, no separate server. The index file IS the artifact.

Cross-domain connection finding: embed documents from domain A and B into the same semantic space, compute cross-domain nearest neighbors. Proximity = potential serendipitous connection. An LLM `recordable` op then evaluates whether the connection is substantive.

---

## 7. FlowTime Relationship — Defined

FlowTime (github.com/23min/flowtime) is a flow modeling platform: visualizes and simulates how work moves through complex systems. It ingests telemetry, builds deterministic discrete-time models, generates what-if scenarios. Currently: alpha stage, C#/.NET 9, Blazor WebAssembly UI, running locally but not deployed.

**The relationship:** co-evolution with mutual influence, not a planned v1 integration.

- Liminara and FlowTime share philosophical DNA (determinism, DAG evaluation, immutability, time as structure)
- FlowTime is a natural future Op executor — the geometry kernel of flow modeling, the way a structural solver is the geometry kernel of the house compiler
- Liminara should inform FlowTime's design: what does FlowTime need to expose to be a clean Liminara Op executor? What does a FlowTime model need to be a properly typed artifact?
- Integration happens at the earliest opportunity FlowTime is ready, not on a fixed schedule

**The three integration models** (from [06_FlowTime_and_Liminara.md](06_FlowTime_and_Liminara.md)):
1. FlowTime as an Op executor — a computation engine Packs use
2. FlowTime model-building as a Liminara pipeline — Liminara orchestrates the AI-assisted construction of FlowTime models, recording design decisions
3. Shared philosophical DNA — two tools that compose naturally because they share core convictions about determinism and provenance

---

## 8. What Is Cut — Definitive List

| Cut | Rationale |
|-----|-----------|
| Multi-tenancy | Solo developer. `tenant_id = "default"` everywhere. Add when second user exists. |
| Distributed execution | Single BEAM node. Distributed Erlang is a trap. Use `:port`/`:container` for remote compute. |
| Wasm executor | `:port` and `:container` cover all real cases. |
| Discovery mode (v1) | Massively more complex than pipeline mode. Defer until pipeline mode is proven. |
| Visual DAG designer | Observation (read-only) yes. Design tool (write) is a different product entirely. |
| Budget enforcement | Track costs (log LLM token usage), don't enforce in v1. |
| Complex GC for artifact store | Time-based retention policy is sufficient. |
| Phoenix as a dependency | Phoenix LiveView for MVP UI is fine; avoid Phoenix as a platform dependency. |

**Domain pack tiers:**

| Tier | Packs | Status |
|------|-------|--------|
| **Active** | Report Compiler (fixture), Radar (product), House Compiler (validation) | On the critical path |
| **Hobby** | Software Factory | Not on critical path, but kept as a learning pack. Not competing with Claude Code/Cursor — orchestrating *over* them with provenance and decision recording. Build after House Compiler at hobby pace. |
| **Related** | Process Mining, FlowTime Integration | Significant synergy (Process Mining feeds FlowTime models). Build when FlowTime is ready. |
| **Far horizon** | Agent Fleets, Population Simulation, Behavior DSL, Evolutionary Factory, LodeTime | Aspirations of the author. Documented in `docs/domain_packs/`. Not scheduled. |

---

## 9. Development Sequence — Revised

The Python SDK (Phase 1) was built before the Elixir runtime to validate the data model spec when changes were cheap. It also produces a runnable demo artifact for pitches and funding applications — but it is not a product. The compliance reporting it generates is a consequence of Liminara's architecture, not a standalone value proposition. Anyone could build equivalent compliance-only tooling in a weekend.

```
Phase 0: Data model definition (before any code)
  Define once: event format, artifact hash format, decision record schema,
  hash chain algorithm. Both Python SDK and Elixir runtime implement this model.

Phase 1: Python SDK / data model validation  (integrations/python/)
  Validates the data model spec end-to-end in a running implementation.
  - liminara/ Python SDK with decorators
  - Example 01: raw Python + Anthropic SDK (data model demo)
  - Example 02: LangChain RAG + LiminaraCallbackHandler (named integration)
  - CLI + Docker (runnable in 5 minutes)
  - Full test suite (output equivalence, completeness, correctness, tamper-evidence)
  Deliverable: validated data model, runnable demo artifact for pitches.

Phase 2: Elixir walking skeleton
  Artifact.Store, Event.Store, Plan, Run.Server, Op behaviour.
  Reads the same file format the Python SDK writes.

Phase 3: Report Compiler pack (Elixir, test fixture)

Phase 4: Observation layer (ex_a2ui or Phoenix LiveView)

Phase 5: Radar pack (first real product, uses Python SDK compliance layer)

Phase 6: Oban + Postgres (scheduling)

Phase 7: House compiler (second domain, proof of generality)
```

See [09_Compliance_Demo_Tool.md](09_Compliance_Demo_Tool.md) for the full demo tool design.

---

## 10. Open Questions

| Question | Status | Notes |
|----------|--------|-------|
| Radar collection layer: separate service or Liminara Pack? | **Decided: Liminara Pack** | Everything runs on Liminara. Discovery mode needed sooner than expected. |
| Hash-chained event log: add to v1 or v2? | Open | Adds Article 12 tamper-resistance; low implementation overhead; might be worth v1 |
| W3C PROV export: when? | Open | High interoperability value for compliance market; post-MVP |
| FlowTime Pack integration: timeline? | Open | Co-evolve; earliest opportunity FlowTime is ready |
| Funding: Vinnova Innovative Startups application | Open | Check next call opening; low barrier, good early validation funding |
| EIC Accelerator Step 1: target date? | Open | September or November 2026 cutoff; needs MVP running (TRL 6) |

---

*See also:*
- *[01_CORE.md](../architecture/01_CORE.md) — runtime architecture*
- *[02_PLAN.md](../architecture/02_PLAN.md) — living build plan*
- *[02_Fresh_Analysis.md](02_Fresh_Analysis.md) — landscape and competitive analysis*
- *[05_Why_Replay.md](05_Why_Replay.md) — the case for recorded decisions and replay*
- *[ADJACENT_TECHNOLOGIES.md](../research/ADJACENT_TECHNOLOGIES.md) — intellectual ancestors and adjacent technologies*
- *[09_Compliance_Demo_Tool.md](09_Compliance_Demo_Tool.md) — Python SDK demo tool design and repo structure*
- *[07_Compliance_Layer.md](07_Compliance_Layer.md) — full compliance layer architecture*
- *[08_Article_12_Summary.md](08_Article_12_Summary.md) — plain-language Article 12 explanation*
- *[03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md) — regulatory and funding context*
- *[11_Data_Model_Spec.md](11_Data_Model_Spec.md) — canonical on-disk format: hashing, event log, artifacts, decisions (Phase 0)*
