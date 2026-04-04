---
id: M-TRUTH-01-execution-spec-outcome-design
epic: E-20-execution-truth
status: complete
depends_on: M-RAD-04-webui-scheduler
---

# M-TRUTH-01: Execution Spec + Outcome Design

## Goal

Lock the canonical execution contract before any more Phase 5c implementation lands. After this milestone, E-19 and E-12 should have one agreed runtime shape to build on, and M-TRUTH-02 can implement that shape without discovering semantics mid-flight.

## Context

The current runtime contract is split across separate callbacks and conventions:

- `name/0`
- `version/0`
- `determinism/0`
- optional `executor/0`
- optional `python_op/0`
- optional `env_vars/0`
- return-shape conventions that distinguish outputs and decisions but not warnings

This is manageable only while the runtime is small. It stops scaling as soon as more concerns land:

- warnings and degraded outcomes
- sandbox/isolation capabilities
- runtime-owned execution context
- replay policy and cache policy details
- future resource and contract metadata

This milestone is design-first on purpose. It should resolve the contract before E-19 and E-12 implementation, not after.

## Milestone Boundary

M-TRUTH-01 is allowed to codify the canonical shared structs and focused contract tests in `liminara_core` when that helps freeze names, defaults, and field shapes. That codification is schema-freezing only.

This milestone does not implement:

- runtime legacy callback bridges
- legacy tuple or Python JSON result normalization into `OpResult`
- pack or executor migration onto the new contract

Those runtime bridge and adaptation changes belong to M-TRUTH-02.

## Acceptance Criteria

1. **Canonical op definition is specified**
   - `execution_spec/0` is the canonical long-term surface
   - The spec is structured into five sections: `identity`, `determinism`, `execution`, `isolation`, `contracts`
   - Each section has defined ownership and semantics

2. **Runtime execution context is specified**
   - Runtime-owned identity and provenance fields are explicitly defined
   - Execution context is separate from plan inputs
   - Pack code no longer needs to fabricate values that look like runtime metadata

3. **Canonical result and warning contract is specified**
   - Outputs, decisions, and warnings share one canonical result shape
   - Warning-bearing success is modeled explicitly
   - Decisions remain distinct from warnings

4. **Exception-only migration strategy is specified**
  - Existing callbacks are only supported where a documented temporary shim is required
  - Every shim carries a removal trigger and owning milestone
  - Cross-language protocol transition is defined for Python ops
  - Bridge and result-adaptation implementation is explicitly deferred to M-TRUTH-02

5. **Downstream specs are aligned**
   - E-19 explicitly consumes the warning/result contract defined here
   - E-12 explicitly consumes the `isolation` section defined here
   - Neither epic introduces a standalone callback or local shape that bypasses this contract

## Non-Goals

- Implementing the runtime changes themselves
- Implementing legacy callback bridge paths in runtime execution
- Implementing legacy tuple or Python response normalization into `OpResult`
- Migrating packs or executor call sites onto the new contract
- Refactoring Radar dedup in this milestone
- Delivering warning UI in this milestone
- Delivering sandbox enforcement in this milestone

## Target Design

### 1. Canonical Op Shape

Preferred canonical shape:

```elixir
defmodule Liminara.ExecutionSpec do
  defstruct [
    :identity,
    :determinism,
    :execution,
    :isolation,
    :contracts
  ]
end
```

The sub-sections should be concrete structs or normalized maps with stable keys.

#### `identity`

Owns stable op identity.

Minimum fields:

- `name`
- `version`

#### `determinism`

Owns semantic execution class and replay/cache meaning.

Minimum fields:

- `class` in `:pure | :pinned_env | :recordable | :side_effecting`
- `cache_policy`
- `replay_policy`

Important rule: if an op mutates external state, durable local state, or wall-clock-derived semantic data, it is not `:pure`.

#### `execution`

Owns how the runtime invokes the op.

Minimum fields:

- `executor`
- `entrypoint`
- `timeout_ms`
- `requires_execution_context`

Examples:

- Elixir inline ops use `executor: :inline`
- Python ops use `executor: :port` and an explicit `entrypoint`

#### `isolation`

Owns declared execution capabilities.

Minimum fields:

- `env_vars`
- `network`
- `bootstrap_read_paths`
- `runtime_read_paths`
- `runtime_write_paths`

The `bootstrap_read_paths` vs `runtime_*` split is intentional. It resolves the known E-12 contradiction where the runner must import code and dependencies but should not get unrestricted mutable runtime access.

#### `contracts`

Owns the contract surface between the runtime and the op.

Minimum fields:

- `inputs`
- `outputs`
- `decisions`
- `warnings`

At minimum, this section must express:

- whether the op may emit decisions
- whether the op may emit warnings
- expected output keys or output schema references

### 2. Runtime Execution Context

Execution context must be runtime-owned and distinct from plan inputs.

Preferred shape:

```elixir
%Liminara.ExecutionContext{
  run_id: "run-...",
  started_at: "2026-04-03T10:00:00Z",
  pack_id: :radar,
  pack_version: "0.1.0",
  replay_of_run_id: nil,
  topic_id: nil
}
```

Rules:

- `run_id` is never synthesized in pack code
- logical document ids such as a daily briefing id, if needed, are separate values and must not masquerade as `run_id`
- replay uses stored execution context, not freshly regenerated equivalents

### 3. Canonical Op Result

Preferred canonical result:

```elixir
defmodule Liminara.OpResult do
  defstruct [
    outputs: %{},
    decisions: [],
    warnings: []
  ]
end
```

Rules:

- `outputs` are required
- `decisions` default to `[]`
- `warnings` default to `[]`
- degraded-success is derived from `warnings != []`, not from a second ad hoc flag scattered across the stack

### 4. Canonical Warning Shape

Preferred warning shape:

```elixir
defmodule Liminara.Warning do
  defstruct [
    :code,
    :severity,
    :summary,
    :cause,
    :remediation,
    :affected_outputs
  ]
end
```

Rules:

- warnings describe execution quality or execution conditions
- decisions describe nondeterministic choices
- warnings are visible to the operator even when output is produced successfully

### 5. Cross-Language Protocol Direction

Python request/response should evolve toward the same shape rather than carrying a local protocol forever.

Preferred request direction:

```json
{"id":"...","op":"module_name","inputs":{...},"context":{...}}
```

Preferred success response direction:

```json
{
  "id": "...",
  "status": "ok",
  "outputs": {...},
  "decisions": [...],
  "warnings": [...]
}
```

Migration rule: current Python ops may continue returning `outputs` and optional `decisions` during transition, but M-TRUTH-02 must define the normalizer path into the canonical runtime result.

## Migration Strategy

### Phase 1: Temporary Canonical Bridge

- Add `execution_spec/0` as the preferred callback
- This milestone defines the bridge contract, ownership, and removal requirements only
- M-TRUTH-02 implements any runtime-derived spec path needed for unmigrated ops
- Each shim names the legacy surface it is retiring and the milestone that removes it

### Phase 2: Result Normalization

- This milestone defines the canonical target result shape and Python wire direction only
- M-TRUTH-02 implements runtime normalization of legacy tuple and Python JSON responses into that contract
- No indefinite dual result surface remains after migration

## Governance References

- `docs/architecture/contracts/00_TRUTH_MODEL.md`
- `docs/architecture/contracts/02_SHIM_POLICY.md`

### Phase 3: Pack Migration

- New or touched ops adopt `execution_spec/0`
- Radar becomes the first pack migrated end-to-end in M-TRUTH-03

## Deliverables

- Milestone spec approved as the canonical contract design for Phase 5c
- E-19 updated to implement the warning/result contract defined here
- E-12 updated to implement the `isolation` section defined here
- Shared core structs and focused contract tests may be codified to freeze the canonical shape, but no runtime bridge or result-adaptation path ships in this milestone
- Architecture plan and roadmap aligned with this milestone as the first blocking item after M-RAD-04 validation

## Validation

This is a design milestone. Validation is primarily by document alignment and downstream dependency correctness. Limited schema-freezing code is allowed in this milestone only when it exists to lock shared names, defaults, and field shapes.

Required validation:

- the roadmap places this milestone before E-19 and E-12
- E-19 references this milestone for warning/result semantics
- E-12 references this milestone for isolation/capability semantics
- shared contract structs, if codified, are limited to canonical shape declarations plus focused contract tests
- no runtime path in this milestone implements legacy callback bridging or legacy result normalization
- no downstream spec still proposes a standalone callback that contradicts D-015

## Dependencies

- M-RAD-04 must be finished and tested before this milestone starts implementation
- D-2026-04-02-015 is the architectural basis
- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md` provides the broader rationale

## References

- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `work/epics/E-20-execution-truth/epic.md`
- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/epics/E-12-op-sandbox/epic.md`