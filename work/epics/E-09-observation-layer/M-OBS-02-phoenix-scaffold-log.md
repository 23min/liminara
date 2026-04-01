# M-OBS-02-phoenix-scaffold — Session Log

Append a new entry after each significant work session. Do not edit previous entries.

---

## 2026-03-19 — Session: Phoenix LiveView runs dashboard implementation

**Agents:** impl-agent
**Branch/worktree:** main (agent-a471fab5 worktree)

**Decisions made:**
- Used Erlang `:pg` groups (`:all_runs` and `{:run, run_id}`) for real-time event delivery to LiveViews, matching the existing broadcast infrastructure in Run.Server
- Index LiveView loads 50 most-recent runs by `events.jsonl` mtime (filesystem sort) to avoid needing a separate metadata index
- Show LiveView builds its own minimal view model from raw events rather than requiring Observation.Server to be running — enables static view of completed runs
- Added `Event.Store.touch/1` to update mtime when Run.Server rebuilds a completed run from its event log, ensuring mtime-based sorting stays accurate
- Added `result_from_event_log/1` fallback in `Run.Server.await/2` for runs that complete and exit before `await` is called
- Changed `Observation.Server` state from bare `ViewModel` to `{view, seen_hashes}` tuple to prevent double-counting events broadcast during rebuild
- During Run.Server rebuild of a completed run, broadcast ALL events from the log (not just the last) so subscribers see the full event stream

**Tried and abandoned:**
- Broadcasting only the terminal event (`run_completed`/`run_failed`) during rebuild — caused BroadcastTest failures when tests expected `run_started` as first event
- Suppressing rebuild broadcasts entirely — caused Index LiveView tests to miss dynamically-started runs whose server exits before the test subscribes

**Outcome:**
- 28 LiminaraWeb tests passing consistently (5/5 sequential runs, 0 failures)
- `mix format`, `mix credo`, `mix dialyzer`, `mix test` all clean
- Files added/modified:
  - `apps/liminara_web/lib/liminara_web/live/runs_live/index.ex` — new
  - `apps/liminara_web/lib/liminara_web/live/runs_live/show.ex` — new
  - `apps/liminara_core/lib/liminara/event/store.ex` — added `touch/1,2`
  - `apps/liminara_core/lib/liminara/run/server.ex` — rebuild broadcasts, `result_from_event_log`, `atomize_event`, `broadcast(:all_runs)`, credo refactors
  - `apps/liminara_observation/lib/liminara/observation/server.ex` — `{view, seen_hashes}` state, deduplication

**Open / next session:**
- M-OBS-03: SVG DAG visualization with real-time updates

---

## 2026-03-19 — Session: PubSub topic split + test stability fix

**Decisions made:**
- Split PubSub into `observation:{run_id}:state` and `observation:{run_id}:events` per `04_OBSERVATION_DESIGN_NOTES.md` (behaviors vs events). DAG view subscribes to `:state`, future timeline subscribes to `:events`.
- Added `get_events/1` API to Observation.Server for accumulated events list.
- Fixed intermittent test failures: root cause was 46K+ stale run directories in `/tmp/liminara_runs/` from previous test sessions. `:erlang.unique_integer([:positive])` resets per BEAM session, causing run_id collisions with old event files. Run.Server's crash recovery read stale events.
- Fix: switched `unique_run_id` to `:crypto.strong_rand_bytes` (collision-proof). Added cleanup of /tmp dirs at start of each test suite in all 3 test_helper.exs files.
- Replaced `Process.sleep` + assert patterns with `await_observation` polling helper.
- Added config/dev.exs, config/test.exs, config/prod.exs for proper env-specific configuration.

**Open / next session:**
- None — milestone complete.
