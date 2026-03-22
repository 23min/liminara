# EU Regulatory Landscape: The Provenance Opportunity

**Date:** 2026-03-21
**Context:** Analysis of 15+ EU regulations (2024-2029) demanding traceability, audit trails, and provenance — and how Liminara's architecture maps to them.

---

## 1. The "Tell Us" to "Prove It" Shift

Something structural is happening across EU regulation. It is not one law — it is a pattern repeating simultaneously in sustainability, supply chains, AI, trade, and cybersecurity.

**The old model:** Fill in a form. Write a narrative. Submit a PDF. Trust is assumed.

**The new model:** Provide machine-readable data. Trace every number to its source. Make evidence tamper-evident. Let auditors verify independently.

This is the shift from *reporting* to *provenance*. CSRD demands XBRL-tagged data points traceable to methodology. The Digital Product Passport requires machine-readable material composition linked to supply chain evidence. EUDR demands geolocation coordinates for every plot of land where a commodity was produced. The AI Act requires automatic, tamper-resistant logs that trace outputs to inputs. CBAM requires embedded emissions traced to actual production facilities — or you pay default rates that assume worst-case carbon intensity.

The regulations differ in domain. The underlying demand is identical: **prove the derivation chain, not just the final number.**

This is the exact problem provenance infrastructure solves. And it is the exact problem that update-in-place databases, narrative PDFs, and spreadsheets cannot solve structurally.

---

## 2. Regulations Mapped to Liminara

Fifteen regulations, organized by how directly they demand the kind of provenance architecture Liminara provides.

### Tier 1: Provenance-First Regulations (Strongest Architectural Fit)

These regulations structurally require traced, machine-readable evidence chains. They don't just want a report — they want the derivation.

#### Digital Product Passport (DPP / ESPR)

The Ecodesign for Sustainable Products Regulation entered into force July 2024. The EU DPP registry launches mid-2026. Battery passports become mandatory February 2027. Textiles and aluminium follow in 2027. Electronics in 2028-2029.

Every product covered by a delegated act gets a machine-readable passport accessible via QR code. The passport must contain material composition, carbon footprint per lifecycle stage, recyclability scores, and supply chain provenance — all linked to evidence. The passport persists through the product's lifecycle: manufacture, sale, repair, recycling. It must be updatable but with full version history.

A DPP is structurally identical to a Liminara run: a DAG of operations (sourcing, manufacturing, testing, certification) producing immutable artifacts (certificates, test results, material declarations), with decisions recorded at each nondeterministic step (supplier selection, test methodology, allocation choices). Content-addressing ensures that the same inputs produce verifiably identical passports.

#### EU Deforestation Regulation (EUDR)

Large operators must comply by December 2026, SMEs by June 2027. Covers seven commodity groups: cattle, cocoa, coffee, palm oil, rubber, soy, and timber (plus derived products).

Every operator importing or exporting covered commodities must submit due diligence statements through the EU TRACES system. The statements must include geolocation data for every plot of land where the commodity was produced, proof of legal land use under the country of origin's laws, and evidence that the land was not subject to deforestation after 31 December 2020. For cattle, this means tracking animals through multiple farms. For palm oil, it means satellite imagery matched to specific plantation boundaries.

The challenge is not collecting this data — it is *proving the chain* from a specific bag of coffee on a shelf in Stockholm to a specific hillside in Colombia. That is a provenance problem.

#### Battery Regulation (EU 2023/1542)

Carbon footprint declarations have been required since February 2025. Digital battery passports become mandatory February 2027 for industrial and EV batteries above 2 kWh.

The regulation demands lifecycle traceability: extraction of raw materials (cobalt, lithium, nickel, graphite), processing, manufacturing, distribution, and end-of-life. Supply chain due diligence must be third-party verified. The battery passport must include carbon footprint calculations per lifecycle stage, material composition, recycled content share, and expected lifetime.

This is a multi-tier supply chain provenance problem. The due diligence requirements alone — proving where the cobalt came from, that the mine met environmental standards, that the processing facility's energy mix was as declared — require exactly the kind of traced, immutable evidence chains that Liminara's architecture produces.

#### Carbon Border Adjustment Mechanism (CBAM)

The definitive phase started January 2026. Covers cement, iron and steel, aluminium, fertilizers, electricity, and hydrogen. Certificate surrender begins September 2027.

Importers must calculate embedded emissions traced to actual production processes — or accept default values that assume worst-case carbon intensity (a significant cost penalty). Third-party verification is required. The incentive structure is clear: if you can prove actual emissions with a verified derivation chain, you pay less. If you cannot, you pay default rates.

This creates direct financial motivation for provenance infrastructure. Every step in the embedded emissions calculation — energy source, grid emission factor, production process, allocation method — must be traceable and verifiable.

#### EU AI Act Article 12

High-risk AI system requirements become enforceable August 2026. This is the regulation most directly discussed in [03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md), but it belongs in the broader landscape.

Requirements: automatic, tamper-resistant logging. Output-to-input traceability. Model version recording. Governing policy capture. Minimum 6-month retention. Fines up to EUR 35 million or 7% of global annual revenue.

Liminara's mapping to Article 12 is nearly 1:1 — see the detailed analysis in [03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md).

### Tier 2: Reporting + Some Provenance (Moderate Fit)

These regulations primarily demand reporting, but the reporting increasingly requires traceable data points — not just numbers, but numbers with methodology and source documentation.

#### CSRD (Post-Omnibus Simplification)

The CSRD has been significantly scaled back under the February 2026 Omnibus proposal. Scope now covers only companies with more than 1,000 employees **and** more than EUR 450 million turnover. Wave 2 companies report on financial year 2027, publishing in 2028. Required data points have been reduced from approximately 1,073 to roughly 320. Double materiality assessment remains but is simplified.

The reduction in scope matters: far fewer companies are directly subject to CSRD. But the value chain effects persist — large companies still need ESG data from their suppliers to complete their own reports. The data demands flow downhill.

XBRL tagging remains required, meaning the data must be machine-readable and structured. Each data point should be traceable to its methodology and source data. This is where provenance infrastructure adds value even in a reporting context.

#### Voluntary SME Standard (VSME)

Recommended by EFRAG in July 2025. Two modules: Basic (11 disclosures, approximately 60 indicators) and Comprehensive (9 additional disclosures, approximately 80 indicators total). Uses "if applicable" thresholds instead of mandatory double materiality assessment.

The VSME exists because CSRD value chain requirements push ESG data demands down to companies that are not themselves in scope. A small supplier to a CSRD-reporting company needs to provide carbon data, workforce data, and governance data — even though the supplier is not directly regulated. The VSME gives them a framework, but they still need infrastructure to produce and evidence the data.

#### EU Taxonomy

Follows the CSRD timeline. Six environmental objectives (climate mitigation, climate adaptation, water, circular economy, pollution, biodiversity). For each activity, companies must demonstrate substantial contribution to at least one objective plus do-no-significant-harm (DNSH) to the others. Technical screening criteria define quantitative thresholds.

The simplification delegated act of January 2026 reduced complexity somewhat, but the fundamental requirement remains: demonstrate that a specific economic activity meets specific quantitative criteria, with evidence. Taxonomy alignment percentages in annual reports must be traceable to activity-level assessments.

#### CSDDD (Corporate Sustainability Due Diligence Directive)

Transposition deadline July 2028, first application July 2029. Narrowed under Omnibus to companies with more than 5,000 employees **and** more than EUR 1.5 billion turnover.

Requires human rights and environmental due diligence throughout the value chain. Companies must identify, prevent, mitigate, and account for adverse impacts. The due diligence process itself — risk assessment, stakeholder engagement, remediation actions — is a sequence of decisions that should be recorded and traceable.

### Tier 3: Process/Policy Regulations (Weaker Fit, Audit Trail Relevant)

These regulations focus on operational resilience and security rather than provenance per se, but they all require audit trails and incident traceability.

#### DORA (Digital Operational Resilience Act)

Fully applicable since January 2025. Applies to financial sector entities: banks, insurers, payment providers, and their critical ICT service providers. Requires ICT risk management frameworks, incident reporting, digital operational resilience testing, and third-party risk management. Audit logs for incident root-cause analysis are mandatory.

#### NIS2 (Network and Information Security Directive)

Transposition ongoing — Germany's implementing act took effect January 2026. Applies to essential and important entities across 18 sectors. Requires 24-hour early warning and 72-hour incident notification. Supply chain security risk management. Management body accountability.

#### Cyber Resilience Act

Vulnerability reporting obligations from September 2026, full obligations from December 2027. Applies to all products with digital elements placed on the EU market. Requires secure-by-design development, vulnerability handling processes, and security updates throughout the product lifecycle.

#### EU Data Act

Main provisions applicable from September 2025. Data-by-design requirements from September 2026. Governs access to data generated by connected devices and cloud services. Relevant to Liminara insofar as data provenance and portability requirements may apply to any data processing infrastructure.

---

## 3. Master Enforcement Timeline

| Date | Regulation | Milestone |
|------|-----------|-----------|
| **2025** | | |
| Jan 2025 | DORA | Fully applicable |
| Feb 2025 | Battery Reg | Carbon footprint declarations required |
| Feb 2025 | AI Act | Prohibited practices ban + AI literacy |
| Jul 2025 | VSME | Voluntary standard recommended |
| Aug 2025 | AI Act | GPAI model obligations |
| Sep 2025 | EU Data Act | Main provisions applicable |
| **2026** | | |
| Jan 2026 | CBAM | Definitive phase begins |
| Jan 2026 | NIS2 | Germany implementing act in force |
| Jan 2026 | EU Taxonomy | Simplification delegated act |
| Mid-2026 | DPP/ESPR | EU DPP registry launches |
| Aug 2026 | AI Act | **High-risk system requirements enforceable** |
| Sep 2026 | Cyber Resilience Act | Vulnerability reporting obligations |
| Sep 2026 | EU Data Act | Data-by-design requirements |
| Dec 2026 | EUDR | Large operators must comply |
| **2027** | | |
| Feb 2027 | Battery Reg | **Digital battery passport mandatory** |
| Feb 2027 | DPP/ESPR | Battery passports mandatory |
| Jun 2027 | EUDR | SME operators must comply |
| Aug 2027 | AI Act | Full scope (Annex II, regulated products) |
| Sep 2027 | CBAM | Certificate surrender begins |
| 2027 | DPP/ESPR | Textiles and aluminium passports |
| **2028** | | |
| 2028 | CSRD | Wave 2 reports (on FY2027) published |
| Jul 2028 | CSDDD | Transposition deadline |
| 2028-2029 | DPP/ESPR | Electronics passports |
| Dec 2027 | Cyber Resilience Act | Full obligations |
| **2029** | | |
| Jul 2029 | CSDDD | First application |

The cluster of enforcement dates in 2026-2027 is not coincidental — the EU deliberately sequenced these regulations to create mutually reinforcing compliance pressure. A company importing aluminium faces CBAM (embedded emissions), DPP (product passport), and potentially CSRD (sustainability reporting) simultaneously. The data requirements overlap. The provenance infrastructure should be shared.

---

## 4. Enterprise Compliance Landscape

The question is not whether companies need compliance tooling — the question is what the current tools actually provide and where the gaps are.

### Enterprise Platforms

**SAP** — Sustainability Control Tower and Green Ledger (GA December 2024). Deep ERP integration. ESRS-aligned reporting templates. Carbon accounting at the transaction level. Pricing starts at EUR 50K/year and scales to EUR 500K+ for large deployments. The strongest option for SAP shops. The weakness: SAP logs report *changes* (who edited what field when) but does not trace *derivation chains* (how was this carbon number calculated from what source data through what methodology). Update-in-place database architecture.

**Microsoft** — Sustainability Manager integrated with Copilot AI. Scope 1/2/3 emissions tracking. CSRD reporting templates. Period locking for audit trail. Lives in the Dynamics 365 ecosystem. Still maturing compared to specialized tools — broad but not deep.

**Salesforce** — Net Zero Cloud. Supplier-level carbon footprint tracking. Scenario planning. CRM-centric — strongest when sustainability data flows from customer and supplier relationships already in Salesforce.

**Oracle** — Fusion Cloud Sustainability. Multi-framework support. Oracle ecosystem dependency. Similar strengths and limitations as SAP for Oracle shops.

**Workiva** — Strong audit and assurance workflow support. Multi-framework reporting (CSRD, GRI, SEC). The most reporting-focused platform. Good at producing compliant documents. Not designed for operational provenance.

### Specialized SaaS

Greenly, Plan A, Coolset, Arbor, and similar vendors. Pricing typically EUR 5K-30K/year. Good for SMEs needing basic carbon accounting and CSRD-lite reporting. None of them provide provenance infrastructure — they collect data, calculate metrics, and produce reports. The derivation chain from source data to reported number is opaque.

### SME Reality

Most SMEs facing ESG data demands (from their customers' CSRD value chain requirements, from DPP supply chain obligations, from EUDR due diligence) currently use one of three approaches: Excel spreadsheets (free, fragile, no audit trail), sustainability consultants (EUR 5K-50K per engagement, produces a PDF, knowledge leaves when the consultant does), or nothing (hoping the requirements go away or do not apply to them yet).

---

## 5. Gap Analysis: What's Missing

Six structural gaps in the current compliance tooling landscape. These are not feature gaps — they are architectural gaps that cannot be solved by adding features to existing platforms.

### Gap 1: Provenance, Not Just Audit Trails

Every enterprise platform has audit trails. SAP records who changed a field and when. Workiva tracks document versions. But audit trails answer "who edited this?" — they do not answer "how was this number derived from what source data through what methodology?"

Provenance answers the second question. A carbon footprint number should trace back through the calculation methodology, the emission factors used, the activity data sources, the allocation decisions, and the quality assessments — each step immutable and verifiable. Current tools log *changes to reports*. They do not log *derivation of results*.

### Gap 2: Immutability

Enterprise sustainability tools use conventional databases. Records are updated in place. A carbon number reported in March can be silently changed in June. Audit trails catch the change, but the original derivation chain is gone — overwritten.

Content-addressed, append-only storage (the architecture Liminara uses for artifacts and events) makes this structurally impossible. The March calculation and the June recalculation both exist as immutable records. The difference between them is a verifiable, inspectable diff — not a log entry saying "field changed."

### Gap 3: Cross-Platform Supply Chain Interoperability

DPP, EUDR, Battery Regulation, and CBAM all require data to flow across organizational boundaries. A battery passport aggregates data from mining companies, refineries, cathode manufacturers, cell manufacturers, and OEMs — each potentially using different systems.

Current platforms are walled gardens. SAP talks to SAP. Salesforce talks to Salesforce. There is no standard provenance interchange format. Content-addressed artifacts with deterministic identifiers are inherently interoperable — the hash is the identifier, regardless of which system produced it.

### Gap 4: SME Accessibility

Enterprise platforms cost EUR 50K-500K/year. Specialized SaaS costs EUR 5K-30K/year. SMEs with 10-50 employees and EUR 2-10 million revenue — the ones being asked for supply chain data by their larger customers — cannot afford either tier.

The open-source core of a provenance engine, deployable on a single server, could serve this tier. The value is not in the UI (that can be simple) but in the infrastructure: produce a verifiable evidence package that your customer's auditor can validate independently.

### Gap 5: Multi-Regulation Coherence

A company importing aluminium from a non-EU source faces CBAM (embedded emissions), DPP (product passport), CSRD (sustainability reporting), and potentially EUDR (if the aluminium supply chain touches deforestation-risk regions). Each regulation requires overlapping but not identical data. Current approach: separate tools, separate data collection, separate consultants for each regulation.

A shared provenance layer would collect the source data once, derive regulation-specific outputs through documented transformation chains, and produce separate compliant outputs — each traceable to the same underlying evidence.

### Gap 6: The "Prove It" Infrastructure

The deepest gap. Regulations are shifting from "tell us your carbon footprint" to "prove your carbon footprint." The difference is structural. A report is a claim. An evidence package is a verifiable derivation chain from source data through methodology to result, with every step immutable and every decision recorded.

No current platform produces evidence packages in this sense. They produce reports with varying degrees of audit trail. The infrastructure to produce, store, transmit, and verify evidence packages — across organizations, across regulations, across time — does not exist yet.

---

## 6. Market Context

The regulatory pressure is creating measurable market demand.

| Segment | Size (2025) | Growth | Source |
|---------|------------|--------|--------|
| Europe ESG Software | USD 403M | ~21% CAGR | Various analyst reports (2024-2025) |
| Digital Product Passport Platforms | USD 2.4B | USD 10.8B by 2035 (~16% CAGR) | Allied Market Research (2024) |
| Global RegTech | ~USD 13B | ~USD 82B by 2033 (~26% CAGR) | Fortune Business Insights (2024) |

These numbers describe the market for compliance tooling broadly. The provenance infrastructure layer — the "prove it" layer underneath the reporting tools — is not yet a recognized market segment. That is both a risk (no established buyer category) and an opportunity (no established competitors in the specific niche).

The relevant comparison: HashiCorp built infrastructure tooling (Terraform, Vault, Consul) for a problem that every company had but no company thought of as a product category. "Infrastructure as code" was not a market segment until HashiCorp made it one. "Provenance as infrastructure" is in a similar position — the demand exists (15+ regulations requiring it), but the category does not yet have a name.

---

## 7. Implications for Liminara

This analysis does not change what Liminara is. Liminara is a provenance engine for nondeterministic computation — it was designed for reproducibility, not for regulatory compliance. But the regulatory landscape creates a significant tailwind.

The key observations:

1. **The demand is real and time-bound.** Fifteen regulations with enforcement dates between 2025 and 2029. Companies cannot defer indefinitely.

2. **The architectural fit is genuine, not forced.** Content-addressed artifacts, append-only event logs, decision records, and determinism classes map naturally to what these regulations require. This is not a pivot — it is a consequence of building the right architecture for the right problem.

3. **The gap is infrastructure, not applications.** The market has reporting tools. It has dashboards and templates. What it lacks is the underlying provenance layer — the thing that makes every number traceable, every derivation verifiable, every evidence chain immutable. That is what Liminara provides.

4. **DPP is the most structurally aligned regulation.** A Digital Product Passport is, architecturally, a Liminara run: a DAG of operations producing immutable artifacts with recorded decisions. This is not metaphorical — the data structures are isomorphic.

5. **SME supply chain pressure creates a large underserved market.** CSRD, DPP, EUDR, and Battery Regulation all push data demands down the supply chain to companies that cannot afford enterprise tooling. Open-source provenance infrastructure addresses this directly.

---

## References

- EU AI Act: Regulation (EU) 2024/1689, OJ L 2024/1689
- CSRD: Directive (EU) 2022/2464, OJ L 322
- Omnibus simplification package: COM(2025) 80 final (26 February 2025)
- ESPR / DPP: Regulation (EU) 2024/1781, OJ L 2024/1781
- EUDR: Regulation (EU) 2023/1115, OJ L 150
- Battery Regulation: Regulation (EU) 2023/1542, OJ L 191
- CBAM: Regulation (EU) 2023/956, OJ L 130
- CSDDD: Directive (EU) 2024/1760, OJ L 2024/1760
- DORA: Regulation (EU) 2022/2554, OJ L 333
- NIS2: Directive (EU) 2022/2555, OJ L 333
- Cyber Resilience Act: Regulation (EU) 2024/2847, OJ L 2024/2847
- EU Data Act: Regulation (EU) 2023/2854, OJ L 2023/2854
- EU Taxonomy: Regulation (EU) 2020/852, OJ L 198
- VSME: EFRAG VSME Exposure Draft (January 2024), adopted July 2025
- Allied Market Research, "Digital Product Passport Market" (2024)
- Fortune Business Insights, "RegTech Market Size" (2024)

---

*This document extends [03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md) from a single-regulation focus to the full EU regulatory landscape. See also [07_Compliance_Layer.md](07_Compliance_Layer.md) and [09_Compliance_Demo_Tool.md](09_Compliance_Demo_Tool.md) for implementation-level discussion.*
