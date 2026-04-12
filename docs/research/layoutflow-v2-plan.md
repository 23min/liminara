# layoutFlowV2 — Design Plan

## What the research tells us we're missing

### Critical gaps (the competition has these)

| Feature | Celonis | Disco | Our layoutFlow | Impact |
|---------|---------|-------|----------------|--------|
| **Crossing minimization** | Yes | Yes | None | Spaghetti on complex graphs |
| **Progressive abstraction** (activities/paths sliders) | Yes (killer feature) | Yes (killer feature) | No | Can't handle large processes |
| **Layout stability** across filter changes | Celonis: partial | Disco: partial | No | Mental map lost on updates |
| **Virtual nodes** for long edges | Standard Sugiyama | Standard | No | Unpredictable edge routing |
| **Happy path** highlighting | Yes | Yes | No | Can't see the main flow |

### Important capabilities to plan for

| Feature | What it does | Priority |
|---------|-------------|----------|
| **Variant explorer** | Show top-N paths ranked by frequency | High — maps to dag-map's route concept |
| **Edge grouping/bundling** | Shared segments as single visual path | High — reduces clutter |
| **Swimlane constraints** | Nodes stay in assigned lanes | High — core of Mode 2 |
| **Port constraints** | Control where edges attach to nodes | Medium |
| **Conformance overlay** | Highlight deviations from reference | Medium — rendering layer |
| **Object-centric multi-layer** | One DFG per object type, interleaved | Future — directly relevant to Liminara |
| **Semantic zoom** | Different detail levels at different zoom | Future |
| **Token animation** | Entities flowing through the process | Future |

### Key research papers to build on

1. **Mennens et al. (2019)** — "A stable graph layout algorithm for processes"
   - Global ranking + order constraints for layout stability
   - Phased animation between layout states
   - Directly applicable to slider-based abstraction

2. **Lee, Song, van der Aalst (2025-2026)** — OC-DFG layout
   - Multi-layer layout for object-centric process mining
   - Edge cross-minimization across object type layers
   - Relevant for Liminara's multi-route model

3. **Brandes-Köpf** — coordinate assignment algorithm
   - 4 alignments, take median → robust, compact coordinates
   - Implemented in dagre, well-documented

### What users prefer (from perception research)

- No-crossings layouts preferred even when crossing layouts enable faster tasks
- Curved edges preferred when crossings occur
- Progressive disclosure (show less, explore more) > showing everything at once

## layoutFlowV2 Architecture

### Core principles

1. **Proper Sugiyama pipeline** — not ad-hoc heuristics
2. **Routes as first-class concept** — not bolted on
3. **Swimlane = constraint** on Y, not separate engine
4. **Station cards = optional layer** — toggle on/off
5. **GA-evolvable** — key parameters exposed
6. **Stable across updates** — Mennens-style constraints

### The pipeline

```
Input: DAG + routes + (optional) lane assignments + (optional) metrics

Phase 1: STRUCTURE
  1a. Topo sort + layer assignment (network simplex or longest-path)
  1b. Virtual node insertion for long edges
  1c. Route membership: which routes pass through each node

Phase 2: ORDERING (crossing minimization)
  2a. Initial ordering: barycenter or spectral
  2b. Crossing reduction: multi-pass barycenter sweep (10-25 passes)
  2c. Route-aware refinement: same-route nodes prefer adjacency
  2d. Swimlane constraints: nodes stay in assigned lanes

Phase 3: POSITIONING
  3a. X assignment: layer × spacing (or consumer-provided)
  3b. Y assignment:
      - Swimlane mode: each route = own Y lane
      - Free mode: Brandes-Köpf coordinate assignment
  3c. Compact X (optional): pull toward neighbor barycenters

Phase 4: EDGE ROUTING
  4a. Shared segments: bundle parallel edges
  4b. H-V-H routing with rounded corners
  4c. Obstacle avoidance around station cards (if cards enabled)
  4d. Edge grouping at ports

Phase 5: RENDERING
  5a. Stations: dots (simple) or cards (with label + data)
  5b. Interchange stations: pills spanning track offsets
  5c. Route lines: colored, per-route styling
  5d. Metrics overlay: heatmap coloring by performance/frequency
  5e. Lane dividers: horizontal lines separating swimlanes

Phase 6: INTERACTION (future)
  6a. Progressive abstraction sliders (activities, paths)
  6b. Click-to-filter
  6c. Hover tooltips with metrics
  6d. Semantic zoom
```

### Evolvable parameters

| Parameter | Type | Range | What it controls |
|-----------|------|-------|-----------------|
| `layerAssignment` | categorical | longest-path, network-simplex | How layers are assigned |
| `crossingPasses` | continuous | 1-50 | Crossing reduction iterations |
| `coordinateMethod` | categorical | brandes-kopf, barycenter, centroid | X/Y fine-tuning |
| `laneHeight` | continuous | 40-120 | Swimlane spacing |
| `edgeRouting` | categorical | hvh, bezier, straight | Edge style |
| `bundleThreshold` | continuous | 0-1 | When to bundle shared edges |
| `cardMode` | categorical | none, compact, full | Station card detail level |

### Relationship to existing code

```
dag-map/src/
  layout-metro.js     — Mode 1 (metro map) — KEEP, already evolved
  layout-flow.js      — Mode 2 legacy — KEEP as reference, mark deprecated
  layout-flow-v2.js   — Mode 2 new — BUILD THIS
  layout-hasse.js     — Lattice layout — KEEP
  strategies/          — Shared strategies (crossing reduction, ordering, etc.)
```

layoutFlowV2 REUSES strategies from the shared `strategies/` directory:
- `crossing-utils.js` — layer building, crossing count
- `matrix.js` — adjacency matrix, Laplacian
- `track-assignment.js` — MLCM at interchanges
- `order-nodes-*.js` — ordering strategies

## Lessons from Flow Legacy vs FlowV2 Comparison (2026-04-12)

### What Legacy does well that FlowV2 must adopt

1. **Shared spine model** — routes share the trunk's Y axis and deviate only
   at divergence points. NOT one-lane-per-route swimlanes. This is the
   "directly-follows graph" paradigm from process mining.

2. **Global side assignment** — each non-trunk route gets a FIXED side
   (left/right of trunk) maintained everywhere. Prevents crossings.

3. **Dot spacing at shared nodes** — parallel routes spread by `dotSpacing`
   (12px), not `laneHeight` (70px). Very compact.

4. **Station cards with obstacle routing** — cards placed next to stations,
   edges route around them via occupancy grid.

5. **Sequential trunk-first placement** — trunk laid first gets best path,
   other routes route around existing obstacles.

### What Legacy does poorly that FlowV2 must fix

1. **No crossing minimization** — relies purely on side assignment
2. **Hardcoded heuristics** — not evolvable
3. **No progressive abstraction**
4. **O(n²) occupancy grid**
5. **Card overlap on dense graphs** — only tries 6 positions

### The right FlowV2 model

NOT swimlanes. Instead: **shared-spine with deviation tracks**.

```
Trunk:     ────●────●────●────●────●────
Route A:   ────●────●──┐ ●────●────●────
                       └─●
Route B:        ●──┐    ●────●
                   └────●
```

### Revised milestones

```
FV2-1: ✅ Basic swimlane pipeline (proved wrong approach)

FV2-2: Shared-spine model — trunk-first, global side assignment,
       dot spacing. Clean code, evolvable params. Match Legacy quality.

FV2-3: Crossing minimization — barycenter sweep at shared nodes.
       Measure improvement vs Legacy on MLCM + internal fixtures.

FV2-3: Station cards + obstacle routing — optional cards with
       label/data, edges route around cards.

FV2-4: Edge bundling + port constraints — shared segments as
       single visual path, controlled edge attachment points.

FV2-5: GA integration — expose parameters, evolve best configuration.
       Compare against Celonis/Disco screenshots (visual benchmark).

FV2-6: Progressive abstraction — activities/paths sliders,
       layout stability (Mennens constraints).
```

### Success criteria

- [ ] Visually comparable to Celonis/Disco on simple process maps
- [ ] Zero crossing on all MLCM fixtures
- [ ] Station cards optional and clean
- [ ] GA converges on a configuration
- [ ] Works for Liminara Radar pack execution DAGs
- [ ] Handles 50+ activities without spaghetti
