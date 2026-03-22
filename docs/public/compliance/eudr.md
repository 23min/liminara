# EUDR — Deforestation-Free Commodity Traceability

**Can you trace a 100g chocolate bar back to specific farm plots in West Africa — through the blending point where traceability usually dies?**

Research | [EUDR (EU) 2023/1115](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1115), geolocation, commodity traceability, aggregation provenance, due diligence

---

## The scenario

Choklad Kompaniet is a craft chocolate maker in Malmö. They source 12 tonnes of cocoa per year from three cooperatives: Coopérative Aboisso and Coopérative Sassandra in Côte d'Ivoire, and Cooperativa Alto Huallaga in Peru. Between the three cooperatives, roughly 380 smallholder farmers supply cocoa.

Under the [EU Deforestation Regulation](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1115), large operators must comply by December 2026. Choklad Kompaniet must prove that every kilogram of cocoa they import was produced on land not deforested after 31 December 2020. They must submit a due diligence statement through the EU TRACES system with geolocation data for every plot of land where the cocoa was produced.

The data collection is difficult. The traceability is harder. And the hardest problem of all sits at the cooperative washing station, where cocoa from 150 farms is fermented, dried, and bagged together. That is the blending point — and it is where most traceability systems quietly give up.

---

## The pipeline

```
        FARM-LEVEL SOURCE DATA (per cooperative, ~150 farms each)
        ───────────────────────────────────────────────────────────

Farm CIV-AB-037:                Farm CIV-AB-038:              ... × 148 more
  GPS: 5°23'12"N, 3°47'05"W      GPS: 5°23'41"N, 3°46'52"W
  Plot area: 2.3 ha               Plot area: 1.7 ha
  Crop: Theobroma cacao           Crop: Theobroma cacao
  Land title: CI-2019-AB-1042     Land title: CI-2019-AB-1087
  Yield this harvest: 184 kg      Yield this harvest: 127 kg
  sha256:3a91...                   sha256:c7f4...
           │                              │
           └──────────────┬───────────────┘
                          ▼
        ┌─── satellite verification ─────────────────────────┐
        │          (pure)                                    │
        │                                                    │
        │  For each plot:                                    │
        │    compare current land cover against              │
        │    2020 baseline (Hansen Global Forest Change)     │
        │                                                    │
        │  Farm CIV-AB-037: 2.3 ha                          │
        │    forest cover 2020: 0.0 ha (already cultivated)  │
        │    forest cover 2024: 0.0 ha                       │
        │    deforestation: NONE ✓                           │
        │                                                    │
        │  Farm CIV-AB-038: 1.7 ha                          │
        │    forest cover 2020: 0.0 ha                       │
        │    forest cover 2024: 0.0 ha                       │
        │    deforestation: NONE ✓                           │
        │                                                    │
        │  148 more plots verified...                        │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        ┌─── legal land use verification ────────────────────┐
        │          (side-effecting)                          │
        │                                                    │
        │  Cross-reference each land title against           │
        │  national registry (Côte d'Ivoire: AFOR/BNETD)    │
        │                                                    │
        │  Farm CIV-AB-037: title CI-2019-AB-1042            │
        │    registered owner: Konan Yao                     │
        │    status: VALID                                   │
        │    expiry: 2029-03-15                              │
        │    land use designation: agricultural              │
        │    protected area overlap: NONE                    │
        │    sha256:d4e2...                                  │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        ┌─── AGGREGATION AT COOPERATIVE ─────────────────────┐
        │          (recordable)                              │
        │                                                    │
        │  THIS IS THE CRITICAL STEP.                        │
        │                                                    │
        │  Coopérative Aboisso washing station:              │
        │  150 farms deliver cocoa → fermented → dried →     │
        │  bagged as Lot AB-2026-003 (4,200 kg)             │
        │                                                    │
        │  The physical cocoa is mixed.                      │
        │  The provenance must NOT be mixed.                 │
        │                                                    │
        │  Aggregation decision records proportional blend:  │
        │    Farm CIV-AB-037: 184 kg / 4,200 kg = 4.38%    │
        │    Farm CIV-AB-038: 127 kg / 4,200 kg = 3.02%    │
        │    Farm CIV-AB-039: 203 kg / 4,200 kg = 4.83%    │
        │    ...                                             │
        │    Farm CIV-AB-150: 31 kg / 4,200 kg = 0.74%     │
        │    ────────────────────────────────────────────    │
        │    Total: 4,200 kg / 4,200 kg = 100.00%          │
        │                                                    │
        │  Each farm's contribution is a content-addressed   │
        │  artifact. The blend proportions are a recorded    │
        │  decision. The lot inherits ALL plot geolocations. │
        │                                                    │
        │  Lot AB-2026-003: sha256:8b17...                  │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        ┌─── shipping and import ────────────────────────────┐
        │          (side-effecting)                          │
        │                                                    │
        │  Bill of lading: MAEU-2026-SAN-0847               │
        │  Origin port: San Pedro, Côte d'Ivoire            │
        │  Destination: Malmö, Sweden                        │
        │  Commodity: cocoa beans, 4,200 kg                  │
        │  Lot reference: AB-2026-003                        │
        │  Phytosanitary cert: CI-PHYTO-2026-1184           │
        │  sha256:f1a9...                                    │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        ┌─── risk assessment ────────────────────────────────┐
        │          (recordable)                              │
        │                                                    │
        │  Country risk: Côte d'Ivoire → HIGH               │
        │  (per EU benchmarking, Art. 29)                    │
        │                                                    │
        │  Plot-level risk (aggregated):                     │
        │    150 plots verified deforestation-free:  150     │
        │    Land titles valid:                      150     │
        │    Protected area overlap:                   0     │
        │    Satellite anomalies flagged:               0    │
        │    ────────────────────────────────────────────    │
        │    Cooperative risk score: LOW                     │
        │    (decision recorded with rationale)              │
        │                                                    │
        │  "Country is high-risk, but all plot-level         │
        │   checks pass. Cooperative has 6-year              │
        │   track record. Risk: LOW."                        │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        ┌─── due diligence statement ────────────────────────┐
        │          (pure)                                    │
        │                                                    │
        │  Generate TRACES submission:                       │
        │    Operator: Choklad Kompaniet AB                  │
        │    Commodity: cocoa (CN 1801 00 00)                │
        │    Quantity: 4,200 kg                              │
        │    Country of production: Côte d'Ivoire            │
        │    Geolocation: 150 plot polygons attached         │
        │    Deforestation status: compliant                 │
        │    Legal compliance: verified                      │
        │    Risk assessment: LOW                            │
        │                                                    │
        │  due-diligence-AB-2026-003.json: sha256:2c4d...   │
        │  seal.json: sha256:a87e...                         │
        └────────────────────────────────────────────────────┘
                             │
                             ▼
        ┌─── submit to TRACES ───────────────────────────────┐
        │          (side-effecting)                          │
        │                                                    │
        │  Upload due diligence statement                    │
        │  Receive reference number                          │
        │  Reference: EUDR-DDS-2026-SE-00847                │
        └────────────────────────────────────────────────────┘
```

**The blending problem, solved:** When a customer picks up a 100g bar of Choklad Kompaniet's single-origin Aboisso dark chocolate, the EUDR due diligence statement references Lot AB-2026-003. That lot's aggregation decision artifact (sha256:8b17...) records that the lot contains cocoa from 150 specific plots, each with GPS coordinates, satellite verification results, and land title checks. The 100g bar can be traced — proportionally — to 150 specific farm plots. Not "somewhere in Côte d'Ivoire." To 5°23'12"N, 3°47'05"W.

This works because the aggregation step is a recorded decision, not a data loss event. The physical cocoa is blended. The provenance is preserved as a proportional attribution artifact.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Which plots contributed to this shipment?" | The aggregation decision for Lot AB-2026-003 (sha256:8b17...) lists all 150 farms with exact GPS polygons, areas, yields, and proportional contributions. |
| "What's the deforestation risk score for Coopérative Aboisso?" | Aggregate satellite verification results across all 150 plots: zero deforestation events detected against the 2020 baseline. Six-year compliance track record. Risk score: LOW. Decision rationale recorded. |
| "Can we prove this meets the December 2020 cutoff?" | Each plot's satellite verification artifact contains the 2020 baseline comparison. Farm CIV-AB-037 (sha256:3a91...): forest cover in 2020 = 0.0 ha (already under cultivation). The cutoff date is embedded in the verification methodology, not asserted after the fact. |
| "What happens if one farm fails verification next year?" | That farm's satellite check produces a different result → the aggregation decision for any lot containing that farm's cocoa triggers a cache miss → risk assessment recalculates → due diligence statement regenerates. All other farms' data: cache hit. |
| "Can an auditor verify the entire chain independently?" | The seal (sha256:a87e...) commits to the full event log. Recompute the hash chain: if the final hash matches, the log is intact. The auditor can trace from the TRACES submission back to individual farm GPS coordinates without accessing Choklad Kompaniet's systems — only the sealed artifacts. |

---

## Before and after

**Today:** Choklad Kompaniet receives a spreadsheet from each cooperative listing farm names and approximate GPS coordinates. The data was collected by a field agent with a smartphone, transcribed into Excel, emailed to the cooperative manager, who forwards it to Choklad Kompaniet's import partner. Nobody is certain the coordinates match the actual farms. When the cooperative blends cocoa from 150 farms into one lot, the spreadsheet becomes the only link between the lot and its origins — and that spreadsheet is a copy of a copy. The TRACES submission references this spreadsheet. If challenged, Choklad Kompaniet produces an email thread.

**With provenance:** Each farm's data is a content-addressed artifact at the point of collection. Satellite imagery verification is automated and recorded. The aggregation at the cooperative is a recorded decision preserving proportional attribution. The due diligence statement is a sealed artifact tracing through every step. When an auditor asks "where does this cocoa come from?", the answer is a hash chain, not an email thread. When a farm's status changes, only the affected calculations re-run.

---

*Looking for commodity importers, cooperative supply chain managers, and EUDR compliance practitioners. [Contact ->]*
