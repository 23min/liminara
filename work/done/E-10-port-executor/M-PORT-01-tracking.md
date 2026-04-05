# M-PORT-01: Port Protocol + Executor + Python Runner — Tracking

**Started:** 2026-04-01
**Branch:** `milestone/M-PORT-01`
**Spec:** `work/done/E-10-port-executor/M-PORT-01-protocol-executor-runner.md`

## Acceptance Criteria

- [x] AC1: `Liminara.Executor.Port` module — spawn Python, framed JSON, timeout, crash detection
- [x] AC2: `Liminara.Executor.run/3` dispatches to `:port` (via optional `executor/0` callback)
- [x] AC3: JSON protocol with correlation IDs (request/success/error schemas)
- [x] AC4: Python op runner (`liminara_op_runner.py`) — read/dispatch/write/error handling
- [x] AC5: Python project scaffold (`runtime/python/`, pyproject.toml, uv)
- [x] AC6: Echo op end-to-end
- [x] AC7: Python crash detection (`os._exit` → `:port_exit`, exception → JSON error)
- [x] AC8: Timeout + port cleanup (`:os.cmd` kill, no zombies)

## Pre-existing Issues

- 5 test failures in liminara_web (resolve_inputs badmatch) — unrelated to this milestone

## Test Summary

- Elixir: 16 tests (13 port + 3 dispatch), 0 failures
- Python: 11 tests, 0 failures
- Core suite: 296 tests, 0 failures (no regressions)

## Notes

- `kill` is a shell built-in in this container — used `:os.cmd` instead of `System.cmd`
- `test_crash.py` uses `os._exit(42)` for true process crash (bypasses Python exception handlers)
- `test_raise.py` uses `raise ValueError` for handled exception path
- `uv` warns about VIRTUAL_ENV mismatch with integrations/python — harmless, different projects
