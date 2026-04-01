# Session Snapshot — 2026-03-22

> For picking up work on a different machine/session. Delete after resuming.

## What was completed: M-OBS-04a (Node Inspector + Artifact Viewer)

**Status:** Done. All tests pass (60/60). **Not yet committed** — user reviews and commits.

**Branch:** `epic/E-09-observation-layer`

## Files changed (uncommitted)

Backend:
- `apps/liminara_observation/lib/liminara/observation/server.ex` — added `get_artifact_content/2` and `/3` API
- `apps/liminara_core/lib/liminara/artifact/store.ex` — fixed `get/2` to handle all File.read errors as `:not_found`

Frontend:
- `apps/liminara_web/lib/liminara_web/live/runs_live/show.ex` — inspector panel, artifact viewer, dashboard grid layout, deselect_node/view_artifact/close_artifact events, auto-starts Observation.Server on mount for rich node data
- `apps/liminara_web/lib/liminara_web/components/layouts/root.html.heex` — PanelResize hook, CSS for inspector/grid/artifact-viewer, hash truncation styling

Tests (new):
- `apps/liminara_observation/test/liminara/observation/server_artifact_test.exs` — 8 tests
- `apps/liminara_web/test/liminara_web/live/runs_live_inspector_test.exs` — 35 tests

Demo:
- `apps/liminara_web/lib/mix/tasks/demo_run.ex` — rewritten to use real Run.Server

Milestone docs:
- `work/epics/E-09-observation-layer/M-OBS-04a-inspector.md` — created, status: done
- `work/epics/E-09-observation-layer/M-OBS-04a-inspector-log.md` — session log
- `work/epics/E-09-observation-layer/M-OBS-04b-timeline.md` — created, status: draft
- `work/epics/E-09-observation-layer/M-OBS-04-inspectors.md` — deleted (split into 04a + 04b)
- `work/epics/E-09-observation-layer/epic.md` — milestone table updated
- `work/roadmap.md` — M-OBS-04a checked off

## Key decisions made

- Split M-OBS-04 into 04a (inspector + artifact viewer) and 04b (timeline + decision viewer)
- Artifact access via `Observation.Server.get_artifact_content/2` — all observation through one door
- Artifact viewer is sub-component inside inspector panel
- Dashboard layout: CSS Grid + PanelResize JS hook, no libraries
- Event filtering (for 04b): server-side via LiveView
- Event storage (for 04b): ViewModel with cap
- Hash display truncated to `sha256:abcd1234...`

## Known issues

- 4 pre-existing failures in `runs_live_index_test.exs`
- 1 pre-existing failure in `runs_live_show_test.exs` (multi-node run)

## What's next

1. **Commit** the M-OBS-04a changes
2. **M-OBS-04b** — Event Timeline + Decision Viewer (spec at `M-OBS-04b-timeline.md`)
3. **M-OBS-05** — A2UI experimental renderer (last milestone in E-09)
