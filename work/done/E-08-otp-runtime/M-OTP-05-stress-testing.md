---
id: M-OTP-05-stress-testing
epic: E-08-otp-runtime
status: complete
---

# M-OTP-05: Property-Based Stress Testing and Toy Pack

## Goal

Two objectives in one milestone: (1) add StreamData property-based tests that stress-test the OTP layer with randomized inputs, and (2) build a toy pack that exercises all four determinism classes, gates, and binary artifacts through the async runtime. Together, these validate that the foundation is solid before the observation layer.

## Acceptance criteria

### StreamData property-based tests
- [ ] `stream_data` added as a test dependency in `mix.exs`
- [ ] DAG generator: produces random valid plans with configurable width (1–10 nodes), depth (1–5 levels), and branching factor
- [ ] All generated DAGs are valid (no cycles, no dangling refs) — the generator guarantees this by construction
- [ ] **Termination invariant**: every generated plan, when run through the GenServer, terminates (completes or fails) within a timeout
- [ ] **Event integrity invariant**: every completed run has a valid hash chain in its event log
- [ ] **Completeness invariant**: every completed run has a `node_completed` or `node_failed` event for each node in the plan
- [ ] **Determinism invariant**: running the same plan with the same inputs twice → pure ops produce identical output hashes
- [ ] **Isolation invariant**: running two plans concurrently → each produces a valid, independent event log
- [ ] **Crash resilience invariant**: injecting random op failures into a plan → run still terminates, event log is valid, no orphaned processes
- [ ] Property tests run at least 100 cases each (configurable via `max_runs`)

### Toy pack: `Liminara.ToyPack`
- [ ] Implements `Liminara.Pack` behaviour
- [ ] Plan: `parse → enrich → gate → render → deliver`
  - `parse` — `:pure`, takes input text, produces structured data artifact
  - `enrich` — `:recordable`, simulates LLM enrichment, records decision
  - `gate` — human approval gate (`:recordable` with gate semantics)
  - `render` — `:pinned_env`, produces a binary artifact (simulated PDF — just bytes with a header)
  - `deliver` — `:side_effecting`, simulates delivery (writes to a file or returns a receipt)
- [ ] All four determinism classes exercised
- [ ] Gate: the run pauses at the gate node, resumes when `gate_resolved` message is sent
- [ ] Binary artifact: the render op produces a non-JSON binary blob, stored and retrievable by hash
- [ ] Cache behavior: re-running with same input → `parse` cache-hits, `enrich` re-executes
- [ ] Replay: replaying a completed run → `enrich` injects stored decision, `gate` injects stored approval, `deliver` is skipped, output matches

### OTP tooling verification (manual, documented)
- [ ] Document in the session log: Observer screenshot or description showing the supervision tree during a ToyPack run
- [ ] Document in the session log: `:sys.get_state/1` output for a Run.Server mid-execution
- [ ] Document in the session log: `:sys.trace/2` output showing message flow for one op dispatch cycle

## Tests

### Property-based: DAG shape generator
- Generator produces only valid plans (property: `Plan.validate(plan) == :ok` for all generated plans)
- Generator covers: single-node plans, linear chains, fan-out, fan-in, diamonds, wide-and-shallow, narrow-and-deep

### Property-based: execution invariants
- Termination: `for_all plan <- dag_generator(), run(plan) terminates within 5 seconds`
- Event integrity: `for_all plan <- dag_generator(), run(plan) |> event_log |> hash_chain_valid?`
- Completeness: `for_all plan <- dag_generator(), run(plan) |> all_nodes_have_terminal_event?`
- Determinism: `for_all plan <- pure_dag_generator(), run(plan).outputs == run(plan).outputs`
- Isolation: `for_all {p1, p2} <- {dag_generator(), dag_generator()}, concurrent_run(p1, p2) |> both_valid?`

### Property-based: crash injection
- Inject random op failures (op raises with probability P) → run terminates, event log valid
- Inject random op slowness (op sleeps 0–100ms) → run still completes, no ordering violations

### Toy pack: functional tests
- Full run: parse → enrich → gate (auto-resolve in test) → render → deliver → run completes
- Gate pauses the run until resolved
- Gate resolved with approval → run continues
- Binary artifact stored and retrievable (content matches what render produced)
- Cache hit on parse (second run, same input)
- Replay produces identical output for parse + enrich + render
- Replay skips deliver

### Toy pack: through the public API
- `Liminara.run(ToyPack, input)` completes (with gate auto-resolved)
- `Liminara.replay(ToyPack, input, run_id)` replays successfully
- Subscriber receives all events from the ToyPack run

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Design notes

### StreamData DAG generator

```elixir
defmodule Liminara.Generators do
  use ExUnitProperties

  def dag_plan() do
    gen all width <- integer(1..10),
            depth <- integer(1..5) do
      build_random_dag(width, depth)
    end
  end

  defp build_random_dag(width, depth) do
    # Generate layers of nodes, each layer can reference nodes from previous layers
    # This guarantees acyclicity by construction
    ...
  end
end
```

The generator builds DAGs layer-by-layer. Each layer's nodes can only reference nodes in previous layers, guaranteeing acyclicity by construction. Ops for generated nodes use simple test ops (Identity, Concat, or randomly-failing variants).

### Gate implementation

Gates are implemented as `:recordable` ops that, instead of executing immediately, emit a `gate_requested` event and transition the node to `:waiting`. The Run.Server handles `gate_resolved` messages:

```elixir
def handle_cast({:resolve_gate, node_id, response}, state) do
  # Record gate decision, complete the node, dispatch ready nodes
end
```

In tests, gates can be auto-resolved by a test process that subscribes to run events and sends `gate_resolved` when it sees `gate_requested`.

### Why combine property tests and toy pack in one milestone?

They validate different aspects of the same layer:
- Property tests validate structural correctness (any shape, any failure pattern)
- The toy pack validates semantic correctness (all determinism classes, gates, binary artifacts, replay)

Both need the full OTP layer (M-01 through M-04) to be complete. Splitting them into two milestones would mean two sessions that both just exercise the existing code — better to do both in one pass.

## Out of scope

- Observation UI
- Real domain logic
- Performance benchmarking (just correctness)
- Load testing (hundreds of concurrent runs)

## Spec reference

- `docs/architecture/01_CORE.md` § "Five concepts", § "The scheduler: ten lines"
- StreamData: https://hexdocs.pm/stream_data/
- ExUnitProperties: https://hexdocs.pm/stream_data/ExUnitProperties.html
