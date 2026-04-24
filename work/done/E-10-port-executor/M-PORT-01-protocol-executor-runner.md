---
id: M-PORT-01-protocol-executor-runner
epic: E-10-port-executor
status: complete
---

# M-PORT-01: Port Protocol + Executor + Python Runner

## Goal

Build the complete `:port` executor pipeline: an Elixir module that spawns a Python process via `Port.open/2`, exchanges length-framed JSON over stdio, and a Python-side dispatcher that receives requests, routes to op modules, and returns results. After this milestone, an Elixir op module can delegate to a Python script and receive artifacts back.

## Context

The runtime has two executor types: `:inline` (direct call) and `:task` (supervised async Task), dispatched via `Liminara.Executor.run/3`. Python ops — needed for Radar and future domain packs — require a third type: `:port`.

The OTP-standard pattern is `Port.open/2` with `{packet, 4}` (4-byte big-endian length prefix) for message framing. This is zero-dependency, battle-tested, and the community-converged approach.

Relevant existing code:
- `Liminara.Executor` — `runtime/apps/liminara_core/lib/liminara/executor.ex`
- `Liminara.Op` behaviour — `runtime/apps/liminara_core/lib/liminara/op.ex`

## Acceptance Criteria

1. `Liminara.Executor.Port` module exists with a `run/3` function that:
   - Spawns a Python process via `Port.open({:spawn_executable, ...}, [:binary, {:packet, 4}, :exit_status])`
   - Sends a JSON request to stdin (length-framed)
   - Reads a JSON response from stdout (length-framed)
   - Returns `{:ok, outputs, duration_ms}` or `{:ok, outputs, duration_ms, decisions}` or `{:error, reason, duration_ms}`
   - Kills the Python process and returns `{:error, :timeout, duration_ms}` if it exceeds the configured timeout

2. `Liminara.Executor.run/3` dispatches to `Executor.Port` when `executor: :port` is passed, alongside the existing `:inline` and `:task` paths

3. The JSON protocol includes correlation IDs in every request/response:
   - Request: `{"id": "<correlation_id>", "op": "<module_name>", "inputs": {...}}`
   - Success: `{"id": "<correlation_id>", "status": "ok", "outputs": {...}}`
   - Success with decisions: `{"id": "<correlation_id>", "status": "ok", "outputs": {...}, "decisions": [...]}`
   - Error: `{"id": "<correlation_id>", "status": "error", "error": "<message>"}`

4. Python op runner (`liminara_op_runner.py`) exists at `runtime/python/src/liminara_op_runner.py`:
   - Reads 4-byte length prefix + JSON payload from stdin
   - Dispatches to op module based on `op` field in request
   - Catches all exceptions and returns JSON error response (no unhandled crashes to stderr)
   - Writes 4-byte length prefix + JSON response to stdout
   - Exits cleanly on EOF (port closed)

5. Python project scaffold exists at `runtime/python/`:
   - `pyproject.toml` with `uv` configuration, Python >= 3.12
   - `src/liminara_op_runner.py` — the dispatcher
   - `src/ops/echo.py` — trivial echo op (returns inputs as outputs)
   - `src/ops/__init__.py`

6. Echo op works end-to-end:
   - Elixir test calls `Executor.Port.run(echo_op_module, %{"message" => "hello"}, timeout: 5000)`
   - Python echo op receives `{"message": "hello"}`, returns `{"message": "hello"}`
   - Elixir receives `{:ok, %{"message" => "hello"}, _duration_ms}`

7. Python process crash is detected:
   - If the Python process exits with non-zero status, Elixir returns `{:error, {:port_exit, status}, duration_ms}`
   - If the Python process is killed (SIGKILL), Elixir returns an error (not a hang)

8. Port cleanup on timeout:
   - When timeout fires, Elixir closes the port and kills the OS process (via `Port.info(port, :os_pid)`)
   - No zombie Python processes left after timeout

## Tests

### Protocol tests (Elixir unit)
- Encode a request map to length-framed JSON binary, decode it back — round-trip
- Decode a success response, an error response, a response with decisions
- Decode malformed JSON — returns `{:error, :invalid_json, _}`

### Executor tests (Elixir integration)
- Echo op: send inputs, receive same inputs back as outputs
- Echo op with decisions: Python returns decisions list, Elixir gets `{:ok, outputs, duration, decisions}`
- Timeout: Python op that sleeps forever → `{:error, :timeout, _}` within configured timeout + tolerance
- Crash: Python op that calls `sys.exit(1)` → `{:error, {:port_exit, 1}, _}`
- Large payload: send and receive a 1MB JSON payload — no truncation
- Invalid JSON from Python: runner returns malformed data → `{:error, :invalid_json, _}`

### Python runner tests (pytest)
- Read a length-framed message, dispatch to echo op, write length-framed response
- Unknown op name → error response with descriptive message
- Op that raises exception → error response with traceback string
- EOF on stdin → clean exit (no crash)

## Technical Notes

### Elixir side

The `Executor.Port` module is a simple function module (not a GenServer) for V1. It:
1. Resolves the Python script path from op module metadata or config
2. Spawns via `Port.open({:spawn_executable, uv_path}, args: ["run", "python", runner_path])`
3. Sends one framed JSON message
4. Waits for one framed JSON response (with timeout)
5. Closes the port

The op module needs a way to declare it uses `:port` execution. Options:
- (a) Op module implements an optional `executor/0` callback returning `:port`
- (b) Plan node metadata includes `executor: :port`
- (c) Config/convention: ops in a specific namespace use `:port`

**Question for implementation:** Which approach is cleanest? (a) keeps it in the op module, (b) is more flexible. Suggest (a) for simplicity.

### Python side

The runner uses only stdlib (`sys`, `struct`, `json`, `importlib`, `traceback`). Op modules are imported dynamically:

```python
module = importlib.import_module(f"ops.{op_name}")
result = module.execute(inputs)
```

### uv integration

The Python process is spawned via `uv run python src/liminara_op_runner.py` from the `runtime/python/` directory. `uv` handles the virtualenv transparently.

## Out of Scope

- Long-running worker pool (V2 — future optimization)
- NimblePool integration
- Separate stderr channel
- Any domain-specific ops (Radar ops belong to E-11)
- GenServer wrapper around the port (V1 is spawn-per-call)
- Run.Server integration (that's M-PORT-02)

## Dependencies

- `uv` must be available in the environment (devcontainer, CI)
- Python >= 3.12

## Resolved Questions

- **Op executor declaration:** Op module implements an optional `executor/0` callback returning `:port` (or `:inline` default). Executor dispatch checks `op_module.executor/0` if defined, falls back to `:inline`. No plan-level override for now — add later if needed.
