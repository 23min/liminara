# EU AI Act: Compliance Opportunity and Funding Paths

**Date:** 2026-03-14
**Context:** Assessment of how the EU AI Act creates both market demand and funding opportunities for Liminara

---

## 1. The Regulatory Tailwind

The EU AI Act entered into force on 1 August 2024 with phased enforcement:

| Date | What takes effect |
|------|-------------------|
| 2 Feb 2025 | Prohibited AI practices ban + AI literacy obligations |
| 2 Aug 2025 | Governance rules + GPAI model obligations |
| **2 Aug 2026** | **Main deadline: High-risk AI system requirements enforceable** |
| 2 Aug 2027 | Full scope applies (Annex II, AI in regulated products) |

### Risk Categories

1. **Prohibited** — Social scoring, manipulative AI, predictive policing (banned since Feb 2025)
2. **High-Risk** — Law enforcement, healthcare, education, critical infrastructure, employment, migration. Heaviest compliance burden.
3. **Limited Risk** — Transparency obligations only (chatbots must disclose they are AI)
4. **Minimal Risk** — Unregulated

### Where Liminara Falls

Liminara itself is **minimal risk** — it's infrastructure tooling, not an AI system making consequential decisions. But it is precisely the kind of tool that high-risk AI system providers **need** to comply with the Act. This makes Liminara a **compliance enabler**: not regulated, but essential for those who are.

---

## 2. Article 12: The Article That Justifies Liminara

Article 12 ("Record-Keeping") requires all high-risk AI systems to technically allow for **automatic recording of events (logs) over the lifetime of the system**.

### What Article 12 Demands

Logging capabilities must enable recording of events relevant to:
- Identifying situations where the system may present a risk or require modification
- Facilitating post-market monitoring
- Monitoring system operation by deployers

Requirements include:
- **Automatic** logging (not optional, not manual)
- **Tamper-resistant** logs
- Sufficient information to **trace outputs to inputs**, model versions, and governing policies
- **Minimum 6-month retention**

### How Liminara Maps to Article 12

| Article 12 Requirement | Liminara Feature |
|------------------------|-----------------|
| Automatic recording of events | Append-only event log (one per run, automatic) |
| Tamper-resistant logs | Content-addressed artifacts (hash-verified), append-only files |
| Trace outputs to inputs | DAG of artifacts with content-addressed edges |
| Record model versions/policies | Decision records capture LLM responses, model IDs, parameters |
| Identify risk situations | Determinism classes flag which ops are nondeterministic |
| 6-month retention | Event files on filesystem (retained indefinitely) |
| Facilitate monitoring | Observation layer (ex_a2ui / Phoenix LiveView) |

The mapping is almost 1:1. Liminara's architecture was designed for reproducibility, but it also happens to be exactly what the EU AI Act requires for compliance.

### Fines for Non-Compliance

- Up to **EUR 35 million** or **7% of global revenue** for prohibited practices
- Up to **EUR 15 million** or **3% of global revenue** for other violations
- Up to **EUR 7.5 million** or **1.5% of global revenue** for incorrect information to authorities

---

## 3. Funding Paths

### 3.1 Vinnova "Innovative Startups" — Start Here

| Aspect | Details |
|--------|---------|
| **Grant size** | Up to ~SEK 1M (~EUR 90K) |
| **Eligibility** | Swedish AB, max 10 employees, max SEK 10M turnover |
| **Barrier** | Low. Single applicant. |
| **Calls** | Rolling/periodic — check vinnova.se |
| **Fit** | Perfect for early validation funding |

### 3.2 EIC Accelerator — The Big One

| Aspect | Details |
|--------|---------|
| **Grant** | Up to EUR 2.5M |
| **Equity** | EUR 1-10M (optional) |
| **2026 budget** | EUR 634M total |
| **Eligibility** | Single startups, SMEs, even natural persons. Solo founders explicitly eligible. |
| **TRL required** | 6-8 (working prototype demonstrated in relevant environment) |
| **Success rate** | 3-7% end-to-end |

**2026 deadlines (batching dates):**
- ~~7 January 2026~~ (passed)
- ~~4 March 2026~~ (passed)
- **6 May 2026**
- **8 July 2026**
- **2 September 2026**
- **4 November 2026**

**Application process:**
1. Short proposal (rolling): 12-page form + 10-slide deck + 3-min video → feedback in 4-6 weeks
2. Full proposal: 20-page form + implementation plan + financials → results in 8-9 weeks
3. Jury interview → results in 2-3 weeks
4. Grant agreement + due diligence → 2-6 months

**Strategy:** Target **September or November 2026** cutoff. By then the Hetzner MVP should be running with Radar producing real briefings (TRL 6). Frame as "AI Act compliance infrastructure."

### 3.3 Horizon Europe — Cluster 4 (Consortium Required)

**Relevant call:** HORIZON-CL4-2026-04-DATA-06 "Efficient and compliant access to and use of data"
- Budget: EUR 46.5M (3 projects, EUR 11.5-23.5M each)
- Explicitly mentions AI Act compliance
- Deadline: 15 April 2026
- Requires 3+ partners across multiple countries

**How to join a consortium:**
- Contact Vinnova NCPs: Johan Lindberg (johan.lindberg@vinnova.se, +46 8 454 64 53) or Jeannette Spuhler (jeannette.spuhler@vinnova.se, +46 8 473 32 57)
- Attend Vinnova brokerage events
- Use the Ideal-ist network or Enterprise Europe Network

**Other relevant Horizon Europe calls (deadline 15 April 2026):**
- GenAI4EU Booster (HORIZON-CL4-2026-04-DIGITAL-EMERGING-19)
- Next-Gen AI Agents for Real-World Applications (HORIZON-CL4-2026-05-DIGITAL-EMERGING-02, EUR 38M)
- Trustworthy AI models (EUR 21.2M)

### 3.4 AI Factories — Free Compute

- Sweden: **MIMER AI Factory**
- Finland: **LUMI AI Factory** (accessible to Nordic companies)
- Up to **50,000 GPU hours free** for 3 months (fast lane, approved within 4 working days)
- Less relevant unless domain packs need heavy compute

### 3.5 Vinnova — Other Calls

| Call | Grant | Deadline | Notes |
|------|-------|----------|-------|
| AI and Cybersecurity | SEK 1-10M | 9 April 2026 | Needs 2+ partners |
| Applied AI for Industry | SEK 2-10M | Varies | Needs 2+ partners |
| Advanced and Innovative AI | SEK 2-7M (max 60% of costs) | Varies | Research-oriented |

---

## 4. The Pitch

### For Funding Applications

> The EU AI Act (Article 12) requires automatic, tamper-resistant logging for all high-risk AI systems by August 2026. No open-source tool exists that provides content-addressed artifact provenance, decision recording, and deterministic replay for AI workflows. Liminara fills this gap.

### Key Angles

1. **Compliance infrastructure** — not another AI framework, but the audit layer every AI system needs
2. **Open-source sovereignty** — EU explicitly favors open-source for digital sovereignty
3. **Timing** — August 2026 enforcement deadline creates urgent market demand
4. **Technical differentiation** — decision recording + determinism classes + content-addressed artifacts = combination nobody else offers

### Market Sizing Argument

- Every company deploying high-risk AI in the EU needs Article 12 compliance
- Temporal (durable execution, no AI-specific audit trails) is valued at $5B
- The compliance tooling market for AI will be substantial — analogous to GDPR spawning a multi-billion-dollar compliance industry

---

## 5. Action Items

| Priority | Action | When |
|----------|--------|------|
| 1 | Register on EU Funding & Tenders Portal, get PIC number | This week |
| 2 | Contact Vinnova NCPs (Lindberg/Spuhler) to discuss positioning | This month |
| 3 | Check Vinnova Innovative Startups for next call opening | This month |
| 4 | Build MVP on Hetzner (Radar + core runtime) | Weeks 1-12 |
| 5 | Submit EIC Accelerator Step 1 (short proposal) | Once MVP is running (~August 2026) |
| 6 | Explore Horizon Europe consortium opportunities for 2027 calls | After MVP |

---

*This document complements [02_Fresh_Analysis.md](02_Fresh_Analysis.md) with regulatory and funding context.*
