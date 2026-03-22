# VSME — Sustainability Reporting for SMEs

**Can provenance infrastructure turn a compliance burden into a trust advantage?**

Research | [VSME standard](https://www.efrag.org/en/projects/vsme-standard/concluded), sustainability, value chain data, Swedish SMEs

---

## The scenario

Björk Metall AB is a 25-person metalworking shop outside Borås. Their largest customer — a CSRD-bound manufacturer — now requires ESG data from their entire supply chain. Björk Metall has received three different questionnaires in three different formats this quarter. They don't have a sustainability department. They have Fortnox, an electricity contract with Vattenfall, and a payroll system.

Under [VSME](https://www.efrag.org/en/projects/vsme-standard/concluded), Björk Metall can produce one standardized report that replaces all three questionnaires. But the customer still has to trust the numbers. Where did the emissions figure come from? Did they use the right factors? Did they account for the new CNC machine?

---

## The pipeline

![VSME pipeline diagram](vsme-pipeline.svg)

```
Fortnox ──→ ┐                                          ┌──→ VSME report (PDF/XBRL)
             ├─→ validate ──→ calculate ──→ assess ──→ render
Vattenfall ─→ ┤    (pure)      (pure)    (recordable)   (pure)  └──→ sealed evidence package
             │                    │            │
Payroll ────→ ┘                   │            │
                                  │            └── "B5 pollution: not applicable
                                  │                 — no process chemicals used"
                                  │                 (decision recorded)
                                  │
                                  ├── Scope 1: 14.2 tCO₂e
                                  │   ├── company vehicles: 8.1 tCO₂e (diesel, 32,400 km)
                                  │   └── gas heating: 6.1 tCO₂e (natural gas, 28,000 kWh)
                                  │
                                  └── Scope 2: 3.8 tCO₂e
                                      └── purchased electricity: 186,000 kWh
                                          × 20.4 gCO₂/kWh (Vattenfall Nordic mix 2025)
```

**Data sources** (side-effecting — fetched from external systems):
- Fortnox API: revenue, vehicle fuel expenses, gas bills, classified expenses
- Vattenfall annual statement: kWh consumed, contract type, energy mix
- Payroll export: headcount, gender split, contract types, training hours

**Calculations** (pure — same inputs always produce same result):
- Scope 1: fuel consumption × DEFRA emission factors v2025 → tCO₂e
- Scope 2: kWh × supplier-specific emission factor → tCO₂e
- Workforce: headcount, gender ratio, training hours per employee

**Applicability assessment** (recordable — a judgment call):
- B1 Basis for preparation: **applicable** (always)
- B2 Practices: **applicable** (energy efficiency measures)
- B3 Energy and GHG: **applicable** (Scope 1 + 2 calculated)
- B4 Biodiversity: **not applicable** (urban industrial zone, no significant land use)
- B5 Pollution: **not applicable** (no process chemicals) ← *decision recorded with rationale*
- B6 Water: **not applicable** (domestic use only, no industrial water consumption)
- B7 Workers: **applicable** (25 employees)
- B8–B11: assessed individually...

Each "not applicable" is a recorded decision — not a skipped checkbox. Next year, if someone asks "why didn't you report on pollution?", the answer traces back to a specific assessment with a specific rationale, not a blank field.

**Output artifacts:**
- `vsme-report-bjork-2025.pdf` — the human-readable report (sha256:a4f2...)
- `vsme-report-bjork-2025.xbrl` — the machine-readable XBRL (sha256:7c01...)
- `seal.json` — run seal committing to the entire pipeline (sha256:e91d...)

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Where does the 14.2 tCO₂e Scope 1 figure come from?" | Trace artifact: 8.1 (vehicles, from Fortnox fuel expenses × DEFRA 2025 diesel factor) + 6.1 (gas, from Vattenfall statement × natural gas factor) |
| "Which emission factors were used?" | Reference data artifact: DEFRA v2025, registered as `emission-factors-defra-2025` (sha256:b3c8...). Pinned to this version. |
| "Why wasn't pollution reported?" | Decision record for B5: "not applicable — no process chemicals used in metalworking operations, only cutting fluids captured in closed system" |
| "What changes if we update to DEFRA v2026 factors?" | Re-run: factor version changes → cache key changes → Scope 1 and Scope 2 recalculate → report regenerates. All other steps (data collection, applicability) cache-hit. Takes seconds. |
| "Can we verify this wasn't altered after the fact?" | Verify the run seal: recompute the hash chain from events.jsonl. If the final hash matches seal.json, the log is intact. Any party can do this with a SHA-256 implementation. |

---

## Before and after

**Today:** Björk Metall's controller spends two days filling in three different questionnaires with the same numbers copied from different sources. The customer receives an Excel file. There is no way to verify the numbers. Next year, the controller does it again from scratch.

**With provenance:** Björk Metall runs the pipeline once. The report goes to all three customers. Each receives the same sealed package. Numbers trace to source. Next year, the pipeline re-runs against new data — unchanged calculations cache-hit, only new data flows through. The controller reviews the diff, not the whole report.

---

*Looking for sustainability reporting practitioners and Swedish SMEs facing value chain ESG data requests. [Contact →]*
