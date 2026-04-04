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
- Python's built-in `hash()` is process-salted. Do not use it for deterministic fixture seeds when tests spawn subprocesses or compare values across runs.

### Conventions established
- Op modules declare `:port` executor via optional `executor/0` callback
- Op modules declare Python op name via optional `python_op/0` callback
- Python test ops live in `runtime/python/src/ops/test_*.py`
- Elixir test op wrappers live in `test/support/test_port_ops.ex`

## M-RAD-06: Replay Correctness (2026-04-03)

### Patterns that worked
- Store output_hashes alongside decisions for replay — avoids reconstructing outputs from decision content
- Backward compat via format sniffing: JSON object → wrap in list; JSON with `"decisions"` key → new format
- Optional `env_vars/0` callback on op modules — no behaviour change needed, `function_exported?/3` check in executor
- `RadarReplayTestPack` with literal fixture items — tests full Python port pipeline without network calls
- Characterization test (`ReplayGapPack`) for unit-level replay, separate Radar test for pipeline-level

### Pitfalls
- Both `run.ex` (sync) and `run/server.ex` (async) have independent replay paths — must update both
- `uv run` sets its own `VIRTUAL_ENV` in child process — can't test "VIRTUAL_ENV absent", only "host value doesn't leak"
- Env whitelist without op-declared vars silently breaks API key access — test suite stays green but live runs fail
- Marking ACs done without the required test is worse than leaving them open — reviewers catch it
- Run only changed test files during TDD; full core suite takes 15+ seconds (server stress/timeout tests)

### Conventions established
- Decision file format: `{"decisions": [...], "output_hashes": {...}}` per node_id
- Op modules can declare `env_vars/0` returning a list of env var names to preserve through port executor
- Radar test packs live in `apps/liminara_radar/test/support/`
- `mix.exs` needs `elixirc_paths` override for test support files to compile

## M-RAD-04: Web UI + Scheduler (2026-04-03)

### Patterns that worked
- Starting with GenServer (pure logic, no UI deps) before LiveView pages — fastest TDD cycle
- `Decision.Store.get_outputs/3` for keyed artifact lookup — events only store flat hash lists
- Config-gated supervisor children: `if enabled, do: [child_spec], else: []` in application.ex
- `Application.get_env` overrides in test setup + `on_exit` cleanup — clean isolation for LiveView tests

### Pitfalls
- Event payload `output_hashes` is `Map.values(hash_map)` — a flat list, not a keyed map. Tests with `%{"key" => hash}` pass but real runs fail. Always use Decision.Store for keyed lookups.
- Cross-app module references (web → radar) cause "undefined module" warnings unless `mix.exs` declares the umbrella dependency
- `Artifact.Store.get/2` needs the 2-arity (direct) form with explicit store_root, not the 1-arity GenServer form, when reading from configurable paths

### Conventions established
- Radar LiveView pages live in `apps/liminara_web/lib/liminara_web/live/radar_live/`
- Global nav bar in `app.html.heex` layout (not per-page inline nav)
- Scheduler is config-gated: `config :liminara_radar, :scheduler, enabled: true, daily_at: ~T[06:00:00]`
- Sources config path configurable via `config :liminara_radar, :sources_path`

## M-TRUTH-01: Execution Spec + Outcome Design (2026-04-04)

### Patterns that worked
- For a design milestone, limited shared-struct codification plus focused contract tests is acceptable when the purpose is only to freeze canonical names, defaults, and field shapes.
- Use the milestone spec plus downstream epic references to decide scope boundaries, not an opportunistic next implementation step.
- On a dirty milestone branch, close with scoped validation of the touched contract files and record unrelated umbrella blockers explicitly instead of broadening the milestone to fix off-scope drift.

### Pitfalls
- Suggesting legacy callback bridges or tuple/JSON result normalizers inside M-TRUTH-01 blurs the design milestone into M-TRUTH-02.
- Placeholder or newly codified structs are schema-freezing artifacts until live runtime paths consume them; do not describe that as completed migration.
