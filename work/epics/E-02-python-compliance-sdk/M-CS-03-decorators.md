---
id: M-CS-03-decorators
epic: E-02-python-compliance-sdk
status: done
---

# M-CS-03: Decorators, Run Context Manager, and Configuration

## Goal

Implement the instrumentation layer: `LiminaraConfig` for path configuration, a `run()` context manager that orchestrates event logging and sealing, and `@op`/`@decision` decorators that record execution details. When called outside a run context, decorated functions execute transparently with zero instrumentation.

## Acceptance criteria

### config.py — LiminaraConfig

- [x] `LiminaraConfig` is a dataclass with `store_root` (Path) and `runs_root` (Path)
- [x] Default `store_root` is `.liminara/store/artifacts` relative to cwd
- [x] Default `runs_root` is `.liminara/runs` relative to cwd
- [x] Constructor argument overrides env var; env var overrides default
- [x] Env vars: `LIMINARA_STORE_ROOT` overrides `store_root`, `LIMINARA_RUNS_ROOT` overrides `runs_root`
- [x] Paths are resolved to `Path` objects (strings accepted, converted to `Path`)

### run.py — Run context manager

- [x] `with run(pack_id, pack_version, config=None) as r:` creates a run context
- [x] `run_id` format: `{pack_id}-{YYYYMMDDTHHMMSS}-{8 hex random}` (e.g. `radar-20260314T120000-a1b2c3d4`)
- [x] Creates `EventLog`, `ArtifactStore`, `DecisionStore` instances using config paths
- [x] Emits `run_started` event on enter with payload: `{"run_id", "pack_id", "pack_version", "plan_hash"}` (`plan_hash` is always `null` — plan construction is an Elixir runtime concern, not Python SDK)
- [x] Emits `run_completed` event on normal exit with payload: `{"run_id", "outcome": "success", "artifact_hashes": [...]}`
- [x] Emits `run_failed` event on exception with payload: `{"run_id", "error_type", "error_message"}`
- [x] Does NOT emit `run_completed` when an exception occurs (only `run_failed`)
- [x] Re-raises exceptions — does not swallow them
- [x] Writes `seal.json` on normal exit: canonical JSON (RFC 8785, via `canonical_json()` from `hash.py`) with `{"run_id", "run_seal", "completed_at", "event_count"}`
- [x] `run_seal` in `seal.json` equals `event_hash` of the `run_completed` event
- [x] Does NOT write `seal.json` when the run fails
- [x] Sets a `contextvars.ContextVar` so decorators can find the active run
- [x] `r.run_id` is accessible inside the context block
- [x] `r.event_log`, `r.artifact_store`, `r.decision_store` are accessible
- [x] Maintains a node counter (monotonically increasing, zero-padded to 3 digits in node_id)
- [x] Tracks artifact hashes produced during the run for `run_completed` payload

### decorators.py — @op

- [x] `@op(name, version, determinism)` decorates a function to emit events and store artifacts
- [x] `determinism` must be one of: `"pure"`, `"pinned_env"`, `"recordable"`, `"side_effecting"` — raises `ValueError` at decoration time otherwise
- [x] On call: assigns `node_id` = `{name}-{zero_padded_counter}` (e.g. `summarize-001`)
- [x] Sets `node_id` in a `contextvars.ContextVar` for inner `@decision` to read
- [x] Emits `op_started` event with payload: `{"node_id", "op_id": name, "op_version": version, "input_hashes": [hash]}`
- [x] `input_hashes` contains one hash: the artifact hash of the serialized inputs (`{"args": [...], "kwargs": {...}}` → canonical JSON → bytes → store as artifact → hash)
- [x] Calls the wrapped function
- [x] On success: stores return value as artifact (canonical JSON bytes), emits `op_completed` with payload: `{"node_id", "output_hashes": [hash], "cache_hit": false, "duration_ms": float}`
- [x] `duration_ms` measured with `time.perf_counter()`, stored as float milliseconds
- [x] On exception: emits `op_failed` with payload: `{"node_id", "error_type": type(e).__name__, "error_message": str(e)}`
- [x] Re-raises exceptions from the wrapped function
- [x] Restores previous `node_id` context var after execution (supports future nesting)

### decorators.py — @decision

- [x] `@decision(decision_type)` decorates a function to record its result as a decision
- [x] `decision_type` must be one of: `"llm_response"`, `"human_gate"`, `"stochastic"`, `"model_selection"` — raises `ValueError` at decoration time otherwise
- [x] Calls the wrapped function
- [x] On success: writes decision record via `DecisionStore.write()` with fields: `{"node_id", "op_id", "op_version", "decision_type", "inputs": {"args_hash": hash}, "output": {"result_hash": hash}, "recorded_at": timestamp}` — `DecisionStore.write()` computes and adds `decision_hash` automatically
- [x] Emits `decision_recorded` event with payload: `{"node_id", "decision_hash", "decision_type"}`
- [x] `node_id`, `op_id`, `op_version` are read from the enclosing `@op` context via context vars
- [x] If `@decision` is called inside `with run():` but outside any `@op`, it passes through transparently (same as no-run-context behavior) — `@decision` requires an enclosing `@op` to have context to record

**Note on decision record schema:** The `inputs` and `output` fields are open objects. The data model spec (`11_Data_Model_Spec.md`) shows an LLM-specific example with `prompt_hash`, `model_id`, etc. — that is illustrative of the `llm_response` decision type. The generic decorator uses `{"args_hash": hash}` and `{"result_hash": hash}` as a baseline. Users building LLM integrations (M-CS-05) can extend these objects with domain-specific fields.

### Stacking @op and @decision

- [x] When `@op` is the outer decorator and `@decision` is inner, both emit their events in correct order: `op_started` → `decision_recorded` → `op_completed`
- [x] The decision's `node_id` matches the op's `node_id`

### No-run-context passthrough

- [x] If `@op`-decorated function is called outside `with run():`, it executes normally and returns its result
- [x] If `@decision`-decorated function is called outside `with run():`, it executes normally and returns its result
- [x] No events are emitted, no files are written, no errors are raised when outside a run context
- [x] Stacked `@op` + `@decision` also passes through cleanly outside a run context

### __init__.py exports

- [x] `from liminara import run` works (run context manager)
- [x] `from liminara import op, decision` works (decorators)
- [x] `from liminara import LiminaraConfig` works

## Example usage

```python
from liminara import run, op, decision, LiminaraConfig

@op(name="load_document", version="1.0.0", determinism="pure")
def load_document(path: str) -> str:
    return Path(path).read_text()

@op(name="summarize", version="1.0.0", determinism="recordable")
@decision(decision_type="llm_response")
def summarize(text: str, model: str = "claude-haiku-4-5-20251001") -> str:
    response = anthropic_client.messages.create(...)
    return response.content[0].text

@op(name="save_output", version="1.0.0", determinism="side_effecting")
def save_output(summary: str, path: str) -> None:
    Path(path).write_text(summary)

# Instrumented run — events, artifacts, decisions, seal
with run("example", "0.1.0") as r:
    text = load_document("input.md")
    summary = summarize(text)
    save_output(summary, "output.md")

# Outside run context — functions still work, zero instrumentation
text = load_document("input.md")
```

## Tests

### `test_config.py` (~8 tests)

- Default paths resolve to `.liminara/store/artifacts` and `.liminara/runs`
- Constructor args override defaults
- Env var `LIMINARA_STORE_ROOT` overrides default `store_root`
- Env var `LIMINARA_RUNS_ROOT` overrides default `runs_root`
- Constructor arg takes precedence over env var
- String paths are converted to `Path` objects
- Config with no args and no env vars uses defaults
- Custom config passed to `run()` is respected

### `test_run.py` (~18 tests)

- `run_id` matches pattern `{pack_id}-{YYYYMMDDTHHMMSS}-{8hex}`
- `run_started` is first event in log
- `run_started` payload contains `run_id`, `pack_id`, `pack_version`, `plan_hash: null`
- `run_completed` is last event on normal exit
- `run_completed` payload contains `outcome: "success"` and `artifact_hashes` list
- `run_failed` is last event on exception
- `run_failed` payload contains `error_type` and `error_message`
- No `run_completed` event when exception occurs
- Exception is re-raised (not swallowed)
- `seal.json` exists after normal exit
- `seal.json` contains correct `run_id`, `run_seal`, `completed_at`, `event_count`
- `run_seal` matches `event_hash` of `run_completed` event
- `seal.json` is canonical JSON
- No `seal.json` after failed run
- `r.run_id` is accessible inside context
- `r.event_log` / `r.artifact_store` / `r.decision_store` are accessible
- Hash chain is valid after run completes
- Multiple sequential runs produce separate run directories

### `test_decorators_op.py` (~14 tests)

- `@op` with valid determinism does not raise at decoration time
- `@op` with invalid determinism raises `ValueError` at decoration time
- `node_id` format is `{name}-{counter}` with zero-padded 3-digit counter
- `op_started` event emitted with correct payload
- `input_hashes` contains artifact hash of serialized inputs
- Input artifact exists in store and deserializes to `{"args": [...], "kwargs": {...}}`
- `op_completed` event emitted with correct payload
- `output_hashes` contains artifact hash of serialized return value
- Output artifact exists in store and matches return value
- `cache_hit` is always `false`
- `duration_ms` is a positive float
- `op_failed` event emitted on exception with correct error_type and error_message
- Exception is re-raised from `@op`
- Multiple ops in one run get sequential node_ids (`op-001`, `op-002`, ...)

### `test_decorators_decision.py` (~7 tests)

- `@decision` with valid decision_type does not raise at decoration time
- `@decision` with invalid decision_type raises `ValueError` at decoration time
- Decision record written to `decisions/{node_id}.json`
- Decision record contains correct fields (`node_id`, `op_id`, `op_version`, `decision_type`, `inputs`, `output`, `recorded_at`)
- `decision_hash` is correct (verified by recomputing)
- `decision_recorded` event emitted with correct payload (`node_id`, `decision_hash`, `decision_type`)
- Return value of decorated function is passed through unchanged

### `test_decorators_stacking.py` (~4 tests)

- `@op` outside + `@decision` inside: events emitted in order `op_started` → `decision_recorded` → `op_completed`
- Decision's `node_id` matches enclosing op's `node_id`
- Both artifacts (input/output) and decision record exist on disk
- Return value flows through both decorators unchanged

### `test_no_run_context.py` (~6 tests)

- `@op`-decorated function returns correct result outside run context
- `@decision`-decorated function returns correct result outside run context
- Stacked `@op` + `@decision` returns correct result outside run context
- No files or directories created when called outside run context (use a clean tmp dir)
- No exceptions raised for any decorator combination outside run context
- Functions with args, kwargs, and return values all pass through correctly

### `test_integration.py` (~3 tests)

- End-to-end: `run()` with one plain `@op` and one stacked `@op`+`@decision` produces correct event sequence: `run_started` → `op_started` → `op_completed` → `op_started` → `decision_recorded` → `op_completed` → `run_completed`
- Hash chain verifies successfully after full run
- All artifacts, decision records, and seal.json exist with correct content

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Cache lookup/storage (`cache_hit` is always `false`)
- Replay (injecting stored decisions)
- `@pipeline` decorator (`run()` context manager suffices)
- `@llm_call` shorthand
- Concurrent op execution
- Non-JSON-serializable inputs/outputs (all values must be JSON-serializable)
- `artifact_produced` events (deferred — ops store artifacts, but this event type is not emitted in M-CS-03; can be added later without breaking anything)

## Spec reference

- `docs/analysis/11_Data_Model_Spec.md` — event types, payload schemas, seal format, decision record schema
- `docs/analysis/09_Compliance_Demo_Tool.md` — Python SDK design
- `docs/architecture/01_CORE.md` § Five concepts, § Caching

## Related ADRs

- none yet
