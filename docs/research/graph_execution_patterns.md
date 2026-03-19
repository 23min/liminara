# Graph Execution Patterns: Supply Chains, Smart Contracts, and Liminara

**Date:** 2026-03-19
**Status:** Research / exploration
**Trigger:** Observing structural parallels between Liminara's DAG execution model, physical supply chains, and blockchain smart contracts.

---

## 1. The Pattern

There is a recurring structural pattern across domains that appear unrelated on the surface:

> **A directed graph of transformations, where inputs flow through typed operations to produce outputs, and the lineage of any output can be traced back to its origins.**

This pattern appears in build systems (Make, 1976), data pipelines (Airflow, 2014), smart contracts (Ethereum, 2015), supply chain management, biological pathways, business process management, and now Liminara. Each instance makes different trade-offs around determinism, time scale, verification, and artifact type — but the underlying structure is the same.

The question this document explores: **What are the deep parallels, and what do they reveal about Liminara's generality?**

---

## 2. A Taxonomy of Graph Execution Systems

| System | Artifact type | Determinism | Time scale | Verification | Nondeterminism handling |
|--------|--------------|-------------|------------|-------------|------------------------|
| **Build systems** (Make, Bazel, Nix) | Files (source, object, binary) | Required | Seconds–minutes | Re-execution (same inputs → same output) | Banned. Nondeterminism is a bug. |
| **Data pipelines** (Airflow, Dagster) | Datasets, tables, models | Assumed | Minutes–hours | Asset lineage, checksums | Ignored. Runs may differ; nobody checks. |
| **Smart contracts** (Ethereum, Solana) | State transitions (balances, records) | Required | Milliseconds per tx; contract life: indefinite | Consensus (every node re-executes) | Banned. Determinism enforced by the EVM. |
| **Supply chains** | Physical goods, documents, certificates | Nondeterministic | Days–years | Physical inspection, audit, certification | Accepted as reality. Managed by contracts and trust. |
| **Business processes** (BPMN, Camunda) | Documents, approvals, forms | Mixed | Hours–months | Compliance audit, sign-off trails | Human decisions modeled as tasks. |
| **Scientific workflows** (CWL, Galaxy, Nextflow) | Datasets, papers, models | Desired but hard | Hours–weeks | Reproducibility attempts, checksums | Acknowledged as a problem. Partially recorded. |
| **Biological pathways** | Molecules, proteins, signals | Stochastic | Milliseconds–years | Experimental validation | Fundamental. Stochasticity is the mechanism. |
| **Liminara** | Content-addressed blobs (any type) | Captured (4 classes) | Any | Hash chain + content addressing | **First-class. Recorded as decisions.** |

### What makes each system unique

The variation points are:

1. **What flows through the graph** — bits, atoms, money, molecules, approvals
2. **How nondeterminism is handled** — banned, ignored, accepted, or recorded
3. **How verification works** — re-execution, consensus, hash chain, physical inspection
4. **Time scale** — milliseconds to years
5. **Whether the graph is known upfront** — static (build systems) vs discovered (agent workflows) vs evolving (supply chains)

Liminara's position is unusual: it handles nondeterminism explicitly (recording it) rather than banning it (build systems, smart contracts) or ignoring it (data pipelines). And it works at any time scale because the event log is the source of truth, not an in-memory process.

---

## 3. Ethereum Smart Contracts: Deeper Than the Analogy

### How long do smart contracts run?

This question reveals an important distinction.

**A single contract execution is extremely short.** Each Ethereum transaction completes in milliseconds, bounded by the block gas limit (~30M gas, roughly 100ms of computation). The EVM is designed for small, fast, deterministic computations. You cannot run a long computation in a single transaction — you'll run out of gas.

**But a contract's _lifecycle_ is indefinite.** A contract deployed to Ethereum persists forever (or until self-destructed, which is now deprecated). It can be called millions of times over decades. The *state* of the contract evolves with each call, but each call is an atomic, fast operation.

**Multi-step processes modeled by contracts span days to years:**

| Contract pattern | Duration | How it works |
|-----------------|----------|-------------|
| **Vesting schedule** | 1–4 years | Tokens unlock on a schedule. Each `claim()` call checks elapsed time and releases tokens. Between calls: dormant. |
| **DAO governance** | Days per proposal | Propose → vote (3–7 days) → timelock (2 days) → execute. Each step is a transaction. |
| **Escrow** | Hours–months | Funds locked until conditions met (delivery confirmed, dispute resolved, timeout). |
| **Multi-sig wallet** | Minutes–weeks | Requires N-of-M signatures. Each signature is a transaction. The wallet "waits" between signatures. |
| **Auction** | Hours–days | Bids accumulate. Settlement is a single transaction at the end. |
| **DeFi protocol** | Indefinite | Liquidity pools, lending markets — the protocol "runs" forever, activated by each user interaction. |

### The key insight

**Ethereum contracts don't "run" for a long time. They _exist_ for a long time, and are _activated_ by discrete events.**

Between activations, the contract is dormant — just state on the blockchain. When an event occurs (a user calls a function, a timer expires, another contract triggers it), the contract wakes up, executes a tiny computation, updates its state, and goes back to sleep.

This is a **reactive, event-driven execution model.** The contract is a state machine advanced by external events.

### The parallel to Liminara

Liminara's Run.Server already works this way for gates — it dispatches ops, and when a gate is reached, it waits for external resolution. But for long-running processes (supply chains, business workflows), **every step could be a gate.**

The Run.Server doesn't need to be alive between events. The event log is the durable state. The GenServer is the executor:

```
Event arrives (gate resolved, timer fires, external signal)
    → Start or wake Run.Server
    → Rebuild state from event log (milliseconds)
    → Dispatch newly ready nodes
    → Execute or wait
    → If nothing more to dispatch, stop the GenServer
    → Event log persists. Run state is safe.
```

This is the "activatable run" pattern: **the run exists as an event log on disk, and a GenServer is instantiated only when there's work to do.** This is exactly how Ethereum contracts work — state on chain, computation only on activation.

Liminara already has every piece needed for this:
- Event sourcing (state reconstructed from the log)
- Crash recovery (Run.Server rebuilds from events on restart)
- Gates (external events trigger continuation)
- The only new piece is: **intentionally stopping the Run.Server between events for very long-running runs**, and restarting it on demand (e.g., via Oban job, webhook, or manual trigger).

---

## 4. Supply Chains as Computation

### A Liminara run IS a supply chain

The mapping is not metaphorical — it's structural:

| Supply chain concept | Liminara equivalent | Notes |
|---------------------|---------------------|-------|
| Raw materials | Input artifacts (literals) | The starting resources |
| Intermediate goods | Artifacts between ops | Content-addressed, traceable |
| Manufacturing step | Op (transformation) | Typed function with determinism class |
| Final product | Output artifacts | The result of the run |
| Quality inspection | Gate (human approval) | Recorded as a decision |
| Supplier choice | Decision (recordable) | Nondeterministic, recorded |
| Bill of materials | Plan (DAG) | The graph of ops and dependencies |
| Purchase order | Run (execution) | An instance of the plan being walked |
| Audit trail | Event log (hash-chained) | Tamper-evident, append-only |
| Recall / trace-back | Artifact provenance | Follow content hashes upstream |
| Cost accounting | Metadata on events | Duration, resource usage, per-op |
| Certificate of compliance | Run seal | Cryptographic commitment to entire run |

### What would a supply chain pack look like?

```elixir
defmodule SupplyChain.Pack do
  @behaviour Liminara.Pack

  def id, do: :supply_chain
  def version, do: "0.1.0"

  def ops, do: [
    SupplyChain.Ops.SourceMaterials,      # :recordable — choose suppliers
    SupplyChain.Ops.QualityInspection,    # :recordable — human gate, approve/reject
    SupplyChain.Ops.Manufacture,          # :pure — given exact inputs, output is determined
    SupplyChain.Ops.AssembleSubsystem,    # :pure — deterministic assembly from components
    SupplyChain.Ops.ShipToWarehouse,      # :side_effecting — real-world action
    SupplyChain.Ops.FinalInspection,      # :recordable — human gate
    SupplyChain.Ops.CertifyCompliance,    # :pure — check against rules, deterministic
    SupplyChain.Ops.DeliverToCustomer,    # :side_effecting — real-world action
  ]

  def plan(order) do
    Plan.new()
    |> Plan.node(:source_steel,    :source_materials,    spec: literal(order.steel_spec))
    |> Plan.node(:source_timber,   :source_materials,    spec: literal(order.timber_spec))
    |> Plan.node(:inspect_steel,   :quality_inspection,  material: ref(:source_steel))
    |> Plan.node(:inspect_timber,  :quality_inspection,  material: ref(:source_timber))
    |> Plan.node(:cut_steel,       :manufacture,         material: ref(:inspect_steel),
                                                         program: literal(order.cnc_program))
    |> Plan.node(:treat_timber,    :manufacture,         material: ref(:inspect_timber),
                                                         process: literal(:pressure_treat))
    |> Plan.node(:assemble,        :assemble_subsystem,  frame: ref(:cut_steel),
                                                         panels: ref(:treat_timber))
    |> Plan.node(:final_check,     :final_inspection,    assembly: ref(:assemble))
    |> Plan.node(:certify,         :certify_compliance,  assembly: ref(:final_check),
                                                         ruleset: literal(:iso_9001))
    |> Plan.node(:deliver,         :deliver_to_customer, product: ref(:certify),
                                                         address: literal(order.address))
  end
end
```

This plan would take **weeks to months** to complete. Each gate (quality inspection, final inspection) might take hours or days. Manufacturing steps take days. Shipping takes days to weeks. Between steps, the run is dormant — just an event log on disk.

### Time scales and the "activatable run" pattern

| Liminara domain | Typical run duration | Active computation time | Waiting time |
|----------------|---------------------|----------------------|-------------|
| Report Compiler (toy) | < 1 second | ~100% | ~0% |
| Radar (daily briefing) | 30 seconds–5 minutes | ~90% | ~10% (optional gate) |
| House Compiler | 5–30 minutes | ~95% | ~5% (optional design approval) |
| Software Factory | 10–60 minutes | ~40% | ~60% (human review gates) |
| Supply chain (simple product) | 2–8 weeks | < 0.01% | > 99.99% |
| Supply chain (complex product) | 3–18 months | < 0.001% | > 99.999% |
| Infrastructure project | 1–5 years | negligible | nearly all |

The trend is clear: **as processes move from pure computation to real-world coordination, waiting dominates.** The computation per step is trivial; the elapsed time is determined by the physical world.

This doesn't break Liminara's architecture — it validates it. Event sourcing means the state persists regardless of whether the GenServer is alive. The scheduler loop is the same; it just runs less frequently. A supply chain run might dispatch one node per week.

### Simulation vs live: same DAG, different time scales

A supply chain pack could operate in two modes with the same DAG:

**Simulation mode:**
- All ops execute immediately with synthetic data or cached historical data
- Gates auto-resolve with default decisions (or inject decisions from a previous run)
- The run completes in seconds
- Used for: planning, optimization, cost estimation, what-if analysis
- All nondeterministic ops are either `:pure` (using synthetic inputs) or replay from stored decisions

**Live mode:**
- Ops are gated by real-world events (shipment arrived, inspection passed)
- The run takes weeks/months
- Used for: tracking actual supply chain execution
- Decisions are recorded as they happen in the real world

**The transition:** Start with a simulation to plan the chain. Then "promote" the plan to a live run. As real events arrive, they replace the simulated decisions. The system shows you: **here's what we planned, here's what actually happened, here's where they diverged.**

```
Simulation run:     [plan] ──→ [simulated decisions] ──→ [projected outcome]
Live run:           [same plan] ──→ [real decisions as they happen] ──→ [actual outcome]
Divergence view:    diff(simulation.decisions, live.decisions)
```

This is powerful for supply chain management. You simulate to set expectations, track reality, and the decision diff shows you where the plan broke down — which supplier was late, which quality check failed, which cost overran.

Liminara's decision records make this comparison trivial. Both runs produce decision records. Diffing them shows exactly where reality diverged from the plan.

---

## 5. Transparency and Verification

### Three approaches to trustless verification

The supply chain document envisions "Transparent Capitalism" — fully auditable supply chains where every step is inspectable. This is fundamentally a verification problem: how do you trust that the chain was followed correctly?

| Approach | Mechanism | Cost | Trust model |
|----------|-----------|------|-------------|
| **Blockchain** (Ethereum) | Consensus — every node re-executes every transaction | High (gas fees, energy, network overhead) | Trustless (no single party can cheat) |
| **Liminara** | Hash chain — each event references the previous event's hash | Low (SHA-256 computation, file I/O) | Tamper-evident (cheating is detectable, not prevented) |
| **Physical audit** | Human inspection of records, facilities, processes | Very high (auditor time, travel, expertise) | Trust the auditor |

Ethereum provides the strongest guarantee (trustless: no single party can falsify the record). But it comes at enormous cost — every transaction costs gas, the network processes ~15 transactions per second, and storage is expensive.

Liminara provides a weaker but practical guarantee: **tamper-evidence.** The hash chain means that modifying any event invalidates all subsequent hashes. You can verify the chain by recomputing hashes — much cheaper than blockchain consensus. If someone tampers with the record, you'll know. You can't *prevent* tampering (unlike a decentralized blockchain), but you can detect it.

For supply chain transparency, tamper-evidence is arguably more practical than trustlessness:
- Supply chains already involve trusted parties (auditors, certifiers)
- The cost of blockchain verification for every manufacturing step is prohibitive
- Hash-chain verification is instant and free
- If disputes arise, the hash chain provides cryptographic evidence

### "Transparency breaches flow downstream"

The supply chain document states: *"Transparency breaches flow downstream. This process should be automatic."*

Liminara's cache invalidation already does this for computation. When an upstream artifact changes, all downstream cache keys change — downstream results become suspect and must be recomputed.

For supply chains, the analogous mechanism would be: **if an upstream step is found to be non-compliant (a material fails a later test, a supplier's certification expires, a quality record is disputed), all downstream artifacts that depend on it are automatically flagged.**

```
source_steel ──→ inspect_steel ──→ cut_steel ──→ assemble ──→ final_check ──→ deliver
     │
     └── [FLAGGED: supplier certificate expired]
                    │
                    └── all downstream artifacts marked "tainted"
```

This is artifact provenance in reverse: instead of "where did this output come from?", it's "what does this problem affect?" Both are graph traversals. Content-addressing makes them efficient.

---

## 6. Ricardian Contracts and Computational Agreements

A Ricardian contract (Ian Grigg, 1996) is a document that is simultaneously:
1. Human-readable (a legal contract)
2. Machine-parseable (structured data)
3. Cryptographically signed (tamper-evident)

The concept bridges the gap between legal agreements and executable code. Ethereum smart contracts are one realization — code that executes financial logic with legal implications. But Ricardian contracts are broader: any agreement that can be both read by humans and acted on by machines.

### Connection to Liminara

A Liminara run with its event log and run seal has Ricardian properties:

- **Human-readable:** The event log is JSONL — a human can read it, understand what happened at each step, trace decisions.
- **Machine-parseable:** The events are structured JSON with defined schemas. Programs can process them.
- **Cryptographically signed:** The hash chain provides tamper-evidence. The run seal commits to the entire history.

If a Liminara run represents a business process (a supply chain, an approval workflow, a compliance check), the run seal functions as a **cryptographic receipt** — proof that the process was followed, with every step and decision recorded.

This connects to:
- **EU AI Act Article 12** — requires audit trails for AI-driven decisions. A Liminara event log satisfies this by architecture.
- **ISO 9001 quality management** — requires documented processes and records. A Liminara run IS the documentation.
- **Financial auditing** — requires traceable decision chains. Decision records provide this.

The run seal could be published, shared, or submitted to regulators as evidence. Anyone with the event log can verify the hash chain independently. No blockchain needed — just the log file and a SHA-256 implementation.

---

## 7. Visualization: A Shared Problem Space

All graph execution systems face the same visualization challenge: **show the user what's happening, what happened, and what will happen — at the right level of detail.**

### Existing visualization paradigms

| Domain | Visualization tool | Key features |
|--------|-------------------|-------------|
| Blockchain | Etherscan, blockchain explorers | Transaction flow, address graphs, contract state history |
| Supply chain | SAP IBP, Kinaxis, supply chain maps | Geographic flow, inventory levels, bottleneck highlighting |
| Data pipelines | Dagster Dagit, Airflow UI | DAG view, run timeline, asset lineage |
| Business processes | Camunda, ProcessMaker | BPMN diagram, token animation, task inbox |
| Build systems | Bazel query, Buck2 target graph | Dependency tree, build timeline |
| Scientific workflows | Galaxy, Nextflow Tower | Pipeline DAG, provenance graph, data browser |

### Common visual patterns

Despite domain differences, the same visual patterns recur:

1. **The DAG view** — nodes and edges showing the graph structure, colored by status (pending, running, complete, failed). Every system has this.
2. **The timeline** — events or steps ordered chronologically. Duration bars, wait times, critical path highlighting.
3. **The drill-down** — click a node to inspect details: inputs, outputs, timing, logs, decisions. Progressive disclosure.
4. **The trace** — select an output and highlight everything upstream that contributed. Or select an input and highlight everything downstream that depends on it.
5. **The diff** — compare two runs: what changed, what was the same, where did decisions diverge.
6. **The live feed** — streaming updates as the process executes. For long-running processes, this becomes a dashboard with periodic refresh.

Liminara's observation layer should implement all six. The architecture (content-addressed artifacts, event sourcing, decision records) makes each one natural:

- DAG view: the plan IS a DAG; events provide node states
- Timeline: the event log IS a timeline
- Drill-down: artifact hashes link to content; decision records link to choices
- Trace: follow artifact hashes through the DAG (upstream or downstream)
- Diff: compare decision records between two runs
- Live feed: :pg event broadcasting already provides this

### Canvas vs SVG vs DOM

For Liminara's implementation:

| Technology | Strengths | Weaknesses | Best for |
|-----------|-----------|------------|----------|
| **SVG** | Declarative, CSS-styleable, accessible, LiveView-diffable, scales well to ~500 elements, mobile-friendly | Performance degrades with thousands of elements | DAG views, small-medium graphs |
| **Canvas** | High performance (10K+ elements), pixel-perfect rendering, smooth animation | Imperative (harder with LiveView), not accessible, not searchable | Large visualizations (GA populations, dense graphs), smooth animations |
| **DOM/HTML** | Most natural in LiveView, full CSS/responsive, accessible | Not great for arbitrary graph layout | Dashboards, tables, inspectors, timelines |

**Recommendation for Liminara:** SVG for the DAG view (LiveView can diff SVG natively, and typical plans have 5–50 nodes). DOM/HTML for dashboards and inspectors. Canvas only if needed for specialized views (e.g., a GA population visualization with hundreds of candidates).

---

## 8. What This Means for Liminara

### Validation of generality

The five-concept model (Artifact, Op, Decision, Run, Pack) maps naturally to domains far beyond its original LLM-pipeline and house-compiler targets. Supply chains, business processes, scientific workflows, and even (conceptually) smart contract patterns all reduce to the same primitives.

This is not an argument to build supply chain features now. It's evidence that the architecture is sound — the abstractions are at the right level.

### Architectural implications

Three insights that affect the build plan:

1. **The "activatable run" pattern should be a first-class concept.** For long-running processes, the Run.Server should be able to stop between events and restart on demand. Event sourcing already supports this. The missing piece is an explicit API for it — and Oban (Phase 6) is the natural trigger mechanism. This is not new work; it's recognizing that the existing architecture already supports a wider range of time scales than initially assumed.

2. **Gates are more fundamental than they appear.** In the current design, gates are a special case — an op can optionally return `{:gate, prompt}`. For long-running processes, gates are the *dominant* mechanism. Every interaction with the physical world (shipment confirmation, inspection result, payment received) is a gate. The gate API should be robust enough to handle this: external webhooks resolving gates, timeouts on gates, gate delegation, batch resolution.

3. **The simulation/live duality is a powerful feature.** The ability to run the same DAG in "simulation mode" (instant, with synthetic decisions) and "live mode" (real-time, gated by the physical world) is a consequence of decision recording. This duality should be recognized in the architecture, even if not built immediately.

### What's NOT implied

This analysis does not mean Liminara should:
- Build a supply chain product (no customer, no domain expertise)
- Add blockchain verification (hash chains are sufficient)
- Build a BPMN engine (Liminara is computation-first, not process-first)
- Expand scope beyond the current build plan

The practical takeaway is confidence: the architecture handles more than we're building, which means we're unlikely to paint ourselves into a corner.

---

## 9. Open Questions

1. **Could the observation layer borrow from supply chain visualization tools?** Geographic flow maps, Sankey diagrams, and bottleneck highlighting are mature patterns that might translate to computation DAGs.

2. **Is there a market for "auditable computation" beyond AI?** The EU AI Act drives compliance for AI systems, but regulated industries (pharma, aerospace, financial services) have similar audit requirements for non-AI processes. Liminara's architecture applies to both.

3. **Could Liminara serve as the "transparent accounting layer" the supply chain document envisions?** Not as a product — but as a proof of concept? A toy supply chain pack that demonstrates end-to-end transparency would be a compelling demo.

4. **What's the relationship between Liminara and process mining?** Process mining reconstructs business processes from event logs. Liminara *produces* event logs. Could Liminara's event format be compatible with process mining tools (XES, OCEL)?

5. **Activatable runs and serverless:** The "wake up, process, sleep" pattern for long-running runs resembles serverless function execution. Is there a connection to Oban's job model that should be made explicit in Phase 6?

---

*This document is exploratory. It identifies patterns and connections, not commitments. For the build plan, see [02_PLAN.md](../architecture/02_PLAN.md). For the core architecture, see [01_CORE.md](../architecture/01_CORE.md).*
