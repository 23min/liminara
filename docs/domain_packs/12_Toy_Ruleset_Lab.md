# Domain Pack: Ruleset Lab (Toy Pack / Policy & Rules)

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `toy.ruleset_lab`

---

## 1. Purpose and value

Evaluate a dataset/config against a versioned ruleset to produce a compliance report.

Purpose: validate **rules-as-data**, **version pinning**, **selective refresh**, and **human overrides** in the core runtime.

### Fit with the core runtime

Rulesets are a natural IR: parse → validate → evaluate → report; perfect for replay/diff.

### Non-goals

- Full enterprise GRC suite.
- A universal rules language—start small with one safe DSL.

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

### Input Facts (`IR0`)

Normalized dataset/config facts to be evaluated.

**Artifact(s):**
- `rules.facts.v1`

### Ruleset (`IR1`)

Versioned ruleset text + metadata.

**Artifact(s):**
- `rules.ruleset.v1`

### Checked Rules (`IR2`)

Parsed + validated rules AST (safe, bounded).

**Artifact(s):**
- `rules.checked_ast.v1`

### Evaluation Result (`IR3`)

Violations, passes, severities, and evidence references to facts.

**Artifact(s):**
- `rules.eval_result.v1`

### Compliance Report (`IR4`)

Human-readable report + machine-readable summary.

**Artifact(s):**
- `rules.report_md.v1`
- `rules.report_json.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`rules.normalize_facts`** — *Pure deterministic*, *no side-effects*
  - Normalize raw inputs into facts.
  - Inputs: `rules.raw_input.v1`
  - Outputs: `rules.facts.v1`
- **`rules.parse_validate`** — *Pure deterministic*, *no side-effects*
  - Parse and validate ruleset into checked AST.
  - Inputs: `rules.ruleset.v1`
  - Outputs: `rules.checked_ast.v1`
- **`rules.evaluate`** — *Pure deterministic*, *no side-effects*
  - Evaluate checked rules over facts.
  - Inputs: `rules.facts.v1`, `rules.checked_ast.v1`
  - Outputs: `rules.eval_result.v1`
- **`rules.render_report`** — *Pure deterministic*, *no side-effects*
  - Render report artifacts.
  - Inputs: `rules.eval_result.v1`
  - Outputs: `rules.report_md.v1`, `rules.report_json.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Rule exceptions/waivers**: Human decisions to waive specific violations with rationale and expiry.
  - Stored as: `decision.waiver.v1`
  - Used for: Replay and audit.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Ruleset editor with validation diagnostics.
- Violation explorer (evidence links to facts).
- Waiver workflow (approve/expire).
- Run diff: 'what changed due to ruleset change vs facts change'.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Interpreter (in-BEAM) for a small safe DSL (JsonLogic-like) OR external (OPA/CEL) evaluator via ports.

---

## 8. MVP plan (incremental, testable)

- Pick one safe rules DSL (JsonLogic-like).
- Validate AST bounds (depth, nodes).
- Generate report + diff runs.
- Waiver decision record + selective refresh.

---

## 9. Should / shouldn’t

### Should

- Make rule evaluation deterministic and side-effect free.
- Record waivers and overrides as decision records.
- Keep rule language safe (non-Turing complete if possible).

### Shouldn’t

- Don’t eval arbitrary Elixir from rules text.
- Don’t allow rules to call network/tools directly.

---

## 10. Risks and mitigations

- **Risk:** Rules become a programming language
  - **Why it matters:** Hard to validate/sandbox; hard to explain.
  - **Mitigation:** Prefer non-Turing-complete DSL; bounded evaluation; strong types.
- **Risk:** Policy drift
  - **Why it matters:** Ruleset updates change outcomes silently.
  - **Mitigation:** Version pinning; mandatory diff review for ruleset bumps.

---

## Appendix: Related work and competitive tech

- [Open Policy Agent (OPA)](https://openpolicyagent.org/docs) — Policy-as-code engine (Rego).
- [Drools](https://docs.drools.org/latest/drools-docs/drools/rule-engine/index.html) — Rule engine / BRMS.
- [JsonLogic](https://jsonlogic.com/) — Rules-as-data DSL.
- [CEL](https://cel.dev/) — Safe expression language; embeddable.
