# Pack Design and Development Guide

How to design, build, and harden a Liminara pack.
Last updated: 2026-04-08.

---

## Purpose

This guide exists because pack knowledge is currently spread across architecture docs, analysis notes, milestone specs, and live code. It collects the practical rules for pack authors in one place.

Use this guide when:
- designing a new pack
- deciding whether logic belongs in the runtime or in the pack
- adding pack-owned persistent data
- defining ops and plans
- deciding how warnings, decisions, replay, and side effects should behave

This guide distinguishes three kinds of truth:
- **Validated today**: behavior that exists in live code now
- **Decided next**: approved direction already established in active decisions or architecture docs
- **Directional thesis**: plausible future direction, not yet approved

---

## What a pack is

**Validated today**

A pack is the unit of domain composition in Liminara. The pack provides:
- identity
- version
- op modules
- a plan builder

The live behavior is defined in `Liminara.Pack`:

```elixir
defmodule Liminara.Pack do
  @callback id() :: atom()
  @callback version() :: String.t()
  @callback ops() :: [module()]
  @callback plan(input :: term()) :: Liminara.Plan.t()
end
```

The runtime provides execution, replay, caching, event logs, stores, supervision, and observation.

**Decided next**

Some pack-facing surfaces are evolving beyond this minimal behavior. In particular:
- op modules are converging on canonical `execution_spec/0`
- packs may have explicit reference-data initialization again as a stable surface
- warning and degraded-success handling is being standardized

Do not treat those future surfaces as fully live unless the runtime path already consumes them.

---

## Runtime vs Pack Ownership

This boundary matters more than almost anything else. Most semantic drift in the codebase has come from blurring runtime-owned values with pack-owned values.

### Runtime owns

**Validated today / decided next**

The runtime owns:
- run identity
- replay provenance
- execution timestamps
- scheduling context
- artifact storage
- run event logs
- decision persistence
- terminal run status
- warning transport and operator-facing observation surfaces

If a value represents runtime identity, the runtime owns it. Packs may consume it through explicit runtime context, but must not synthesize it.

### Pack owns

**Validated today**

The pack owns:
- domain inputs
- plan structure
- domain op catalog
- pack-specific reference data
- domain-specific policies such as ranking heuristics, thresholds, and warning-vs-fail choices

### Smell test

If removing the pack would make the value meaningless, it is probably pack-owned.
If replacing the pack with another pack should still preserve the value, it is probably runtime-owned.

Examples:
- `run_id`: runtime-owned
- `started_at`: runtime-owned
- `topic_id`: pack-owned or pack-logical context
- `briefing_date`: pack-owned
- `lancedb_path` for Radar semantic history: pack-owned persistent state, but it must still obey runtime persistence rules

---

## Pack Design Process

### 1. Define the domain boundary

Start with the actual user-visible product or workflow, not abstract runtime capability.

Write down:
- what problem the pack solves
- what the primary outputs are
- what counts as source truth in the domain
- which parts are deterministic, recordable, or side-effecting

Good pack framing:
- Radar: daily intelligence briefing with provenance
- VSME: evidence-backed compliance report with recorded judgment

Weak pack framing:
- “a pack that uses embeddings”
- “a pack that demonstrates MCP”

Those are implementation choices, not products.

### 2. Define the semantic pipeline

Describe the pack as a DAG of meaningful domain transformations.

For each stage, ask:
- what artifact or record is produced
- whether the output is immutable truth or derived working state
- whether the step is pure, pinned-env, recordable, or side-effecting
- whether replay should re-execute or inject recorded results

### 3. Separate source truth from working state

Derived indexes, caches, and materialized search structures are not the semantic source of truth. Durable truth belongs in explicit artifacts and run history.

Examples:
- a LanceDB index may support search, but the pack’s durable semantic record must still be visible in artifacts and run logs
- generated HTML or PDF may be a final artifact, but not the only place where domain meaning exists

### 4. Keep the pack honest about determinism

If an op mutates history, reads wall clock, depends on live external state, or chooses from nondeterministic alternatives, it must not pretend to be pure.

If replay should reuse recorded results, say so. If repeated live runs should re-execute because history changes, say so.

---

## Persistent Data Rules

This is the part the repo has been underspecifying.

### Hard rule

Any durable pack data directory must be explicitly defined in both development and deployment configuration.

Hidden fallbacks are allowed only for:
- tests using temporary directories
- disposable local scratch data that is intentionally not part of durable pack behavior

Durable pack state must never silently resolve from:
- `System.tmp_dir!/0`
- compiled build output such as `_build/...`
- inherited tool caches
- ad hoc working directories that an operator would not know to back up

### Development layout

**Preferred rule**

Durable pack state in development should live under:

```text
runtime/data/<pack>/...
```

Examples:
- `runtime/data/radar/lancedb`
- `runtime/data/vsme/reference`
- `runtime/data/vsme/renders`

Core runtime storage remains separate:
- `runtime/data/store`
- `runtime/data/runs`

### Deployment layout

**Preferred rule**

Durable pack state in deployment should live under an explicit operator-owned persistent root, normally:

```text
/var/lib/liminara/<pack>/...
```

Examples:
- `/var/lib/liminara/radar/lancedb`
- `/var/lib/liminara/vsme/reference`

If deployment uses another persistent root, it must still be explicit and operator-visible.

### Provenance rule

Recorded plans and runtime metadata should reflect the resolved durable path for pack-owned persistent state when that path materially affects execution.

This keeps drift visible. If a pack silently writes durable state into `_build`, the run record should make that visible immediately.

### Path ownership today

Today, durable pack paths are modeled as explicit pack-owned config keys.

Example:
- `:liminara_radar, :lancedb_path`

A future runtime-owned persistent root may derive those values, but that would still need to resolve into explicit per-pack durable paths. Hidden inference is not the contract.

---

## Reference Data

Pack reference data is not the same thing as runtime event data.

Reference data includes things like:
- rulesets
- emission factors
- material databases
- geographic lookup tables
- prompt libraries when versioned as pack assets

### Rules

Reference data should be:
- versioned
- explicit
- pack-owned
- reproducible from source control or a defined initialization step

Reference data should not be:
- hidden mutable state
- silently downloaded into unknown directories and then treated as canonical
- mixed with run event storage

If a pack needs bootstrap assets from external sources, document:
- where they come from
- where they live in dev
- where they live in deployment
- how version changes invalidate downstream cache assumptions

---

## Python Environment Ownership

Python may be available in the devcontainer as a platform capability without being an ambient repo-wide dependency surface.

### Rules

- There is no single shared repo-wide Python environment contract.
- The runtime Python op environment is owned by `runtime/python/` and managed with Astral `uv`.
- The SDK and integration environment is owned by `integrations/python/` and managed separately with Astral `uv`.
- Additional Python environments are allowed only when their ownership is explicit and documented.
- Pack logic should not silently depend on whichever Python environment a developer happened to activate.

### Practical consequence

If a pack uses Python ops, the Python environment it relies on must be an explicit part of the pack or runtime surface design. Python being installed in the container is not enough.

---

## Op Design Inside a Pack

### Prefer small semantic ops

Split ops by semantic boundary, not by arbitrary implementation detail.

Good split:
- fetch
- normalize
- classify
- rank
- render

Bad split:
- helper_a
- helper_b
- postprocess_everything

### Choose the determinism class truthfully

Use the strongest truthful class, not the most convenient one.

General guide:
- `pure`: output is only a function of explicit immutable inputs
- `pinned_env`: behavior depends on a pinned toolchain or environment version
- `recordable`: behavior includes a nondeterministic choice that can be recorded and replayed
- `side_effecting`: behavior mutates external state or performs real-world effects

### Warnings are not decisions

If an op chooses between alternatives nondeterministically, that is a decision.
If an op completed but under degraded conditions, that is a warning-bearing success.

Do not use decision records to smuggle degraded execution status.

### Side-effecting ops need replay policy discipline

Some side-effecting ops should not rerun on replay. In those cases, the runtime should replay recorded outputs rather than re-executing the mutation.

That is usually better than lying about purity.

---

## Plan Design Rules

### Plans should express domain logic, not runtime bookkeeping

A plan should describe the pack’s domain pipeline.
It should not fabricate runtime-owned fields just to wire execution together.

Avoid putting these into plan literals unless they are genuinely domain inputs:
- synthetic run IDs
- current timestamps standing in for runtime execution time
- hidden fallback file paths
- implicit environment-derived values

### Plans should be readable

A future maintainer should be able to open the pack module and understand:
- the sequence of domain steps
- the branch points
- which outputs feed which downstream consumers

If the plan is unreadable, the pack is too implicit.

---

## Config Rules

### Separate these concerns

Keep configuration separated into:
- domain config
- runtime storage config
- reference-data config
- external credentials or provider config

### Prefer explicit config keys over fallback magic

If a pack depends on a durable directory, model path selection as configuration, not as a path-computing trick relative to an app directory.

### Development and deployment must both be first-class

Do not only define a dev path and say “production can be figured out later.”
Do not only define a deployment path and leave dev to tmp defaults.

The pack is not fully designed until both environments have explicit durable-path rules.

---

## Pack Testing Strategy

### Always test at three layers when they matter

#### 1. Op-level tests

Verify the local semantics of individual ops:
- happy path
- edge cases
- invalid inputs
- replay-sensitive fields
- warning-bearing behavior when relevant

#### 2. Pack plan tests

Verify that the plan itself is correct:
- expected nodes exist
- references are wired correctly
- durable paths come from explicit config
- runtime-owned values are not fabricated in literals

#### 3. End-to-end pack execution tests

Verify the pack behaves truthfully through the runtime:
- discovery run
- replay run
- repeated live run where mutable history exists
- degraded or warning-bearing execution when applicable

### Use temp directories only in tests

Tests should isolate filesystem state with temporary directories. That does not justify tmp fallbacks in live dev or deployment code.

---

## When To Add a Runtime Feature Instead of Pack Logic

Add or change the runtime when the problem is:
- cross-pack
- part of execution truth
- part of replay or caching semantics
- part of warning or decision transport
- part of scheduling, supervision, or persistence primitives

Keep logic in the pack when the problem is:
- domain-specific ranking or scoring
- domain-specific thresholds
- whether a business condition should warn or fail
- pack-specific reference data
- pack-specific rendering or output structure

Rule of thumb:
one pack proving a need is evidence;
two packs needing the same thing in the same shape is a strong candidate for runtime generalization.

---

## Minimum Checklist For A New Pack

- Define the user-visible problem and outputs
- Define the semantic DAG in domain terms
- Classify each op truthfully by determinism and replay behavior
- Identify runtime-owned vs pack-owned values
- Define explicit dev paths for durable pack data
- Define explicit deployment paths for durable pack data
- Define reference data ownership and versioning
- Add plan tests that catch fabricated runtime values and hidden fallback paths
- Add replay tests for any recordable or side-effecting behavior
- Decide what counts as warning-bearing success versus failure

---

## Current Gaps This Guide Does Not Pretend To Solve

These areas still need active design or implementation work elsewhere:
- a fully standardized persistent-root contract for pack-owned storage
- canonical warning/degraded-success runtime behavior across all packs
- final stable pack-facing initialization surface for reference data
- full migration of live op execution onto canonical `execution_spec/0`

This guide is meant to reduce drift now, not to claim those migrations are already complete.

---

## Related Sources

- `runtime/apps/liminara_core/lib/liminara/pack.ex`
- `docs/architecture/01_CORE.md`
- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `docs/liminara.md`
- `docs/analysis/15_Radar_Pack_Plan.md`
- `docs/analysis/14_VSME_Pack_Plan.md`
- `work/decisions.md`
- `work/gaps.md`