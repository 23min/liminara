# M-ES-02 Session Log

## 2026-03-18 — Golden test fixtures + cross-language verification

**Milestone:** M-ES-02-fixtures
**Outcome:** Done

### What was done

1. Wrote `scripts/generate_golden_fixtures.py` — uses Python SDK's `hash.py` to generate `test_fixtures/golden_run/` with correct hashes by construction.
2. Generated fixtures: 7 events (valid hash chain), seal, 1 decision record, 2 artifact blobs, tampered event log, canary file.
3. TDD (Elixir): wrote 22 failing tests across `canonical_test.exs`, `hash_test.exs`, `golden_fixtures_test.exs` (red).
4. Implemented `Liminara.Canonical` (RFC 8785 canonical JSON via Jason + sorted keys) and `Liminara.Hash` (hash_bytes, hash_event, hash_decision). All tests pass (green).
5. Wrote 7 Python golden fixture tests (`test_golden_fixtures.py`). All pass immediately — confirms cross-language hash compatibility.
6. Full validation: Elixir (24 tests, format, credo, dialyzer) + Python (82 tests, ruff) all pass.

### Decisions

- **Canonical JSON in Elixir**: Used `Jason.OrderedObject` to control key ordering rather than adding a `canonicaljson` dependency. This produces byte-identical output to Python's `canonicaljson` package for all tested inputs.
- **Jason dep placement**: Moved `jason` from umbrella root to `liminara_core/mix.exs` only, fixing compile-time warnings about undefined modules.
- **Decision file naming**: Spec said `summarize_cluster_3.json` but we used `summarize.json` (matching `node_id`). This aligns with how `DecisionStore` in the Python SDK works (`{node_id}.json`).

### Open items

- None. E-04 is complete. Next: E-05 (Storage Layer).
