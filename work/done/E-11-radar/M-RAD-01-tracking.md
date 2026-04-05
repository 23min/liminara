# M-RAD-01: Pack + Source Config + Fetch — Tracking

**Started:** 2026-04-01
**Branch:** `milestone/M-RAD-01`
**Spec:** `work/done/E-11-radar/M-RAD-01-pack-config-fetch.md`

## Acceptance Criteria

- [x] AC1: Liminara.Radar Pack module in liminara_radar umbrella app
- [x] AC2: Source config JSONL (45 sources) + Radar.Config loader/validator
- [x] AC3: Radar.Ops.FetchRss (Python, side_effecting) — feedparser + httpx
- [x] AC4: Radar.Ops.FetchWeb (Python, side_effecting) — httpx + trafilatura
- [x] AC5: Radar.Ops.CollectItems (Elixir, pure) — merge, URL dedup, health
- [x] AC6: mix radar.run task (--tags, --config flags)
- [x] AC7: Source health tracking artifact (per-source items_fetched, error)
- [x] AC8: Persistent storage paths in dev config (runtime/data/)
- [x] AC9: Python deps (feedparser, httpx, trafilatura)

## Test Summary

- Elixir radar: 22 tests, 0 failures
- Elixir core: 306 tests, 0 failures (no regressions)
- Python: 18 tests (11 runner + 7 fetch), 0 failures

## Notes

- Source config format: JSONL (one source per line, Jason parsing, no new deps)
- Test fixtures: minimal XML + mocked httpx for unit tests
- 45 sources: 31 RSS, 14 web
- CollectItems stores items and source_health as JSON artifact strings
