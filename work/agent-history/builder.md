# Builder Agent History

## E-10: Port Executor (2026-04-01)

### Patterns that worked
- TDD cycle worked cleanly: protocol tests first, then execution tests, then integration
- Putting Python project at `runtime/python/` with `uv` — transparent venv management
- `{packet, 4}` framing: BEAM handles length prefix automatically on send, just send raw payload via `Port.command`
- Self-configuring executor: `default_python_root/0` resolves from app config or `__DIR__` — Run.Server needs no changes

### Pitfalls
- `kill` is a shell built-in in Debian slim containers — use `:os.cmd/1` not `System.cmd("kill", ...)`
- `sys.exit()` in Python raises `SystemExit(BaseException)`, not caught by `except Exception`. Added explicit `SystemExit` catch in runner. For true crash tests, use `os._exit(42)`.
- Cache tests need explicit ETS table passed via `cache: ctx.cache` — the supervised Cache GenServer may not be running in tests
- `VIRTUAL_ENV` env var from `integrations/python/` causes uv warnings — harmless but noisy

### Conventions established
- Op modules declare `:port` executor via optional `executor/0` callback
- Op modules declare Python op name via optional `python_op/0` callback
- Python test ops live in `runtime/python/src/ops/test_*.py`
- Elixir test op wrappers live in `test/support/test_port_ops.ex`
