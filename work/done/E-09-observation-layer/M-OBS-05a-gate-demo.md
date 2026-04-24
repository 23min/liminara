---
id: M-OBS-05a-gate-demo
epic: E-09-observation-layer
status: complete
---

# M-OBS-05a: Gate Demo + LiveView Gate Interaction

## Goal

Make gates testable end-to-end in the browser. Add a gate op to DemoOps, update the demo run to include a gate node that pauses execution mid-pipeline, and add approve/reject UI in the LiveView inspector so a user can resolve the gate from the browser. The run then continues to completion.

This is valuable standalone (completes the observation layer's interactive story) and is a prerequisite for testing A2UI gate interaction in M-OBS-05b.

## Context

The gate infrastructure already exists in the runtime:
- Op can return `{:gate, prompt}` → Executor wraps as `{:gate, prompt, duration_ms}`
- `Run.Server` handles `{:gate, ...}` → emits `gate_requested`, node goes to `:waiting`
- `Run.Server.resolve_gate(run_id, node_id, response)` → records decision, emits `gate_resolved` + `op_completed`, continues DAG
- `ViewModel` handles `gate_requested`/`gate_resolved` events
- Inspector already displays gate_prompt and gate_response

What's missing: a gate op, a demo that uses it, and UI to trigger `resolve_gate`.

## Acceptance criteria

### Gate op
- [x] `DemoOps.Approve` op exists with determinism `:side_effecting`
- [x] `Approve.execute/1` returns `{:gate, prompt}` where prompt is derived from inputs
- [x] Op behaviour contract satisfied (name, version, determinism, execute)

### Demo run with gate
- [x] `mix demo_run` creates a run with a gate node mid-pipeline
- [x] The gate node pauses execution — downstream nodes remain `:pending`
- [x] The run shows as `:running` (not `:completed`) until the gate is resolved
- [x] After gate resolution, the run completes normally

### LiveView gate interaction
- [x] When a gate node is `:waiting`, the inspector shows approve/reject buttons
- [x] Clicking "Approve" calls `Run.Server.resolve_gate(run_id, node_id, response)`
- [x] Clicking "Reject" calls `resolve_gate` with a rejection response
- [x] After resolution, the inspector updates to show the gate response
- [x] The DAG updates in real-time (waiting node → running → completed)
- [x] The timeline shows `gate_requested` and `gate_resolved` events

### Interactive demo flow
- [x] User runs `mix demo_run`, opens the run in the browser
- [x] DAG shows some nodes completed, gate node pulsing/waiting, downstream pending
- [x] User clicks the gate node → inspector shows the prompt + approve/reject buttons
- [x] User clicks approve → run completes, all nodes turn completed
- [x] Full roundtrip works without page reload

## Tests

### Gate op tests
- `DemoOps.Approve` returns `{:gate, prompt}` with correct prompt text
- `DemoOps.Approve` has determinism `:side_effecting`
- Executor wraps gate return correctly (already tested, verify integration)

### Gate interaction LiveView tests
- Select a waiting gate node, verify approve/reject buttons appear
- Click approve, verify `resolve_gate` is called and inspector updates
- Click reject, verify `resolve_gate` is called with rejection
- Select a non-gate node, verify no approve/reject buttons
- Select a resolved gate node, verify buttons are gone, response is shown

### Demo run integration tests
- Start demo run, verify it pauses at the gate (run_status remains :running)
- Resolve the gate, verify run completes
- Verify gate events appear in the timeline

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- A2UI rendering of gates (M-OBS-05b)
- Multiple gates in a single run (one gate is sufficient for demo)
- Gate timeout / auto-reject
- Custom gate response forms (just approve/reject for now)

## Spec reference

- `docs/architecture/01_CORE.md §Decisions and Gates`
- Gate handling in `Run.Server`: `handle_gate_requested/3`, `handle_gate_resolved/3`, `resolve_gate/3`
- Executor: `wrap_result({:gate, prompt}, duration_ms)`

## Related ADRs

- none yet
