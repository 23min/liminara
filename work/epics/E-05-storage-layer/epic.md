---
id: E-05-storage-layer
phase: 2
status: done
---

# E-05: Storage Layer (Artifact Store + Event Store + Decision Store)

## Goal

Implement the three storage components of the Liminara runtime as Elixir modules: content-addressed artifact store, hash-chained event log, and decision record store. All on-disk formats must match `11_Data_Model_Spec.md` and validate against the golden fixtures from E-04.

## Scope

**In:**

### Artifact Store (`Liminara.Artifact.Store`)
- Filesystem blob storage: content-addressed, Git-style sharding (`{hex[0:2]}/{hex[2:4]}/{hex}`)
- `put(store_root, bytes)` → returns `"sha256:{hash}"`, writes blob to disk
- `get(store_root, hash)` → returns `{:ok, bytes}` or `{:error, :not_found}`
- `exists?(store_root, hash)` → boolean
- Write-once semantics: idempotent (same content → same hash → skip if exists)
- Pure functional module (no GenServer/ETS yet — defer process management to E-06)

### Event Store (`Liminara.Event.Store`)
- Append event → writes one canonical JSON line to `{runs_root}/{run_id}/events.jsonl`
- Event schema: `{event_hash, event_type, payload, prev_hash, timestamp}`
- Hash chain: `event_hash = sha256(canonical_json({event_type, payload, prev_hash, timestamp}))`
- `append(runs_root, run_id, event_type, payload, prev_hash)` → returns event map with computed hash
- `read_all(runs_root, run_id)` → returns list of event maps
- `verify(runs_root, run_id)` → returns `{:ok, event_count}` or `{:error, index, reason}`
- Run seal: `write_seal(runs_root, run_id, events)` writes `seal.json` from final event

### Decision Store (`Liminara.Decision.Store`)
- Write decision record → canonical JSON at `{runs_root}/{run_id}/decisions/{node_id}.json`
- `decision_hash = sha256(canonical_json(all fields except decision_hash))`
- `put(runs_root, run_id, record)` → writes file, returns `{:ok, decision_hash}`
- `get(runs_root, run_id, node_id)` → returns `{:ok, record}` or `{:error, :not_found}`

### Interoperability
- All on-disk formats match `docs/analysis/11_Data_Model_Spec.md`
- Tests validate against golden fixtures from E-04
- A JSONL event log written by the Python SDK must be readable and verifiable by the Elixir Event Store

**Out:**
- GenServer/process wrappers (E-06 — stores are plain modules here)
- ETS metadata tables (E-06 — defer until Run.Server needs them)
- Plan, Op, Run.Server (E-06)
- Caching / memoization (E-06 or E-07)
- Garbage collection
- Large file streaming optimization

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-SL-01-artifact-store | Artifact.Store: content-addressed filesystem blobs | done |
| M-SL-02-event-store | Event.Store: JSONL append, hash chain, verification, seal | done |
| M-SL-03-decision-store | Decision.Store: canonical JSON records, decision hashing | done |

Note: SHA-256 hashing and canonical JSON (`Liminara.Hash`, `Liminara.Canonical`) were implemented in E-04 M-ES-02. These modules are the foundation the stores build on.

## Success criteria

- [x] Artifact store round-trip: put bytes, get bytes, identical
- [x] Artifact store idempotent: put same content twice, one file on disk
- [x] Artifact store reads golden fixture artifacts correctly
- [x] Event store hash chain: append N events, verify chain passes
- [x] Event store tamper detection: modify one event, verify fails
- [x] Event store reads golden fixture events correctly
- [x] Event store seal matches golden fixture seal
- [x] Decision store round-trip: put decision, get decision, identical hash
- [x] Decision store reads golden fixture decision correctly
- [x] On-disk formats match 11_Data_Model_Spec.md (directory layout, file formats, hash encoding)
- [x] Validation pipeline passes: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## References

- Data model: `docs/analysis/11_Data_Model_Spec.md`
- Architecture: `docs/architecture/01_CORE.md` § Five concepts (Artifact, Run)
- Build plan: `docs/architecture/02_PLAN.md` § Phase 2
- Golden fixtures: `test_fixtures/golden_run/` (from E-04)
- Python reference: `integrations/python/liminara/artifact_store.py`, `event_log.py`, `decision_store.py`
- Existing Elixir: `runtime/apps/liminara_core/lib/liminara/hash.ex`, `canonical.ex`
