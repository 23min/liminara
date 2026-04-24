---
id: M-SL-02-event-store
epic: E-05-storage-layer
status: complete
---

# M-SL-02: Event Store

## Goal

Implement `Liminara.Event.Store` — a module for append-only, hash-chained event logs stored as JSONL files. Each run gets one event log. The module must produce files byte-identical to the Python SDK's `EventLog` and validate against the golden fixtures.

## Acceptance criteria

### Module: `Liminara.Event.Store`

- [x] `append(runs_root, run_id, event_type, payload, prev_hash)` → `{:ok, event_map}` with computed `event_hash` and `timestamp`
- [x] `read_all(runs_root, run_id)` → `{:ok, [event_map, ...]}` or `{:ok, []}` if no events
- [x] `verify(runs_root, run_id)` → `{:ok, event_count}` or `{:error, index, reason}`
- [x] `write_seal(runs_root, run_id)` → `{:ok, seal_map}` — reads events, writes `seal.json` from final event

### Event format

- [x] Each event is one line of canonical JSON (RFC 8785) in `{runs_root}/{run_id}/events.jsonl`
- [x] Event fields: `event_hash`, `event_type`, `payload`, `prev_hash`, `timestamp`
- [x] `event_hash = sha256(canonical_json({event_type, payload, prev_hash, timestamp}))` — event_hash NOT included in hash input
- [x] `prev_hash` is `nil` (serialized as `null`) for the first event
- [x] `timestamp` is ISO 8601 UTC with millisecond precision (`YYYY-MM-DDTHH:MM:SS.SSSZ`)
- [x] Lines terminated with `\n`
- [x] Parent directories created automatically on first append

### Hash chain

- [x] Each event's `prev_hash` equals the previous event's `event_hash`
- [x] `verify/2` recomputes every `event_hash` and checks `prev_hash` linkage
- [x] `verify/2` returns `{:error, index, reason}` on first mismatch (stops early)

### Run seal

- [x] `write_seal/2` writes `{runs_root}/{run_id}/seal.json` as canonical JSON
- [x] Seal fields: `run_id`, `run_seal` (= final event's `event_hash`), `completed_at` (= final event's `timestamp`), `event_count`
- [x] Seal is only valid if final event is `run_completed`

### Golden fixture validation

- [x] `read_all` correctly reads `test_fixtures/golden_run/events.jsonl` (7 events)
- [x] `verify` passes on the golden fixture events
- [x] `verify` fails on `test_fixtures/golden_run/events_tampered.jsonl`
- [x] Seal from golden fixtures matches `test_fixtures/golden_run/seal.json`

### Interoperability

- [x] A fresh event log appended by Elixir is readable by the Python SDK's `EventLog.verify()` (verified by writing a small roundtrip test or by structural equivalence with golden fixtures)

## Tests

### `test/liminara/event/store_test.exs`

**Append and read:**
- Append one event → read_all returns list with one event
- Event has all required fields (event_hash, event_type, payload, prev_hash, timestamp)
- payload is preserved exactly
- Append multiple events → read_all returns them in order

**Hash chain:**
- First event has `prev_hash: nil`
- Second event's `prev_hash` equals first event's `event_hash`
- Chain of 5 events: `verify` returns `{:ok, 5}`

**Tamper detection:**
- Append 3 events, manually corrupt middle event's payload in the file, `verify` returns `{:error, 1, _reason}` (0-indexed) or `{:error, 2, _reason}` depending on which breaks

**Run seal:**
- Append run_started + run_completed → `write_seal` produces correct seal
- Seal `run_seal` equals final event's `event_hash`
- Seal `event_count` matches number of events

**Golden fixtures:**
- `read_all` on golden events returns 7 events
- `verify` on golden events returns `{:ok, 7}`
- `verify` on tampered events returns an error
- Golden seal matches expected values

**Edge cases:**
- `read_all` on non-existent run returns `{:ok, []}`
- `verify` on empty log returns `{:ok, 0}`
- Timestamp format matches `~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/`

## TDD sequence

1. **Test agent** reads this spec, writes `event/store_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Event.Store` until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## Out of scope

- Process management / GenServer (E-06)
- Maintaining `prev_hash` state across appends (caller passes `prev_hash`; Run.Server will track this in E-06)
- Event log compaction or rotation
- Querying events by type or payload

## Spec reference

- `docs/analysis/11_Data_Model_Spec.md` § Event Log, § Run Seal
- `integrations/python/liminara/event_log.py` — reference implementation
- `runtime/apps/liminara_core/lib/liminara/hash.ex` — `hash_event/4`
- `runtime/apps/liminara_core/lib/liminara/canonical.ex` — `encode/1`
