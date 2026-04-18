---
id: M-WARN-01-runtime-warning-contract
epic: E-19-warnings-degraded-outcomes
status: complete
depends_on: M-TRUTH-03-radar-semantic-cleanup
---

# M-WARN-01: Runtime Warning Contract

## Goal

Finalize the runtime-side warning/degraded-success contract so a run with warning-bearing ops is a first-class, queryable outcome rather than an ordinary success. After this milestone, the core runtime validates warning shape, aggregates warnings at the run level, and exposes a derived degraded status through `Run.Result` and the `run_completed` event — without introducing any UI surface, observation projection, or pack-level changes (those belong to M-WARN-02 and M-WARN-03).

## Context

M-TRUTH-01 locked the canonical warning contract (`Liminara.Warning`, `Liminara.OpResult.warnings`, `Liminara.ExecutionSpec.Contracts.warnings.may_emit`). M-TRUTH-02 wired it through the runtime: `Liminara.Executor` normalizes `{:ok, outputs, decisions, warnings}` into `OpResult`; `Liminara.Executor.Port` normalizes Python warning payloads and coerces severity strings into atoms; `Liminara.Run.Server` persists warnings via `Decision.Store.put_warnings/get_warnings` and emits a `warnings` list on `op_completed`. M-TRUTH-03 made Radar the first pack to honestly use that transport: `radar_summarize`'s placeholder and LLM-error paths, dedup's safe-default path, and fetch-error embedding now emit canonical warning payloads instead of smuggling rationale through decisions.

What remains open before E-19 can surface warnings to operators:

- `%Liminara.Warning{}` accepts any combination of nil fields; there is no validated constructor, no severity taxonomy, no rule about which fields are required.
- `Liminara.Run.Result` exposes `status :: :success | :partial | :failed` and does not distinguish plain success from success-with-warnings. No warning count, no list of degraded node ids, no aggregated warning payload is reachable from the result.
- The `run_completed` event payload carries `run_id`, `outcome: "success"`, and `artifact_hashes` only. There is no run-level warning summary, so downstream consumers (observation projection, CLI, replay) cannot answer "did this run degrade?" without walking every `op_completed` payload.
- `ExecutionSpec.Contracts.warnings.may_emit` is declared but unenforced: an op can emit warnings while claiming it does not, and vice versa.
- Warning `affected_outputs` is a free list; the contract does not require entries to correspond to keys in `OpResult.outputs`.

M-WARN-01 closes those gaps at the runtime boundary only. UI rendering, observation-layer projection shape, and pack-level briefing annotation are out of scope here.

## Milestone Boundary

M-WARN-01 may implement:

- A validated `Liminara.Warning.new/1` constructor and a locked severity taxonomy
- Enforcement (or documented deferred enforcement with a named trigger) of `Contracts.warnings.may_emit` on ops that return warnings
- Run-level aggregation reachable through `Liminara.Run.Result` and the `run_completed` event payload
- A derived run status value for success-with-warnings, consumed by `Run.Result`
- Node-level derived "completed-with-warnings" marker reachable through the run result without changing the `op_completed` event's existing warning field shape beyond aggregation
- Round-trip, replay, and recovery tests that prove aggregation survives event replay and crash recovery

M-WARN-01 does not implement:

- Changes to observation projection or `Liminara.Observation.ViewModel`
- LiveView run inspector, DAG badges, or any UI rendering
- CLI output changes
- Radar pack-level changes (briefing annotation, pack-level tests for degraded outcomes)
- New warning surfaces in Python ops or the port wire protocol beyond what M-TRUTH-02 already locked
- Retry/backoff/alerting or any automated remediation

## Acceptance Criteria

1. **Warning construction is validated and severity taxonomy is locked**
   - `Liminara.Warning.new/1` accepts a map or keyword list and returns a validated `%Liminara.Warning{}`
   - `code` (binary), `severity` (atom from the locked taxonomy), and `summary` (binary) are required; missing or wrong-typed values raise `ArgumentError`
   - `cause`, `remediation`, and `affected_outputs` are optional; `affected_outputs` defaults to `[]` and must be a list of binaries when present
   - Severity taxonomy is explicitly enumerated in the module and pinned by contract tests (proposed: `:info | :low | :medium | :high | :degraded`; final set locked in this milestone)
   - `Liminara.Executor.Port.normalize_warning/1` uses `Warning.new/1` rather than `struct/2`, and Python-side severity strings outside the taxonomy are rejected as an execution error rather than silently coerced

2. **`Contracts.warnings.may_emit` is enforced at the runtime boundary**
   - If an op's `OpResult.warnings` is non-empty while its `ExecutionSpec.contracts.warnings.may_emit` is `false`, the runtime surfaces a canonical violation (either a contract error or a runtime-injected warning with code `"op_warning_contract_violation"` — final choice locked in this milestone)
   - Tests cover: conforming op with `may_emit: true` and non-empty warnings; conforming op with `may_emit: false` and empty warnings; violating op with `may_emit: false` and non-empty warnings

3. **`Liminara.Run.Result` exposes warning aggregation**
   - `Result` gains `warning_count :: non_neg_integer()`, `degraded_nodes :: [node_id]`, and a derived `degraded :: boolean()` (true iff the run completed without failure and has at least one warning-bearing node)
   - The existing `status` field semantics are preserved; degraded success keeps `status: :success` and is distinguished through the new fields, not by adding `:degraded` to the status enum (rationale: status reports execution outcome, degraded reports output quality)
   - `Run.Server.await/2` and the event-log rebuild path (`result_from_event_log/1`) produce identical aggregation values for the same run

4. **`run_completed` event payload carries a warning summary**
   - `run_completed` payload gains a `"warning_summary"` key with `%{"warning_count" => N, "degraded_node_ids" => [...]}`
   - Plain success runs emit `"warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}` so downstream consumers see a stable key shape
   - `op_completed` event payload's existing `"warnings"` list is unchanged in shape; this milestone only adds the run-level summary, it does not reshape per-node warning payloads
   - Event hash chain remains valid across existing fixtures after the payload addition (frontloaded event payload additions are permitted; shape changes to existing fields are not)

5. **Replay and crash recovery preserve aggregation**
   - Replay of a warning-bearing source run reproduces `warning_count` and `degraded_nodes` on the replay run's `Result` without re-executing warning emission
   - Crash-recovered runs (rebuild via `{:continue, {:rebuild, events}}`) report the same aggregation the original run would have reported
   - Result reconstruction from the event log alone (`result_from_event_log/1`) returns matching aggregation for completed runs

6. **Contract tests freeze the milestone boundary**
   - `test/liminara/execution_contract_structs_test.exs` gains tests for `Warning.new/1` validation, severity taxonomy, and the `affected_outputs` shape rule
   - `test/liminara/execution_runtime_contract_test.exs` gains tests for `may_emit` enforcement
   - `test/liminara/run/` gains tests for run-level aggregation, the `run_completed` summary payload, and replay/recovery parity
   - Existing runtime suites continue to pass without relaxing assertions

## Tests

Use the repository TDD conventions. Required categories for this milestone:

- **Happy path**
  - `Warning.new/1` with all fields produces a canonical struct
  - An op emitting warnings with `may_emit: true` completes successfully; `Run.Result.degraded` is `true`, `warning_count` matches, `degraded_nodes` lists the emitting node
  - `run_completed` payload contains the warning summary

- **Edge cases**
  - Run with zero warning-bearing nodes emits summary with `warning_count: 0` and `degraded_nodes: []`, and `Result.degraded` is `false`
  - Run with a node emitting multiple warnings counts every warning and reports the node once in `degraded_nodes`
  - Op returning an empty `warnings: []` list is indistinguishable from an op omitting the field

- **Error cases**
  - `Warning.new/1` raises `ArgumentError` on missing `code`, `summary`, or `severity`
  - `Warning.new/1` raises `ArgumentError` on a severity outside the locked taxonomy
  - `Executor.Port.normalize_warning/1` rejects Python payloads with unknown severity rather than silently coercing
  - Op that emits warnings while declaring `may_emit: false` triggers the chosen violation behavior

- **Round-trip / replay / recovery**
  - Replay of a warning-bearing run reproduces aggregation without re-executing the emitter
  - Crash recovery on a warning-bearing run yields the same `Result` aggregation as the completed run
  - `result_from_event_log/1` returns the same aggregation for a completed warning-bearing run

- **Format compliance**
  - `warnings` list in `op_completed` remains a list of maps with the documented keys
  - `warning_summary` key is present in every `run_completed` payload, regardless of warning count
  - Event hash chain remains valid for existing fixtures and newly produced events

## TDD Sequence

1. Write failing tests for `Warning.new/1` validation and the locked severity taxonomy; land the constructor and taxonomy.
2. Write failing tests for `may_emit` enforcement; implement the chosen violation behavior.
3. Write failing tests for `Run.Result` aggregation (degraded flag, warning_count, degraded_nodes) across forward execution, replay, and event-log reconstruction; extend `Run.Result` and `Run.Server` finish paths.
4. Write failing tests for the `run_completed` warning summary payload; extend `finish_run/2`.
5. Run the full `liminara_core` test suite, then the observation and radar app suites to confirm no regression in code that may already read `op_completed.warnings` or `run_completed` payload shape.

## Technical Notes

- Expected core touch points:
  - `runtime/apps/liminara_core/lib/liminara/warning.ex`
  - `runtime/apps/liminara_core/lib/liminara/op_result.ex` (typespec tightening only; no shape change)
  - `runtime/apps/liminara_core/lib/liminara/executor.ex`
  - `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
  - `runtime/apps/liminara_core/lib/liminara/run.ex` (or `run/result.ex` — whichever currently hosts the `Result` struct)
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex`
- Keep `status :: :success | :partial | :failed` untouched. Degraded is derived state, not a fourth terminal status. Adding a fourth status would ripple into every observation projection, CLI, and persisted event consumer and is not justified by current operator needs.
- `warning_summary` is additive. Do not mutate `op_completed.warnings` shape or rename existing payload keys; M-WARN-02 and E-21a (ADR-OPSPEC-01 CUE codification) both consume the shape locked here.
- Enforcement choice for `may_emit`: prefer runtime-injected warning (`"op_warning_contract_violation"`) over hard error. Reason: a contract mismatch should not crash a run mid-flight when the op has already produced outputs; the violation is itself a degraded-outcome signal and should surface through the same channel. Finalize in the TDD cycle.
- Severity taxonomy: prefer `:info | :low | :medium | :high | :degraded`. Rationale: Radar already emits `:degraded` and the port executor already coerces `"degraded"`; forcing a taxonomy change at M-WARN-01 would reopen M-TRUTH-03 scope. `:info`/`:low`/`:medium`/`:high` give pack authors a conventional scale for non-degraded advisories (e.g., "fetch succeeded but 3 of 47 sources were stale"). Lock the final set in review before implementation.
- `affected_outputs` entries must reference keys in the emitting op's `OpResult.outputs`. Validation here is runtime-side only; the CUE codification in ADR-OPSPEC-01 (E-21a) will mirror the rule.

## Out of Scope

- Observation projection changes or `Liminara.Observation.ViewModel` evolution — owned by M-WARN-02
- LiveView badges, node inspector rendering, timeline summary changes — owned by M-WARN-02
- CLI degraded-run surfacing — owned by M-WARN-02
- Radar briefing annotation and pack-level degraded-outcome tests — owned by M-WARN-03
- Converting other packs or non-Radar soft edges to warnings — explicitly excluded by E-19 Out of Scope
- CUE schema codification of the warning contract — owned by E-21a ADR-OPSPEC-01 after E-19 merges
- Retry, backoff, alerting, policy engines, health scoring — excluded by E-19

## Dependencies

- M-TRUTH-03 is complete and merged (Radar pack emits canonical warnings on its known degraded paths; M-WARN-01 tests can use Radar ops as warning-emitting fixtures without any Radar changes)
- `docs/architecture/contracts/00_TRUTH_MODEL.md`, `docs/architecture/contracts/01_CONTRACT_MATRIX.md`
- Decision D-2026-04-02-015 (unified execution spec) is the architectural basis
- Work/epics/E-19-warnings-degraded-outcomes/epic.md locks the epic-level scope

## Spec Reference

- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
- `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`
- `work/done/E-20-execution-truth/M-TRUTH-03-radar-semantic-cleanup.md`

## Downstream Consumers

- **M-WARN-02** consumes the `Result` aggregation shape and `run_completed.warning_summary` payload for observation/UI surfacing. Any shape change after M-WARN-01 lands must be coordinated with M-WARN-02.
- **M-WARN-03** consumes the milestone boundary to add Radar briefing annotation and pack-level tests; it does not reshape warning payloads.
- **E-21a ADR-OPSPEC-01** codifies the warning contract as CUE. ADR-OPSPEC-01 depends on the shape locked here and cannot begin before E-19 merges.
