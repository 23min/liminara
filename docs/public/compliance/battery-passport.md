# Battery Passport — Carbon Footprint as Competitive Advantage

**Can a sodium-ion startup prove its carbon advantage with numbers that trace to their source — and hold up when emission factors change?**

Research | [Battery Regulation (EU) 2023/1542](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1542), carbon footprint declaration, digital passport, mineral due diligence, sodium-ion

---

## The scenario

Polar Cells AB manufactures sodium-ion battery cells in Skellefteå for stationary energy storage — grid-scale batteries, industrial UPS systems, telecom backup. Their chemistry uses iron, manganese, and sodium. No cobalt. No lithium. No nickel. This is not a compromise — it is a strategic choice. Sodium-ion cells are cheaper, safer, use abundant materials, and have a significantly lower carbon footprint than lithium-ion. For stationary storage where energy density matters less than cost and cycle life, the chemistry is ideal.

Under the [Battery Regulation](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1542), carbon footprint declarations have been required since February 2025. Digital passports become mandatory in February 2027 for industrial batteries above 2 kWh. Polar Cells' standard product — a 48V 280Ah sodium-ion module (13.4 kWh) — is well above the threshold.

Here is the thing: Polar Cells' carbon footprint is their competitive advantage. Their Na-ion cells clock in at roughly 38 kgCO2e/kWh. A comparable lithium-ion NMC cell is typically 65-90 kgCO2e/kWh. That difference is not marketing — it is traceable to specific material choices, specific suppliers, and Sweden's electricity grid. But only if the numbers are provable.

---

## The pipeline

```
        RAW MATERIAL SOURCING
        ─────────────────────────────────────────────────────

Iron (cathode)           Manganese (cathode)       Sodium carbonate
LKAB, Kiruna, Sweden     South African mine,       Domsjö Fabriker,
                         Hotazel, Northern Cape     Örnsköldsvik, Sweden
                         │                          │
                         │                          │
  ┌──────────────────────┼──────────────────────────┼─────────┐
  │                      │                          │         │
  ▼                      ▼                          ▼         │
┌─── material sourcing evidence ───────────────────────────┐  │
│          (side-effecting)                                │  │
│                                                          │  │
│  Iron: LKAB Kiruna                                       │  │
│    emission factor: 1.06 tCO₂/t iron (LKAB EPD 2025)   │  │
│    transport: 950 km rail Kiruna→Skellefteå              │  │
│    sha256:4a22...                                        │  │
│                                                          │  │
│  Manganese: South Africa                                 │  │
│    emission factor: 1.83 tCO₂/t Mn ore (actual, v2025) │  │
│    transport: 14,200 km sea + 320 km rail                │  │
│    due diligence: OECD Annex II compliant               │  │
│    sha256:b7c1...                                        │  │
│                                                          │  │
│  Sodium carbonate: Domsjö                                │  │
│    emission factor: 0.41 tCO₂/t Na₂CO₃ (biorefinery)  │  │
│    transport: 380 km road Örnsköldsvik→Skellefteå       │  │
│    sha256:e3d9...                                        │  │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── emission factor registry ─────────────────────────────┐
│          (pinned_env)                                    │
│                                                          │
│  Versioned reference data — registered via Pack.init/0   │
│                                                          │
│  emission-factors-v2025:                                 │
│    Swedish grid mix:     7.1 gCO₂/kWh (Energimynd. 2025)│
│    LKAB iron (EPD):     1.06 tCO₂/t                     │
│    SA manganese (actual): 1.83 tCO₂/t                   │
│    Domsjö Na₂CO₃ (EPD): 0.41 tCO₂/t                    │
│    Road transport SE:    0.062 kgCO₂/tkm                │
│    Rail transport SE:    0.005 kgCO₂/tkm                │
│    Sea transport:        0.008 kgCO₂/tkm                │
│    sha256:91f7...                                        │
│                                                          │
│  When factors update → cache key changes →               │
│  all downstream calculations invalidate                  │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── carbon footprint calculation ─────────────────────────┐
│          (pure)                                          │
│                                                          │
│  Per 48V 280Ah module (13.4 kWh):                       │
│                                                          │
│  1. Raw material acquisition          12.8 kgCO₂e       │
│     ├── Iron (cathode active):         4.2 kgCO₂e       │
│     ├── Manganese (cathode active):    3.9 kgCO₂e       │
│     ├── Sodium carbonate (cathode):    1.1 kgCO₂e       │
│     ├── Aluminium (current collector): 2.4 kgCO₂e       │
│     └── Other (electrolyte, separator): 1.2 kgCO₂e      │
│                                                          │
│  2. Raw material transport             2.6 kgCO₂e       │
│     ├── Iron (950 km rail):            0.1 kgCO₂e       │
│     ├── Manganese (14,200 km sea +     1.9 kgCO₂e       │
│     │   320 km rail):                                    │
│     ├── Sodium carbonate (380 km road): 0.4 kgCO₂e      │
│     └── Other materials:               0.2 kgCO₂e       │
│                                                          │
│  3. Cell manufacturing                 1.4 kgCO₂e       │
│     ├── Electrode preparation:         0.5 kgCO₂e       │
│     ├── Cell assembly (dry room):      0.4 kgCO₂e       │
│     ├── Formation cycling:             0.3 kgCO₂e       │
│     └── Quality testing:               0.2 kgCO₂e       │
│     (all powered by Swedish grid: 7.1 gCO₂/kWh)        │
│                                                          │
│  4. Module assembly                    0.6 kgCO₂e       │
│     ├── BMS electronics:               0.3 kgCO₂e       │
│     └── Housing, wiring, assembly:     0.3 kgCO₂e       │
│                                                          │
│  ──────────────────────────────────────────────────      │
│  Total: 17.4 kgCO₂e per module                          │
│  Per kWh: 17.4 / 13.4 = 1.30 kgCO₂e/kWh               │
│                                                          │
│  For comparison (same calculation, NMC811 Li-ion):       │
│    Raw materials:      41.2 kgCO₂e (cobalt, lithium)    │
│    Transport:           3.1 kgCO₂e                      │
│    Cell mfg:            8.7 kgCO₂e (higher energy)      │
│    Module assembly:     0.8 kgCO₂e                      │
│    Total:              53.8 kgCO₂e → 4.01 kgCO₂e/kWh  │
│                                                          │
│  Polar Cells advantage: ~68% lower carbon footprint     │
│                                                          │
│  sha256:c54b...                                          │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── manganese due diligence ──────────────────────────────┐
│          (recordable)                                    │
│                                                          │
│  Battery Regulation Art. 52: supply chain due diligence  │
│  for cobalt, lithium, nickel, natural graphite, AND      │
│  manganese (added in Annex X).                           │
│                                                          │
│  Polar Cells uses no cobalt, lithium, or nickel.         │
│  But manganese requires OECD Annex II due diligence.     │
│                                                          │
│  Supplier: Hotazel Manganese Mines                       │
│  Country: South Africa (not conflict-affected)           │
│  OECD Step 1-5 assessment: COMPLIANT                     │
│  Third-party audit: Bureau Veritas, 2025-09-12           │
│  Certification: sha256:7d83...                           │
│                                                          │
│  Decision: "Manganese sourced from South Africa,         │
│  OECD-compliant, audited. No conflict mineral risk.      │
│  Na-ion chemistry eliminates cobalt/lithium/nickel       │
│  due diligence requirements entirely."                   │
│  (decision recorded)                                     │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── quality and performance data ─────────────────────────┐
│          (pure)                                          │
│                                                          │
│  Nominal capacity: 280 Ah                                │
│  Nominal voltage: 48V (16S configuration)                │
│  Energy: 13.4 kWh                                        │
│  Cycle life: >4,000 cycles at 80% DoD                   │
│  Round-trip efficiency: 92%                               │
│  Operating temp: -20°C to +60°C                          │
│  Expected lifetime: 15 years                              │
│  Recyclability: 87% (iron and manganese recoverable)     │
│  sha256:a2e6...                                          │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── compose passport ─────────────────────────────────────┐
│          (pure)                                          │
│                                                          │
│  Passport ID: PC-NAI-48V280-2026-00142                   │
│  Manufacturer: Polar Cells AB, Skellefteå, Sweden       │
│  Chemistry: Sodium-ion (Prussian White cathode)          │
│  Carbon footprint: 1.30 kgCO₂e/kWh                     │
│    breakdown: materials 12.8 + transport 2.6 +           │
│    manufacturing 1.4 + assembly 0.6                      │
│  Mineral due diligence: Mn (compliant), no Co/Li/Ni     │
│  Recyclability: 87%                                      │
│  Performance class: A (per forthcoming classification)   │
│                                                          │
│  passport-PC-NAI-48V280-2026-00142.json: sha256:e1f3... │
│  seal.json: sha256:39b2...                               │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─── register with EU battery passport system ─────────────┐
│          (side-effecting)                                │
│                                                          │
│  Upload passport to EU registry                          │
│  Generate QR code link                                   │
│  Battery Passport ID: EU-BP-2026-SE-004781               │
└──────────────────────────────────────────────────────────┘
                     │
                     ▼
              Battery Passport
              sha256:e1f3...
              ┌──────────────────────┐
              │ [QR] <- passport URL │
              │ Polar Cells AB       │
              │ Na-ion 48V 280Ah     │
              │ 1.30 kgCO₂e/kWh    │
              │ Seal: 39b2...        │
              └──────────────────────┘
```

**What happens when emission factors update:** In March 2026, Energimyndigheten publishes updated Swedish grid emission factors: 6.8 gCO₂/kWh (down from 7.1). The emission factor registry artifact changes from sha256:91f7... to sha256:44c2... The cache key for the carbon footprint calculation changes. The pipeline re-runs: material sourcing data is unchanged (cache hit), but the manufacturing stage recalculates using the new grid factor. Cell manufacturing drops from 1.4 to 1.34 kgCO₂e. The passport regenerates. Every passport issued before the update still references the old factor version — verifiably. Every passport issued after references the new one. No ambiguity about which factors were in effect for which product.

**The sodium-ion advantage, proven:** Any competitor can claim lower emissions. Polar Cells can prove it: the 1.30 kgCO₂e/kWh figure traces through every lifecycle stage to specific suppliers, specific emission factors, and a specific electricity grid. A potential customer can verify the calculation. A regulator can audit it. The 68% advantage over lithium-ion NMC is not a marketing number — it is a sealed, reproducible computation.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Where does the 1.30 kgCO₂e/kWh figure come from?" | Trace the carbon footprint artifact (sha256:c54b...): 12.8 (materials, from supplier EPDs and actuals) + 2.6 (transport, from distances × modal factors) + 1.4 (manufacturing, from facility energy × grid factor) + 0.6 (assembly). Each term traces to a versioned emission factor and a measured quantity. |
| "Which emission factor version was used for this passport?" | The passport references emission-factors-v2025 (sha256:91f7...). The registry artifact contains every factor with its source and publication date. Passports issued after the March 2026 update reference emission-factors-v2026 (sha256:44c2...). |
| "Does Polar Cells meet the manganese due diligence requirement?" | Decision record: manganese sourced from Hotazel Manganese Mines, South Africa. OECD Annex II Steps 1-5 assessment: compliant. Third-party audit by Bureau Veritas (certification artifact sha256:7d83...). Na-ion chemistry eliminates cobalt, lithium, and nickel from the due diligence scope entirely. |
| "How does this compare to a lithium-ion alternative?" | The same calculation pipeline run with NMC811 inputs produces 4.01 kgCO₂e/kWh. Both calculations use the same emission factor registry and methodology. The difference is in the inputs — materials, energy intensity, supply chain distances — not in the method. An evaluator can verify both pipelines share the same structure. |
| "What if the manganese supplier changes?" | New supplier → new sourcing evidence artifact → cache miss on material acquisition stage → carbon footprint recalculates → passport regenerates. Due diligence assessment re-runs for the new supplier. Old passports remain valid for products already manufactured (they reference the original supplier's sealed data). |

---

## Before and after

**Today:** Polar Cells calculates their carbon footprint in a spreadsheet. They collect supplier EPDs by email, look up grid emission factors on Energimyndigheten's website, and enter numbers into a calculation template. When a customer asks how their footprint compares to lithium-ion, they send a PDF. When an auditor asks where the 1.06 tCO₂/t iron figure comes from, they search for the LKAB EPD email. When emission factors update, someone remembers to update the spreadsheet — or doesn't. The 68% advantage over lithium-ion is a claim. A credible one, but a claim.

**With provenance:** The carbon footprint is a reproducible computation. Every number traces to a versioned source. When factors update, affected passports are automatically identified and recalculated. The comparison with lithium-ion uses the same methodology and the same emission factor versions — the difference is in the chemistry, provably. The 68% advantage is not a claim. It is a sealed artifact with a hash chain.

---

*Looking for battery manufacturers, especially alternative chemistries (Na-ion, LFP), preparing for the February 2027 digital passport deadline. [Contact ->]*
