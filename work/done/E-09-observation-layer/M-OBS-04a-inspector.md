---
id: M-OBS-04a-inspector
epic: E-09-observation-layer
status: complete
---

# M-OBS-04a: Node Inspector + Artifact Viewer

## Goal

Build the drill-down panel that gives the observation layer its depth. When a user selects a node in the DAG, an inspector panel slides in showing everything about that node: op definition, timing, inputs/outputs with artifact hashes, cache status, gate/decision details. Clicking an artifact hash renders the artifact content inline within the inspector. This also introduces the dashboard panel layout (CSS Grid + resize hook) that M-OBS-04b and future milestones build on.

This is the "click a cell, see its formula" quality from the Excel analogy.

## Architecture decisions

- **Artifact content access**: via `Observation.Server.get_artifact_content(run_id, hash)` — all observation goes through one door. LiveView and future renderers (A2UI) use the same API.
- **Artifact viewer**: a sub-component inside the inspector panel, not a separate panel. The inspector is the stable container; the artifact viewer is a pluggable content area within it.
- **Dashboard layout**: CSS Grid + a small `PanelResize` JS hook for drag-to-resize. No library dependencies. Mobile: grid collapses to single column, inspector becomes full-screen overlay.

## Acceptance criteria

### Dashboard layout shell
- [x] Run detail page uses CSS Grid panel layout: DAG (primary) + Inspector (detail)
- [x] Inspector panel appears when a node is selected, hidden when nothing selected
- [x] Panels are resizable via drag handle between them (JS hook)
- [x] Panels are collapsible (minimize to header bar)
- [x] Mobile: inspector is a full-screen overlay triggered by node selection
- [x] Layout is modular — adding a new panel (timeline in 04b) means adding a grid area

### Node inspector
- [x] Selecting a node in the DAG opens the inspector panel
- [x] Inspector shows: node_id, op name, op version, determinism class, status
- [x] Inspector shows timing: started_at, completed_at, duration_ms
- [x] Inspector shows inputs: for each input, the source (literal value or ref to another node), artifact hash, and a clickable link to view artifact content
- [x] Inspector shows outputs: for each output, the artifact hash and a clickable link to view content
- [x] Inspector shows cache status: whether the result was a cache hit
- [x] For gate nodes: shows the gate prompt and the resolution (approved/rejected + response data)
- [x] For recordable nodes: shows decision summary (decision_type, decision_hash)
- [x] Inspector panel is dismissible (close button or click empty DAG area)

### Artifact viewer (inside inspector)
- [x] `Observation.Server.get_artifact_content(run_id, hash)` API exists and delegates to Artifact Store
- [x] Clicking an artifact hash in the inspector renders artifact content inline
- [x] JSON artifacts: pretty-printed with syntax highlighting
- [x] Text/string artifacts: displayed as plain text
- [x] Binary artifacts: shows type, size, and hash (no inline rendering of PDFs/images yet)
- [x] Back/close button returns to the node detail view

## Tests

### Dashboard layout tests
- Mount run detail page, verify CSS Grid layout renders
- Select a node, verify inspector panel appears
- Deselect node (close button), verify inspector panel hides
- Verify panel resize hook is attached

### Node inspector tests
- Select a completed node, verify inspector shows correct op info, timing, inputs, outputs
- Select a failed node, verify inspector shows error information
- Select a gate node (waiting), verify inspector shows gate prompt
- Select a gate node (resolved), verify inspector shows gate response and decision
- Select a cached node, verify inspector shows cache_hit: true
- Deselect node, verify inspector panel closes

### Artifact viewer tests
- `Observation.Server.get_artifact_content/2` returns content for a known hash
- `Observation.Server.get_artifact_content/2` returns error for unknown hash
- Click artifact hash in inspector, verify content renders inline
- View a JSON artifact, verify it renders as pretty-printed JSON
- View a text/string artifact, verify it renders as plain text
- View a binary artifact, verify it shows type/size/hash metadata

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Event timeline (M-OBS-04b)
- Decision viewer (M-OBS-04b)
- Inline rendering of binary artifacts (PDFs, images)
- Run-to-run comparison / decision diffing
- Search across runs
- Export functionality

## Spec reference

- `docs/architecture/01_CORE.md §Observation: the Excel quality`
- `docs/history/architecture/03_PHASE3_REFERENCE.md §Event types and hash chain`

## Related ADRs

- none yet
