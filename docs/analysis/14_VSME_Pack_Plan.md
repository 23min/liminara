# VSME Compliance Pack — Design Plan

## Overview

The VSME (Voluntary SME Standard) pack is the first compliance application of Liminara. It validates the compliance pack pattern on a real regulatory domain before scaling to DPP, EUDR, and CBAM.

**Scenario:** Bjork Metall AB — 25-person Swedish metalworking shop facing ESG data requests from three different customers, each with a different questionnaire format.

**Value proposition:** One sealed, traceable report replaces three questionnaires. Every number traces to its source. Every judgment has a recorded rationale. When emission factors update, the report auto-refreshes in seconds.

## DAG Structure (~25 nodes)

```
                    ┌─ fetch_fortnox ─── validate_financial ─┐
                    │                                         │
init_config ────────┼─ fetch_vattenfall ─ validate_energy ───┼── calc_scope1
                    │                                         │
                    └─ fetch_payroll ──── validate_workforce ─┼── calc_scope2
                                                              │
                    load_factors_v2025 ───────────────────────┘
                                                              │
                              ┌────────────────────────────────┘
                              │
                    assess_b1_basis ──────┐
                    assess_b2_practices ──┤
                    assess_b3_energy ─────┤
                    assess_b4_biodiversity┤  (each is a recorded decision)
                    assess_b5_pollution ──┤
                    assess_b6_workforce ──┤
                              ...         │
                              └───────────┼── compose_report
                                          │
                              calc_scope1 ─┤
                              calc_scope2 ─┘
                                          │
                                    render_pdf ──┐
                                    render_xbrl ─┼── seal_package ── [GATE: publish]
                                    render_json ─┘
```

## Ops by Determinism Class

| Op | Class | Notes |
|----|-------|-------|
| fetch_fortnox, fetch_vattenfall, fetch_payroll | side_effecting | Data source pulls (fixture data for demo) |
| validate_financial, validate_energy, validate_workforce | pure | Normalize, canonicalize, hash |
| load_factors_v2025 | pure | Pack.init/0 reference data, versioned, immutable |
| calc_scope1, calc_scope2 | pure | Cacheable. Scope 1: fuel × DEFRA factor. Scope 2: kWh × grid factor |
| assess_b1 through assess_b11 | recordable | LLM-drafted, human-approved. Decision recorded with rationale |
| compose_report | pure | Assemble assessments + calculations |
| render_pdf, render_xbrl, render_json | pinned_env | Pandoc/typst version matters |
| seal_package | pure | SHA-256 over evidence package |
| publish | side_effecting + gate | Human approves before delivery |

## Key Demo Scenarios

### 1. First run (baseline)
- Fetch fixture data, calculate emissions, assess disclosures
- Show full graph with ~25 nodes, color-coded by determinism class
- Inspector shows real artifacts: emission calculation, assessment rationale
- Result: PDF + JSON + sealed evidence package

### 2. Factor update (the "aha" moment)
- DEFRA publishes v2026 factors
- Re-run: only calc_scope1, calc_scope2, compose, render re-execute
- 22 of 25 nodes served from cache (assessments replayed from decisions)
- Diff: "Scope 1 changed from 14.2 to 13.8 tCO₂e due to updated diesel factor"

### 3. New reporting period (selective refresh)
- New year, new Fortnox data
- Most assessments replayed (B4 unchanged: "not applicable")
- B2 re-assessed (new energy efficiency measures) — new decision recorded
- Only changed nodes re-run

### 4. Auditor verification
- Verify sealed package (SHA-256)
- Click through: Scope 1 → Fortnox fuel data → DEFRA v2025 factor → exact multiplication
- Click: B4 assessment → recorded decision with rationale
- Every number traces to source, every judgment has recorded rationale

## What We Need to Build

**Required:**
- VSME Pack module (ops + plan/1)
- Fixture data (realistic Bjork Metall numbers)
- DEFRA v2025 emission factors as Pack.init/0 reference data
- LLM assessment ops (recordable, decision-recorded)
- Basic PDF renderer (pandoc or typst)
- Existing observation UI (DAG, inspector, timeline, gates)

**Not required for demo:**
- Real Fortnox/Vattenfall API integration (fixtures are fine)
- Oban/Postgres scheduling (manual runs)
- XBRL rendering (JSON + PDF sufficient)
- Multi-tenant (single user)

## Sequencing

VSME comes after Report Compiler (toy) validates caching, binary artifacts, and external tools. Report Compiler is the dress rehearsal; VSME is the first real performance.

## Market Context

- VSME recommended July 2025, increasingly expected post-Omnibus
- Swedish SMEs facing value chain ESG pressure from CSRD-reporting customers
- No affordable tooling exists for 25-person companies
- Entry point for compliance pack family (DPP, EUDR, CBAM follow)
- Feeds EIC Accelerator pitch (Sep/Nov 2026)
