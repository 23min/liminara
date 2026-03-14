# Domain Pack: Evolutionary Software Factory Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `evolutionary_factory`

---

## 1. Purpose and value

Use evolutionary methods to improve prompts, tool policies, agent workflows, and evaluation harnesses over time — turning the runtime into an “evolution engine” for agentic software factories.

This is *not* about optimizing the runner itself; it’s about optimizing strategies and programs executed on top of it.

### Fit with the core runtime

Maps directly to GA Sandbox + decision records + evaluation runs. The core substrate stays unchanged; this pack is a structured use of it.

### Non-goals

- Assume unlimited LLM budget. Must support cheap models and offline evaluation.
- Run uncontrolled self-modifying behavior without audit.

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

### Optimization Spec (`IR0`)

Population size, mutation operators, evaluation suite, constraints and cost limits.

**Artifact(s):**
- `evo.spec.v1`

### Candidate Programs/Prompts (`IR1`)

Prompt/program candidates (often DSL artifacts).

**Artifact(s):**
- `evo.candidate_set.v1`

### Evaluation Results (`IR2`)

Per-candidate scores across test suite; cost and safety metrics included.

**Artifact(s):**
- `evo.eval_set.v1`

### Selected Best + Frontier (`IR3`)

Best candidates and lineage; publishable recommendations.

**Artifact(s):**
- `evo.best.v1`
- `evo.frontier.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`evo.propose`** — *Nondeterministic but recordable*, *no side-effects*
  - Generate candidate prompts/programs (possibly via LLM).
  - Inputs: `evo.spec.v1`
  - Outputs: `evo.candidate_set.v1`
- **`evo.evaluate`** — *Deterministic w/ pinned env*, *no side-effects*
  - Run evaluation harness; produce scores + artifacts.
  - Inputs: `evo.candidate_set.v1`
  - Outputs: `evo.eval_set.v1`
- **`evo.select_mutate`** — *Nondeterministic but recordable*, *no side-effects*
  - Selection and mutation/crossover.
  - Inputs: `evo.eval_set.v1`
  - Outputs: `evo.candidate_set.v1`
- **`evo.summarize`** — *Pure deterministic*, *no side-effects*
  - Compute best/frontier; produce report.
  - Inputs: `evo.eval_set.v1`
  - Outputs: `evo.best.v1`, `evo.frontier.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Evolution steps**: Selection and mutation decisions, seeds, and candidate lineage.
  - Stored as: `decision.ga_step.v1`
  - Used for: Replay and audit.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Leaderboard and frontier charts.
- Candidate diff view (prompt/program diffs).
- Evaluation suite explorer (where candidates fail).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Evaluation harness executors (often reusing Software Factory or Radar or Simulation packs).
- LLM executor (cheap model) + offline eval executor.

---

## 8. MVP plan (incremental, testable)

- Start with optimizing a small prompt in Radar (e.g., cluster labeling).
- Add offline evaluation set and cost metrics.
- Then evolve a small DSL policy (tool allowlist rules).

---

## 9. Should / shouldn’t

### Should

- Include safety metrics in fitness (not just quality).
- Bound cost and require human review before adopting winners.

### Shouldn’t

- Don’t let evolved artifacts auto-deploy without a gate.

---

## 10. Risks and mitigations

- **Risk:** Evaluation overfitting
  - **Why it matters:** Optimizing for the benchmark harms generalization.
  - **Mitigation:** Holdout sets; rotating suites; adversarial tests.
- **Risk:** Cost blowups
  - **Why it matters:** Evolution uses many evaluations.
  - **Mitigation:** Cheap models, caching, offline evals, early stopping.

---

## Appendix: Related work and competitive tech

- [OPRO paper](https://arxiv.org/abs/2309.03409) — LLMs as optimizers.
- [EvoPrompt paper](https://arxiv.org/abs/2309.08532) — Evolutionary prompt optimization.
- [GAAPO paper (Frontiers 2025)](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2025.1613007/full) — GA applied to prompt optimization.
- [Nevergrad](https://facebookresearch.github.io/nevergrad/) — Ask/tell optimization patterns.
