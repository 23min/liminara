# M-SL-02 Session Log

## 2026-03-18 — Event Store implementation

**Milestone:** M-SL-02-event-store
**Outcome:** Done

### What was done

1. TDD: wrote 19 failing tests for `Liminara.Event.Store` (red).
2. Implemented `Liminara.Event.Store` — `append/5`, `read_all/2`, `verify/2`, `write_seal/2`.
3. Hash chain verified against golden fixtures (7 events pass, tampered log detected).
4. Seal generation produces canonical JSON matching Python SDK output.

### Decisions

- **Caller manages prev_hash**: `append/5` takes `prev_hash` as a parameter rather than tracking it internally. `Run.Server` (E-06) will manage this state.
- **Timestamp generation**: Uses `DateTime.utc_now()` with millisecond precision, formatted as ISO 8601 UTC.

### Open items

- None.
