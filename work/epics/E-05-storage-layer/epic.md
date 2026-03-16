---
id: E-05-storage-layer
phase: 2
status: draft
---

# E-05: Storage Layer (Artifact Store + Event Store)

## Goal

Implement the two storage components of the runtime: the content-addressed artifact store (ETS + filesystem) and the hash-chained event log (JSONL files). These implement the same data model spec as the Python SDK and must pass against the golden test fixtures.

## Scope

**In:**

### Artifact Store (`Liminara.Artifact.Store`)
- ETS table for artifact metadata (hash → type, size, timestamp)
- Filesystem blob storage: content-addressed, Git-style sharding (`{hex[0:2]}/{hex[2:4]}/{hex}`)
- `put(bytes)` → returns `sha256:{hash}`, stores blob on disk, indexes in ETS
- `get(hash)` → returns raw bytes (streams for large files)
- `exists?(hash)` → boolean
- Write-once semantics: idempotent (same content → same hash → skip if exists)
- SHA-256 hashing: `sha256:{64 lowercase hex chars}` encoding
- Canonical JSON serialization: RFC 8785 (sorted keys, no whitespace, UTF-8)
- Started as a GenServer or Agent under the supervision tree
- ETS table rebuilt from filesystem on startup (scan artifact directories)

### Event Store (`Liminara.Event.Store`)
- Append event → writes one canonical JSON line to `{runs_root}/{run_id}/events.jsonl`
- Event schema: `{event_hash, event_type, payload, prev_hash, timestamp}`
- Hash chain: `event_hash = sha256(canonical_json({event_type, payload, prev_hash, timestamp}))`
- First event has `prev_hash: null`
- `append(run_id, event_type, payload)` → returns event with computed hash
- `read_events(run_id)` → returns list of event maps
- `verify_chain(run_id)` → returns `{:ok, event_count}` or `{:error, detail}`
- Run seal: `seal.json` written on `run_completed` event

### Decision Store (`Liminara.Decision.Store`)
- Write decision record → canonical JSON at `{runs_root}/{run_id}/decisions/{node_id}.json`
- `decision_hash = sha256(canonical_json(all fields except decision_hash))`
- `put(run_id, node_id, decision)` → writes file, returns hash
- `get(run_id, node_id)` → returns decision map

### Interoperability
- All on-disk formats match `docs/analysis/11_Data_Model_Spec.md`
- Tests validate against golden fixtures from E-04
- A JSONL event log written by the Python SDK must be readable and verifiable by the Elixir Event Store

**Out:**
- Plan, Op, Run.Server (E-06)
- Caching / memoization (E-06 or E-07)
- Garbage collection
- Large file streaming optimization (not needed for walking skeleton)

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-SL-01-hashing | SHA-256 hashing, canonical JSON (RFC 8785), hash encoding | draft |
| M-SL-02-artifact-store | Artifact.Store GenServer, ETS + filesystem, content-addressed blobs | draft |
| M-SL-03-event-store | Event.Store, JSONL append, hash chain, verification, run seal | draft |
| M-SL-04-decision-store | Decision.Store, canonical JSON records, decision hashing | draft |

## Success criteria

- [ ] Artifact store round-trip: put bytes, get bytes, identical
- [ ] Artifact store idempotent: put same content twice, one file on disk
- [ ] Event store hash chain: append N events, verify chain passes
- [ ] Event store tamper detection: modify one event, verify fails
- [ ] Decision store round-trip: put decision, get decision, identical hash
- [ ] All stores read golden fixtures from E-04 correctly
- [ ] On-disk formats match 11_Data_Model_Spec.md (directory layout, file formats, hash encoding)

## References

- Data model: `docs/analysis/11_Data_Model_Spec.md`
- Architecture: `docs/architecture/01_CORE.md` § Five concepts (Artifact, Run), § What's actually hard (artifact store under load)
- Golden fixtures: `test_fixtures/` (from E-04)
