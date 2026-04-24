---
id: M-CS-02-hash-and-store
epic: E-02-python-compliance-sdk
status: complete
---

# M-CS-02: Hashing, Canonical JSON, Artifact Store, and Event Log

## Goal

Implement the storage layer: SHA-256 hashing with canonical JSON serialization, content-addressed artifact store, and hash-chained JSONL event log. These are the foundation everything else builds on.

## Acceptance criteria

- [x] `hash.py`: SHA-256 hashing produces `sha256:{64 lowercase hex}` encoding
- [x] `hash.py`: canonical JSON serialization matches RFC 8785 (sorted keys, no whitespace, UTF-8)
- [x] `hash.py`: `hash_bytes(raw_bytes)` → artifact hash
- [x] `hash.py`: `hash_event(event_type, payload, prev_hash, timestamp)` → event hash (excludes event_hash itself from input)
- [x] `artifact_store.py`: write blob → returns hash, stored at `{store_root}/{hash[0:2]}/{hash[2:4]}/{hash}`
- [x] `artifact_store.py`: write is idempotent (same content → same hash → skip if exists)
- [x] `artifact_store.py`: read by hash → returns raw bytes
- [x] `event_log.py`: append event → writes one canonical JSON line to `{runs_root}/{run_id}/events.jsonl`
- [x] `event_log.py`: each event contains `event_hash`, `event_type`, `payload`, `prev_hash`, `timestamp`
- [x] `event_log.py`: first event has `prev_hash: null`
- [x] `event_log.py`: each subsequent event's `prev_hash` equals previous event's `event_hash`
- [x] `event_log.py`: read all events from a run → returns list of event dicts
- [x] `event_log.py`: verify hash chain → returns (valid: bool, error_detail: str | None)
- [x] `decision_store.py`: write decision record → canonical JSON at `{runs_root}/{run_id}/decisions/{node_id}.json`
- [x] `decision_store.py`: decision_hash computed over all fields except decision_hash itself
- [x] All on-disk formats match `docs/analysis/11_Data_Model_Spec.md` exactly

## Tests

- `test_hash.py`:
  - Known-input SHA-256 produces expected output
  - Canonical JSON: key ordering, no whitespace, Unicode handling
  - Event hash computation matches spec (hash of {event_type, payload, prev_hash, timestamp})
- `test_artifact_store.py`:
  - Write + read round-trip
  - Idempotent write (same content twice → one file)
  - Directory sharding matches spec
  - Empty content has correct hash
- `test_event_log.py`:
  - Append single event, read back
  - Append multiple events, hash chain is valid
  - First event has prev_hash null
  - Tamper with one event → verify detects it
  - Tamper with first event → all subsequent hashes invalid
- `test_decision_store.py`:
  - Write + read round-trip
  - decision_hash is correct
  - Canonical JSON formatting

## Out of scope

- Decorators and run context manager (M-CS-03)
- CLI (M-CS-04)
- Report generation (M-CS-04)
- Large file streaming (not needed for Phase 1 — all artifacts are small text)

## Spec reference

`docs/analysis/11_Data_Model_Spec.md` — the entire document. This milestone implements it.
