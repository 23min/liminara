# Position Paper: proliminal.net/provenance

> Draft content for a standalone page on proliminal.net.
> This is the longer piece — the thing that gets linked from LinkedIn.
> Tone: thoughtful, concrete, inviting. Lead with the problem. Be honest about what exists and what doesn't.
> Written in English; Swedish translation is a separate step.

---

# Provenance for the "Prove It" Era

## The shift

Something is changing in how the EU thinks about trust.

For decades, regulatory compliance meant reporting: fill in the numbers, write a narrative, submit a document, and trust that the numbers are real. That model worked when the stakes were lower and the systems were simpler.

It doesn't work anymore.

Between 2024 and 2029, the EU is rolling out more than fifteen regulations that share a common demand: *don't just tell us what happened — prove it.*

- The [**Digital Product Passport**](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1781) (ESPR, 2026–2029) requires a machine-readable record of every product's material composition, carbon footprint, and supply chain provenance — traceable through its entire lifecycle, accessible via QR code.
- The [**EU Deforestation Regulation**](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1115) (December 2026) demands geolocation data for every plot of land where covered commodities were produced, with proof of legal use and absence of deforestation.
- The [**Battery Regulation**](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1542) (February 2027) requires a digital passport tracing each battery's carbon footprint from mineral extraction through manufacturing to end-of-life, verified by a third party.
- The [**CBAM**](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R0956) (active since January 2026) requires importers to calculate and verify the embedded emissions of steel, cement, aluminium, and other materials — traced to actual production data.
- The [**EU AI Act**](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689) (August 2026) mandates automatic, tamper-resistant logging for all high-risk AI systems, with full traceability from outputs to inputs.
- The [**VSME**](https://www.efrag.org/en/projects/vsme-standard/concluded) standard (recommended July 2025) gives SMEs a common language for sustainability reporting — because their larger customers, now under [CSRD](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022L2464) obligations, need ESG data from their entire value chain.

The pattern is consistent: machine-readable data. Source-to-output traceability. Tamper-evident records. Independent verifiability.

This is not a reporting problem. It's a provenance problem.

## The gap

The enterprise platforms — SAP, Microsoft, Salesforce, Oracle — are strong at collecting data and producing reports. They were built for that. But they were not built for provenance.

When an auditor asks "where does this Scope 3 emissions figure come from?", most enterprise systems can answer "it was entered by this user on this date." They cannot answer "it was calculated from these 47 supplier data points, using this specific version of emission factors, through this sequence of calculations, and here is a cryptographic proof that none of this has been altered."

That's not a feature gap. It's an architectural gap. Traditional databases use update-in-place semantics — records can be changed after the fact. "Period locking" is a policy control, not a mathematical guarantee. There is no hash chain. No content addressing. No immutable event log.

Meanwhile, the companies at the bottom of the supply chain — the SMEs that all of this data ultimately comes from — have even less. Suppliers increasingly receive sustainability data requests from their customers, often in different formats with different scopes. Most respond with spreadsheets. There is no way for the receiving company to verify where the numbers came from.

## An architectural approach

These problems have a common structure, and that structure has a known solution — it just hasn't been applied to regulatory compliance yet.

**Content-addressed artifacts.** Every piece of data — a source document, a calculation result, a finished report — is identified by the cryptographic hash of its content. Same content, same identity, always. This is how Git tracks source code and how Nix ensures reproducible builds. Applied to compliance: every number in a report has a stable, verifiable identity.

**Decision records.** When a process involves genuine judgment — an LLM classifying an expense, a human deciding which disclosures are applicable, an algorithm selecting emission factors — that choice is recorded as an immutable decision record. This enables two things: you can trace *why* a specific output was produced, and you can replay the process later to verify it produces the same result.

**Hash-chained event logs.** Every step in the process is recorded in an append-only log where each entry includes the cryptographic hash of the previous entry. Modifying any entry invalidates all subsequent hashes. The final hash — the "seal" — is a single value that commits to the entire process history. Any auditor can verify the chain independently, without trusting the system that produced it.

**Determinism classes.** Each operation in the pipeline is classified by its deterministic behavior: pure (always produces the same output from the same inputs), environment-dependent (deterministic given a pinned environment version), recordable (nondeterministic but the choice is recorded), or side-effecting (interacts with the outside world). This classification controls what can be cached, what must be re-executed, and what must be recorded — automatically.

These aren't theoretical concepts. They're proven in practice: [Git](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects), [Nix](https://nixos.org/guides/how-nix-works), [Bazel](https://bazel.build/remote/caching), and [Certificate Transparency](https://certificate.transparency.dev/) all use subsets of this approach. The combination — applied to regulatory compliance pipelines — is what's new.

## What this looks like in practice

Consider a Swedish SME that manufactures components for a larger customer bound by [CSRD](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022L2464). The customer needs ESG data from their supply chain. Today, the SME fills in a questionnaire. Tomorrow, with the right infrastructure:

The SME runs a compliance pipeline that ingests data from their accounting system, HR records, and energy bills. The pipeline validates, calculates, assesses applicability ("if applicable" per VSME), and generates a standardized report. Every step produces content-addressed artifacts. Every judgment call is recorded as a decision. The entire process is captured in a hash-chained event log.

The output is two things: (1) the report itself, and (2) a cryptographic seal proving how it was produced.

The customer receives the sealed package and can verify — independently, instantly, without special software — that the data was produced through a defined process and hasn't been altered. They can trace any number back to its source. They don't need to trust the SME's word; they can verify the math.

This is not a replacement for SAP or any enterprise system. It's a different layer — the provenance layer that sits beneath reporting platforms and provides what they currently cannot: verifiable evidence trails.

## Liminara

This is what I'm building. Liminara is an open-source runtime (Elixir/OTP, Apache 2.0) that implements the architecture described above. Five core concepts: Artifact (immutable, content-addressed data), Op (typed operation with a determinism class), Decision (recorded nondeterministic choice), Run (append-only event log + execution plan), Pack (domain-specific plugin providing operations and planning logic).

The core runtime is working — DAG execution with concurrent fan-out, decision recording, deterministic replay, content-addressed artifact storage, hash-chained event logs, crash recovery. Built on pure BEAM with zero external dependencies.

What's next: building domain-specific packs for regulatory compliance — starting with VSME for Swedish SMEs, then Digital Product Passports, then broader supply chain applications.

## Where I'm looking for help

I'm a systems architect with thirty years of experience in complex systems, but I'm not a regulatory compliance expert. What I have is an architecture that maps naturally to the technical demands these regulations create. What I need is domain expertise:

- **Sustainability reporting practitioners** who understand VSME, CSRD, and EU Taxonomy in practice — not just the text of the regulation, but the real workflows companies follow and where they struggle.
- **Supply chain professionals** who deal with DPP, EUDR, or Battery Regulation requirements and can help validate whether provenance-based evidence packages solve a real pain point.
- **SMEs facing ESG data requests** from larger customers who would be willing to pilot a VSME reporting pipeline.
- **Technology partners** interested in building compliance tooling on open-source provenance infrastructure.

If any of this resonates — whether you're deep in regulatory compliance, managing a supply chain, or building tools in this space — I'd welcome the conversation.

**Peter Bruinsma**
Proliminal AB | Sweden
[Email] | [LinkedIn] | [GitHub]

---

*Liminara is a Proliminal project. The core runtime is open source under Apache 2.0. Domain packs for specific regulations are in development.*

## References

**EU regulations cited:**

- ESPR / Digital Product Passport — [Regulation (EU) 2024/1781](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1781), in force July 2024. DPP registry expected mid-2026; battery passports mandatory February 2027.
- EU Deforestation Regulation — [Regulation (EU) 2023/1115](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1115), as revised by [Regulation (EU) 2025/2650](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32025R2650). Large operators comply December 2026.
- Battery Regulation — [Regulation (EU) 2023/1542](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R1542). Carbon footprint declaration required since February 2025; digital passport from February 2027.
- CBAM — [Regulation (EU) 2023/956](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32023R0956). Definitive phase since January 2026.
- EU AI Act — [Regulation (EU) 2024/1689](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689). Article 12 (record-keeping) enforceable August 2026.
- CSRD — [Directive (EU) 2022/2464](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022L2464). Wave 1 reporting active. Scope narrowed by [Omnibus simplification package](https://ec.europa.eu/commission/presscorner/detail/en/ip_25_842) (February 2025).
- VSME — [EFRAG Voluntary SME Standard](https://www.efrag.org/en/projects/vsme-standard/concluded). Commission recommendation adopted July 2025.

**Architectural references:**

- Certificate Transparency — [RFC 9162](https://www.rfc-editor.org/rfc/rfc9162), the reference architecture for publicly auditable hash-chained logs.
- JSON Canonicalization Scheme — [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785), deterministic JSON serialization for stable hashing across platforms.

---

## Implementation notes

*Page structure for Astro:*
- *URL: /provenance (or /compliance or /prove-it — your choice)*
- *No sidebar navigation needed — it reads as a single-flow essay*
- *Consider a subtle visual: the hash chain concept (events linked by hashes) could be a simple diagram*
- *The "Where I'm looking for help" section should have a prominent contact CTA*
- *Swedish translation: this should be translated, not just machine-translated. The regulatory terminology needs to be correct (VSME is already used in Swedish contexts; "hållbarhetsrapportering" for sustainability reporting; "värdekedjan" for value chain; "spårbarhet" for traceability)*
- *LinkedIn sharing: the page should have good Open Graph meta tags (title, description, image) for when it's shared*
- *Consider a PDF version for sharing in professional contexts*
