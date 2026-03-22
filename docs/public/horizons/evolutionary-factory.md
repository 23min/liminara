# Evolutionary Factory — Supply Chain Optimization Through Composition

**What happens when three packs — evolution, simulation, and process mining — compose into one optimization loop?**

Far horizon | pack composition, evolutionary search, simulation-based fitness, pattern discovery

---

## The scenario

Nordvik Logistik, a mid-size Swedish distributor of industrial fasteners, sources from 12 suppliers across Europe and Asia, operates two warehouses (Gothenburg and Norrköping), and delivers to 340 B2B customers. Their supply chain configuration — which suppliers to use for which product families, which warehouse handles which customer regions, what safety stock levels to maintain — was designed five years ago and hasn't been systematically re-evaluated since. Container shipping costs have doubled. Two suppliers have moved facilities. Lead times from Asia have become less predictable.

The Evolutionary Factory optimizes Nordvik's supply chain configuration using three Liminara packs working together:

```
  ┌──────────────────────────────────────────────────────────┐
  │  Evolutionary Factory (outer loop)                       │
  │                                                          │
  │  Population: 80 candidate configurations                 │
  │  Each candidate: supplier assignments, routing rules,    │
  │                  inventory levels, warehouse allocation   │
  │                                                          │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │  For each candidate:                               │  │
  │  │                                                    │  │
  │  │  ┌─ FlowTime (simulation) ──────────────────────┐  │  │
  │  │  │  Simulate 12 months of order flow             │  │  │
  │  │  │  - order arrivals (from historical data)      │  │  │
  │  │  │  - supplier lead times (stochastic, recorded) │  │  │
  │  │  │  - transport disruptions (probability model)  │  │  │
  │  │  │                                               │  │  │
  │  │  │  Output: delivery performance, total cost,    │  │  │
  │  │  │  stockout frequency, warehouse utilization    │  │  │
  │  │  └──────────────────────────────────────────────┘  │  │
  │  │                         │                          │  │
  │  │                    fitness score                    │  │
  │  │          (cost × 0.4 + service × 0.4 +             │  │
  │  │           resilience × 0.2)                        │  │
  │  └────────────────────────────────────────────────────┘  │
  │                         │                                │
  │              select → crossover → mutate                 │
  │             (all stochastic, all recorded)                │
  │                         │                                │
  │                  next generation                          │
  └──────────────────────────────────────────────────────────┘
                            │
                   after 30 generations
                            │
                            ▼
  ┌──────────────────────────────────────────────────────────┐
  │  Process Mining (analysis of the optimization itself)    │
  │                                                          │
  │  Input: the event logs from all 2,400 simulation runs   │
  │                                                          │
  │  Discover patterns:                                      │
  │  - "Configurations that route fragile goods through      │
  │     Gothenburg consistently score 12% higher on          │
  │     service level"                                       │
  │  - "Dual-sourcing for product family F3 eliminated       │
  │     stockouts after generation 8 — all surviving         │
  │     candidates use it"                                   │
  │  - "Safety stock above 3 weeks for Asian suppliers       │
  │     shows diminishing returns after generation 15"       │
  │                                                          │
  │  These patterns are artifacts, not ephemeral insights.   │
  └──────────────────────────────────────────────────────────┘
```

The winning configuration (generation 30, candidate #42: 8.2% cost reduction, 99.1% on-time delivery, resilient to single-supplier disruption) is not just a set of numbers. It has a full evolutionary lineage: which parent configurations, which crossover combined Gothenburg routing with dual-sourcing, which mutation introduced the higher safety stock for Asian suppliers. And the Process Mining analysis explains *why* this configuration works — not just that it won the tournament.

## What makes this interesting as a Liminara validation

**Three packs composing.** The Evolutionary Factory provides the optimization loop. FlowTime provides the fitness evaluation (each candidate is a simulation run). Process Mining analyzes the trajectory of the optimization itself. Each pack operates through its own IR pipeline with its own artifact types, but they compose through shared artifacts: the Evolutionary Factory produces candidate configurations (artifacts) consumed by FlowTime; FlowTime produces simulation results (artifacts) consumed by both the Evolutionary Factory (as fitness scores) and Process Mining (as event logs to analyze).

**Simulation as fitness function.** Each FlowTime simulation is a full Liminara run with its own event log. The stochastic elements (supplier lead time variation, transport disruptions) are recorded decisions with pinned seeds. This means: the same candidate evaluated twice produces the same fitness score (replay determinism). Different candidates experiencing the same disruption scenario can be compared fairly.

**Meta-provenance.** Process Mining discovers patterns in the optimization trajectory — patterns that are themselves content-addressed artifacts. The insight "dual-sourcing for F3 eliminated stockouts" traces to specific simulation runs, specific candidate lineages, and specific generation boundaries. It is a finding with evidence, not an assertion.

**Caching across generations.** If a candidate configuration from generation 5 reappears (through convergent evolution or unchanged crossover) in generation 22, the FlowTime simulation is a cache hit. The fitness landscape is computed incrementally, not from scratch each generation. For 80 candidates over 30 generations, caching typically eliminates 15-25% of simulation runs in practice.

---

*Far-horizon exploration. Validates: multi-pack composition, simulation-based fitness evaluation, process mining over optimization trajectories, cross-pack artifact flow.*
