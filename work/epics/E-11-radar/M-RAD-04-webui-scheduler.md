---
id: M-RAD-04-webui-scheduler
epic: E-11-radar
status: not started
depends_on: M-RAD-03-cluster-rank-render
---

# M-RAD-04: Web UI + Scheduler

## Goal

Add a LiveView page for viewing Radar briefings in the browser and a GenServer scheduler for automated daily runs. After this milestone, Radar runs on a schedule and briefings are viewable at `/radar/briefings/:run_id` in the existing web UI.

## Context

M-RAD-03 produces an HTML briefing artifact. This milestone integrates it into the LiveView web app and adds automation via a scheduler.

The scheduler is a supervised GenServer using `:timer` — it prepares the path for Oban migration in Phase 6. The triggering logic (load config, start run) becomes the Oban worker's `perform/1` body later.

## Acceptance Criteria

1. **Briefing list page** at `/radar/briefings`:
   - Lists all Radar runs with: date, status (running/completed/failed), item count, cluster count, duration
   - Sorted by date (newest first)
   - Click a run → navigates to briefing detail page
   - Runs are discovered from the existing run infrastructure (Run.Server / event logs)

2. **Briefing detail page** at `/radar/briefings/:run_id`:
   - Renders the HTML briefing artifact inline (not as a download)
   - Shows run metadata: date, duration, source count, item count, cluster count
   - Shows source health summary: top contributors, sources with errors, sources with zero items
   - Link to the observation UI run detail page (existing `/runs/:run_id`) for full DAG/event inspection

3. **Source health dashboard** at `/radar/sources`:
   - Table of all configured sources with columns: name, type, tags, enabled, last fetch status, items contributed (last run), items contributed (rolling average last 7 runs)
   - Sources sorted by: contribution (descending), then name
   - Sources with zero contribution for 7+ runs highlighted as cull candidates
   - Toggle enabled/disabled from the UI (writes back to config file)

4. **Navigation integration:**
   - Radar pages accessible from the main navigation in the existing Phoenix app
   - "Radar" nav item with sub-items: Briefings, Sources

5. **GenServer scheduler** (`Liminara.Radar.Scheduler`):
   - OTP-supervised process that triggers Radar runs on a configurable schedule
   - Configuration: `{:daily_at, ~T[06:00:00]}` or `{:interval, :timer.hours(24)}`
   - On trigger: loads source config, calls `Radar.plan(config)`, starts run via Run.Server
   - Recalculates next run time after each trigger (handles app restarts gracefully)
   - Provides `next_run_at/0` and `last_run_at/0` for UI display
   - Can be manually triggered: `Scheduler.run_now/0`

6. **Scheduler status** visible in the UI:
   - On the briefings list page: "Next run at HH:MM" / "Scheduler paused"
   - Manual trigger button: "Run now"

7. **mix radar.run** continues to work for manual one-off runs

## Tests

### LiveView tests
- Briefings list page renders with correct columns
- Briefings list shows running/completed/failed status correctly
- Briefing detail page renders HTML artifact content
- Briefing detail page shows metadata and source health
- Source health dashboard shows all sources with metrics
- Navigation links present and working

### Scheduler tests (Elixir — ExUnit)
- Scheduler starts and calculates next run time correctly
- `{:daily_at, ~T[06:00:00]}` with current time 05:00 → next run in 1 hour
- `{:daily_at, ~T[06:00:00]}` with current time 07:00 → next run tomorrow at 06:00
- `run_now/0` triggers a run immediately
- Scheduler handles Run.Server start failure gracefully (logs error, schedules next run)
- Scheduler does not trigger concurrent runs (if previous run still active, skip or queue)
- `next_run_at/0` and `last_run_at/0` return correct values

### Integration test
- Start scheduler → wait for trigger (or use `run_now`) → verify run starts → verify briefing appears in list page
- Manual trigger via UI button → run starts

## Technical Notes

### LiveView structure

```
runtime/apps/liminara_web/lib/liminara_web/live/radar_live/
  briefings.ex          # List page
  briefing_show.ex      # Detail page
  sources.ex            # Source health dashboard
```

Templates:
```
runtime/apps/liminara_web/lib/liminara_web/live/radar_live/
  briefings.html.heex
  briefing_show.html.heex
  sources.html.heex
```

### Router

```elixir
scope "/radar", LiminaraWeb.RadarLive do
  live "/briefings", Briefings, :index
  live "/briefings/:run_id", BriefingShow, :show
  live "/sources", Sources, :index
end
```

### Scheduler implementation

```elixir
defmodule Liminara.Radar.Scheduler do
  use GenServer

  def init(config) do
    ms = ms_until_next(config.daily_at)
    timer_ref = Process.send_after(self(), :trigger, ms)
    {:ok, %{config: config, timer_ref: timer_ref, last_run_at: nil}}
  end

  def handle_info(:trigger, state) do
    # Start run (async — don't block scheduler)
    Task.start(fn -> run_radar(state.config) end)
    ms = ms_until_next(state.config.daily_at)
    timer_ref = Process.send_after(self(), :trigger, ms)
    {:noreply, %{state | timer_ref: timer_ref, last_run_at: DateTime.utc_now()}}
  end
end
```

### Briefing discovery

The briefing list page queries completed runs where `pack_id == :radar`. This uses the existing run infrastructure — no separate database needed. Run metadata (item count, cluster count) is extracted from the run's stored artifacts.

### Source health aggregation

Source health per run is stored as an artifact by M-RAD-01's CollectItems op. The source health dashboard reads the last N run artifacts and computes rolling averages. This is a read-only view — no new data storage needed.

## Out of Scope

- Email/Slack delivery
- Briefing search or filtering
- Historical trend charts (source health over time)
- Oban integration (Phase 6)
- Authentication / multi-user
- Serendipity (M-RAD-05)

## Dependencies

- M-RAD-03 (full pipeline producing HTML briefing artifacts)
- Existing Phoenix app (`liminara_web`)
- Existing observation UI (for cross-links)
