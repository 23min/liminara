# Behavior DSL — Regulations as Versioned Artifacts

**When the building code changes, which designs are still valid? Can the system tell you automatically?**

Far horizon | rules as artifacts, cache invalidation, regulatory change propagation

---

## The scenario

On January 1, 2027, Boverket publishes an updated BBR (Boverkets Byggregler) with stricter energy requirements for climate zone III (northern Sweden). The maximum allowed specific energy use for residential buildings drops from 95 kWh/m^2 to 85 kWh/m^2. This change affects every house design that Trähusfabriken has compiled for delivery sites north of Sundsvall.

In a traditional workflow, someone reads the Boverket announcement, manually checks which projects are affected, and reruns the energy calculations. Some projects get missed. Some get rechecked unnecessarily.

With Behavior DSL, the BBR is not embedded in code. It is a **versioned, content-addressed artifact** — a ruleset expressed in a safe DSL, parsed to an AST, type-checked, and evaluated by a pure op. When the BBR artifact changes, the system knows exactly what to invalidate.

```
  BBR v2026 (artifact)                  BBR v2027 (artifact)
  sha256:4a12...                        sha256:8f93...
  ┌────────────────────┐                ┌────────────────────┐
  │ climate_zone_III:  │                │ climate_zone_III:  │
  │   max_energy: 95   │   ──update──→  │   max_energy: 85   │
  │   ...              │                │   ...              │
  └────────┬───────────┘                └────────┬───────────┘
           │                                     │
           ▼                                     ▼
  cache_key = hash(                     cache_key = hash(
    energy_check_op,                      energy_check_op,
    design_hash,                          design_hash,      ← same
    bbr_4a12...                           bbr_8f93...       ← different
  )                                     )
  → cache HIT (old result)             → cache MISS (must re-evaluate)
```

The cache key for every energy check op includes the BBR artifact hash. When the BBR hash changes, every energy check that used the old BBR misses cache. Every design that used only the unchanged climate zones (I and II) still cache-hits — their portion of the BBR artifact is unchanged, and if the ruleset is structured per zone, their specific rule artifact hash hasn't changed.

The system can report: "47 designs used BBR v2026 climate zone III rules. Of those, 31 still pass under v2027. 16 require design modifications." No manual triage. No missed projects.

## What makes this interesting as a Liminara validation

**The boundary between data and logic.** The BBR is neither pure data (it contains conditional logic: if building type is residential AND climate zone is III, then max energy is 85) nor pure code (it is a versioned, inspectable, diffable artifact). The Behavior DSL makes this boundary explicit: the rule engine is an op; the ruleset is reference data. Both are content-addressed. Both participate in cache key computation. But they change at different rates — the engine changes rarely, the rules change when regulations update.

**Automatic propagation of regulatory changes.** The runtime does not need a special "regulatory change" feature. The propagation falls out of content-addressed caching: change an input artifact, and all downstream computations that depend on it miss cache. This is the same mechanism that handles updated emission factors in the VSME pack or updated dependency versions in LodeTime. The generality of the pattern is the point.

**Diffable regulations.** Because both BBR v2026 and BBR v2027 are content-addressed artifacts with structured DSL source, the change is diffable: "climate zone III max_energy changed from 95 to 85; all other zones unchanged." This diff is an artifact itself — it can be attached to the re-evaluation run as context for why the run was triggered.

**Composability with Population Sim.** When the BBR updates, the evolutionary optimization can be re-run against the new rules. Candidates that passed under the old rules but fail under the new ones are automatically excluded. The fitness landscape shifts, and the optimizer adapts — but the history of the old landscape is preserved for comparison.

---

*Far-horizon exploration. Validates: rules as content-addressed artifacts, automatic cache invalidation on regulatory change, the data/logic boundary in provenance systems.*
