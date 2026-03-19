---
id: M-EE-02-op
epic: E-06-execution-engine
status: done
---

# M-EE-02: Op Behaviour

## Goal

Define the `Liminara.Op` behaviour — the contract that all operations implement. An op is a typed function (inputs → outputs) with a determinism class that controls caching and replay. This milestone also implements executor dispatch (`:inline` and `:task`).

## Acceptance criteria

### Behaviour: `Liminara.Op`

- [x] Defines callbacks:
  - `name() :: String.t()` — op identifier
  - `version() :: String.t()` — op version (for cache key)
  - `determinism() :: :pure | :pinned_env | :recordable | :side_effecting`
  - `execute(inputs :: map()) :: {:ok, outputs :: map()} | {:ok, outputs :: map(), decisions :: list()} | {:error, term()}`
- [x] A module implementing `@behaviour Liminara.Op` can be called by the executor

### Determinism classes

- [x] `:pure` — same inputs always produce same output
- [x] `:pinned_env` — same inputs + same environment → same output
- [x] `:recordable` — nondeterministic, decision is recorded
- [x] `:side_effecting` — changes the outside world
- [x] Each op declares its determinism class via the callback

### Executor dispatch: `Liminara.Executor`

- [x] `Executor.run(op_module, inputs, opts)` → dispatches to the correct executor
- [x] `:inline` executor — calls `op_module.execute(inputs)` directly in the calling process
- [x] `:task` executor — spawns a `Task` under a given `Task.Supervisor`, returns result
- [x] Default executor is `:inline`
- [x] Executor measures `duration_ms` and returns it alongside the result

### Test ops

- [x] `Liminara.TestOps.Upcase` — pure op that upcases a string input
- [x] `Liminara.TestOps.Concat` — pure op that concatenates two string inputs
- [x] `Liminara.TestOps.Fail` — op that always returns `{:error, :intentional_failure}`
- [x] `Liminara.TestOps.Recordable` — recordable op that returns a decision
- [x] These live in `test/support/` and are only compiled for tests

## Tests

### `test/liminara/op_test.exs`

**Behaviour compliance:**
- Test op implements all callbacks
- `name/0`, `version/0`, `determinism/0` return expected values
- `execute/1` with valid inputs returns `{:ok, outputs}`
- `execute/1` returning error works

**Executor dispatch:**
- `:inline` executor calls op directly, returns `{:ok, result, duration_ms}`
- `:task` executor runs op in a separate process, returns `{:ok, result, duration_ms}`
- Duration is a positive integer (milliseconds)
- Failed op returns `{:error, reason, duration_ms}` through both executors

**Determinism:**
- Pure op declares `:pure`
- Recordable op declares `:recordable`
- Recordable op returns decisions in the result tuple

## TDD sequence

1. **Test agent** reads this spec, writes `op_test.exs` and test ops in `test/support/`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Op` behaviour and `Liminara.Executor` until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline.

## Out of scope

- Port, NIF, or container executors
- Op registration or discovery
- Input/output type validation
- Retry logic

## Spec reference

- `docs/architecture/01_CORE.md` § Five concepts (Op), § Determinism classes
