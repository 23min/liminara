# Execution Truth Plan

## Purpose

Get Liminara back onto a contract that is true to its thesis:

- op metadata must mean exactly what runtime behavior does
- replay and cache semantics must follow real side-effect boundaries
- runtime identity must come from the runtime, not be fabricated in pack code
- degraded output must be explicit, never smuggled through plain success
- mocks, stubs, and placeholder behavior must stay in tests or be surfaced as degraded outcomes in production

This plan operationalizes D-2026-04-02-015 instead of treating the unified execution spec as a later cleanup.

## Why This Must Happen Now

Radar has already exposed contract drift that should be treated as architectural debt, not local bugs:

- `Radar.Ops.Dedup` is declared `:pure`, but mutates LanceDB history and uses wall-clock time
- Radar briefing metadata still uses a plan-time synthetic `run_id`, not the runtime execution `run_id`
- Placeholder summaries and safe-default LLM dedup behavior can produce degraded output without a first-class degraded-success contract
- Some pack inputs still encode future intent rather than current truth, for example inert ranking inputs

If E-19 and E-12 land on top of those loose semantics, the codebase gets a cleaner UI and a stronger sandbox around contracts that are still not fully honest.

## Existing Commitments This Plan Pulls Together

- D-2026-04-02-012: Radar hardening happens before VSME, but stays bounded to Radar-proven needs
- D-2026-04-02-013: sequence is Radar correctness -> Radar hardening -> VSME -> platform generalization
- D-2026-04-02-015: unify op shape under `execution_spec/0`
- E-19: warnings and degraded outcomes must not become a one-off side channel
- E-12: sandbox capabilities and provenance should be implemented against the unified execution spec, not against callback sprawl

## Placement In The Roadmap

Current state: M-RAD-04 is closed. The prerequisite for starting this plan is satisfied.

Recommended order:

1. Start this plan immediately after M-RAD-04 as the first blocking slice of Phase 5c.
2. Implement E-19 on top of this contract.
3. Implement E-12 on top of this contract.
4. Continue with the remaining Radar hardening work.

This should not wait until after E-19 or E-12. Those epics depend on a truthful op/runtime contract.

## Rule For M-RAD-04 While It Is In Flight

M-RAD-04 should finish, but it should not create new local schemas or shortcuts that this plan would immediately delete.

Guardrails:

- do not invent a one-off warning shape in the web layer
- do not introduce new synthetic run identifiers in the UI or scheduler
- do not add new production fallbacks that silently degrade output
- keep UI wiring thin so E-19 can add the real degraded-outcome contract later

## Architectural Principles

### 1. Truthful Semantics Over Convenience

If an op mutates external state, it is not pure.

If an output is degraded, it is not an ordinary success.

If a value represents runtime identity, the runtime owns it.

### 2. Immutable Semantic Inputs

Pure and recordable behavior must be functions of explicit inputs. Hidden mutable stores, wall-clock timestamps, inherited env vars, and implied defaults are not semantic inputs.

### 3. Runtime-Owned Execution Context

Run identity, replay provenance, schedule context, and execution timestamps belong to the runtime. Packs may consume them, but must not synthesize them.

### 4. Materialized Indexes Are Not Source Of Truth

LanceDB and similar indexes should be treated as derived working state. The durable semantic record must be explicit in artifacts and run history.

### 5. Production Fallbacks Must Be Declared

If the system chooses to continue without a required dependency or model, the result must carry an explicit degraded-success contract. Test doubles remain test-only.

## Target Contract

### Unified Op Shape

Introduce `execution_spec/0` as the canonical op definition. Existing callbacks do not remain as a supported compatibility surface during migration.

Target sections:

- `identity`: name, version
- `determinism`: class
- `execution`: executor-specific invocation shape, timeout, runtime context requirements
- `isolation`: env vars, network, allowed read/write paths, capability declarations
- `contracts`: keyed input schema, keyed output schema, warning contract

Important rule: new concerns extend this structure instead of adding new top-level callbacks.

Additional rule: decision capability is derived from determinism, not declared as a separate contract flag. Output keys are named DAG edges and must be preserved exactly through event persistence and replay.

### Runtime Execution Context

The runtime should inject one explicit execution context into nodes that need it.

Minimum fields:

- `run_id`
- `started_at`
- `pack_id`
- `pack_version`
- `replay_of_run_id` when applicable
- optional logical context such as `topic_id`

If Radar needs a daily logical identifier distinct from `run_id`, that should be a separate field such as `briefing_id`, not a fake run id.

### Success Model

The runtime should support three meaningful outcomes:

- `success`
- `failed`
- `success_with_warnings`

"Degraded" is the operator-facing interpretation of warning-bearing success, not a separate vague state tree.

Warnings are not decisions. Decisions capture nondeterministic choice. Warnings capture quality, availability, isolation, and execution-condition problems.

## Workstreams

### Workstream A: Unified Execution Spec

Goal: make the op shape explicit before more runtime features land.

Deliverables:

- final `execution_spec/0` structure
- removal of legacy `determinism/0`, `executor/0`, `python_op/0`, `env_vars/0`, and tuple-result surfaces from active runtime use
- executor-specific execution shapes instead of a mixed `entrypoint` field
- explicit keyed output schema preserved exactly through persistence and replay
- decision capability derived from determinism rather than an independent declaration
- migration plan for existing ops
- updated E-19 and E-12 specs to target this contract

### Workstream B: Runtime Identity And Provenance Truth

Goal: remove fabricated runtime identity from packs.

Deliverables:

- runtime-injected execution context
- actual runtime `run_id` threaded into pack outputs and UI
- replay uses stored execution context rather than rebuilding fresh identity data
- explicit distinction between execution identity and logical document identity

### Workstream C: Side-Effect Boundary Realignment

Goal: make purity and side effects line up with real behavior.

Deliverables:

- split Radar dedup into separate stages:
  - pure classification against an explicit history snapshot
  - recordable ambiguity resolution
  - side-effecting history commit
- make history snapshot / commit semantics explicit
- remove wall-clock writes from pure paths
- ensure replay and cache rules match the new boundaries

### Workstream D: Degraded Outcomes Contract

Goal: eliminate silent degradation in production.

Deliverables:

- warning payload shape with code, severity, summary, cause, remediation, affected outputs
- executor and event propagation for warning-bearing success
- observation and UI surfacing
- Radar adoption for summarize and LLM dedup fallback paths
- briefing annotation when degraded content exists

Constraint: `affected_outputs` must reference declared output keys from the canonical output schema rather than free-form labels.

### Workstream E: Production Configuration Honesty

Goal: remove test-oriented defaults from production semantics.

Deliverables:

- no ambient mock providers in production code paths
- missing required provider/config should fail or enter explicit degraded mode
- inert semantic inputs removed or replaced by real computed context

## Proposed Milestones

This should be executed as a short, blocking hardening program immediately after M-RAD-04.

### M-TRUTH-01: Execution Spec And Outcome Design

Goal: finalize the contract before implementation.

Acceptance criteria:

- `execution_spec/0` structure is defined
- runtime execution context shape is defined
- warning-bearing success contract is defined
- executor-specific execution shapes are defined
- output keys are part of the canonical persisted/replayed contract
- decision capability is derived from determinism, not a separate contract flag
- migration plan for current ops is written
- E-19 and E-12 specs are updated to build on this design

### M-TRUTH-02: Core Runtime Contract Migration

Goal: move runtime execution to the new shape without breaking current packs.

Acceptance criteria:

- all active ops adopt the canonical contract; no compatibility layer remains in the runtime path
- executor path understands warning-bearing success
- persisted/replayed output hashes preserve declared keys exactly; rebuild does not invent fallback names
- non-recordable ops returning decisions are rejected by the runtime
- run events and replay store execution context explicitly
- real runtime `run_id` is available to pack outputs without pack-side synthesis

### M-TRUTH-03: Radar Semantic Cleanup

Goal: make Radar the first pack that is fully honest about its contracts.

Acceptance criteria:

- dedup no longer mixes pure classification with durable mutation
- briefing metadata uses runtime truth
- placeholder and fallback paths use the warning contract or fail hard
- production defaults do not silently select mocks
- ranking inputs are either real or removed from semantic scoring

### M-WARN-01..03 / E-19: Warnings And Degraded Outcomes

Goal: build the operator-facing warning system on the new runtime contract.

Rule: E-19 should consume the result of M-TRUTH-01..03, not invent its own local structure.

### M-ISO-01..02 / E-12: Sandbox And Provenance

Goal: implement capability-driven isolation on the `isolation` section of `execution_spec/0`.

Rule: E-12 should not add `sandbox_capabilities/0` as another standalone callback.

## Concrete Design Rules

These should be treated as hard rules, not style preferences.

### Pure Ops

- no wall-clock reads
- no filesystem mutation
- no hidden index mutation
- no network
- no inherited undeclared env vars

### Recordable Ops

- nondeterminism captured as explicit decision records
- no silent fallback that changes semantic quality without warning
- replay uses stored decisions and stored execution context

### Side-Effecting Ops

- side effects are explicit in spec and provenance
- skipped or handled specially on replay according to the runtime contract
- external mutation targets are declared in the isolation section

### Production Code

- no default mock provider selection
- no placeholder content presented as ordinary success
- no UI-only metadata invented to cover missing runtime truth
- no test support modules or doubles on production paths

## What This Plan Is Not

This is not a generic platform detour.

It is a bounded hardening slice justified by Radar's existing contract drift and already anticipated by D-015, E-19, and E-12.

It should make the next work simpler:

- E-19 becomes a contract implementation, not a semantic rescue mission
- E-12 becomes a clean isolation implementation against an explicit op shape
- VSME inherits a runtime whose terms mean what they say

## Recommendation

Yes: this belongs immediately after M-RAD-04.

That is the right balance between not thrashing the active milestone and not letting more hardening work pile onto a runtime contract that is still too loose.