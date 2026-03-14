# Domain Pack: GA Sandbox (Toy Pack / Optimization Harness)

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `toy.ga_sandbox`

---

## 1. Purpose and value

Provide a generic evolutionary optimization harness: evolve candidate parameter vectors against a user-provided fitness evaluator.

Purpose: stress **dynamic graph expansion**, **massive caching reuse**, and **decision record lineage** (randomness + selection).

### Fit with the core runtime

GA loops map naturally to the run DAG: each candidate evaluation is an Op (or a sub-run) producing a fitness artifact.

### Non-goals

- Compete with full hyperparameter optimization suites out of the gate.
- Hide the evaluation function—packs should own evaluation semantics.

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

### Experiment Spec (`IR0`)

Search space, seed(s), constraints, evaluation budget, and objective(s).

**Artifact(s):**
- `ga.experiment_spec.v1`

### Population (`IR1`)

Population snapshot with genomes and metadata.

**Artifact(s):**
- `ga.population.v1`

### Fitness Results (`IR2`)

Per-candidate fitness + metrics + provenance links to evaluation artifacts.

**Artifact(s):**
- `ga.fitness_set.v1`

### Frontier / Best-of (`IR3`)

Pareto frontier or best candidate(s), plus explanation and lineage.

**Artifact(s):**
- `ga.frontier.v1`
- `ga.best_candidate.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`ga.init_population`** — *Nondeterministic but recordable*, *no side-effects*
  - Initialize population (seeded RNG); record seed/choices.
  - Inputs: `ga.experiment_spec.v1`
  - Outputs: `ga.population.v1`
- **`ga.evaluate_candidate`** — *Depends on evaluator*, *no side-effects*
  - Evaluate one candidate via a delegated evaluator Op or sub-run.
  - Inputs: `ga.candidate.v1`
  - Outputs: `ga.fitness.v1`
- **`ga.select_mutate`** — *Nondeterministic but recordable*, *no side-effects*
  - Selection + mutation/crossover; record RNG + parentage.
  - Inputs: `ga.population.v1`, `ga.fitness_set.v1`
  - Outputs: `ga.population.v1`
- **`ga.summarize`** — *Pure deterministic*, *no side-effects*
  - Compute frontier / best-of aggregates.
  - Inputs: `ga.fitness_set.v1`
  - Outputs: `ga.frontier.v1`, `ga.best_candidate.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **GA randomness + selection**: Seeds, selected parents, mutation deltas.
  - Stored as: `decision.ga_step.v1`
  - Used for: Exact replay of evolutionary trajectory.
- **Optional human steering**: Pin candidates, adjust constraints mid-run.
  - Stored as: `decision.override.v1`
  - Used for: Interactive optimization.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Population viewer (histograms, diversity metrics).
- Lineage browser (which parents produced this candidate).
- Pareto frontier view.
- Budget/cost dashboard (token + compute).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Candidate evaluator is pluggable: can call other domain-pack ops (e.g., simulation epoch, build/test, ruleset evaluation).
- Parallel execution across nodes for candidate eval.

---

## 8. MVP plan (incremental, testable)

- Support numeric vectors and simple mutation/crossover.
- Provide a reference evaluator (e.g., optimize a synthetic function).
- Parallel candidate eval + caching.
- Checkpoint population each generation.

---

## 9. Should / shouldn’t

### Should

- Make candidate eval idempotent and cache-friendly.
- Treat each generation as a checkpoint artifact (resume/replay).

### Shouldn’t

- Don’t embed large per-candidate outputs in the GA state; store artifacts and reference by hash.

---

## 10. Risks and mitigations

- **Risk:** Exploding state and storage
  - **Why it matters:** GA generates many candidates and artifacts.
  - **Mitigation:** Retention policies; store summaries by default; sample full traces; compress.
- **Risk:** Fitness function nondeterminism
  - **Why it matters:** Breaks caching and comparability.
  - **Mitigation:** Require evaluator determinism declaration; pin seeds; record decisions.

---

## Appendix: Related work and competitive tech

- [Nevergrad](https://facebookresearch.github.io/nevergrad/) — Derivative-free optimization library; ask/tell.
- [Ray Tune PBT guide](https://docs.ray.io/en/latest/tune/examples/pbt_guide.html) — Population-based optimization at scale.
- [Optuna](https://optuna.org/) — Hyperparameter optimization framework.
- [DEAP](https://deap.readthedocs.io/en/master/) — Evolutionary algorithms in Python.
