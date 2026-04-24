---
id: M-IR-03-end-to-end
epic: E-07-integration-and-replay
status: complete
---

# M-IR-03: End-to-End Integration Tests

## Goal

Comprehensive integration tests proving the walking skeleton works: discovery run, replay run, cache behaviour, and interop with golden fixtures from E-04.

## Acceptance criteria

- [x] End-to-end discovery run: all ops execute, events valid, seal written
- [x] End-to-end replay: output matches discovery run for pure + recordable ops
- [x] Cache test: second fresh run → pure ops cache-hit
- [x] Golden fixtures readable by Elixir storage layer
- [x] Elixir-written event log matches canonical JSON spec

## Tests

### `test/liminara/integration_test.exs`

- Full discovery → replay cycle with TestPack
- Cache hit verification on repeated runs
- Golden fixture interop (already partially covered in E-04, extend here)
- Elixir-written events are valid canonical JSON

## TDD sequence

1. Tests first (red), then any fixes needed (green).
