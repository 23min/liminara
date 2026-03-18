---
id: M-SL-03-decision-store
epic: E-05-storage-layer
status: done
---

# M-SL-03: Decision Store

## Goal

Implement `Liminara.Decision.Store` — a module for storing and retrieving nondeterministic decision records as canonical JSON files. Each recordable op execution produces one decision record. The module must produce files byte-identical to the Python SDK's `DecisionStore`.

## Acceptance criteria

### Module: `Liminara.Decision.Store`

- [x] `put(runs_root, run_id, record)` → `{:ok, decision_hash}` — computes hash, writes file
- [x] `get(runs_root, run_id, node_id)` → `{:ok, record_with_hash}` or `{:error, :not_found}`
- [x] `verify(runs_root, run_id, node_id)` → `{:ok, decision_hash}` or `{:error, :hash_mismatch}`

### Decision record format

- [x] File path: `{runs_root}/{run_id}/decisions/{node_id}.json`
- [x] File content is canonical JSON (RFC 8785)
- [x] `decision_hash` is computed over all fields except `decision_hash` itself: `sha256(canonical_json(record_without_hash))`
- [x] `decision_hash` is included in the written record
- [x] Parent directories created automatically on write

### Hash computation

- [x] Uses `Liminara.Hash.hash_decision/1` for hash computation
- [x] Hash is deterministic: same record always produces same hash
- [x] If caller passes a `decision_hash` field, it is stripped before hashing and replaced with the computed hash

### Golden fixture validation

- [x] Can read `test_fixtures/golden_run/decisions/summarize.json`
- [x] `verify` confirms the golden fixture decision hash is valid
- [x] Round-trip: write a record, read it back, all fields match including `decision_hash`

## Tests

### `test/liminara/decision/store_test.exs`

**Round-trip:**
- `put` returns `{:ok, "sha256:{hex}"}` hash
- `get` returns the record with `decision_hash` included
- All original fields preserved exactly
- `decision_hash` in the returned record matches the hash from `put`

**Hash computation:**
- Hash is computed over all fields except `decision_hash`
- Same record produces same hash on repeated puts
- Different records produce different hashes
- If record already contains `decision_hash`, it's replaced with correctly computed one

**Verify:**
- `verify` on a correctly written record returns `{:ok, hash}`
- `verify` on a manually corrupted file returns `{:error, :hash_mismatch}`

**Golden fixtures:**
- Read golden decision → fields match expected values
- `verify` on golden decision returns `{:ok, expected_hash}`
- Decision hash matches the one referenced in golden events' `decision_recorded` event

**Edge cases:**
- `get` on non-existent node_id returns `{:error, :not_found}`
- Record with nested maps and arrays (like `inputs` and `output` fields) round-trips correctly
- Floats in records (e.g., `temperature: 0.7`) serialize correctly in canonical JSON

## TDD sequence

1. **Test agent** reads this spec, writes `decision/store_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Decision.Store` until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## Out of scope

- Process management / GenServer (E-06)
- Listing all decisions for a run
- Decision record schema validation (caller is responsible for correct fields)
- Decision replay logic (E-07)

## Spec reference

- `docs/analysis/11_Data_Model_Spec.md` § Decision Records
- `integrations/python/liminara/decision_store.py` — reference implementation
- `runtime/apps/liminara_core/lib/liminara/hash.ex` — `hash_decision/1`
- `runtime/apps/liminara_core/lib/liminara/canonical.ex` — `encode/1`, `encode_to_iodata/1`
