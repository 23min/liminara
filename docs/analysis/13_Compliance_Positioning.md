# Liminara: Compliance Positioning Strategy

**Date:** 2026-03-21
**Context:** How Liminara's provenance architecture maps to the EU regulatory compliance opportunity. Complements [12_Regulatory_Landscape.md](12_Regulatory_Landscape.md) with strategic decisions.

---

## 1. The Thesis

The EU is shifting from "tell us what happened" to "prove what happened, with evidence." 15+ regulations arriving 2024-2029 demand traceability, tamper-evidence, and provenance. Enterprise platforms (SAP, Microsoft, Salesforce) were built for the "tell us" era — they produce reports from databases with update-in-place semantics. They cannot produce cryptographically verifiable evidence chains.

Liminara's architecture (content-addressed artifacts, hash-chained event logs, decision records, determinism classes) was designed for exactly this "prove it" model. The question is not whether Liminara can compete with SAP — it can't and shouldn't. The question is: what layer is missing, and can Liminara be it?

---

## 2. The Layer Model — Settled

Liminara is not an ERP. Not a reporting platform. It's the provenance substrate.

```
Layer 3: Business systems (SAP, Microsoft, Salesforce, Oracle, Excel, nothing)
  → Where operational data lives

Layer 2: Compliance platforms (Workiva, Greenly, Plan A, Coolset, consultants)
  → Where reports and disclosures are assembled

Layer 1: Provenance engine (Liminara)
  → Where the verifiable evidence trail is produced
```

Liminara doesn't replace anything in Layer 2 or 3. It provides what neither offers: cryptographically verifiable provenance — how specific outputs were derived from specific inputs through specific decisions, with tamper-evident event logs and content-addressed artifacts.

---

## 3. Three Integration Models

### Model A: Standalone for SMEs

For companies too small for enterprise platforms. Liminara IS the pipeline: data sources → validate → calculate → assess applicability → generate report → produce sealed evidence package.

The SME hands two things to their customer/bank: (1) the standardized report, and (2) the run seal proving how it was produced. Cost: near zero (open-source). Effort: configure data sources, run the pack.

Best for: VSME reporting, small Battery Reg suppliers, EUDR commodity producers.

### Model B: Provenance layer for enterprise

Large company uses SAP for data, Workiva for report assembly. Liminara sits underneath providing the audit trail SAP doesn't have.

Integration via: OTel bridge (if enterprise stack emits traces), event bridge (Kafka/webhook), SDK decorators on critical calculation functions. Same architecture as the Article 12 compliance layer already designed.

Best for: CSRD Scope 3 verification, DPP for large manufacturers.

### Model C: Supply chain trust anchor (strongest opportunity)

The hardest problem: getting reliable ESG data from hundreds of suppliers using different systems or none.

Current: Large company sends questionnaire → supplier fills Excel form → no verification possible.

With Liminara: Supplier runs compliance pack → produces sealed evidence package (report + run seal + artifact hashes) → transmits to customer → customer's system verifies seal (trivial SHA-256 chain check) → traces any number to source.

The sealed evidence package is vendor-neutral (JSON + SHA-256). Any system can verify. Solves cross-platform interoperability because the output format is simple.

Best for: VSME data packages for value chain, DPP supply chain data, EUDR due diligence evidence.

---

## 4. Which Regulation to Lead With — Decided

Ranking by strategic fit:

1. **DPP (Digital Product Passport)** — Strongest. Mandatory. Item-level traceability. Machine-readable format. Largest market (USD 2.4B → 10.8B). A DPP IS a Liminara run artifact. Central EU registry mid-2026.

2. **EUDR** — Most urgent pain. Dec 2026 enforcement. Geolocation tracing from plot to product. Companies scrambling.

3. **VSME** — Best SME entry point. Voluntary but increasingly expected. Solves questionnaire chaos. Natural Radar extension. Swedish market relevance.

4. **Battery Regulation** — Concrete, near-term, well-defined pipeline. Good demo candidate.

5. **AI Act Article 12** — Already mapped. Important but narrow (only high-risk AI).

Strategy: Lead with VSME for market entry (Swedish SMEs, lowest barrier), build toward DPP as the high-value application.

---

## 5. The Compliance Pack Family

Shared infrastructure (in core or compliance library):
- Data source connectors (accounting, HR, energy, ERP APIs)
- Emission factor databases (versioned reference data via `Pack.init/0`)
- Seal generation and verification
- XBRL/ESEF output rendering
- Evidence package format (standard bundle: run + seal + artifacts)

Domain-specific packs:
- `VSME.Pack` — sustainability reporting for SMEs
- `DPP.Pack` — digital product passport generation
- `EUDR.Pack` — deforestation-free supply chain verification
- `BatteryPassport.Pack` — battery lifecycle carbon footprint + passport
- `CBAM.Pack` — embedded emissions for imports
- `CSRD.Pack` — for larger companies (more ambitious, later)

Each pack shares provenance properties but targets a specific regulation's data model and output format.

---

## 6. Swedish Market Focus

Why Sweden first:
- Proliminal AB is Swedish
- Vinnova funding (Innovative Startups, AI & Cybersecurity calls)
- Swedish SMEs face indirect CSRD pressure through value chain
- VSME expected to become the standard ESG communication tool for Swedish SMEs post-Omnibus
- Sweden has strong sustainability culture and early adoption tendency
- MIMER AI Factory for compute if needed

Concrete path:
1. VSME Pack as first compliance application
2. Target Swedish SMEs facing value chain ESG data requests
3. Vinnova Innovative Startups funding application
4. Expand to DPP when EU registry goes live (mid-2026)

---

## 7. Defensibility

Why enterprise platforms can't easily add this:

1. **Architectural mismatch** — append-only event logs + content-addressed storage requires rebuilding the data layer, not adding a feature
2. **Supply chain gap** — SAP will never be free; the bottom of supply chains needs lighter tools
3. **Cross-platform by design** — Liminara evidence packages are vendor-neutral (JSON + SHA-256); SAP's trails only work within SAP
4. **Open-source trust** — for evidence to be trusted, the process should be inspectable. Apache 2.0.

---

## 8. Honest Risks

- **Selling to SMEs is hard** — no budget, no time, near-zero friction required
- **Regulation can be delayed or watered down** — Omnibus already removed 80% from CSRD scope
- **The "good enough" problem** — if regulators accept Excel, cryptographic seals are unnecessary
- **Integration complexity** — connecting to real accounting/HR/ERP systems is unglamorous plumbing
- **Solo developer building compliance tooling** — without domain expertise in any specific regulation

---

## 9. Relationship to Existing Roadmap

The compliance direction does not change the build plan — it extends it. The core runtime, observation layer, and Radar pack remain the foundation. Compliance packs are built ON the proven platform, not instead of it.

Sequence:
- Phase 4 (observation) + Phase 5 (Radar) — current plan, unchanged
- VSME Pack — after Radar validates the Pack abstraction with real data
- DPP Pack — after VSME proves the compliance pack pattern
- Other compliance packs — as regulations mature and domain expertise is acquired

The compliance vision strengthens the funding narrative: "not just AI compliance — auditable computation for any regulatory reporting."

---

## 10. What's Needed

To make compliance packs real, Liminara needs:
- Domain expertise in specific regulations (collaboration opportunity)
- Data source connectors (accounting system APIs, HR system APIs)
- XBRL rendering capability
- Evidence package format specification
- A pilot SME willing to test VSME reporting through Liminara

---

Sources: [12_Regulatory_Landscape.md](12_Regulatory_Landscape.md), [03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md), [07_Compliance_Layer.md](07_Compliance_Layer.md), [10_Synthesis.md](10_Synthesis.md)
