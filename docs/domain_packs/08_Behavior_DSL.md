# Domain Pack: Behavior DSL Pack (LLM-authored programs as data)

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `behavior_dsl`

---

## 1. Purpose and value

Provide a safe, inspectable DSL for expressing rules/behaviors/algorithms that LLMs can generate and humans can review.

This pack can be reused by Simulation, Ruleset Lab, Radar classification, and even parts of the Software Factory (policy checks).

### Fit with the core runtime

The runtime already wants compiler-shaped passes; DSL fits perfectly: text → AST → checked IR → execute/compile.

### Non-goals

- Execute arbitrary Elixir code from LLM output.
- Support full Turing completeness in v0.

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

### DSL Source (`IR0`)

User/LLM-provided program text plus schema version.

**Artifact(s):**
- `dsl.source.v1`

### AST (`IR1`)

Parsed AST with source spans for diagnostics.

**Artifact(s):**
- `dsl.ast.v1`

### Checked AST (`IR2`)

Type-checked, bounded, safe AST.

**Artifact(s):**
- `dsl.checked.v1`

### Executable Form (optional) (`IR3`)

Compiled BEAM module or Wasm binary for faster/sandboxed execution.

**Artifact(s):**
- `dsl.beam_bin.v1`
- `dsl.wasm.v1`

### Evaluation Result (`IR4`)

Result values + traces + cost counters.

**Artifact(s):**
- `dsl.eval_result.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`dsl.parse`** — *Pure deterministic*, *no side-effects*
  - Parse DSL source to AST.
  - Inputs: `dsl.source.v1`
  - Outputs: `dsl.ast.v1`
- **`dsl.check`** — *Pure deterministic*, *no side-effects*
  - Type/bounds check; reject unsafe programs.
  - Inputs: `dsl.ast.v1`
  - Outputs: `dsl.checked.v1`
- **`dsl.compile_wasm`** — *Deterministic w/ pinned env*, *no side-effects*
  - Compile checked AST to Wasm (sandbox).
  - Inputs: `dsl.checked.v1`
  - Outputs: `dsl.wasm.v1`
- **`dsl.eval`** — *Pure deterministic*, *no side-effects*
  - Evaluate checked program against inputs; bounded steps.
  - Inputs: `dsl.checked.v1`, `dsl.inputs.v1`
  - Outputs: `dsl.eval_result.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **LLM program generation**: The generated DSL program and rationale.
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay; safety review; diff.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Source + AST viewer (with diagnostics).
- Step-trace viewer for evaluation.
- Sandbox status (Wasm vs interpreter).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Interpreter in BEAM for v0.
- Optional Wasm executor (Wasmex) for sandboxing.
- Optional external compiler via ports.

---

## 8. MVP plan (incremental, testable)

- Define a tiny expression + rule DSL (if/else, comparisons, arithmetic, whitelisted host calls).
- Parse + check + eval in BEAM.
- Add Wasm compilation later if needed.

---

## 9. Should / shouldn’t

### Should

- Make programs non-Turing complete or at least bounded (no unbounded loops).
- Treat all host calls as explicit, typed, and metered.

### Shouldn’t

- Don’t use `Code.eval_string`/`Code.compile_string` on untrusted input.

---

## 10. Risks and mitigations

- **Risk:** DSL scope explosion
  - **Why it matters:** A DSL can become a programming language and absorb infinite time.
  - **Mitigation:** Keep core small; add host primitives instead of language features.
- **Risk:** Sandbox escape (if compiling)
  - **Why it matters:** Generated code can exploit runtime bugs.
  - **Mitigation:** Prefer Wasm sandbox or ports; pin versions; fuzz/test.

---

## Appendix: Related work and competitive tech

- [JsonLogic](https://jsonlogic.com/) — Safe rules-as-data inspiration.
- [CEL](https://cel.dev/) — Safe expression language inspiration.
- [Wasmex](https://hexdocs.pm/wasmex/Wasmex.html) — Wasm runtime.
- [Elixir Code warnings](https://hexdocs.pm/elixir/Code.html) — Avoid eval/compile on untrusted input.
