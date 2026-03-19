---
id: M-OBS-03-dag-visualization
epic: E-09-observation-layer
status: draft
---

# M-OBS-03: SVG DAG Visualization with Real-Time Updates

## Goal

Build the core visual feature: an SVG-based DAG visualization that renders the run's plan as a directed graph, with nodes colored by state, updating in real-time as events arrive. This is the "Excel quality" — you can see the entire computation at a glance.

## Acceptance criteria

- [ ] DAG layout algorithm: given a plan (nodes + edges), compute x/y positions using a layered (Sugiyama-style) layout
- [ ] Nodes positioned in layers by topological depth (inputs left, outputs right — or top to bottom)
- [ ] Edges rendered as paths between nodes, with arrowheads showing direction
- [ ] Node visual states: pending (gray), running (blue, animated), completed (green), failed (red), waiting/gate (amber)
- [ ] SVG renders inline in the run detail LiveView page
- [ ] SVG updates in real-time as node states change (no full page re-render — LiveView diffs the SVG)
- [ ] Clicking a node selects it (visual highlight, emits event for inspector in M-OBS-04)
- [ ] Nodes display: op name and short status text
- [ ] Layout handles linear pipelines, fan-out, and fan-in correctly
- [ ] SVG is responsive: scales to fit container width, maintains aspect ratio
- [ ] Works on mobile: nodes are tap-selectable, graph is scrollable/zoomable if it overflows

## Tests

### Unit tests — layout algorithm
- Linear pipeline (A→B→C): nodes arranged in 3 layers, edges go left-to-right (or top-to-bottom)
- Fan-out (A→B, A→C, A→D): A in first layer, B/C/D in second layer
- Fan-in (A→C, B→C): A and B in first layer, C in second layer
- Diamond (A→B, A→C, B→D, C→D): 3 layers, D depends on both B and C
- Complex DAG (ToyPack plan): verify no overlapping nodes, all edges connect correct nodes
- Single node plan: degenerate case, renders one node
- Edge ordering: edges don't cross unnecessarily (minimize crossings)

### Component tests — SVG rendering
- Given a layout (nodes with positions + edges), verify SVG output contains correct elements: `<rect>` or `<circle>` per node, `<path>` or `<line>` per edge, `<text>` for labels
- Verify node CSS classes match their state (e.g., `class="node node--completed"`)
- Verify arrowheads are present on edges

### LiveView tests — real-time updates
- Mount run detail page with an active run. Start the run. Verify SVG node states update as events arrive (pending → running → completed).
- Verify that clicking a node emits a `select_node` event with the node_id
- Verify the selected node has a distinct visual style (e.g., `class="node node--selected"`)

### Responsiveness tests
- Verify SVG has `viewBox` attribute and scales to container width
- Verify SVG is scrollable on small screens when the graph is wider than the viewport

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Canvas-based rendering (SVG only for now)
- Node inspector panel content (M-OBS-04 — this milestone only emits the selection event)
- Edge labels or artifact names on edges
- Animation beyond state-change transitions (no particle effects, no physics)
- Discovery mode (dynamic DAG expansion visualization)
- DAG editing (observation is read-only)

## Spec reference

- `docs/architecture/01_CORE.md §The plan: a DAG you can read`
- `docs/research/graph_execution_patterns.md §7 Visualization`

## Related ADRs

- none yet
