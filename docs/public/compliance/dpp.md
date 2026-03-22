# Digital Product Passport — Supply Chain Provenance

**A product passport IS a provenance chain. Can Liminara generate them?**

Research | [ESPR (EU) 2024/1781](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1781), supply chain traceability, material composition, carbon footprint

---

## The scenario

NorthCell Energy assembles lithium-ion battery packs for light electric vehicles at a facility in Västerås. Their cells come from a manufacturer in Poland, who sources cathode material from a refiner in Finland, who processes lithium hydroxide imported from Chile. The [Battery Regulation](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1542) requires that by February 2027, every battery pack NorthCell sells must carry a digital passport: a QR code linking to machine-readable data covering material composition, carbon footprint per lifecycle stage, and mineral provenance — all verifiable.

NorthCell doesn't control most of this data. They depend on three suppliers across three countries, each with their own systems. The question isn't just "how do we produce a passport?" — it's "how do we produce one where every number traces to a real source?"

---

## The pipeline

```
                SUPPLIER DATA (sealed evidence packages)
                ─────────────────────────────────────────
Chile mine ──→ lithium extraction        Finland refiner ──→ cathode processing
               certificate (sealed)                          certificate (sealed)
               4.2 tCO₂/t LiOH                             2.1 tCO₂/t cathode
                    │                                             │
                    └──────────────┬───────────────────────────────┘
                                   │
                                   ▼
               ┌─── verify supplier seals ───┐
               │        (pure)               │
               │  check hash chains          │
               │  extract emission data      │
               └─────────────┬───────────────┘
                             │
                Poland cell  │   NorthCell facility
                mfg data ────┤   assembly data
                (sealed)     │   (internal)
                             ▼
               ┌─── calculate lifecycle CO₂ ──┐
               │        (pure)                │
               │                              │
               │  extraction:   4.2 tCO₂/t   │
               │  refining:     2.1 tCO₂/t   │
               │  cell mfg:     1.8 tCO₂/t   │
               │  pack assembly: 0.4 tCO₂/t  │
               │  logistics:     0.3 tCO₂/t  │
               │  ─────────────────────────── │
               │  total:        8.8 tCO₂/t   │
               └─────────────┬────────────────┘
                             │
                             ▼
               ┌─── compose passport ─────────┐
               │        (pure)                │
               │                              │
               │  material: Li, Co, Ni, Mn    │
               │  carbon: 8.8 tCO₂/t         │
               │  recyclability: 94%          │
               │  supplier chain: verified    │
               └─────────────┬────────────────┘
                             │
                             ▼
               ┌─── register with EU DPP ─────┐
               │     (side-effecting)         │
               │                              │
               │  upload to EU registry       │
               │  receive DPP identifier      │
               │  generate QR code            │
               └──────────────────────────────┘
                             │
                             ▼
                    Battery Passport
                    sha256:f7a3...
                    ┌──────────────────┐
                    │ [QR] ← DPP link │
                    │ 48V 28Ah LFP    │
                    │ 8.8 tCO₂/t      │
                    │ Seal: e91d...    │
                    └──────────────────┘
```

The key architectural point: each supplier provides a **sealed evidence package**, not raw data. NorthCell doesn't need access to their suppliers' systems. They verify the seal (a SHA-256 hash chain check — trivial, instant, no special software) and extract the data they need. The trust is in the math, not the relationship.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Where does the 4.2 tCO₂/t lithium extraction figure come from?" | Trace to supplier's sealed package → their event log → their extraction facility data. NorthCell can verify the seal; they can't see the internal data (the supplier's process is their own). |
| "What if the Finnish refiner updates their emission factor?" | The refiner issues a new sealed package with updated data. Re-run: the old package hash changes → lifecycle calculation cache miss → passport regenerates. Extraction and assembly data are unchanged → cache hit. |
| "Can an auditor verify the entire chain?" | Each level has its own seal. The auditor verifies NorthCell's seal (covers the passport calculation), then checks that each supplier seal referenced in the inputs is valid. Recursive but straightforward. |
| "What happens when the battery is repaired or recycled?" | A new event is appended to the passport's lifecycle log. The passport's content-addressed artifacts don't change (the original manufacturing data is immutable). The lifecycle log grows. |
| "Is the cobalt from a certified source?" | Decision record: supplier selection for cobalt shows the certified refiner (DRC origin, OECD due diligence compliant), with the certification artifact hash for reference. |

---

## Why this is hard without provenance

**Today:** NorthCell collects supplier data via email and spreadsheets. They enter numbers into a reporting tool. A third-party verifier audits the result. The verifier asks "where does this come from?" and NorthCell produces an email chain. The chain is fragile: one supplier provides updated numbers, and the entire audit trail breaks.

**The cross-organizational problem:** Four companies across four countries need to contribute to one passport without sharing their internal systems. Sealed evidence packages solve this — each company runs their own provenance pipeline and shares the sealed output. The receiving company verifies the seal without needing access to the source data.

This is the architectural pattern that makes DPP feasible for real supply chains, not just single-company products.

---

*Looking for supply chain professionals and battery industry contacts preparing for the February 2027 deadline. [Contact →]*
