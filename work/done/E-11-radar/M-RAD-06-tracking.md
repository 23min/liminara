# M-RAD-06: Replay Correctness — Tracking

**Started:** 2026-04-03
**Branch:** `milestone/M-RAD-06`
**Spec:** `work/done/E-11-radar/M-RAD-06-replay-correctness.md`

## Acceptance Criteria

- [x] AC1: Decision.Store supports multi-decision nodes (list per node_id, backward compat)
  - File format: `{"decisions": [...], "output_hashes": {...}}`
  - `put/3` appends to list, `get/3` always returns list
  - `put_outputs/4` + `get_outputs/3` for replay output restoration
  - Backward compat: old single-object files load as one-element list
- [x] AC2: Run.Server replay restores multi-decision outputs (handle_replay_inject rework)
  - Both sync (`run.ex`) and async (`server.ex`) paths updated
  - Replay reads stored `output_hashes` directly instead of reconstructing from decisions
  - `record_decisions` now also stores `output_hashes` during discovery
  - Characterization test (`ReplayGapCharacterizationTest`) passes and runs by default
- [x] AC3: End-to-end Radar replay test
  - `RadarReplayTestPack`: cluster → rank → summarize → compose → render with fixture items
  - Discovery → replay → identical output artifacts for all 5 pipeline nodes
  - Replay emits matching `decision_recorded` events (same hashes, same count)
  - HTML briefing byte-identical between discovery and replay
  - Tests use real Python port ops (cluster, rank, summarize) — no mocks
- [x] AC4: Executor.Port env whitelist (clean env, no VIRTUAL_ENV leakage)
  - `@env_whitelist` module attribute: PATH, HOME, LANG, TERM, USER, SHELL, LC_ALL, LC_CTYPE
  - `clean_env/0` unsets everything not in whitelist, adds PYTHONDONTWRITEBYTECODE
  - 7 new tests including end-to-end port op with clean env

## Test Summary

- Decision.Store: 25 tests, 0 failures
- Run replay: 6 tests, 0 failures
- Replay characterization: 2 tests, 0 failures, 1 excluded (stored plan — deferred)
- Port executor: 20 tests, 0 failures
- Server: 107 tests, 0 failures
- Radar: 49 tests, 0 failures

## Notes

- `ReplayGapCharacterizationTest` runs by default; only the stored-plan case is excluded via `@tag :deferred_stored_plan`
- Existing `ReplayGapPack` fixtures ready for use
