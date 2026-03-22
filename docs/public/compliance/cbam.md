# CBAM — Embedded Emissions Verification

**Can a steel importer prove that actual production data is worth more than the default — and calculate exactly how much more?**

Research | [CBAM (EU) 2023/956](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R0956), embedded emissions, import verification, emission factors, steel

---

## The scenario

Stalimport Norr AB is a small steel trader in Lulea. They import approximately 500 tonnes per year of hot-rolled coil from Iskenderun Demir ve Celik A.S. (ISDEMIR), a steel mill in Iskenderun, Turkey. Their customers are fabricators and construction companies across northern Sweden.

Under the [Carbon Border Adjustment Mechanism](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R0956), the definitive phase began January 2026. From September 2027, CBAM certificates must be surrendered — one certificate per tonne of embedded CO2. The certificate price tracks the EU ETS carbon price. At current levels, roughly 80 EUR per tonne of CO2.

Here is the math that makes provenance a business case, not a compliance exercise:

The ISDEMIR mill operates two production routes. Their electric arc furnace (EAF) line — fed by scrap steel and powered partly by renewables — produces coil at approximately 1.4 tCO2 per tonne of steel. Their basic oxygen furnace (BOF) line — using iron ore and coal — produces at approximately 2.3 tCO2/t. The EU default value for hot-rolled coil, used when actual data cannot be verified, is 2.1 tCO2/t.

For 500 tonnes of EAF-route coil: 500 x 1.4 x 80 EUR = 56,000 EUR in certificates.
For 500 tonnes at EU default: 500 x 2.1 x 80 EUR = 84,000 EUR in certificates.
Difference: 28,000 EUR per year.

The question is not whether actual data is better. The question is whether Stalimport can prove it.

---

## The pipeline

```
        PRODUCTION DATA FROM TURKISH MILL
        ─────────────────────────────────────────────────────

ISDEMIR provides production data for Shipment ISK-2026-0847:

  ┌─── mill production declaration ────────────────────────┐
  │          (side-effecting)                              │
  │                                                        │
  │  Mill: ISDEMIR, Iskenderun, Turkey                     │
  │  Product: hot-rolled coil, CN 7208                     │
  │  Shipment: ISK-2026-0847                               │
  │  Quantity: 125 tonnes                                  │
  │                                                        │
  │  Production route: Electric Arc Furnace (EAF)          │
  │  Scrap ratio: 92%                                      │
  │  Energy sources:                                       │
  │    Grid electricity: 410 kWh/t (Turkish grid mix)      │
  │    Natural gas: 18 m³/t (preheating, ladle furnace)   │
  │    Electrode consumption: 2.1 kg/t                     │
  │                                                        │
  │  Direct emissions: 0.31 tCO₂/t                        │
  │    ├── natural gas combustion: 0.18 tCO₂/t            │
  │    ├── electrode oxidation: 0.07 tCO₂/t              │
  │    └── lime calcination: 0.06 tCO₂/t                 │
  │                                                        │
  │  Indirect emissions: 1.09 tCO₂/t                      │
  │    └── grid electricity: 410 kWh × 2.66 kgCO₂/kWh   │
  │        (Turkish grid weighted average 2025)            │
  │                                                        │
  │  Total embedded: 1.40 tCO₂/t steel                    │
  │                                                        │
  │  Sealed by ISDEMIR: sha256:5e41...                     │
  └────────────────────┬───────────────────────────────────┘
                       │
                       ▼
  ┌─── production route verification ──────────────────────┐
  │          (recordable)                                  │
  │                                                        │
  │  THIS IS THE CRITICAL DECISION.                        │
  │                                                        │
  │  Can Stålimport verify that this shipment actually     │
  │  came from the EAF line, not the BOF line?             │
  │                                                        │
  │  Evidence evaluated:                                   │
  │    ✓ Mill production schedule (EAF campaign week 12)   │
  │    ✓ Heat numbers on coils match EAF sequence          │
  │    ✓ Chemical analysis consistent with scrap-based     │
  │      production (residual Cu, Sn within EAF range)     │
  │    ✓ Third-party verification: SGS Iskenderun          │
  │      inspection report 2026-03-18 (sha256:c8a3...)     │
  │                                                        │
  │  Decision: "Production route verified as EAF.          │
  │  Heat numbers ISK-E-26-1847 through ISK-E-26-1853     │
  │  confirmed on EAF production log. Chemical analysis    │
  │  consistent. SGS on-site verification obtained."       │
  │                                                        │
  │  Alternative considered: use mill weighted average      │
  │  (1.85 tCO₂/t, blending EAF and BOF production).      │
  │  Rejected: specific production route is traceable      │
  │  for this shipment.                                    │
  │  (decision recorded with full rationale)               │
  └────────────────────┬───────────────────────────────────┘
                       │
                       ▼
  ┌─── emission calculation ───────────────────────────────┐
  │          (pure)                                        │
  │                                                        │
  │  Shipment ISK-2026-0847: 125 tonnes hot-rolled coil   │
  │                                                        │
  │  Method: ACTUAL (verified production data)             │
  │                                                        │
  │  Embedded emissions:                                   │
  │    Direct:   125 t × 0.31 tCO₂/t =   38.75 tCO₂     │
  │    Indirect: 125 t × 1.09 tCO₂/t =  136.25 tCO₂     │
  │    Total:    125 t × 1.40 tCO₂/t =  175.00 tCO₂     │
  │                                                        │
  │  For comparison (EU default):                          │
  │    125 t × 2.10 tCO₂/t =  262.50 tCO₂               │
  │                                                        │
  │  Saving from actual data: 87.50 tCO₂                  │
  │  At ~€80/certificate: €7,000 saved on this shipment   │
  │                                                        │
  │  Turkish carbon price paid: €0/t (Turkey has no        │
  │  operational ETS — no deduction applicable)            │
  │                                                        │
  │  sha256:d93a...                                        │
  └────────────────────┬───────────────────────────────────┘
                       │
                       ▼
  ┌─── certificate calculation ────────────────────────────┐
  │          (pure)                                        │
  │                                                        │
  │  Embedded emissions:        175.00 tCO₂               │
  │  Carbon price paid abroad:    0.00 tCO₂ equivalent    │
  │  ──────────────────────────────────────────            │
  │  Certificates required:     175                        │
  │  Estimated cost:            175 × €80 = €14,000       │
  │                                                        │
  │  (If EU default had been used:                         │
  │   263 certificates × €80 = €21,040                     │
  │   Additional cost: €7,040)                             │
  │                                                        │
  │  sha256:17b5...                                        │
  └────────────────────┬───────────────────────────────────┘
                       │
                       ▼
  ┌─── CBAM declaration ───────────────────────────────────┐
  │          (pure)                                        │
  │                                                        │
  │  Declarant: Stålimport Norr AB                        │
  │  EORI: SE5569123456                                    │
  │  Quarter: Q1 2026                                      │
  │  Goods: hot-rolled coil, CN 7208 10 00                 │
  │                                                        │
  │  Shipment ISK-2026-0847:                               │
  │    Origin: Turkey                                      │
  │    Mill: ISDEMIR, Iskenderun                           │
  │    Quantity: 125 t                                     │
  │    Embedded emissions: 175.00 tCO₂ (actual)           │
  │    Method: actual, verified                            │
  │    Certificates: 175                                   │
  │                                                        │
  │  Shipment ISK-2026-0912:                               │
  │    (same mill, BOF route — different numbers)          │
  │    Quantity: 80 t                                      │
  │    Embedded emissions: 184.00 tCO₂ (actual)           │
  │    Method: actual, verified                            │
  │    Certificates: 184                                   │
  │                                                        │
  │  Quarter total: 205 t, 359 tCO₂, 359 certificates    │
  │                                                        │
  │  cbam-declaration-Q1-2026.json: sha256:4f8c...         │
  │  seal.json: sha256:bb91...                             │
  └────────────────────┬───────────────────────────────────┘
                       │
                       ▼
  ┌─── submit CBAM declaration ────────────────────────────┐
  │          (side-effecting)                              │
  │                                                        │
  │  Upload to CBAM transitional registry                  │
  │  Declaration ref: CBAM-SE-2026-Q1-00284                │
  │  Certificate surrender: September 2027                 │
  └────────────────────────────────────────────────────────┘


        THE ANNUAL PICTURE
        ─────────────────────────────────────────────────────

  4 shipments/year, ~500 tonnes total:

  With actual data (verified EAF route where applicable):
    ~700 tCO₂ embedded → ~700 certificates → ~€56,000/year

  With EU default values:
    ~1,050 tCO₂ embedded → ~1,050 certificates → ~€84,000/year

  Annual saving from provenance: ~€28,000

  Cost of provenance infrastructure: significantly less than €28,000.
  The system pays for itself in the first year.
```

**The production route decision:** This is where provenance earns its keep. ISDEMIR operates two furnace types with very different emission profiles. The weighted average across both lines is 1.85 tCO2/t. The EAF line alone is 1.4 tCO2/t. The BOF line is 2.3 tCO2/t. If Stalimport can trace a specific shipment to a specific production line — with heat numbers, chemical analysis, and third-party verification — they pay for 1.4, not 1.85 or the EU default of 2.1.

The decision to use production-route-specific data rather than a mill average is recorded. The evidence supporting that decision — heat number matching, chemical analysis, SGS verification — is captured as content-addressed artifacts. An auditor can examine the decision and its supporting evidence. If the evidence is insufficient for a given shipment, the pipeline falls back to the mill average or the EU default. The decision records why.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why does this shipment show 1.4 tCO₂/t instead of the EU default 2.1?" | Decision record for shipment ISK-2026-0847: production route verified as EAF via heat number matching + chemical analysis + SGS inspection (sha256:c8a3...). Actual emission data from ISDEMIR sealed evidence package (sha256:5e41...). |
| "How much did actual data save us this quarter?" | Emission calculation artifacts for each shipment contain both actual and default figures. Q1 2026: actual = 359 tCO₂, default would have been 430.5 tCO₂. Difference: 71.5 certificates x ~EUR 80 = ~EUR 5,720 saved. |
| "What if Turkey introduces an ETS with a carbon price?" | The pipeline includes a "carbon price paid abroad" input, currently EUR 0. When Turkey's ETS becomes operational, the Turkish carbon price artifact updates, the certificate calculation subtracts the amount already paid, and fewer certificates are required. All other steps: cache hit. |
| "Can an auditor trace the 0.31 tCO₂/t direct emissions figure?" | The mill's sealed evidence package (sha256:5e41...) breaks direct emissions into natural gas combustion (0.18, from 18 m3/t x emission factor), electrode oxidation (0.07, from 2.1 kg/t x carbon content), and lime calcination (0.06). Each figure traces to a measured input and a referenced emission factor. |
| "What happens if we can't verify the production route for a shipment?" | The production route verification decision records: "insufficient evidence for route-specific attribution." The pipeline uses the mill weighted average (1.85 tCO₂/t) or falls back to the EU default (2.1 tCO₂/t). The higher cost is the price of missing provenance — quantified to the euro. |

---

## Before and after

**Today:** Stalimport receives a PDF from ISDEMIR stating "1.4 tCO2/t, EAF production." They enter this number into their CBAM declaration. An auditor asks: "How do you know this came from the EAF line?" Stalimport forwards the PDF. The auditor asks: "How do you know the PDF is accurate?" Stalimport has no answer beyond trust. If the auditor rejects the actual data, Stalimport pays the EU default: 2.1 tCO2/t. The difference — EUR 28,000 per year — is the cost of unverifiable claims.

**With provenance:** The mill's production data is a sealed evidence package. The production route verification is a recorded decision with supporting artifacts — heat numbers, chemical analysis, third-party inspection. The emission calculation is a reproducible computation. When the auditor asks "how do you know?", the answer is a hash chain from the CBAM declaration back to the EAF production log and the SGS inspection report. The EUR 28,000 saving is not a hope. It is a verifiable consequence of traceable data.

---

*Looking for steel importers, commodity traders, and CBAM compliance practitioners preparing for the September 2027 certificate surrender deadline. [Contact ->]*
