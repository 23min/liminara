# M-RAD-04: Web UI + Scheduler — Tracking

**Started:** 2026-04-03
**Completed:** 2026-04-03
**Branch:** `milestone/M-RAD-04`
**Spec:** `work/epics/E-11-radar/M-RAD-04-webui-scheduler.md`
**Status:** complete

## Acceptance Criteria

- [x] AC1: Briefing list page at `/radar/briefings`
  - Lists all Radar runs with date, status, item count, cluster count, duration
  - Sorted newest first (by run_id which contains timestamp)
  - Click navigates to briefing detail
- [x] AC2: Briefing detail page at `/radar/briefings/:run_id`
  - Renders HTML briefing artifact inline
  - Shows run metadata (date, duration, source count, item count, cluster count)
  - Shows source health summary (collapsible)
  - Link to observation UI run detail page (`/runs/:run_id`)
- [x] AC3: Source health dashboard at `/radar/sources`
  - Table of all sources with status, contribution, rolling average
  - Cull candidates highlighted
  - Toggle enabled/disabled (writes back to config)
- [x] AC4: Navigation integration
  - Global nav bar in app layout: Runs, Radar, Sources
- [x] AC5: GenServer scheduler (`Liminara.Radar.Scheduler`)
  - OTP-supervised, configurable daily trigger
  - `next_run_at/0`, `last_run_at/0`, `run_now/0`
  - Recalculates on restart, no concurrent runs
- [x] AC6: Scheduler status visible in UI
  - "Next run at HH:MM" / "Last run HH:MM" on briefings page
  - "Run now" button
- [x] AC7: `mix radar.run` continues to work (unchanged, compiles clean)

## Baseline

- Build: compiles cleanly
- Pre-existing test failures: 7 (web LiveView tests on runs_live — unrelated to M-RAD-04)

## Implementation Phases

1. GenServer scheduler (AC5) — pure logic, no UI dependency
2. Briefing list + detail pages (AC1, AC2) — LiveView pages with run discovery
3. Source health dashboard (AC3) — LiveView with config read/write
4. Navigation + scheduler UI + integration (AC4, AC6, AC7) — glue everything together

## Test Summary

- **Scheduler tests:** 12 (ms_until_next, lifecycle, run_now, concurrency guard, failure handling, timer trigger)
- **Briefings list/detail tests:** 11 (list rendering, sort, navigation, detail with inline HTML, metadata, source health, cross-link, not-found)
- **Sources dashboard tests:** 7 (rendering, config display, health metrics, cull candidates, toggle enabled/disabled)
- **Navigation tests:** 3 (cross-page links)
- **Scheduler UI tests:** 3 (status display, run now button, absent scheduler)
- **Total new tests:** 36, all passing
