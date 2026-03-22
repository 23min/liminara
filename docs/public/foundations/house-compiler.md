# House Compiler — Parametric Timber Frame Manufacturing

**Can a provenance engine turn a set of building parameters into manufacturable outputs — and make design exploration safe?**

Research | Eurocode 5, BBR energy requirements, timber frame prefabrication, binary artifact generation, fan-out DAG

---

## The scenario

Lindberg Trähus is a twelve-person timber frame house company in Rättvik, Dalarna. They design and manufacture prefabricated wall, floor, and roof elements — CNC-cut, assembled in their workshop, delivered to site on trucks. Their engineering process today: a senior carpenter works in SketchUp, an engineer checks the structure in a spreadsheet, a drafter produces shop drawings by hand, and a CNC operator programs the machine from the drawings. The whole chain takes two weeks per project and lives in one person's head at each step.

A customer wants a 120 m² single-family house. Three bedrooms, pitched roof at 27°, site in Falun (climate zone III, SMHI snow load zone 2.0 kN/m²). Standard timber frame: 45×195 mm studs at 600 mm c/c, 22 mm OSB sheathing, mineral wool insulation.

The customer's first question after seeing the price: "What if we change the roof pitch to 35°?"

Today that question costs Lindberg Trähus three days. With provenance, it costs twelve seconds.

---

## The pipeline

```
                         REFERENCE DATA (versioned, pack-managed)
                         ═══════════════════════════════════════
                         Eurocode 5 (SS-EN 1995-1-1:2004/A2:2014)
                         SMHI snow loads, Dalarna (2.0 kN/m², zone map v2024)
                         BBR energy requirements (BFS 2011:6, amendment 2024:2)
                         Material library: timber grades, insulation λ-values
                              │           │            │           │
                              ▼           ▼            ▼           ▼


params ──→ semanticize ──→ structural_check ──→ thermal_check ──→ manufacture_plan ──→ ┐
(JSON)      (pinned_env)    (pinned_env)         (pinned_env)      (pure)              │
                                                                                       │
 ┌─────────────────────────────────────────────────────────────────────────────────────┘
 │
 │  FAN-OUT (three outputs, parallel)
 │
 ├──→ render_drawings ──→ drawings.pdf      (sha256:4a7f...)
 │     (pinned_env)       A1 floor plan, A2 sections, A3 wall elevations, A4 details
 │
 ├──→ generate_nc ──→ framing.btl           (sha256:8c12...)
 │     (pinned_env)   BTL/BTLx for Hundegger Speed-Cut
 │                    234 cuts, 48 notches, 12 mortises
 │
 └──→ export_bom ──→ bom.csv               (sha256:e3d1...)
       (pure)        183 line items, grouped by element
                     total timber: 14.2 m³ (C24 grade)
```

**Parameters** (the starting artifact):
- Footprint: 10 × 12 m, single story
- Bedrooms: 3 (two at 12 m², one at 14 m²)
- Roof: pitched, 27°, ridge along long axis
- Site: Falun, climate zone III
- Foundation: plinth (given by site survey)
- Standard: Eurocode 5 + BBR 2024

**Semanticize** (pinned_env — depends on geometry kernel version):
- Parse parameters into a typed building model: spaces, walls (load-bearing and partition), openings, roof geometry, load paths
- Geometry kernel: Rust NIF via `:port` executor (pinned version: `house-geo v0.3.2`)
- Output: `house.semantic_model.v1` (sha256:b9a2...) — 847 elements, 23 load paths identified

**Structural check** (pinned_env — depends on solver version and reference data):
- Check each load path against Eurocode 5
- Snow load: 2.0 kN/m² (characteristic) × 0.8 (shape factor, 27° pitch) = 1.6 kN/m² on roof
- Ridge beam: GL28c 90×360 mm, utilization ratio 0.74 (pass)
- Studs: C24 45×195 mm @ 600 c/c, utilization ratio 0.61 (pass)
- Output: `house.structural_report.v1` — all members pass, 3 warnings (header spans at limit)

**Thermal check** (pinned_env — depends on BBR version):
- U-values: walls 0.18 W/m²K, roof 0.13 W/m²K, floor 0.15 W/m²K
- Total energy demand: 78 kWh/m²/year (BBR limit for zone III: 90 kWh/m²/year — pass)
- Output: `house.thermal_report.v1`

**Manufacture plan** (pure — deterministic transform from model + structural constraints):
- Wall panelization: 14 elements (max 2.4 × 8.0 m for transport)
- Floor cassettes: 8 elements
- Roof trusses: 11 × prefabricated W-trusses @ 1200 c/c
- Output: `house.manufacturing_model.v1`, `house.bom.v1`

**Fan-out** — three rendering ops run in parallel, each producing a different binary artifact type. All are `pinned_env` (depend on the rendering toolchain version). The manufacture plan doesn't change; only the output format differs.

---

## What happens when the customer asks about 35°

The customer calls back: "What if we go to 35° on the roof? We want more attic space."

One parameter changes. The pipeline re-executes:

```
params (27° → 35°)
  │
  ▼
semanticize         → CACHE MISS (roof geometry changed)
  │                   new model: steeper rafters, different load paths
  ▼
structural_check    → CACHE MISS (model changed)
  │                   snow shape factor: 0.8 → 0.6 (steeper = less snow accumulation)
  │                   BUT: longer rafters, higher wind load on gable
  │                   ridge beam: utilization 0.74 → 0.82 (still passes)
  │                   gable studs: utilization 0.61 → 0.78 (still passes, tighter)
  ▼
thermal_check       → CACHE MISS (roof area and geometry changed)
  │                   slightly more roof area, same U-value
  │                   energy demand: 78 → 81 kWh/m²/year (still under 90 limit)
  ▼
manufacture_plan    → CACHE MISS (different truss geometry)
  │                   trusses change from W-type to scissors type
  │                   timber volume: 14.2 → 15.8 m³ (+11%)
  ▼
render_drawings     → CACHE MISS → new PDF
generate_nc         → CACHE MISS → new BTL (different cut angles)
export_bom          → CACHE MISS → new BOM (+1.6 m³ timber, +2 truss connectors)
```

Everything downstream of the parameter change re-executes. But the customer then asks: "Actually, go back to 27° but change to four bedrooms instead of three." Now:

```
params (back to 27°, 3 → 4 bedrooms)
  │
  ▼
semanticize         → CACHE MISS (interior layout changed)
  │                   one partition wall added, door relocated
  ▼
structural_check    → cache HIT on all load-bearing members
  │                   (partition wall is non-structural — load paths unchanged)
  ▼
thermal_check       → CACHE HIT (envelope unchanged)
  ▼
manufacture_plan    → partial CACHE MISS (one wall panel differs)
  │                   only panel W-07 changes (new door opening)
  ▼
render_drawings     → CACHE MISS (floor plan changed)
generate_nc         → partial CACHE MISS (only W-07 re-cut)
export_bom          → CACHE MISS (one additional door, one modified panel)
```

Structural and thermal checks cache-hit because the building envelope didn't change. The customer gets an answer in seconds, with full structural verification — not an approximation, not a guess.

---

## Reference data and regulatory updates

Reference data is versioned and registered as pack-managed artifacts:

| Dataset | Artifact ID | Current version | Update frequency |
|---------|------------|-----------------|------------------|
| Eurocode 5 (timber) | `ref.eurocode5.v1` | SS-EN 1995-1-1:2004/A2:2014 | ~5 years |
| SMHI snow load map | `ref.smhi_snow.v1` | Zone map v2024 | Annual review |
| BBR energy requirements | `ref.bbr_energy.v1` | BFS 2011:6, amend. 2024:2 | ~2 years |
| Material properties | `ref.timber_materials.v1` | C24/GL28c/CLT library v3 | As needed |

When Boverket updates BBR energy limits, Lindberg Trähus registers the new version. Every project compiled against the old version remains valid (its artifacts reference the pinned version). New projects use the new version. If they want to check whether an old design still complies under new rules, they re-run with the updated reference — only thermal_check and downstream re-execute.

The structural engineer can always answer: "Which version of Eurocode 5 was this checked against?" The answer is in the artifact metadata, not in someone's memory.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why is the ridge beam GL28c 90×360?" | Trace: structural_report ← structural_check op used semantic_model load path LP-03 (ridge, 6.0 m span, 1.6 kN/m² snow + 0.5 kN/m² self-weight) against Eurocode 5 §6.1.6 (bending), utilization 0.74. GL28c 90×315 would give 0.89 — acceptable but above the 0.85 comfort threshold. |
| "What snow load was used for Falun?" | Reference artifact `ref.smhi_snow.v1` (sha256:d4e7...), zone map v2024, Dalarna zone = 2.0 kN/m² characteristic. Shape factor from Eurocode 5 §5.3.3, table 5.2: μ₁ = 0.8 for 27° pitch. |
| "What changed between the 27° and 35° versions?" | Diff two runs: 6 artifacts differ. Structural utilization ratios shifted (details per member). Timber volume +11%. Truss type changed. Full diff available as artifact pairs with matching content hashes for unchanged elements. |
| "Can we verify this was checked against current Eurocode?" | The structural_check op's cache key includes `hash(ref.eurocode5.v1)`. The artifact metadata records the exact version. Re-run with current reference data: if the hash matches, the check is current. If not, re-execution shows what changed. |
| "What if timber prices go up 20% — which design is cheaper?" | Both BOM artifacts exist (27° and 35° versions). Cost comparison is a pure calculation against the material price list. No re-execution of upstream ops needed. |

---

## Before and after

**Today:** Lindberg Trähus takes two weeks from parameters to shop drawings. Design changes restart the process — the engineer re-checks by hand, the drafter redraws, the CNC operator reprograms. The customer gets frustrated. When something goes wrong on site and the contractor asks "was this checked for snow load?", someone digs through email to find the spreadsheet. The senior carpenter retires next year. Half the knowledge goes with him.

**With provenance:** Parameters go in, manufacturable outputs come out. Design exploration is safe — each variation is a re-run with upstream caching. The customer gets real answers to "what if?" in the meeting, not three days later. Every structural decision traces to a code clause, a load calculation, and a reference data version. When the senior carpenter retires, the compilation pipeline remains. When regulations update, affected projects are identifiable by querying which runs reference the old version.

The 35° roof pitch question? Twelve seconds, fully verified, with a BOM diff showing exactly what it costs.

---

*The House Compiler validates fan-out DAGs (one model, multiple output formats), binary artifact handling (PDF, BTL/NC, CSV), heavy compute isolation via `:port` executors (Rust geometry kernel off the BEAM), and pack-managed reference data with version-controlled regulatory propagation. Looking for timber frame manufacturers and structural engineers interested in parametric design-to-manufacture pipelines. [Contact ->]*
