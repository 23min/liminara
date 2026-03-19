---
id: M-ES-02-fixtures
epic: E-04-elixir-scaffolding
status: done
---

# M-ES-02: Golden Test Fixtures

## Goal

Create hand-crafted golden test fixtures representing a valid Liminara run on disk, and verify them from both Elixir and Python — proving the data model spec produces identical results across languages.

## Context: Why golden fixtures?

The data model spec (`docs/analysis/11_Data_Model_Spec.md`) defines the on-disk format. Both the Python SDK and the Elixir runtime must read and write this format identically. Golden fixtures are the contract test: hand-written files with pre-computed hashes that both implementations validate against. If either implementation changes serialization in a way that breaks interop, the golden fixture tests fail.

## Acceptance criteria

### Fixture directory (`test_fixtures/golden_run/`)

Located at repo root so both `integrations/python/` and `runtime/` can access them.

- [x] Directory structure matches 11_Data_Model_Spec layout:
  ```
  test_fixtures/golden_run/
    events.jsonl
    seal.json
    decisions/
      summarize.json
    artifacts/
      {hex[0:2]}/{hex[2:4]}/{hex}    (two artifacts)
  ```

### Event log (`events.jsonl`)

- [x] Contains 7 events representing a minimal Radar-like run:
  1. `run_started` — pack_id: "test_pack", plan_hash, etc.
  2. `op_started` — node "fetch", determinism "pinned_env"
  3. `op_completed` — node "fetch", output_hashes referencing artifact 1
  4. `op_started` — node "summarize", determinism "recordable"
  5. `decision_recorded` — node "summarize", decision_hash referencing the decision file
  6. `op_completed` — node "summarize", output_hashes referencing artifact 2
  7. `run_completed` — outcome "success", both artifact hashes
- [x] Each line is RFC 8785 canonical JSON (sorted keys, no whitespace)
- [x] Hash chain is valid: each event's `prev_hash` equals the previous event's `event_hash`
- [x] First event has `prev_hash: null`
- [x] All `event_hash` values are correctly computed over `{event_type, payload, prev_hash, timestamp}`

### Run seal (`seal.json`)

- [x] `run_seal` matches the `event_hash` of the `run_completed` event
- [x] Contains `run_id`, `completed_at`, `event_count`

### Decision record (`decisions/summarize.json`)

- [x] Canonical JSON with all fields from 11_Data_Model_Spec § Decision Records
- [x] `decision_hash` correctly computed over all fields except itself
- [x] `decision_hash` matches the hash referenced in the `decision_recorded` event

### Artifact blobs (`artifacts/`)

- [x] Two artifacts stored in Git-style sharded paths: `{hex[0:2]}/{hex[2:4]}/{hex}`
- [x] Artifact 1: a small JSON blob (e.g., fetched documents list)
- [x] Artifact 2: a small text blob (e.g., summary output)
- [x] `sha256(raw_bytes)` of each file matches its filename/path

### Tampered event log (`events_tampered.jsonl`)

- [x] Copy of `events.jsonl` with one event's payload modified (e.g., changed `duration_ms`)
- [x] Hash chain is broken — verification must detect the tampering

### Elixir verification (`runtime/`)

- [x] `Liminara.Canonical` module: canonical JSON encoding (RFC 8785 key sorting via Jason)
- [x] `Liminara.Hash` module: `hash_bytes/1`, `hash_event/4`, `hash_decision/1`
- [x] Hash functions produce the same output as the Python SDK's `liminara/hash.py`
- [x] Test: read `events.jsonl`, verify hash chain passes
- [x] Test: read `events_tampered.jsonl`, verify hash chain fails with error on the tampered event
- [x] Test: read `seal.json`, verify seal matches final event hash
- [x] Test: read decision file, verify `decision_hash` is correct
- [x] Test: read artifact files, verify `sha256(bytes)` matches expected hash
- [x] Test: canonical JSON output byte-for-byte matches Python's `canonicaljson` for the same input

### Python verification (`integrations/python/`)

- [x] Test: read `test_fixtures/golden_run/events.jsonl`, verify hash chain using existing `EventLog.verify()` logic
- [x] Test: read `events_tampered.jsonl`, verify tamper detection
- [x] Test: read seal, verify it matches final event hash
- [x] Test: read decision, verify `decision_hash`
- [x] Test: read artifacts, verify content hashes

### Cross-language canary

- [x] A known JSON object is included as a comment/fixture note with its expected canonical form and SHA-256 hash. Both Elixir and Python tests assert the same hash for this object. This is the "canary" — if canonical JSON diverges between languages, this test fails first.

## Tests

### Elixir tests (`runtime/apps/liminara_core/test/`)

- `liminara/canonical_test.exs`:
  - Canonical JSON sorts keys lexicographically
  - Numbers have no trailing zeros
  - Null/boolean values serialize correctly
  - Nested objects sort recursively
  - Known test vector produces expected bytes (canary)

- `liminara/hash_test.exs`:
  - `hash_bytes/1` returns `"sha256:{64 hex chars}"` format
  - `hash_event/4` matches hand-computed hash for a known event
  - `hash_decision/1` matches hand-computed hash

- `liminara/golden_fixtures_test.exs`:
  - Hash chain verification passes on `events.jsonl`
  - Hash chain verification fails on `events_tampered.jsonl`
  - Seal matches final event hash
  - Decision hash is valid
  - Artifact content hashes match paths
  - Canary hash matches expected value

### Python tests (`integrations/python/tests/`)

- `test_golden_fixtures.py`:
  - Hash chain verification passes on `events.jsonl`
  - Hash chain verification fails on `events_tampered.jsonl`
  - Seal matches final event hash
  - Decision hash is valid
  - Artifact content hashes match paths
  - Canary hash matches expected value

## TDD sequence

1. **Fixture generation**: Write a Python script (`scripts/generate_golden_fixtures.py`) that uses the existing Python SDK's `hash.py` to generate `test_fixtures/golden_run/` with all files and correct hashes. This ensures the fixtures are correct by construction. Commit the script AND the generated fixtures.
2. **Test agent (Elixir)**: Write `canonical_test.exs`, `hash_test.exs`, `golden_fixtures_test.exs`. All fail (red) — modules don't exist yet.
3. Human reviews tests.
4. **Impl agent (Elixir)**: Implement `Liminara.Canonical`, `Liminara.Hash`, and the verification logic until all Elixir tests pass (green).
5. **Test agent (Python)**: Write `test_golden_fixtures.py`. Should pass immediately since it uses existing SDK functions against correctly-generated fixtures. If any fail, there's a bug.
6. Human reviews everything.
7. Full validation: Elixir pipeline (`mix format --check-formatted && mix credo && mix dialyzer && mix test`) + Python pipeline (`uv run ruff check . && uv run ruff format --check . && uv run pytest`).

## Out of scope

- Event log writing (append) — that's E-05 (Event Store)
- Artifact store implementation — that's E-05
- Decision store implementation — that's E-05
- Any runtime logic (scheduler, Run.Server, etc.)

## Spec reference

- `docs/analysis/11_Data_Model_Spec.md` — canonical format, hash computation, directory layout, event types
- `integrations/python/liminara/hash.py` — reference implementation of hash functions
- `integrations/python/liminara/event_log.py` — reference implementation of hash chain verification
