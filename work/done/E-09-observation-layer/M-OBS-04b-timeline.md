---
id: M-OBS-04b-timeline
epic: E-09-observation-layer
status: complete
---

# M-OBS-04b: Event Timeline + Decision Viewer

## Goal

Add the event timeline and decision viewer to the observation dashboard. The timeline shows the full chronological event stream for a run, filterable by event type and node, with cross-linking to the DAG. The decision viewer provides a focused view of all recorded nondeterministic choices. Both integrate into the panel layout established in M-OBS-04a.

## Architecture decisions

- **Event storage**: ViewModel stores events (with configurable cap, e.g., last 1000) so all renderers get timeline data through the same Observation.Server API. Event Store remains the canonical archive.
- **Filtering**: Server-side (LiveView owns filter state, re-renders filtered list). Testable in Elixir, consistent with LiveView model, future-proof for large runs.
- **Layout**: Timeline is a new collapsible panel in the CSS Grid layout from M-OBS-04a.

## Acceptance criteria

### ViewModel event storage
- [ ] ViewModel stores events list (append-only, capped at configurable limit)
- [ ] `Observation.Server.get_events(run_id)` API returns stored events
- [ ] `Observation.Server.get_events(run_id, filters)` supports filtering by event_type and node_id
- [ ] Events beyond the cap are dropped (oldest first)

### Event timeline panel
- [ ] Timeline panel added to dashboard grid layout (collapsible bottom panel)
- [ ] Shows all events for the current run in chronological order
- [ ] Each event shows: timestamp, event_type, relevant payload summary (node_id, status, etc.)
- [ ] Events stream in real-time for active runs
- [ ] Filterable by event type (e.g., show only op_completed events)
- [ ] Filterable by node (e.g., show only events for node "summarize")
- [ ] Clicking an event in the timeline selects the corresponding node in the DAG
- [ ] Timeline panel is collapsible/expandable

### Decision viewer
- [ ] A tab or section within the inspector (or timeline) showing all decisions for the run
- [ ] Each decision shows: node_id, decision_type, inputs summary, output/choice summary, recorded_at
- [ ] Clicking a decision selects the corresponding node in the DAG

### Layout integration
- [ ] Timeline integrates into CSS Grid layout from M-OBS-04a as a new panel area
- [ ] Mobile: timeline is a full-screen overlay or tab
- [ ] All panels (DAG, inspector, timeline) update in real-time for active runs

## Tests

### ViewModel event storage tests
- Apply events to ViewModel, verify events list is populated
- Apply events beyond cap, verify oldest events are dropped
- Filter events by event_type, verify only matching events returned
- Filter events by node_id, verify only matching events returned

### Event timeline tests
- Load timeline for a completed run, verify all events present in chronological order
- Load timeline for an active run, verify new events appear in real-time
- Filter by event type, verify only matching events shown
- Filter by node_id, verify only events for that node shown
- Click an event, verify corresponding node is selected in the DAG

### Decision viewer tests
- Load decision viewer for a run with recorded decisions, verify all decisions listed
- Click a decision, verify corresponding node is selected

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Client-side filtering (JS)
- Full-text search across events
- Event export (CSV, JSON download)
- Artifact provenance graph (upstream trace across multiple runs)
- Run-to-run comparison / decision diffing

## Spec reference

- `docs/architecture/01_CORE.md §Observation: the Excel quality`
- `docs/history/architecture/03_PHASE3_REFERENCE.md §Event types and hash chain`

## Related ADRs

- none yet
