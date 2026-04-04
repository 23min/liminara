---
title: Visualization Design Spec
doc_type: architecture-history
truth_class: historical
status: archived
owner: history
archived_on: 2026-04-04
snapshot_date: 2026-04-04
superseded_by:
  - work/done/E-09-observation-layer/M-OBS-03-dag-visualization.md
  - runtime/apps/liminara_web/
---

# Visualization Design Spec

How the DAG observation UI should look, feel, and scale. Informs M-OBS-03 (DAG visualization), M-OBS-04 (inspectors), and future visualization work.

For design principles (what to show), see `04_OBSERVATION_DESIGN_NOTES.md`.
For the observation server architecture, see `03_PHASE3_REFERENCE.md`.

---

## Visual identity

The goal: **an annotated notebook page that fills in as computation proceeds.** Not a workflow dashboard, not a pipeline monitor. A warm, readable surface where results appear.

### Aesthetic references

- **Giorgia Lupi / Dear Data** — small marks, annotation-first, cream paper, constrained warm palette, hand-drawn quality, layered density that reveals pattern at distance and detail up close.
- **TouchDesigner** — each node is a live viewport of its output. The graph IS the results.
- **Disco (Fluxicon)** — animated dots flowing through a process graph, making bottlenecks visible as accumulation.
- **RxMarbles** — temporal-first, values flowing through operators as colored dots on a timeline.

### Palette

Built on the proliminal.net design system (cream paper, ink hierarchy, IBM Plex Mono).

| Role | Token | Approx value | Use |
|------|-------|-------------|-----|
| Background | `--paper-warm` | Cream | Canvas surface |
| Structure | `--ink` | Near-black | Primary text, key edges |
| Secondary | `--ink-light` | Medium gray | Annotations, leader lines |
| Ghost | `--ink-ghost` | Light gray | Cached/replayed nodes, inactive edges |
| Pure ops | `--teal` | `#2B8A8E` | Deterministic computation |
| Recordable ops | `--coral` | `#E8846B` | LLM calls, nondeterministic choices |
| Side-effecting | `--amber` | `#D4944C` | HTTP fetches, file I/O, external calls |
| Error / gate | `--red` | Existing | Failed ops, blocked gates |
| Cached | `--ink-ghost` | Existing | Already-computed, muted presence |

Four semantic colors (teal, coral, amber, red) map to the four determinism classes (pure, recordable, pinned_env, side_effecting). This encoding is consistent across all views.

### Typography

- **IBM Plex Mono** — node labels, artifact previews, annotations, legends
- Small sizes (11-13px for labels, 10px for annotations)
- The annotated-notebook feel comes from monospace at small scale with generous spacing

### Marks

- **Nodes are small filled circles** (8-12px radius), not rectangles
- **Edges are thin curved lines** (1-1.5px stroke, quadratic bezier), not straight arrows with heavy arrowheads
- **Arrowheads are minimal** — small tapered endpoint or tiny triangle, barely visible
- **Edge opacity** at 0.3-0.5 by default, full opacity on hover or when active
- **Leader lines** (thin, dashed) connect nodes to floating annotations
- **Slight stroke variation** via SVG `feTurbulence` filter — subtle warmth, not gimmicky sketch effect

### What this is NOT

- Not pixel-perfect corporate dashboard aesthetic
- Not dark-theme neon-glow monitoring tool
- Not hand-drawn/sketch aesthetic taken to comic-book extreme
- The warmth is subtle. The imperfection is a whisper.

---

## Layout system

### Three layout modes

The layout engine should support multiple strategies. Packs or users select the appropriate one.

#### 1. Layered (default) — modified Sugiyama

For general DAGs. Standard for most Packs.

- **Layer assignment**: topological depth (inputs left/top, outputs right/bottom)
- **Crossing minimization**: median heuristic (sufficient for DAGs under 100 nodes)
- **Time-proportional spacing** (optional): horizontal distance between layers proportional to wall-clock execution time. Even spacing as fallback when no timing data exists. Wide gaps = bottlenecks, visible at a glance.
- **Implementation**: ELK (elkjs) or dagre for layout computation. Cache layouts in IndexedDB (per Dagster's approach — first layout of 2000 nodes: minutes; cached: instant).

#### 2. Metro (OCTI) — for stable pipelines

For pipeline-shaped Packs (Radar, FlowTime) where the topology is fixed and users see it repeatedly.

- **Lines**: each execution path through the DAG is a colored line. Color = Pack-defined semantic grouping or auto-assigned.
- **Stations**: ops are evenly-spaced stations on the line. Station dot size can encode duration or importance.
- **Interchanges**: fan-out/fan-in points where lines cross are interchange nodes.
- **Routing**: octilinear (0°/45°/90° edges only) via OCTI algorithm.
- **When to use**: Pack provides a layout hint, or user selects. Best for pipelines with < 30 nodes that are run repeatedly.

#### 3. Particle field — for large DAGs

For 500+ node DAGs (Software Factory, Agent Fleets, Process Mining).

- At far zoom: nodes are tiny dots in a force-directed cloud. Clusters visible as density. Color shows status distribution at a glance.
- The layout provides overview and orientation, not readability of individual nodes.
- Drill-in via semantic zoom (see below) or progressive expansion (see below).
- **Implementation**: Sigma.js or Cytoscape.js WebGL renderer for GPU-accelerated dot rendering.

### Layout selection

Packs can declare a preferred layout in their module:

```elixir
def layout_hint, do: :layered  # or :metro, or :auto
```

`:auto` selects based on DAG shape — linear/pipeline → metro, general → layered, large → particle field. User can always override.

---

## Scale strategy

### Semantic zoom (three detail levels)

As the user zooms in/out, the visualization transitions between detail levels:

| Zoom level | Nodes | Edges | Labels | Artifact previews |
|------------|-------|-------|--------|-------------------|
| **Far** (overview) | Dots (4-6px) | Thin lines, bundled | None | None |
| **Medium** (navigate) | Dots (8-12px) with state color | Individual lines | Op name on hover | None |
| **Close** (inspect) | Cards with inline preview | Full detail, animated flow | Always visible, floating | Visible — first line of text, JSON snippet, image thumb |

Transitions between levels are animated (fade labels in/out, expand dots to cards). The key property from the research: **semantic consistency** — anything visible at a zoom level stays visible at all closer levels.

### Progressive expansion (for very large DAGs)

Borrowed from Chainalysis Reactor's graph notebook pattern:

- Start with the DAG's entry point (or the node the user navigated to)
- Show its immediate neighbors
- Click a neighbor to expand its connections
- The visible subgraph grows interactively
- A minimap shows position within the full DAG

This is complementary to semantic zoom — zoom controls detail level, expansion controls scope.

### Happy-path slider (for complex DAGs)

Borrowed from Celonis/Disco process mining:

- A slider controls what percentage of paths are visible
- At 100%: full DAG, all paths
- At 20%: only the critical path (longest execution path, or most frequently traversed in repeated runs)
- Paths fade in/out smoothly as the slider moves
- For Liminara: filter by execution time contribution ("show me the nodes responsible for 80% of wall-clock time")

### Clustering / collapse

Natural grouping units for Liminara DAGs:

- **Pack phases**: if a Pack's plan has logical phases, cluster by phase
- **Topological depth bands**: group nodes at similar depth
- **Subgraph patterns**: fan-out groups (one input, many outputs) collapse into a single node showing "N parallel ops"
- Collapsed clusters show: node count, status distribution (pie-dot or stacked bar), aggregate timing

---

## Dynamic DAGs (discovery mode)

When the DAG grows during execution (Software Factory, dynamic plan expansion):

### Layout approach: incremental Sugiyama

Based on DynaDAG (North, 1995):

1. New node appears → compute its layer from dependencies
2. Insert into layer, minimize crossings against existing nodes only
3. Existing nodes shift minimally to accommodate (animated over ~400ms)
4. New node fades in at computed position over ~300ms
5. New edges draw progressively (SVG `stroke-dashoffset` animation)

Alternative: Cola.js/WebCola with DAG direction constraints. Constraint-based force simulation gives naturally smooth incremental updates while enforcing layered structure. Better for exploratory/organic feel; worse for deterministic reproducibility.

### Mental map preservation

Research confirms (Archambault & Purchase, 2011; Springer 2013): for incremental changes (nodes added one at a time), preserving existing positions helps users track what's happening. Rules:

- Never move a completed node unless absolutely necessary
- New nodes appear in the "frontier" (rightmost/bottommost layer)
- If inserting a node mid-graph requires shifting, animate the shift, don't snap
- Batch shifts: never move more than ~30% of visible nodes simultaneously

### Visual treatment of growth

- Pending/future nodes: not shown (the DAG only shows what exists)
- Newly discovered nodes: fade in from `--ink-ghost` to full color over ~500ms
- The frontier (currently executing layer) has full opacity; earlier layers gradually desaturate
- The effect: the DAG grows rightward like a document being written

---

## Animation model

### Artifact flow

The signature animation: when an op completes and its output becomes available to downstream ops, a **colored dot (artifact particle) travels along the connecting edge** from source to destination.

- Particle is a small filled circle (4-6px) in the source node's color
- Travels along the edge bezier at a speed proportional to... constant speed (not data-dependent — this is aesthetic, not informational)
- When it arrives at the destination node, it's absorbed (fades into the node)
- If multiple artifacts flow simultaneously, multiple particles travel in parallel
- This makes the data flow visible and the DAG feel alive

### State transitions

- **Pending → Running**: node border animates from ghost to full color; subtle pulse
- **Running**: gentle breathing animation (opacity oscillation, 2s period) — not a spinner
- **Running → Completed**: node fills with artifact preview (text fades in); particle(s) depart along outgoing edges
- **Running → Failed**: node flashes `--red` once, then settles to red fill with error preview
- **Gate (waiting)**: node pulses slowly in `--red`/`--amber`; shows prompt as annotation
- **Gate resolved**: same as completed transition

### Temporal unfolding

On first viewing a run (live or replay):

- The DAG starts as a skeleton — just the structure (dots and thin lines) in `--ink-ghost`
- As execution proceeds, nodes activate left-to-right (or top-to-bottom)
- Completed regions solidify (full color, value previews appear)
- The running frontier is the visual focus (full opacity, animation)
- Completed regions behind the frontier gently desaturate (not fully — they're still readable, just not focal)

On viewing a completed run: the full DAG is shown immediately in its final state. Temporal unfolding is available as a "replay" mode.

---

## Node rendering (the inline preview)

At close zoom, each node expands from a dot to a **card** showing its artifact content. This is the "show the grid not the logic" principle from `04_OBSERVATION_DESIGN_NOTES.md`.

### Card anatomy

```
┌─ op name (small, --ink-light) ──────────────────┐
│                                                   │
│  Artifact preview (dominant, --ink)               │
│  "The Swedish housing market showed signs of..."  │
│                                                   │
│  ▬▬▬▬▬▬▬▬▬▬░░░░  320ms                          │
└───────────────────────────────────────────────────┘
```

- **Op name**: top, small, secondary color. Not the focus.
- **Artifact preview**: center, dominant. Content depends on artifact type:
  - Text/string: first N characters (configurable, default ~80)
  - JSON: formatted key-value pairs (first 3-4 keys)
  - Binary: type icon + size ("PDF 2.4 MB") + thumbnail if image
  - Multiple outputs: stacked previews or tabbed
- **Timing bar**: bottom edge, proportional to duration, colored by state
- **Border**: left edge colored by determinism class (teal/coral/amber)
- **Decision indicator**: if the op recorded a decision, a small coral dot in the top-right corner

### Card sizing

Cards are variable-width based on content, with a max-width constraint. The layout engine accounts for card dimensions at close zoom (nodes occupy more space, layout spreads).

---

## Technology stack

### Layout computation

| Scale | Library | Notes |
|-------|---------|-------|
| Small/medium (< 500 nodes) | **elkjs** or **dagre** | Sugiyama-based. Layout in Web Worker to avoid blocking UI. Cache in IndexedDB. |
| Large (500+ nodes) | **Cola.js** + constraints | Force-based with DAG direction constraints. Incremental. |
| Metro mode | Custom OCTI or constrained elkjs | Octilinear routing. Simpler than general case for pipeline shapes. |

### Rendering

| Scale | Technology | Notes |
|-------|------------|-------|
| Small/medium | **SVG via LiveView** | LiveView diffs SVG elements efficiently. Rich interactivity (click, hover) via standard DOM events. |
| Large | **Canvas/WebGL** (Cytoscape.js WebGL or Sigma.js) | GPU-accelerated. Necessary above ~2K visible nodes. Loses easy LiveView integration — communicate via hooks. |

### Animation

- SVG transitions via CSS (`transition` on `cx`, `cy`, `fill`, `opacity`)
- Particle flow via `requestAnimationFrame` on a thin Canvas overlay atop the SVG (particles don't need DOM interaction)
- LiveView pushes state changes; client-side JS handles animation interpolation

### Libraries to evaluate

| Library | Role | Why |
|---------|------|-----|
| **elkjs** | Layout engine | Best-in-class Sugiyama with hierarchical support, 140+ config options |
| **d3-dag** | Layout alternative | Lighter, DAG-specific, Zherebko layout for narrow DAGs |
| **Cola.js/WebCola** | Incremental layout | Constraint-based force with DAG direction support |
| **Cytoscape.js** | Large graph rendering | WebGL renderer (v3.31+), good animation API |
| **d3-shape** | Edge curves | Bezier curve generation for edges |
| **d3-zoom** | Pan/zoom | Standard, integrates with SVG and Canvas |

---

## Pack-specific considerations

### Report Compiler (toy, 5-10 nodes)
Full detail always. Every node is a card with preview. Metro layout would look good here as a demo. This is the "screenshot for the README" pack.

### Radar (10-30 nodes, pipeline)
Metro layout as default — Collection Line (teal) and Analysis Line (coral) with interchange at the vector index. Time-proportional spacing shows where LLM calls dominate. The daily briefing result should be readable directly in the terminal node's card.

### House Compiler (30-100 nodes, fan-out heavy)
Layered layout. The fan-out from "manufacture plan" to parallel drawing/NC/BOM generation is the visual signature — a tree spreading rightward. Binary artifact nodes (PDF, NC files) show type+size thumbnails. Semantic zoom useful here: far view shows the tree shape, close view shows individual outputs.

### Software Factory (100-1000+ nodes, discovery mode)
The hard case. Starts small, grows during execution. Incremental layout (DynaDAG or Cola.js). Progressive expansion for navigating the full graph. Happy-path slider for filtering. Temporal unfolding is essential — you watch the DAG grow as the agent works. Particle field overview at far zoom.

### FlowTime Consulting (50-200 nodes, long-running)
Metro layout for the known workflow. Gates are prominent — they're the dominant interaction. The temporal axis spans days/weeks, not seconds. Gate nodes should be visually prominent: larger dots, amber/red, with prompt text always visible as annotation. The "time-proportional spacing" mode here would show long waiting periods as wide gaps.

### Agent Fleets / Population Sim (1000+ nodes)
Particle field only at overview. Clustering by agent or generation. The visualization becomes statistical — showing distributions of states rather than individual node contents. Semantic zoom to inspect individual agents.

---

## Research references

### Layout algorithms
- Sugiyama, Tagawa, Toda (1981) — the original layered graph drawing algorithm
- North (1995) — DynaDAG: incremental layout for hierarchical graphs
- Nöllenburg & Wolff (2011) — OCTI metro map layout via mixed-integer programming

### Scale and performance
- Dagster engineering blog — scaling DAG visualization to 10K+ assets (viewport virtualization, layout caching in IndexedDB, edge culling)
- Cytoscape.js v3.31 — WebGL renderer benchmarks (1200 nodes: 20 FPS canvas → 100+ FPS WebGL)

### Dynamic graphs
- Beck et al. (2016) — taxonomy and survey of dynamic graph visualization
- Archambault & Purchase (2011) — mental map preservation in dynamic graphs
- Cola.js — constraint-based layout with incremental force simulation

### Aesthetics
- Giorgia Lupi — Data Humanism manifesto; Dear Data (with Stefanie Posavec)
- Helen Purchase — empirical research on graph drawing aesthetics (crossing minimization + continuity as most important factors)
- Danny Holten (2006) — hierarchical edge bundling
- Celonis / Disco — happy-path slider, animated case replay
- TouchDesigner — live node previews as primary content
- RxMarbles — temporal flow with colored dots through operators

### Domain precedents
- Chainalysis Reactor — progressive graph expansion for blockchain investigation
- SAP IBP / Kinaxis — supply chain network visualization with KPI-embedded nodes
- Celonis / Disco / ProM — process mining visualization, spaghetti problem solutions
- Metro map metaphor — Beck (1931), applied outside transit for project plans, tech landscapes, patient pathways
