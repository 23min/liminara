---
id: M-IR-02-pack
epic: E-07-integration-and-replay
status: complete
---

# M-IR-02: Pack Behaviour + Public API

## Goal

Define `Liminara.Pack` behaviour and the top-level public API (`Liminara.run/2`, `Liminara.replay/3`). A Pack is a module that provides op definitions, a plan builder, and optional init. The public API is the entry point for using the runtime.

## Acceptance criteria

- [x] `Liminara.Pack` behaviour with callbacks: `id/0`, `version/0`, `ops/0`, `plan/1`
- [x] `Liminara.run(pack_module, input, opts)` → builds plan, executes, returns result
- [x] `Liminara.replay(pack_module, input, replay_run_id, opts)` → replays with stored decisions
- [x] `TestPack` implements the Pack behaviour with test ops
- [x] `Liminara.run(TestPack, input)` works end-to-end

## Tests

### `test/liminara/pack_test.exs`

- TestPack implements all callbacks
- `Liminara.run(TestPack, input)` returns a successful result
- `Liminara.replay(TestPack, input, run_id)` returns matching output

## TDD sequence

1. Tests first (red), then implement (green).

## Out of scope

- `init/0` callback (deferred — not needed for walking skeleton)
- Pack registration or discovery
