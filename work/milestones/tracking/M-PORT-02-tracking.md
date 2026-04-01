# M-PORT-02: Integration Test — Tracking

**Started:** 2026-04-01
**Branch:** `milestone/M-PORT-01` (both milestones on same branch)
**Spec:** `work/epics/E-10-port-executor/M-PORT-02-integration-test.md`

## Acceptance Criteria

- [x] AC1: Pure Python op — cached on second run with same inputs
- [x] AC2: Recordable Python op — replay uses stored decisions, no Python spawn
- [x] AC3: Side_effecting Python op — skipped on replay
- [x] AC4: Pinned_env — behaves like pure (covered by pure test, same cache logic)
- [x] AC5: Mixed Elixir + Python plan — data flows correctly via artifacts
- [x] AC6: Run.Server dispatches to :port based on op's executor/0 callback
- [x] AC7: Python op failure — node fails, downstream not dispatched, run status failed/partial

## Test Summary

- Integration tests: 10, 0 failures
- Core suite: 306 tests (8 properties), 0 failures
- Python: 11 tests, 0 failures
- Total new tests in E-10: 27 Elixir + 11 Python = 38 tests
