# M-WARN-01: Runtime Warning Contract — Tracking

**Started:** 2026-04-17 (spec drafted)
**Wrapped:** 2026-04-17
**Branch:** `epic/E-19-warnings-degraded-outcomes`
**Spec:** `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
**Status:** complete
**Completed:** 2026-04-17

## Wrap note

The runtime work described by this milestone's acceptance criteria was already landed as part of epic **E-20 Execution Truth** — specifically across the commits that closed M-TRUTH-01, M-TRUTH-02, and M-TRUTH-03. When M-WARN-01 was scoped and the spec was drafted, all the runtime plumbing, aggregation, event payload additions, and contract tests the spec asks for were already implemented and green on `main`. No new code landed under this milestone; the spec and this tracking doc ratify and document what is already in place so E-21a (ADR-OPSPEC-01) and M-WARN-02 inherit a named, frozen contract boundary.

## Acceptance Criteria

- [x] AC1: Warning construction is validated and severity taxonomy is locked
  - `Liminara.Warning.new/1` accepts map or keyword input, validates required fields (`code`, `severity`, `summary`), validates optional fields (`cause`, `remediation`, `affected_outputs`), rejects unknown keys, and raises `ArgumentError` on shape or severity-taxonomy violations
  - Severity taxonomy is locked to `:info | :low | :medium | :high | :degraded` and exposed via `Liminara.Warning.severities/0`
  - `Liminara.Executor.Port.normalize_warning/1` routes all non-struct warnings through `Warning.new/1` rather than `struct/2`; unknown severity strings raise rather than silently coerce
  - Evidence: `runtime/apps/liminara_core/lib/liminara/warning.ex`, `runtime/apps/liminara_core/lib/liminara/executor/port.ex:243-285`, `runtime/apps/liminara_core/test/liminara/execution_contract_structs_test.exs:107-380`
- [x] AC2: `Contracts.warnings.may_emit` is enforced at the runtime boundary
  - `Warning.enforce_contract/2` is the single enforcement point; runtime paths call it on op completion and prepend an `"op_warning_contract_violation"` warning when `may_emit: false` and warnings are non-empty
  - Enforcement is applied symmetrically in both runtime entry points: `Liminara.Run.ex:709` and `Liminara.Run.Server.ex:1189`
  - Evidence: `runtime/apps/liminara_core/lib/liminara/warning.ex:44-77`, `runtime/apps/liminara_core/test/liminara/execution_contract_structs_test.exs:245-306`
- [x] AC3: `Liminara.Run.Result` exposes warning aggregation
  - `Result` carries `warning_count :: non_neg_integer()`, `degraded_nodes :: [String.t()]`, and derived `degraded :: boolean()` (true iff status is not `:failed` and `warning_count > 0`)
  - `status :: :success | :partial | :failed` is unchanged; degraded is a derived flag, not a fourth terminal status
  - Parity holds across forward execution, replay, crash recovery (`handle_continue({:rebuild, events}, state)`), and event-log reconstruction (`result_from_event_log/1`)
  - Evidence: `runtime/apps/liminara_core/lib/liminara/run.ex:53-93, 176-220`, `runtime/apps/liminara_core/lib/liminara/run/server.ex:251-262, 780-819, 1002-1035`
- [x] AC4: `run_completed` event payload carries a warning summary
  - Every `run_completed` payload emits `"warning_summary" => %{"warning_count" => N, "degraded_node_ids" => [...]}`, including plain-success runs (zero values) so downstream consumers see a stable key shape
  - `op_completed.warnings` shape is unchanged; this milestone is strictly additive at the run level
  - Event hash chain validation continues to pass after the payload addition
  - Evidence: `runtime/apps/liminara_core/lib/liminara/run/server.ex:780-799`, `runtime/apps/liminara_core/lib/liminara/run.ex:176-220`, `runtime/apps/liminara_core/test/liminara/run/warning_aggregation_test.exs:281-361`
- [x] AC5: Replay and crash recovery preserve aggregation
  - Replay of a warning-bearing source run reproduces `warning_count` and `degraded_nodes` on the replay run's `Result` without re-executing warning emission (warnings are restored from `Decision.Store.get_warnings/2`)
  - Crash-recovered runs rebuild `node_warning_counts` from the event log during `{:continue, {:rebuild, events}}`; rebuilt `Result` matches the live `Result`
  - `result_from_event_log/1` returns matching aggregation for completed warning-bearing runs
  - Evidence: `runtime/apps/liminara_core/test/liminara/run/warning_aggregation_test.exs:191-276`, `runtime/apps/liminara_core/lib/liminara/run/server.ex:1018-1035`
- [x] AC6: Contract tests freeze the milestone boundary
  - `test/liminara/execution_contract_structs_test.exs` covers `Warning.new/1` validation, severity taxonomy, and the `affected_outputs` shape rule (tests 107–242)
  - `test/liminara/execution_contract_structs_test.exs` covers `Warning.enforce_contract/2` semantics (tests 245–306)
  - `test/liminara/execution_contract_structs_test.exs` covers `Executor.Port.normalize_warning/1` routing and rejection (tests 308–380)
  - `test/liminara/run/warning_aggregation_test.exs` covers forward execution, replay, crash recovery, and `run_completed` warning summary
  - `test/liminara/execution_runtime_contract_test.exs` covers runtime enforcement paths

## Test Summary

- **M-WARN-01 targeted suite** (4 files): `mix test apps/liminara_core/test/liminara/execution_contract_structs_test.exs apps/liminara_core/test/liminara/run/warning_aggregation_test.exs apps/liminara_core/test/liminara/execution_runtime_contract_test.exs` → **70 tests, 0 failures** (1.8s)
- **Full umbrella `mix test`** not run to completion in this wrap-up session (prior runs on `main` are the passing baseline). Future wrap-ups for M-WARN-02 / M-WARN-03 will run the full suite on the final E-19 branch.

## Deferred / Out-of-Scope Items

- Observation projection updates (`Liminara.Observation.ViewModel`) — owned by **M-WARN-02**
- LiveView badges, node inspector rendering, CLI degraded-run surfacing — owned by **M-WARN-02**
- Radar briefing annotation, pack-level degraded-outcome tests — owned by **M-WARN-03**
- CUE schema codification of the warning contract — owned by **E-21a ADR-OPSPEC-01** once E-19 merges

## Post-ratification amendment (landed on `epic/E-19-warnings-degraded-outcomes` during M-WARN-02 implementation)

M-WARN-02's contract review surfaced a gap: `op_completed` events were missing the `warnings` key on three `Run.Server` paths (`handle_replay_skip`, `handle_gate_resolved`, `handle_cache_hit`) and two `Run` paths (`handle_replay_skip`, `handle_cache_hit`). Per the "no backward-compat duct tape" rule, the runtime was tightened to emit `"warnings" => []` on every `op_completed` event. The rebuild (`rebuild_from_events`) and event-log aggregation (`warning_aggregation_from_events`) paths now require the key via `Map.fetch!/2`.

The contract this milestone ratifies is therefore strictly stronger than what was true on `main` when the spec was drafted: **every `op_completed` payload carries a `warnings` list**, not just the success/replay-inject paths. Downstream consumers (ViewModel, ADR-OPSPEC-01) can rely on the key being present.

Evidence: see the M-WARN-01 tightening section in `M-WARN-02-tracking.md` for file-level citations and validation output.

## Notes

- M-WARN-01 acts as a ratification milestone: its purpose is to make the implicit runtime contract delivered under E-20 explicit, testable, and cite-able from downstream specs (M-WARN-02, M-WARN-03, E-21a). The post-ratification amendment above is the only runtime code change that landed under this milestone's branch; it closes a contract gap rather than expanding scope.
- `status` stays three-valued (`:success | :partial | :failed`); `degraded` is a derived boolean on `Result`. This decision was made explicit in the M-WARN-01 spec and is carried forward.
- Enforcement choice for `may_emit` violations is a runtime-injected `"op_warning_contract_violation"` warning, not a hard error — a contract mismatch on an otherwise-successful op should not crash a run mid-flight.
- Severity taxonomy locked: `:info | :low | :medium | :high | :degraded`. `:degraded` stays in the severity set because Radar already emits it via M-TRUTH-03; forcing a taxonomy change in M-WARN-01 would reopen M-TRUTH-03's scope.

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Upstream: `work/done/E-20-execution-truth/` (M-TRUTH-01, M-TRUTH-02, M-TRUTH-03 tracking docs)
- Downstream consumer: `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md` (ADR-OPSPEC-01)
