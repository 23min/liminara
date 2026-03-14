# EU AI Act — Article 12: What It Actually Says and Means

**Date:** 2026-03-14
**Context:** Plain-language summary of Article 12 for the Liminara team. Not legal advice. Based on the official text of Regulation (EU) 2024/1689.

---

## The Short Version

**Article 12 says:** If you deploy a high-risk AI system in the EU, it must technically be capable of automatically recording what it did, so that you can explain any output after the fact.

**The enforcement date:** 2 August 2026. That is 5 months away.

**The fine for non-compliance:** Up to EUR 15 million or 3% of global annual revenue, whichever is higher.

---

## The Exact Text

> **Article 12 — Record-keeping**
>
> **Paragraph 1:**
> "High-risk AI systems shall technically allow for the automatic recording of events (logs) over the lifetime of the system."
>
> **Paragraph 2:**
> "In order to ensure a level of traceability appropriate to the intended purpose of the system, logging capabilities shall enable the recording of events relevant for:
> (a) identifying situations that may result in the high-risk AI system presenting a risk within the meaning of Article 79(1) or in a substantial modification;
> (b) facilitating the post-market monitoring referred to in Article 72; and
> (c) monitoring the operation of high-risk AI systems referred to in Article 26(5)."
>
> **Paragraph 3** *(only for biometric identification systems):*
> "For high-risk AI systems referred to in point 1(a) of Annex III, the logging capabilities shall provide, at a minimum:
> (a) recording of the period of each use of the system (start date and time and end date and time of each use);
> (b) the reference database against which input data has been checked by the system;
> (c) the input data for which the search has led to a match;
> (d) the identification of the natural persons involved in the verification of the results."

Source: [EU AI Act Article 12](https://www.euaiact.com/article/12), Regulation (EU) 2024/1689

---

## What It Means in Practice

### Paragraph 1: "Automatic recording"

The word **automatic** is doing a lot of work here. It rules out:
- Writing logs manually after the fact
- Logging only when something goes wrong
- Logging only on request from an auditor
- Logs that require human intervention to produce

It requires that every time the AI system operates, a log is produced without anyone having to do anything. The logging must be built into the system, not bolted on later.

The phrase **"technically allow for"** is interesting — it means the capability must exist in the system itself, not in an external tool that may or may not be connected. An AI system that only logs when monitored by a third-party service does not satisfy Article 12.

### Paragraph 2: What the logs must capture

The three sub-points define the *purpose* of the logs, not a specific format. This is deliberate — the regulation does not mandate a data schema. It mandates that the logs must be sufficient to:

**(a) Identify risk situations:** Given a log, you must be able to identify when the system produced a potentially harmful output, and whether the system has been substantially modified since deployment. In practice: you need to be able to trace a specific output back to the specific inputs and model version that produced it.

**(b) Facilitate post-market monitoring:** After the system is deployed, the company (and the EU) has an obligation to monitor whether it continues to work safely. Logs are the data source for this monitoring. In practice: logs must be retained long enough and be structured enough to run analyses over time ("is the system's behavior drifting?").

**(c) Monitor operation:** The deployer (the company using the AI) must be able to monitor the system while it is running. In practice: logs must be accessible in near-real-time, not just archived.

### What "traceability" means

The law uses the word *traceability* — the ability to trace an output backward through the system to its causes. For an AI system, this means:

- Given an output (a decision, a recommendation, a classification), you can identify:
  - What input data was used
  - Which model version processed it
  - What prompt or configuration was in effect
  - When it happened
  - Who or what triggered it

This is the core compliance requirement. **Content-addressed artifacts + decision records + an event log is the architecture that satisfies traceability.**

### Tamper-resistance (implied, not explicit)

Article 12 does not use the word "tamper-resistant," but the *purpose* of the logs (audit, post-market monitoring, risk identification) implies it. A log that can be modified after the fact is not useful for audit — it proves nothing. Regulatory guidance and good practice treat tamper-resistance as a requirement. Hash-chained event logs (where each event cryptographically commits to the previous one) are the standard technical approach.

### Log retention

Article 12 itself does not specify a retention period. However:
- Article 19 (Automatically Generated Logs) specifies that logs must be kept for **at least 6 months** for limited-purpose systems
- Longer retention may be required depending on the risk category and the deployer's obligation
- The safe approach: retain all logs for at least 3 years, keep compliance-critical runs indefinitely (pinned)

---

## Who Does Article 12 Apply To?

### Only high-risk AI systems

Not every AI system. Only those classified as **high-risk** under the EU AI Act. The classification comes from two sources:

**Annex I:** AI used in safety-critical products already regulated by EU law (medical devices, aircraft, machinery, etc.). If an existing EU product regulation applies, and AI is embedded in that product, it's high-risk.

**Annex III:** A list of 8 specific use-case categories where AI is always considered high-risk:

| Category | Examples |
|----------|---------|
| **1. Biometrics** | Facial recognition, fingerprint matching, emotion recognition in public spaces |
| **2. Critical infrastructure** | AI managing energy grids, water systems, road traffic, digital infrastructure |
| **3. Education & training** | AI deciding school admissions, grading exams, monitoring students during tests |
| **4. Employment** | CV screening, interview assessment, performance monitoring, promotion/termination decisions |
| **5. Essential services** | Credit scoring, insurance risk assessment, social benefit eligibility, healthcare triage |
| **6. Law enforcement** | Criminal risk profiling, evidence reliability assessment, crime prediction, suspect identification |
| **7. Migration & border control** | Asylum application assessment, visa risk scoring, border surveillance |
| **8. Justice & democracy** | AI applying law to facts in court, AI influencing elections or referendums |

Source: [EU AI Act Annex III](https://artificialintelligenceact.eu/annex/3/)

### The threshold question

An AI system in one of these categories is high-risk *unless* it does not pose a significant risk to health, safety, or fundamental rights. There is a self-assessment mechanism, but regulators are expected to scrutinize these assessments. In practice: if your AI makes decisions that affect individuals in these categories, assume it is high-risk.

### Who is responsible?

- **Providers** (those who develop the AI system) must build Article 12 logging capability into the system
- **Deployers** (those who use the AI system in practice) must ensure logs are actually retained and accessible
- Both parties have obligations — compliance is not just the developer's problem or just the deployer's problem

---

## Common Misconceptions

**"We already use CloudWatch / Datadog / LangSmith, we're compliant."**
Observability tools log metrics, traces, and errors. They do not, by default, produce tamper-resistant content-addressed records that trace an AI output back to its exact inputs and model version. They are not Article 12 compliant. They may be part of a compliance solution, but they are not sufficient on their own.

**"Our AI doesn't make decisions, it only makes recommendations."**
The EU AI Act covers systems that *influence* decisions, not just make them autonomously. A system that produces a credit risk score that a human then acts on is high-risk. The human in the loop does not reduce the risk classification.

**"Article 12 only applies after August 2026."**
The enforcement date is August 2026, but Article 12 applies to systems *deployed* after that date. Systems deployed before August 2026 have a transition period (with possible exceptions for systems under an existing product regulation). New AI deployments after August 2026 must be compliant from day one.

**"We're a small company, fines won't reach us."**
The fine is the *higher* of EUR 15 million or 3% of global annual revenue. For a startup with EUR 1M revenue, the cap is EUR 15M — which could be existential. For a company with EUR 1B revenue, the cap is EUR 30M. The regulation does not have SME carve-outs for the high-risk category.

**"Article 12 only applies in the EU."**
It applies to AI systems whose *outputs are used in the EU*, regardless of where the developer or deployer is located. A US company deploying an AI hiring tool used by EU employers is subject to the regulation.

---

## What Compliance Actually Looks Like

A compliant high-risk AI system, from an Article 12 perspective, must be able to answer — automatically, without human intervention — the following questions about any past operation:

1. When did this operation occur? (timestamp, start, end)
2. What was the input? (the exact data the system processed)
3. Which version of the system processed it? (model version, configuration version)
4. What was the output? (the decision, recommendation, or classification)
5. Has the log been modified since it was written? (tamper-evidence)
6. Can I retrieve this log in 6 months? (retention)

If a system cannot answer all six questions about any past operation, it is not Article 12 compliant.

---

## How Liminara Satisfies Article 12

| Article 12 requirement | Liminara mechanism |
|---|---|
| Automatic logging | Append-only event log produced for every run without human action |
| Tamper-resistant | Hash-chained event log (each event contains hash of previous event) + content-addressed artifacts |
| Identify input | Every artifact is SHA-256 hashed; inputs to every op are recorded with their hashes |
| Model version | Decision records capture model ID, model version, prompt hash, response |
| Identify risk situations | Determinism class flags every op as pure / pinned_env / recordable / side_effecting |
| Post-market monitoring | Event log is queryable; compliance report generated per run |
| Monitor operation | Observation layer provides real-time event stream |
| 6-month retention | Filesystem event files and artifact blobs retained by configurable policy |

The key property: Liminara satisfies Article 12 as an **architectural consequence**, not as a feature. The event log, content-addressed artifacts, and decision records exist for reproducibility reasons — compliance is a free side effect.

See [07_Compliance_Layer.md](07_Compliance_Layer.md) for how the compliance layer integrates with existing systems that are not built on Liminara.

---

## Related Articles Worth Knowing

**Article 9 (Risk management):** High-risk AI systems must have a continuous risk management process throughout their lifecycle. Article 12 logs feed this process.

**Article 11 (Technical documentation):** High-risk AI systems must maintain technical documentation describing the system, its purpose, training data, performance metrics, and limitations. Article 12 logs are part of this documentation.

**Article 13 (Transparency):** High-risk AI systems must be sufficiently transparent that deployers can interpret their outputs. Liminara's provenance chain enables this interpretation.

**Article 14 (Human oversight):** High-risk AI systems must be designed to allow effective human oversight. Liminara's gate system (human approval ops) is the architectural implementation of Article 14.

**Article 17 (Quality management):** Providers must have a quality management system covering logging and post-market monitoring. Article 12 logs are the technical foundation.

**Article 19 (Automatically generated logs):** Deployers must keep logs automatically generated under Article 12 for at least 6 months, or longer as required by applicable law or for investigation of incidents.

Sources:
- [EU AI Act Article 12 — euaiact.com](https://www.euaiact.com/article/12)
- [EU AI Act Article 12 — EU AI Act Service Desk](https://ai-act-service-desk.ec.europa.eu/en/ai-act/article-12)
- [EU AI Act Annex III — artificialintelligenceact.eu](https://artificialintelligenceact.eu/annex/3/)
- [Article 12 compliance guide — isms.online](https://www.isms.online/iso-42001/eu-ai-act/article-12/)
- [EU AI Act: Best Practices for Monitoring and Logging](https://medium.com/@axel.schwanke/compliance-under-the-eu-ai-act-best-practices-for-monitoring-and-logging-e098a3d6fe9d)
- [EU AI Act High-Risk Requirements — Dataiku](https://www.dataiku.com/stories/blog/eu-ai-act-high-risk-requirements)
