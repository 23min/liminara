# M-OBS-03 DAG Visualization — Session Log

Append a new entry after each significant work session. Do not edit previous entries.

---

## 2026-03-22 — Session: Real-time updates, node coloring, click-to-select

**Agents:** impl-agent (Claude Opus 4.6)
**Branch/worktree:** epic/E-09-observation-layer

**Decisions made:**
- Added `data-id` attribute to dag-map station circles (render.js) — enables click/tap selection without position-based hit testing
- Added `pending` class (muted gray) to all 6 dag-map themes — runtime state indicator, deliberately not added to the legend (legend shows semantic determinism classes, not states)
- Removed `phx-update="ignore"` from dag-map container — hook's `updated()` callback now fires on every `@dag_data` change, enabling real-time SVG re-renders
- Click handler uses event delegation on `circle[data-id]` elements; selection state (`selectedNodeId`) preserved across re-renders on the hook instance
- Output preview on completed nodes descoped from M-OBS-03 — deferred to dag-map annotation layer (callout boxes with leader lines, per user preference for margin-based content rather than inline labels)

**Tried and abandoned:**
- Nothing abandoned — all approaches worked on first attempt

**Outcome:**
- All 4 remaining M-OBS-03 acceptance criteria checked (node coloring, real-time updates, click-to-select, mobile)
- dag-map changes: render.js (data-id), themes.js (pending class), dag-map.css (--dm-cls-pending)
- Liminara changes: show.ex (removed phx-update="ignore", fixed status_to_cls, added selected node debug display), root.html.heex (click handler + highlight logic)
- 4 new tests added (select_node event, cls mapping for completed/pending/running)
- 25 show tests pass; pre-existing test isolation issue with IndexTest (shared artifact store) unrelated

**Open / next session:**
- M-OBS-04: Inspector panel, artifact viewer, event timeline (separate session)
- M-OBS-05: A2UI viability validation (separate session)
- dag-map roadmap: callout/annotation layer for output previews (future)
- Pre-existing IndexTest failures need investigation (test isolation / shared ETS state)
