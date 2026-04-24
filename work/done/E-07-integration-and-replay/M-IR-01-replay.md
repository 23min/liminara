---
id: M-IR-01-replay
epic: E-07-integration-and-replay
status: complete
---

# M-IR-01: Replay

## Goal

Implement replay support in `Liminara.Run` — when replaying a previous run, recordable ops inject stored decisions instead of executing, and side-effecting ops are skipped. Pure ops re-execute normally (and should produce identical output).

## Acceptance criteria

- [x] `Run.execute/2` accepts a `replay: run_id` option
- [x] In replay mode, recordable ops load the stored decision from the previous run's decision store
- [x] Recordable ops in replay return the stored output without calling `execute/1`
- [x] Pure ops re-execute normally in replay mode (same inputs → same output)
- [x] Side-effecting ops are skipped in replay mode (emit `op_completed` with `cache_hit: true`, no execution)
- [x] Replay run gets its own run_id, event log, and seal
- [x] Replay output for pure + recordable ops matches the original run's output

## Tests

### `test/liminara/run/replay_test.exs`

- Discovery run produces output, events, and decisions
- Replay run: recordable op returns same output as discovery run
- Replay run: pure op re-executes and produces same output
- Replay run: side-effecting op is skipped
- Replay run has its own valid hash chain
- Replay run has its own seal

## TDD sequence

1. **Test agent** writes `replay_test.exs`. Tests fail (red).
2. Human reviews.
3. **Impl agent** implements replay in `Liminara.Run`. Tests pass (green).
4. Validation pipeline.

## Out of scope

- Discovery mode (dynamic DAG)
- Partial replay (replay some ops, re-execute others)
