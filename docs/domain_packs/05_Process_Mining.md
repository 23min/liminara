# Domain Pack: Process Mining Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `process_mining`

---

## 1. Purpose and value

Ingest event logs (XES/OCEL), discover process models, analyze variants/bottlenecks, and perform conformance checking—then export findings as artifacts.

Complements your interest in FlowTime and complex flows by grounding models in observed data.

### Fit with the core runtime

Process mining is inherently IR+artifact heavy: event log → cleaned log → discovered model → reports; excellent for provenance and replay.

### Non-goals

- Compete with enterprise SaaS process mining suites initially.
- Implement mining algorithms from scratch in BEAM.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is “agentic”). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Raw Event Log Snapshot (`IR0`)

Input log as XES/OCEL files + metadata.

**Artifact(s):**
- `pm.eventlog_raw.v1`

### Normalized Event Log (`IR1`)

Parsed, cleaned, filtered log; case/object mapping decisions made explicit.

**Artifact(s):**
- `pm.eventlog_norm.v1`
- `pm.mapping_decisions.v1`

### Discovered Models (`IR2`)

Process model(s): Petri net/BPMN/DFG or object-centric variants.

**Artifact(s):**
- `pm.model.v1`

### Analysis Results (`IR3`)

Variants, bottlenecks, performance stats, conformance deviations.

**Artifact(s):**
- `pm.analysis.v1`
- `pm.conformance.v1`

### Reports & Exports (`IR4`)

Interactive or static reports; export to FlowTime model (optional).

**Artifact(s):**
- `pm.report_md.v1`
- `pm.export_flow.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`pm.parse_log`** — *Deterministic w/ pinned env*, *no side-effects*
  - Parse XES/OCEL into normalized IR.
  - Inputs: `pm.eventlog_raw.v1`
  - Outputs: `pm.eventlog_norm.v1`
- **`pm.discover_model`** — *Deterministic w/ pinned env*, *no side-effects*
  - Run mining algorithm (external python/ProM); produce model artifact.
  - Inputs: `pm.eventlog_norm.v1`
  - Outputs: `pm.model.v1`
- **`pm.analyze`** — *Pure deterministic*, *no side-effects*
  - Compute variants, bottlenecks, stats.
  - Inputs: `pm.eventlog_norm.v1`, `pm.model.v1`
  - Outputs: `pm.analysis.v1`, `pm.conformance.v1`
- **`pm.render_report`** — *Pure deterministic*, *no side-effects*
  - Render report artifacts.
  - Inputs: `pm.analysis.v1`
  - Outputs: `pm.report_md.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Case/object mapping decisions**: How to define 'case' in multi-entity logs; filtering choices.
  - Stored as: `decision.mapping.v1`
  - Used for: Replay and reproducibility of analyses.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Variant explorer and bottleneck heatmaps.
- Object-centric trace viewer (if OCEL).
- Conformance deviation drilldown.
- Export preview to FlowTime.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Python executor running PM4Py (recommended).
- Optional ProM integration (Java) via ports.

---

## 8. MVP plan (incremental, testable)

- Ingest XES and run one discovery algorithm via PM4Py.
- Compute basic throughput/bottleneck stats.
- Render report + A2UI explorer for variants.

---

## 9. Should / shouldn’t

### Should

- Keep mapping decisions explicit and persisted.
- Prefer deterministic algorithms or record random seeds.

### Shouldn’t

- Don’t bake 'case notion' into the core; it’s domain-specific.

---

## 10. Risks and mitigations

- **Risk:** Huge logs
  - **Why it matters:** Event logs can be big; parsing and analysis can be expensive.
  - **Mitigation:** Chunking; sampling; external compute; store only derived views by default.
- **Risk:** Ambiguity of case definition
  - **Why it matters:** Different case definitions produce different models.
  - **Mitigation:** Make mapping a first-class decision record; provide A2UI exploration.

---

## Appendix: Related work and competitive tech

- [XES standard (v1.1 PDF)](https://www.xes-standard.org/_media/xes%3Axesstandarddefinition-1.1.pdf) — Event log interchange format.
- [OCEL 2.0 specification (PDF)](https://ocel-standard.org/2.0/ocel20_specification.pdf) — Object-centric event log standard.
- [PM4Py docs](https://pm4py-source.readthedocs.io/en/stable/) — Python process mining library.
- [ProM](https://promtools.org/) — Java process mining framework.
- [Celonis](https://www.celonis.com/) — Enterprise process mining.
- [Apromore](https://apromore.org/) — Open-source process mining platform (plus commercial).
