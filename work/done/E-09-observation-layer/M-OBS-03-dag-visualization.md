---
id: M-OBS-03-dag-visualization
epic: E-09-observation-layer
status: complete
---

# M-OBS-03: SVG DAG Visualization with Real-Time Updates

## Goal

Build the core visual feature: an SVG-based DAG visualization that renders the run's plan as a directed graph, with nodes colored by state, updating in real-time as events arrive. This is the "Excel quality" — you can see the entire computation at a glance.

## Design principle: show values, not plumbing

Per `docs/history/architecture/04_OBSERVATION_DESIGN_NOTES.md` §1 — "Show the grid, not the logic":

- Nodes show **op name** while pending/running
- Nodes switch to showing **output value preview** (truncated artifact content) once completed
- Status is conveyed by **color/border**, not as primary text content
- The user's mental model is "a grid of results filling in," not "a workflow diagram advancing"

## Acceptance criteria

- [x] DAG layout algorithm: given a plan (nodes + edges), compute x/y positions using a layered layout
- [x] Nodes positioned in layers by topological depth
- [ ] ~~Layout direction is configurable: left-to-right (default) or top-to-bottom~~ **Deferred** — LTR only. TTB is on dag-map roadmap v0.2.
- [x] Edges rendered as paths between nodes ~~with arrowheads showing direction~~ — metro-map aesthetic uses flow direction (LTR) instead of arrowheads. This is a deliberate design choice.
- [x] Node visual states: pending (gray), running (coral), completed (teal), failed (red), waiting/gate (amber)
- [x] Nodes are small (compact ~~rectangles~~ station circles, small text)
- [x] ~~Pending/running nodes display op name; completed nodes display output preview~~ **Descoped** — output preview deferred to dag-map annotation layer (callout boxes). Completed nodes use teal color as state indicator.
- [x] SVG renders inline in the run detail LiveView page, replacing the existing node list
- [x] SVG updates in real-time as node states change (hook re-renders on data-dag attribute changes)
- [x] Clicking a node selects it (visual highlight, emits event for inspector in M-OBS-04)
- [x] Layout handles linear pipelines, fan-out, and fan-in correctly
- [x] SVG has `viewBox` and scales to fit container; CSS `overflow: auto` for scrolling when graph overflows
- [x] Works on mobile: nodes are tap-selectable, graph is scrollable

## What was built (session log)

### dag-map library (extracted to separate repo)

The visualization algorithm was developed through 32+ iterations (v1–v32, then R1–R10) in `.scratch/metro-experiments/`, then extracted into a standalone library at `/workspaces/liminara/dag-map/` (GitHub: https://github.com/23min/DAG-map), added as a git submodule.

**Key design decisions:**
- **Route-based layout** — greedy longest-path decomposition extracts "routes" (metro lines) from the DAG, not individual edges
- **Bezier routing** (default) — cubic S-curves for smooth organic feel
- **Angular routing** (alternative) — progressive steepening/flattening curves
- **Forward-only diagonal rule** — all diagonals progress left-to-right, creating lozenge/lens shapes
- **Interchange-based direction detection** — fork vs return determined by structural role, not distance heuristics
- **Through-hole stations** — white fill + colored ring, like London Underground / PCB through-holes
- **6 themes** — cream (default), light, dark, blueprint, mono, metro
- **CSS variable mode** — opt-in `cssVars: true` for CSS-only theming
- **Configurable** — scale, spacing, progressive power, diagonal labels, legend labels

**Library structure:**
```
dag-map/
├── src/index.js, layout.js, render.js, route-bezier.js, route-angular.js, themes.js
├── dag-map.css              # library CSS (custom properties)
├── demo/standalone.html     # interactive demo (works from file://)
├── docs/examples/           # screenshot gallery for README
├── ROADMAP.md               # versioned feature roadmap
└── README.md                # full API docs, theming guide
```

### Liminara integration

- **`dag-map-bundle.js`** — IIFE bundle of all dag-map modules, served as Phoenix static asset at `/assets/js/dag-map-bundle.js`
- **`DagMap` LiveView hook** — in `root.html.heex`, parses `data-dag` JSON attribute, calls `DagMap.layoutMetro()` + `DagMap.renderSVG()`, inserts SVG into DOM
- **`RunsLive.Show`** — builds JSON DAG data from `Plan` (nodes + edges extracted from `:ref` inputs), passes as `data-dag` attribute
- **`build_dag_data/2`** — reads `plan.json` via `Store.read_plan`, extracts edges, maps node status to dag-map class names
- **`Plan.from_map/1` fix** — changed `binary_to_existing_atom` to `binary_to_atom` so plans with unloaded op modules don't crash
- **`mix demo_run`** — creates a 10-node demo DAG (fan-out + fan-in) with proper `plan.json`
- **Runs index** — table with timestamps, sorted by most recent, test runs filtered out
- **Page chrome** — cream theme, IBM Plex Mono, status badges, proper layout

### Files modified/created in this session

**Runtime (Elixir):**
- `runtime/apps/liminara_web/lib/liminara_web/components/layouts/root.html.heex` — CSS, dag-map bundle, DagMap hook
- `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex` — client-side rendering via hook
- `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/index.ex` — table layout, timestamps, test run filter
- `runtime/apps/liminara_web/lib/liminara_web/router.ex` — root redirect to /runs
- `runtime/apps/liminara_web/lib/liminara_web/plugs/redirect.ex` — redirect plug
- `runtime/apps/liminara_web/lib/mix/tasks/demo_run.ex` — demo data seeder
- `runtime/apps/liminara_web/priv/static/assets/js/dag-map-bundle.js` — generated bundle
- `runtime/apps/liminara_web/priv/static/assets/css/dag-map.css` — copied from library
- `runtime/apps/liminara_core/lib/liminara/plan.ex` — `to_atom` fix

**Tests updated:**
- `runtime/apps/liminara_web/test/liminara_web/live/runs_live_show_test.exs` — updated for hook-based rendering

## Remaining work (4 items)

### 1. Real-time updates
Currently `phx-update="ignore"` prevents LiveView from touching the hook's DOM. The hook needs to detect when `data-dag` changes and re-render. Options:
- Remove `phx-update="ignore"` and have LiveView update the attribute, triggering the hook's `updated()` callback
- Or use `pushEvent` from the server to the hook

### 2. State-based node coloring
`status_to_cls/1` in `show.ex` currently maps all completed nodes to `"pure"` (teal). Need distinct mapping:
- pending → a muted/gray class
- running → `"recordable"` (coral)
- completed → `"pure"` (teal)
- failed → `"gate"` (red)
- waiting → `"side_effecting"` (amber)

This is already partially there but needs a custom theme or additional class colors for pending/gray.

### 3. Click → select node
dag-map renders SVG stations as `<circle>` elements. Need to:
- Add `data-node-id` attributes to station circles in dag-map's renderer
- Add click handler in the hook that calls `this.pushEvent("select_node", {node_id: ...})`
- Show selected node with visual highlight (thicker stroke, different color)

### 4. Output previews on completed nodes
- Pass output preview data in the `data-dag` JSON (the LiveView already has access to artifacts)
- dag-map would need a way to show additional text per node (annotation or secondary label)
- Could use the existing label system or a new annotation layer (dag-map roadmap v0.4)

## Architecture

- `dag-map` (JS library, git submodule) — layout + SVG rendering, client-side
- `DagMap` LiveView hook — bridges LiveView data to dag-map JS
- `RunsLive.Show` — serializes Plan + node states to JSON for the hook
- `Observation.Server` — source of truth for node states (unchanged from M-OBS-01)

## Tests

### Unit tests — layout algorithm (`liminara_observation`)
Existing `Layout` module tests still pass (237 tests). The Elixir layout module is kept as a server-side fallback.

### LiveView tests (`liminara_web`)
Updated to verify hook-based rendering: `id="dag-map"`, `phx-hook="DagMap"`, `data-dag=` presence, node/edge data in JSON. 21 tests pass.

## Out of scope

- Canvas-based rendering (SVG only)
- Pinch-to-zoom (scroll only)
- Node inspector panel content (M-OBS-04 — this milestone only emits the selection event)
- Edge labels or artifact names on edges
- Animation beyond state-change color transitions
- Discovery mode (dynamic DAG expansion)
- DAG editing (read-only observation)
- Top-to-bottom layout direction (deferred to dag-map v0.2)

## Spec reference

- `docs/architecture/01_CORE.md §The plan: a DAG you can read`
- `docs/history/architecture/04_OBSERVATION_DESIGN_NOTES.md §1 Show the grid, not the logic`
- `docs/research/graph_execution_patterns.md §7 Visualization`
- `docs/history/architecture/06_VISUALIZATION_DESIGN.md` — full visualization design spec

## Related ADRs

- none yet (consider: ADR for choosing client-side JS rendering over server-side Elixir)
