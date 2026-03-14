# Domain Pack: House Compiler Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `house_compiler`

---

## 1. Purpose and value

Transform a design (e.g., SketchUp model) into manufacturable outputs: analysis, structural checks, drawings/PDFs, NC/CNC, BOMs, and compliance artifacts.

This is a flagship “compiler” pack: it requires deep IR discipline, ruleset/version control, and safe heavy compute isolation.

### Fit with the core runtime

Directly matches the brief’s 'compiler passes' model and pushes the runtime on determinism, external tool pinning, and multi-output artifacts.

### Non-goals

- Replace full BIM suites in v0.
- Achieve perfect structural compliance without an explicit ruleset and validation strategy.

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

### Design Input Snapshot (`IR0`)

Input model snapshot (SKP/GLTF/etc), metadata, and ruleset references.

**Artifact(s):**
- `house.design_snapshot.v1`
- `house.ruleset_ref.v1`

### Semantic Building Model (`IR1`)

Typed model: spaces, walls, openings, load paths, materials, constraints.

**Artifact(s):**
- `house.semantic_model.v1`

### Structural / Simulation Results (`IR2`)

FEA/structural checks and derived constraints with evidence.

**Artifact(s):**
- `house.structural_report.v1`

### Manufacturing Model (`IR3`)

Framing plans, cut lists, panelization, joint specs.

**Artifact(s):**
- `house.manufacturing_model.v1`
- `house.bom.v1`

### Outputs (`IR4`)

Drawings (PDF), NC files, BOM exports, compliance bundle.

**Artifact(s):**
- `house.drawings_pdf.v1`
- `house.nc_bundle.v1`
- `house.compliance_bundle.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`house.ingest_design`** — *Deterministic w/ pinned env*, *side-effect*
  - Import and snapshot the design file; extract raw geometry.
  - Inputs: `house.design_ref.v1`
  - Outputs: `house.design_snapshot.v1`
- **`house.semanticize`** — *Deterministic w/ pinned env*, *no side-effects*
  - Convert geometry to semantic model; apply basic rules.
  - Inputs: `house.design_snapshot.v1`
  - Outputs: `house.semantic_model.v1`
- **`house.structural_check`** — *Deterministic w/ pinned env*, *no side-effects*
  - Run structural analysis in external solver; record logs.
  - Inputs: `house.semantic_model.v1`, `house.ruleset_ref.v1`
  - Outputs: `house.structural_report.v1`
- **`house.manufacture_plan`** — *Pure deterministic*, *no side-effects*
  - Generate manufacturing model + BOM from semantic + structural constraints.
  - Inputs: `house.semantic_model.v1`, `house.structural_report.v1`
  - Outputs: `house.manufacturing_model.v1`, `house.bom.v1`
- **`house.render_outputs`** — *Deterministic w/ pinned env*, *no side-effects*
  - Render PDFs/NC outputs with pinned toolchain.
  - Inputs: `house.manufacturing_model.v1`
  - Outputs: `house.drawings_pdf.v1`, `house.nc_bundle.v1`
- **`house.publish`** — *Side-effecting*, *side-effect*
  - Deliver outputs to customer/workspace; gated.
  - Inputs: `house.compliance_bundle.v1`
  - Outputs: `house.delivery_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Design ambiguity resolution**: If the design is under-specified, decisions about defaults or inferred constraints.
  - Stored as: `decision.override.v1`
  - Used for: Replay and audit.
- **Optimization trajectory (optional)**: GA/optimizer choices if optimizing layout/material/cost.
  - Stored as: `decision.ga_step.v1`
  - Used for: Replay of optimization.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- IR viewer: semantic model browser (elements, constraints).
- Structural report viewer with traceability to elements and ruleset clauses.
- BOM explorer and diff across revisions.
- Output preview (PDF) + publish gate.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Geometry ingestion/translation toolchain (likely external).
- Structural solver (external, potentially licensed).
- Rendering toolchain for drawings (external, pinned).
- Optional optimizer executor (GA).

---

## 8. MVP plan (incremental, testable)

- Ingest a simple design format and produce a semantic model for a constrained subset.
- Generate a BOM + a simple PDF drawing.
- Introduce structural checks later as an external op with pinned solver.
- Add GA optimization only after correctness baselines.

---

## 9. Should / shouldn’t

### Should

- Treat rulesets as versioned inputs (first-class artifacts).
- Make every derived decision traceable back to inputs and ruleset clauses.
- Isolate heavy/native code out of the control plane VM.

### Shouldn’t

- Don’t let the LLM “invent” structural decisions without recording and review.
- Don’t hide solver versions/parameters—pin and record them.

---

## 10. Risks and mitigations

- **Risk:** Geometry correctness
  - **Why it matters:** Small geometry bugs can invalidate downstream manufacturing outputs.
  - **Mitigation:** Strong validation; golden fixtures; incremental IR validation; visualization in A2UI.
- **Risk:** Ruleset drift and compliance liability
  - **Why it matters:** Changing rules changes outputs; can become contractual.
  - **Mitigation:** Strict version pinning; audit logs; require human approval for ruleset updates.
- **Risk:** Compute/toolchain complexity
  - **Why it matters:** Many external tools must be managed and pinned.
  - **Mitigation:** Executor abstraction; containerization; environment fingerprints and verify replay.

---

## Appendix: Related work and competitive tech

- [SketchUp](https://www.sketchup.com/) — Design tool (input).
- [SLSA provenance](https://slsa.dev/spec/v1.0/provenance) — Useful for provenance thinking.
- [Bazel hermeticity](https://bazel.build/basics/hermeticity) — Hermetic build thinking for toolchain pinning.
