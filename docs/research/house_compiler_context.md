# House Compiler Context: From ChatGPT Design Conversation

**Date:** 2026-03-02
**Source:** User's ChatGPT conversation exploring the house compiler as a domain pack
**Status:** Context capture for architectural analysis

---

## The Problem Statement

A friend uses SketchUp to design timber-frame houses and wants a "press a button" workflow:

**SketchUp model + parameters → complete design → PDFs (views, assemblies) + NC files (CNC) + BOM**

The system should be location-aware (e.g., point to Sollefteå, Sweden → automatically apply correct snow loads, wind loads, frost depth). The user provides high-level parameters (dimensions, insulation thickness, roof pitch), and the system produces a complete, buildable design.

---

## Why It Fits as a Domain Pack (Not a Separate System)

ChatGPT and the user converged on a critical insight: the house compiler is **structurally identical** to the compiler-pass model in the core runtime.

### Shared platform primitives (high leverage)

| Primitive | Omvärldsbevakning use | House compiler use |
|---|---|---|
| Artifact lineage / provenance | Source → normalized → ranked → briefing | SketchUp → semantic model → structural → manufacturing → outputs |
| Versioned knowledge | Feed configs, ranking models | Rulesets (Eurocode, BBR, EKS), material databases |
| Reproducible runs | Same sources → same briefing | Same parameters → same design documents |
| Human-in-the-loop gates | "Approve briefing before delivery" | "Approve structural assumptions before detailing" |
| Parallel exploration | N/A (future) | GA population evaluation across candidates |
| Caching | Embedding, classification results | Load lookups, structural sizing results |
| Evaluation harness | Golden test briefings | Golden test designs (known-correct outputs) |

### The key framing

> "One platform, multiple vertical compilers."

The house compiler is **not** an "LLM chat agent." It's a deterministic compilation pipeline where agents are specialized computation engines that happen to run on the same orchestration substrate.

---

## The Pipeline Architecture (IR Stages)

ChatGPT proposed a compiler-shaped pipeline that maps cleanly to the spec's IR model:

### IR0: Input Intent
- Parameters + site location + selected templates + constraints
- **Artifact:** `house.design_snapshot.v1`, `house.ruleset_ref.v1`

### IR1: Building Semantic Model
- Spaces, walls, roofs, floors, openings, load-bearing classification
- Not just geometry — semantic meaning ("this is a load-bearing wall")
- **Artifact:** `house.semantic_model.v1`

### IR2: Structural Member Model
- Joists, studs, rafters, beams, plates + connection intent
- Sized according to Eurocode 5 + Swedish national annex
- **Artifact:** `house.structural_report.v1`

### IR3: Manufacturing Model
- Individual parts with machining operations
- Panel breakdown for prefabrication
- Assembly sequencing hints
- **Artifact:** `house.manufacturing_model.v1`, `house.bom.v1`

### Backends (Output Generators)
- PDF drawings (plans, elevations, sections, detail views, panel drawings)
- NC files (BTL/BTLx for Hundegger, BVN/BVX, WUP for Weinmann/HOMAG)
- BOM (timber lengths, fastener counts, insulation volumes, membrane areas)
- Compliance bundle (which ruleset, which assumptions, which versions)

---

## The Agent Topology

Each specialist is an OTP-supervised process or process tree:

```
                    ┌─────────────────┐
                    │   GA Optimizer   │  (Population manager,
                    │   (Supervisor)   │   fitness evaluator)
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Design Pipeline │  (Pipeline orchestrator)
                    │   Orchestrator   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                     │
   ┌────▼─────┐      ┌──────▼──────┐      ┌──────▼──────┐
   │ Geometry  │      │  Structural │      │   Thermal   │
   │  Engine   │      │   Engine    │      │   Engine    │
   └────┬─────┘      └──────┬──────┘      └──────┬──────┘
        │                    │                     │
   ┌────▼─────┐      ┌──────▼──────┐      ┌──────▼──────┐
   │ Detail    │      │    Code     │      │  Moisture   │
   │ Generator │      │   Checker   │      │  Analyzer   │
   └────┬─────┘      └─────────────┘      └─────────────┘
        │
   ┌────▼──────────────────────────────┐
   │         Output Generators          │
   │  (PDF, NC/BTL, BOM, SketchUp)     │
   └───────────────────────────────────┘
```

These are **not LLM agents** — they're computational engines (rule engines, constraint solvers, geometry kernels via Rust NIFs or ports). The OTP supervision model (message passing, crash isolation, restart strategies) is architecturally identical regardless of whether the agent wraps an LLM call, a Eurocode 5 calculation, or a geometry boolean operation.

---

## The Design Genome (GA Optimization)

For genetic algorithm optimization, each house design is parameterized:

```elixir
%DesignGenome{
  footprint: {12_000, 8_000},        # mm, length × width
  num_stories: 1,
  roof_type: :gable,
  roof_pitch: 27,                     # degrees
  wall_height: 2_400,                 # mm
  stud_spacing: 600,                  # mm c/c
  stud_dimension: {45, 195},          # mm, width × depth
  insulation_thickness_wall: 195,     # mm
  extra_insulation_wall: 45,          # mm exterior
  insulation_type: :mineral_wool,
  foundation_type: :slab_on_grade,
  frost_depth: 1_800,                 # mm (varies by location)
  location: {63.17, 17.27},           # Sollefteå coordinates
  openings: [...]
}
```

The GA mutates/crosses over parameters. Each candidate runs through the full pipeline. Fitness combines cost, material volume, energy performance, and code compliance (hard constraints as penalties).

**BEAM advantage:** `Task.async_stream` can evaluate 100 candidates in parallel across lightweight processes without infrastructure overhead.

---

## Swedish Regulatory Knowledge Base

The system must encode location-specific Swedish building knowledge:

### Geographic Data
- **Snow loads:** Digitized from SMHI/Boverket maps. Sollefteå ≈ 4.5 kN/m² ground snow load (zone 4.5-5.5).
- **Wind zones:** Reference wind speed by region
- **Frost depth:** By municipality (Sollefteå ≈ 1,800mm)
- **Climate zone:** For BBR energy calculation (Sollefteå = zone 1, harshest)

### Structural Standards (Eurocode + Swedish Annex)
- Eurocode 0: Load combination factors (ψ₀, ψ₁, ψ₂ for Swedish annex)
- Eurocode 1: Snow, wind, imposed loads
- Eurocode 5: Timber design — bending, shear, compression, buckling, deflection
- **EKS 12** (current Swedish national annex modifications)
- Swedish span tables from Svenskt Trä

### Building Regulations (BBR)
- Energy requirements by climate zone (kWh/m²/year)
- Minimum U-values for building elements
- Fire safety (EI classes)
- Accessibility requirements
- Sound insulation requirements

### Critical: Regulatory Transition

**From 1 July 2026, BBR and EKS can no longer be applied in new cases.** Boverket is transitioning to new regulations. This means:

- The system MUST select the applicable ruleset based on case context (date, project phase)
- Ruleset snapshots must be first-class versioned artifacts
- A design started under BBR 31 / EKS 12 must remain under those rules even if completed after the transition
- This is not a nice-to-have — it's a core architectural requirement that validates the "versioned knowledge" primitive

---

## The Two Hardest Problems

### Hard Problem 1: Detail-Level Geometric Correctness

Getting from "a wall exists here" to manufacturable framing:
- Studs at correct spacing (but NOT a simple regular grid)
- Corner conditions (extra studs, corner configurations)
- T-junction conditions (interior wall meets exterior wall)
- Opening framing (king studs, jack studs, headers, cripple studs)
- Sheathing layout (1200×2400mm panels, staggered for racking resistance)
- Panel breaking for prefabrication (max ~12m, limited by transport/crane)
- Connection details (joist hangers, angle brackets, nail patterns)

A simple 100m² house has ~400-600 individual timber members, each with specific dimensions, positions, and connections.

**Approaches:**
1. **Rule-based procedural generation** — how Cadwork/SEMA/Dietrich's work. Proven but enormous domain knowledge needed.
2. **Template-based with parametric variation** — define ~20-30 standard detail templates (exterior wall, interior wall, L-corner, T-junction, window opening, etc.) and compose parametrically. **Recommended starting point.**
3. **Hybrid with LLM assistance** — for edge cases. But structural correctness requires deterministic verification, not probabilistic generation.

For computational geometry (3D booleans, intersections), consider a **Rust NIF** wrapping opencascade-rs or similar, called via Rustler.

### Hard Problem 2: Ruleset/Version Management + Compliance Evidence

Even with perfect calculations, the system is unusable if it can't answer:
- "Which ruleset did this design follow?"
- "Which load assumptions and sources were used?"
- "What changed between revision A and B?"
- "Can I reproduce the PDFs/NC/BOM exactly later?"

This is solved by the core runtime's artifact provenance + decision records + run manifests, but it must be designed in from day one. The Swedish regulatory transition (BBR/EKS phase-out July 2026) makes this urgent, not theoretical.

---

## The Coupled Constraint Problem (Convergence)

Domains interact circularly:
1. Structural agent sizes studs at 45×145mm
2. Thermal agent says 145mm insulation fails BBR for climate zone 1 (need U ≈ 0.18, not 0.25)
3. Need thicker studs (195mm) or external insulation
4. Thicker studs change structural behavior (different buckling, weight)
5. New weight changes load combinations → may change roof truss design
6. Different building height → affects wind load calculation
7. Back to step 1

**Convergence strategies:**
- **(a) Fixed-point iteration:** Run pipeline 2-3 times until outputs stabilize. Works for residential timber (weak coupling).
- **(b) Conservative initial assumptions:** Start oversized, optimize down.
- **(c) Let the GA handle it:** Include consistency penalties in fitness. Elegant but slow.
- **(d) Constraint propagation:** Analytically derive minimum constraints before detailed calculation (e.g., climate zone 1 + mineral wool → minimum 200mm insulation → minimum stud depth).

**Recommendation:** Combine (c) and (d) — constraint propagation to shrink GA search space, then GA explores feasible region.

---

## The NC File Ecosystem

NC export isn't just geometry — it's manufacturing intent. Key formats:
- **BTL/BTLx:** Standard timber CNC format (Hundegger, etc.)
- **BVN/BVX:** Hundegger-specific formats
- **WUP:** Weinmann/HOMAG panel processing format

Each machine vendor has preferences and quirks. The buyer's partners' specific equipment determines which backend to implement first.

**Staged approach:**
1. Human-readable cutlists (CSV/PDF) — immediate value
2. Semi-structured NC (simplified BTL) — machine-parseable
3. Full machine-specific NC (BTL/BTLx/BVX/WUP) — production-ready

---

## Strategic Insight: Platform vs. Product Tension (Resolved)

The user and ChatGPT resolved the platform-vs-product tension:

> **"Build it as a domain pack, but treat it like a flagship vertical."**

Concrete strategy:
1. Start with omvärldsbevakning to validate core runtime
2. Add a tiny "house spike" early (trivial member list → PDF + BOM) to verify non-text artifact generation
3. Build house compiler as the second real pack, using the validated runtime
4. Keep software factory as a later pack that reuses the proven runtime

This avoids: *"We built a generic agent platform... but no vertical works end-to-end."*
And achieves: *"We shipped the house compiler... and now the platform is real."*

---

## Key Insight: The "Agent" Abstraction

The conversation clarified that "agent" in Liminara doesn't mean "LLM chat agent." An agent is any supervised, message-passing capability provider:

| Agent type | Example | Wrapped engine |
|---|---|---|
| LLM agent | Summarizer, classifier | Anthropic/OpenAI API call |
| Computational agent | Structural sizer, thermal checker | Eurocode 5 formulas in Elixir |
| Geometry agent | Framing generator, panel breaker | Rust NIF (opencascade-rs) |
| Rule engine agent | Code checker, BBR compliance | Pattern matching / ETS lookup |
| Lookup agent | Snow load, wind load, frost depth | Geographic database query |
| External tool agent | PDF renderer, NC exporter | Port/container calling external toolchain |
| Human agent | Approval gate, design review | A2UI interactive component |
| Optimizer agent | GA population manager | Task.async_stream of evaluations |

All share the same OTP supervision, message passing, artifact production, and decision recording infrastructure. The runtime doesn't care what's inside the agent — it cares about the contract (inputs → outputs + decisions + events).

---

## What This Conversation Validates in the Core Spec

1. **IR pipeline model** — the house compiler is a textbook compiler, proving the model isn't just metaphorical
2. **Determinism classes** — structural calcs are pinned-env, GA choices are recordable, geometry generation is pure
3. **Decision records** — GA trajectories and design ambiguity resolutions map perfectly
4. **Artifact provenance** — "which ruleset, which version, which assumptions" is existential for compliance
5. **Control plane / compute plane split** — geometry kernels MUST be outside BEAM (NIFs/ports), validating the architecture
6. **Replay** — "once decisions are made, we get a DAG; on replay we just replay decisions, we don't discover them"

## What This Conversation Reveals as Missing from the Core Spec

1. **Convergence protocol** — no mechanism for iterative refinement when agents' outputs are coupled
2. **Binary artifact streaming** — PDFs and NC files are large; the spec doesn't address streaming generation or chunked artifact storage well
3. **Environment fingerprinting depth** — "pinned env" needs to include specific solver versions, NIF library versions, even CPU architecture for float determinism
4. **Regulatory transition handling** — versioned rulesets are mentioned but the spec doesn't address "which version applies when" logic
5. **Template/component library management** — the house compiler needs a library of parametric templates (wall types, junction types); the core has no concept of "pack-managed reference data"
