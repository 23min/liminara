# Population Sim — Evolutionary House Design

**Can you trace a winning design back through 50 generations to the mutation that made it work?**

Far horizon | high-volume decisions, evolutionary lineage, caching synergy

---

## The scenario

Trähusfabriken AB, a modular timber house manufacturer outside Falun, wants to optimize their standard 120 m^2 family home for the Swedish climate zones. The objective: minimize heating energy cost while keeping structural material cost below 485,000 SEK and meeting BBR energy requirements for all three climate zones.

The optimization runs 50 generations of 100 candidates each. Each candidate is a configuration: wall thickness, insulation type, window-to-wall ratio, roof pitch, orientation, ventilation heat recovery rate. Each candidate is evaluated by running a House Compiler pipeline — structural check, energy simulation (SVEBY method), cost estimate. Selection uses tournament selection (stochastic). Crossover and mutation are stochastic. Every stochastic choice is a recorded decision.

```
  Generation 0        Generation 1              Generation 47
  ┌─────────────┐     ┌─────────────┐           ┌─────────────┐
  │ 100 random  │     │ 100 bred    │           │ 100 refined │
  │ candidates  │     │ candidates  │    ...    │ candidates  │
  │             │     │             │           │             │
  │ ┌─┐┌─┐┌─┐  │     │ ┌─┐┌─┐┌─┐  │           │ ┌─┐┌─┐┌─┐  │
  │ │A││B││C│  │     │ │D││E││F│  │           │ │W││X││Y│  │
  │ └┬┘└┬┘└┬┘  │     │ └┬┘└┬┘└┬┘  │           │ └┬┘└┬┘└┬┘  │
  └──┼──┼──┼──┘     └──┼──┼──┼──┘           └──┼──┼──┼──┘
     ▼  ▼  ▼           ▼  ▼  ▼                 ▼  ▼  ▼
  ┌──────────────┐  ┌──────────────┐         ┌──────────────┐
  │House Compiler│  │House Compiler│         │House Compiler│
  │per candidate │  │per candidate │   ...   │per candidate │
  │ struct check │  │ struct check │         │ struct check │
  │ energy sim   │  │ energy sim   │         │ energy sim   │
  │ cost est.    │  │ cost est.    │         │ cost est.    │
  └──────┬───────┘  └──────┬───────┘         └──────┬───────┘
         ▼                 ▼                        ▼
  ┌──────────────┐  ┌──────────────┐         ┌──────────────┐
  │  fitness     │  │  fitness     │         │  fitness     │
  │  14.2 kWh/m² │  │  11.8 kWh/m² │        │   9.1 kWh/m² │
  │  438k SEK    │  │  461k SEK    │         │  472k SEK    │
  └──────────────┘  └──────────────┘         └──────────────┘
         │                 │                        │
         └────── select ───┘─── ... ────── select ──┘
              (stochastic,                (stochastic,
               recorded)                   recorded)
```

**5,000 candidate evaluations** over 50 generations. But content-addressed caching means: if candidate #37 in generation 12 has the same configuration as candidate #81 in generation 23 (convergent evolution), the House Compiler evaluation is computed once. In practice, convergence means roughly 30% of late-generation evaluations are cache hits — the population clusters around good configurations, and duplicates are free.

The winning design (candidate W, generation 47: 9.1 kWh/m^2, 472,000 SEK, passes all three climate zones) has a full lineage. Trace backward: W was bred from candidates in generation 46, which descended from generation 45, and so on — back to the random initializations in generation 0. The crossover at generation 31 that combined high insulation thickness from one lineage with optimized window placement from another is visible as a specific decision record with specific parent candidates.

## What makes this interesting as a Liminara validation

**High-volume decision recording.** 50 generations x 100 candidates x (selection + crossover + mutation) produces thousands of stochastic decision records. The runtime must handle this volume without event log bloat becoming a bottleneck.

**Caching synergy.** The cache key for a House Compiler evaluation is `hash(house_compiler_ops, config_hash)`. Convergent evolution produces identical configurations — the cache naturally deduplicates expensive evaluations. This is not an optimization bolted on; it falls directly out of content-addressed artifact storage.

**Navigable fitness landscape.** The 50 generations of evaluations, stored as artifacts, form a searchable landscape. You can ask: "show me all candidates with energy below 10 kWh/m^2 and cost below 460k SEK" and see when they first appeared, which mutations produced them, and which lineages converged on them. The evolutionary search becomes a dataset, not just a final answer.

**Composability with Behavior DSL.** The BBR energy requirements evaluated in each House Compiler run are themselves content-addressed artifacts (see Behavior DSL pack). When BBR updates, every cached evaluation that used the old rules is invalidated. The population can be re-evaluated against new rules without re-running the evolution — just the fitness evaluations.

---

*Far-horizon exploration. Validates: high-volume decision recording, caching under convergent evolution, composability with House Compiler and Behavior DSL packs.*
