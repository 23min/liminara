# App Legibility: Liminara

Instructions for agents to boot, drive, and verify Liminara end-to-end.

This is a starting point — expand it as E-21 M-PACK-02 introduces the `e2e-harness` skill and the full scenario-test tooling.

## Quick Health Check

```bash
# Phoenix LiveView reachable?
curl -fsS http://localhost:4005/ >/dev/null && echo "phoenix ok"

# A2UI WebSocket endpoint up? (Bandit HTTP root responds with Lit debug renderer)
curl -fsS http://localhost:4006/ >/dev/null && echo "a2ui ok"
```

## Boot

Run from `/workspaces/liminara/runtime/`:

| Service | Command | Port | Ready signal |
|---------|---------|------|--------------|
| Phoenix LiveView (runs + observation UI) | `iex --sname liminara -S mix phx.server` | 4005 | `Running LiminaraWeb.Endpoint with Bandit` in stdout |
| A2UI WebSocket (embedded with Phoenix) | (same process) | 4006 | Liminara observation Bandit server logs `starting on port 4006` |

First-time / after dep changes:

```bash
cd runtime && mix deps.get && mix compile
cd runtime/python && uv sync
```

## Verify a Change

After implementing a feature or fix:

1. **Compile + focused tests** — `cd runtime && mix compile --warnings-as-errors && mix test --only <tag>` or the specific test file(s) touching the change.
2. **Boot the app** — `iex --sname liminara -S mix phx.server` from `runtime/`.
3. **Trigger the affected surface**:
   - Pack / run work → open `http://localhost:4005/runs`, kick off a run, watch the DAG + event timeline
   - Radar-specific → `http://localhost:4005/radar/briefings` or `/radar/sources`
   - A2UI / observation wire → connect via the A2UI debug renderer at `http://localhost:4006/`
4. **Check outputs** — artifacts under `runtime/data/artifacts/`, event log JSONL under `runtime/data/events/<run_id>.jsonl`, decisions under `runtime/data/decisions/<run_id>/`, Radar LanceDB under `runtime/data/radar/lancedb/` (dev).
5. **Full validation pipeline** before handoff:
   - Elixir: `mix format && mix credo && mix dialyzer && mix test`
   - Python: `cd runtime/python && uv run ruff check . && uv run ruff format --check . && uv run ty check && uv run pytest`
   - dag-map submodule (if touched): `cd dag-map && npm test`
6. **Shutdown cleanly** (see below).

## Pack-specific Boot (Radar)

The Radar pack exposes its own UI pages under `/radar/*` and registers a scheduler. To run a Radar discovery end-to-end:

```bash
# From runtime/
iex --sname liminara -S mix phx.server
```

Then in the IEx session:

```elixir
Liminara.Radar.Pack.discover(topic: :default)
```

Watch the Observation UI at `http://localhost:4005/runs` to see the DAG execute.

## Port Safety

- Never run `pkill -f beam.smp` or `killall beam.smp` — that kills **all** Erlang VMs on the machine, including anything running in other devcontainers or worktrees.
- Prefer targeted shutdown (see below) or send `:init.stop()` from an IEx session.

## Shutdown

```bash
# From the IEx session:
:init.stop()

# Or from another shell, targeting the named node only:
epmd -names   # find the liminara node name
pkill -f 'sname liminara'   # targets only the named node
```

If Phoenix is stuck, `Ctrl-C Ctrl-C` twice in the IEx prompt breaks out; use `:init.stop()` for clean shutdown when the supervisor tree needs to flush (event logs, LanceDB).

## Notes for E-21 / M-PACK-02

This file will be superseded or expanded by the `e2e-harness` skill (Playwright + `LiminaraTest.Harness` + `A2UICapture`). Until then, agents should follow the steps above for manual verification.
