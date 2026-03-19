---
id: M-OBS-04-inspectors
epic: E-09-observation-layer
status: draft
---

# M-OBS-04: Node Inspector, Artifact Viewer, Event Timeline

## Goal

Build the drill-down features that give the observation layer its depth. When a user selects a node in the DAG, an inspector panel shows everything about that node: its op definition, inputs and outputs (with artifact content), decisions, and timing. An event timeline shows the full chronological event stream. An artifact viewer displays content by type.

This is the "click a cell, see its formula" quality from the Excel analogy.

## Acceptance criteria

### Node inspector
- [ ] Selecting a node in the DAG (from M-OBS-03) opens an inspector panel
- [ ] Inspector shows: node_id, op name, op version, determinism class, status
- [ ] Inspector shows timing: started_at, completed_at, duration_ms
- [ ] Inspector shows inputs: for each input, the source (literal value or ref to another node), artifact hash, and a link to view the artifact content
- [ ] Inspector shows outputs: for each output, the artifact hash and a link to view content
- [ ] Inspector shows cache status: whether the result was a cache hit
- [ ] For gate nodes: shows the gate prompt and the resolution (approved/rejected + response data)
- [ ] For recordable nodes: shows decision summary (decision_type, decision_hash)
- [ ] Inspector panel is dismissible (close button or click elsewhere)

### Artifact viewer
- [ ] Given an artifact hash, displays the artifact content
- [ ] JSON artifacts: pretty-printed with syntax highlighting
- [ ] Text/string artifacts: displayed as plain text
- [ ] Binary artifacts: shows type, size, and hash (no inline rendering of PDFs/images yet)
- [ ] Artifact viewer is accessible from the inspector (click an artifact hash to view it)

### Event timeline
- [ ] Shows all events for the current run in chronological order
- [ ] Each event shows: timestamp, event_type, relevant payload summary (node_id, status, etc.)
- [ ] Events stream in real-time for active runs
- [ ] Filterable by event type (e.g., show only op_completed events)
- [ ] Filterable by node (e.g., show only events for node "summarize")
- [ ] Clicking an event in the timeline selects the corresponding node in the DAG

### Decision viewer
- [ ] For runs with recorded decisions: a section or tab showing all decisions
- [ ] Each decision shows: node_id, decision_type, inputs summary, output/choice summary, recorded_at
- [ ] Clicking a decision selects the corresponding node in the DAG

### Layout
- [ ] Desktop: DAG on the left/top, inspector on the right/bottom, timeline in a collapsible panel
- [ ] Mobile: inspector and timeline are full-screen overlays triggered by node selection or a tab
- [ ] All panels update in real-time for active runs

## Tests

### Node inspector tests
- Select a completed node, verify inspector shows correct op info, timing, inputs, outputs
- Select a failed node, verify inspector shows error information
- Select a gate node (waiting), verify inspector shows gate prompt
- Select a gate node (resolved), verify inspector shows gate response and decision
- Select a cached node, verify inspector shows cache_hit: true
- Deselect node, verify inspector panel closes

### Artifact viewer tests
- View a JSON artifact, verify it renders as pretty-printed JSON
- View a text/string artifact, verify it renders as plain text
- View a binary artifact, verify it shows type/size/hash metadata
- Attempt to view a non-existent artifact hash, verify error handling

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

- Inline rendering of binary artifacts (PDFs, images) — show metadata only
- Run-to-run comparison / decision diffing
- Artifact provenance graph (upstream trace across multiple runs)
- Search across runs
- Export functionality

## Spec reference

- `docs/architecture/01_CORE.md §Observation: the Excel quality`
- `docs/architecture/03_PHASE3_REFERENCE.md §Event types and hash chain`

## Related ADRs

- none yet
