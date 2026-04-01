---
id: E-10-port-executor
phase: 5
status: done
---

# E-10: Port Executor

## Goal

Enable Liminara ops to delegate computation to external Python processes via Erlang ports, using a zero-dependency, OTP-standard pattern. This unlocks the entire Python ecosystem (feedparser, trafilatura, LLM SDKs, vector stores) for use in Liminara packs while keeping Elixir as the orchestration layer.

## Context

The runtime currently supports two executor types: `:inline` (direct function call) and `:task` (supervised async Task). Python ops — needed for the Radar pack and future domain packs — require a third executor type: `:port`.

The Elixir/OTP community converges on raw Erlang Ports with `{packet, 4}` length-framed JSON as the standard pattern for external process communication. No external libraries are needed. The interface integrates with the existing `Liminara.Executor.run/3` dispatch, so callers (op modules, Run.Server) are unaware of the execution mechanism.

## Scope

### In Scope

- `Liminara.Executor.Port` module — spawn Python via `Port.open/2`, `{packet, 4}` framed JSON protocol, correlation IDs, configurable timeout, crash/exit detection
- Integration with existing executor dispatch (`:port` alongside `:inline` and `:task`)
- Python op runner (`liminara_op_runner.py`) — generic dispatcher that reads framed JSON, routes to op modules, writes framed JSON responses
- Python project scaffold at `runtime/python/` with `uv` for dependency management
- Error protocol: Python catches exceptions → JSON error response; Elixir handles `:exit_status` for process crashes
- End-to-end integration tests: pure Python op (cached), recordable (replayed), side_effecting (skipped on replay)
- Echo op for smoke testing

### Out of Scope

- Long-running worker pool (V2 upgrade — future optimization when spawn overhead matters)
- NimblePool integration (future)
- Separate stderr channel (errors go through JSON protocol)
- Python SDK compatibility (`integrations/python/` is a separate, standalone SDK)
- Specific domain ops (those belong to pack epics)

## Constraints

- Zero Elixir dependencies — raw `Port.open/2` + OTP primitives only
- Python side uses `uv` for package management (already decided, D-2026-04-01-003)
- Spawn-per-call for V1 — each op invocation spawns a fresh Python process
- Protocol must include correlation IDs from day 1 (costs nothing now, required for V2 pooling)
- Must work identically on macOS, devcontainer, and Linux containers

## Success Criteria

- [ ] An Elixir op module can delegate to a Python script via `executor: :port` and receive results
- [ ] The `{packet, 4}` JSON protocol handles requests up to at least 10MB payloads
- [ ] Python process crashes are detected and surfaced as op failures (not silent)
- [ ] Timeouts kill the Python process and report failure
- [ ] All three determinism classes work correctly for Python ops: `:pure` (cached on second run), `:recordable` (replayed from stored decision), `:side_effecting` (skipped on replay)
- [ ] `uv run` manages Python dependencies without manual virtualenv setup
- [ ] Tests are deterministic — no network calls, no time-dependent behavior

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Python startup overhead (~50-200ms per spawn) | Med | Acceptable for V1 where ops take seconds. V2 (NimblePool) eliminates this. |
| `uv` availability in CI/containers | Low | uv is a single binary, easy to install. Already in project toolchain. |
| Large payloads (embeddings, article text) | Low | `{packet, 4}` supports up to 4GB messages. JSON encoding is the bottleneck — acceptable for V1. |
| Zombie Python processes on unclean shutdown | Med | Port.close/1 sends EOF. GenServer terminate/2 fallback: kill via OS PID. Test coverage for crash scenarios. |

## Milestones

| ID | Title | Summary | Status |
|----|-------|---------|--------|
| M-PORT-01 | Port protocol + executor + Python runner | `{packet, 4}` JSON protocol, `Liminara.Executor.Port`, `liminara_op_runner.py`, `uv` project scaffold, echo op | done |
| M-PORT-02 | Integration test | End-to-end via Run.Server across all determinism classes. Artifacts stored, events logged, cache/replay honored. | done |

## Design Notes

### Protocol

```
Elixir → Python (stdin):  [4-byte big-endian length][JSON payload]
Python → Elixir (stdout): [4-byte big-endian length][JSON payload]
```

Request JSON:
```json
{"id": "correlation-id", "op": "module_name", "inputs": {...}}
```

Response JSON (success):
```json
{"id": "correlation-id", "status": "ok", "outputs": {...}}
```

Response JSON (error):
```json
{"id": "correlation-id", "status": "error", "error": "traceback string"}
```

### Upgrade Path to V2

When spawn-per-call becomes a bottleneck:
1. Replace internals of `Executor.Port` with NimblePool of long-running PortWorker GenServers
2. Python runner already handles correlation IDs — no protocol change
3. Callers (op modules, Run.Server) unchanged — same `Executor.run/3` interface

### Python Project Structure

```
runtime/python/
  pyproject.toml          # uv project, minimal deps (just json/struct stdlib)
  src/
    liminara_op_runner.py # Generic dispatcher: read → route → write
    ops/
      echo.py             # Smoke test op
```

## References

- Erlang OTP Ports documentation: erlang.org/doc/system/c_port.html
- Sasa Juric — "Outside Elixir: running external programs with ports"
- Stuart Engineering — "How we use Python within Elixir" (ErlPort + Poolboy case study)
- NimblePool hexdocs (Port worker example)
- Decision D-2026-04-01-003: Python ops via :port for Radar pack
