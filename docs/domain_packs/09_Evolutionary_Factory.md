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

---

## Appendix: Agentic Algorithm Engineering (AAE) — Adjacent Pattern

**Source:** [CHSZLab/AgenticAlgorithmEngineering](https://github.com/CHSZLab/AgenticAlgorithmEngineering), Christian Schulz, Heidelberg University (2025). Based on Sanders (2009) Algorithm Engineering methodology.

AAE deploys Claude Code as an autonomous performance engineer running an indefinite optimization loop: hypothesize → implement → benchmark → evaluate (keep/discard) → repeat. It is *not* a genetic algorithm — it uses **reasoned mutation** (LLM hypothesizes *why* a change should help) instead of random mutation.

### Relationship to this pack

| | Evolutionary Factory | AAE |
|---|---|---|
| **Search strategy** | Population-based (GA: mutation + crossover + selection) | Single-candidate, hypothesis-driven |
| **Candidate generation** | Random/guided mutation of population | LLM reasons about bottleneck, proposes targeted change |
| **Why it works** | Diversity explores the search space broadly | LLM's training data encodes known optimization techniques |
| **Weakness** | Expensive (many evaluations per generation) | Can get stuck in local optima (no population diversity) |
| **Memory** | Lineage in decision records (`decision.ga_step.v1`) | results.tsv + LLM context window |

They share the **generate → evaluate → select → iterate** loop. A hybrid combining GA-style population diversity with LLM-guided mutation (instead of random mutation) could outperform either alone.

### What AAE contributes to pack design

1. **Hypothesis as a structured decision record.** AAE requires every experiment to have a specific, falsifiable hypothesis with predicted direction and magnitude. This is more disciplined than "the LLM chose X." Liminara's decision records for `evo.propose` and `evo.select_mutate` should capture not just *what* was chosen but *why* — the hypothesis and prediction, not just the output.

2. **Correctness assertions as gate ops.** AAE checks invariants before benchmarking (valid partition, sorted output, finite loss). In Liminara terms, these are `pure` validation ops that gate the expensive `side_effecting` benchmark — saving compute when a mutation produces invalid output.

3. **results.tsv as a primitive event log.** AAE logs commit hash, metric, resource usage, status, and hypothesis per experiment. This is a hand-rolled, fragile version of Liminara's event log. It validates the pattern while showing what formalization gains: hash chaining, replay, caching, observation.

4. **The iteration pattern.** AAE's indefinite loop is exactly the pattern that Liminara's planned iteration primitive (FAUST-style unrolling, see `docs/research/dataflow_systems_and_liminara.md` Gap 6) would support — each iteration as observable nodes in the DAG rather than an opaque agent loop.

### Potential hybrid: AAE + Evolutionary Factory

Use the Evolutionary Factory's population-based search for diversity, but replace random mutation with AAE-style hypothesis-driven mutation. Each candidate in the population gets an LLM-generated hypothesis. The GA handles exploration (population diversity, crossover); the LLM handles exploitation (informed mutation). Decision records capture both the GA selection decisions and the LLM hypotheses.

This is not a current build target — it's a design direction to keep in mind when the iteration primitive exists.
