# DAG Layout Evolution — Research Log

## Project Context

dag-map is a DAG visualization library used by Liminara's observation layer. It renders directed acyclic graphs as metro-style maps with routes (colored lines), stations (circles), and bezier curves. The original algorithm (`layoutMetro`) was developed through 32 manual iterations (v1-v32) and produced structurally correct but aesthetically rigid layouts.

This research explores evolutionary and algorithmic approaches to substantially improve dag-map's layout quality, aiming to match or exceed dagre (the de facto standard) while maintaining dag-map's distinctive metro-map aesthetic.

## Timeline

### Phase 1: GA Harness (E-DAGBENCH, 2026-04-09)

**Goal:** Build infrastructure to evolve layout parameters.

**What we built:**
- Energy functional with 8 physics-inspired terms: stretch, bend, crossings, monotone, envelope, channel, repel_nn, repel_ne
- Island-model GA with 3 populations, tournament selection, regression guard
- Tinder-style voting UI with Bradley-Terry weight refit
- External benchmark corpora (North DAGs + Random DAGs from graphdrawing.org, 2,186 graphs)
- dagre and ELK adapters for comparison

**What we learned:**
- The original genome only had 4 render parameters (layerSpacing, mainSpacing, subSpacing, scale) + 4 energy-tuning parameters
- These just "zoom" the layout — they don't change which node is above which or where crossings happen
- The GA optimized for absolute energy, not competitiveness — it could "cheat" by inflating layouts to reduce repulsion

### Phase 2: Evolvable Pipeline (E-EVOLVE, 2026-04-09 to 2026-04-10)

**Goal:** Refactor layoutMetro into swappable strategy slots so the GA can evolve the algorithm itself.

**Pipeline decomposition:**
```
DAG → [Layer Assignment] → [Node Ordering] → [Crossing Reduction] → [Y Assignment] → [X Positioning] → [Coord Refinement] → [Route Extraction] → [Path Building] → Layout
```

**Strategies implemented:**

| Slot | Strategies | Source |
|------|-----------|--------|
| Node ordering | none, barycenter, median, spectral, hybrid, shuffle | barycenter/median ported from layoutHasse |
| Crossing reduction | none, barycenter-sweep, greedy-switching | ported from layoutHasse |
| Lane assignment | default (BFS), ordered, direct, composed | direct = ordering IS the layout |
| X positioning | fixed (grid), compact (no grid), custom, proportional | compact uses neighbor barycenter pull |
| Coord refinement | none, barycenter (route-level) | |

**Key insight — the wiring problem:**
The first implementations of crossing reduction and node ordering computed orderings but the lane assignment IGNORED them. Nodes looked identical across strategies because the ordering result was thrown away. Fixed by creating `assign-lanes-direct` where the ordering directly determines Y positions.

**Key insight — spectral ≈ barycenter:**
Spectral ordering (Fiedler vector of the graph Laplacian) and barycenter sorting produce nearly identical orderings on most graphs because they optimize the same objective: placing connected nodes close together. They're not different enough to be separate island strategies.

### Phase 3: Matrix Infrastructure (E-MATRIX, 2026-04-10)

**Goal:** Replace ad-hoc graph traversals with matrix-based algorithms.

**What we built:**
- Sparse adjacency matrix and graph Laplacian (combinatorial + normalized)
- O(|E| log |V|) crossing count via merge sort (replacing O(|E|²))
- Fiedler vector computation via power iteration
- Hybrid spectral+barycenter ordering with evolvable blend parameter

**What we learned:**
- The efficient crossing count is a real improvement for 30+ node graphs
- Spectral ordering is mathematically interesting but doesn't produce visibly different layouts from barycenter
- The hybrid blend parameter always converges to near-barycenter values

### Phase 4: Fair Comparison + Stretch Fix (2026-04-10)

**Problem:** dag-map was losing to dagre on 80% of benchmarks.

**Root cause analysis:**
Per-term breakdown showed stretch dominated 99% of the total energy gap. dag-map's edges were in the millions of units (squared excess) while dagre's were modest.

**Fix 1 — Fair adapters:**
dagre and ELK adapters were producing straight-line "routes" between node centers. This trivially dodged bend/monotone/channel penalties. Fixed to extract actual edge bend points from dagre/ELK's routing data.

**Fix 2 — Normalized stretch:**
Changed stretch from `(actual - ideal)²` to `((actual - ideal) / ideal)²`. Scale-invariant: a 10% excess penalizes the same regardless of absolute edge length.

**Result:** dag-map went from 17% to 97% win rate vs dagre on 2,220 benchmarks. But this was a measurement fix, not a layout fix.

### Phase 5: Visual Evaluation + Tinder (2026-04-10 to 2026-04-11)

**Problem:** Benchmark numbers improved but layouts didn't look better to human eyes.

**Tinder iterations:**
1. First attempt: pairs were indistinguishable (elite converged)
2. Added cross-island pair selection: still identical (strategies produced same orderings)
3. Pinned islands to different ordering strategies: still similar (ordering didn't affect Y)
4. Fixed wiring: `assign-lanes-direct` makes ordering drive Y positions
5. Force/stress Y positioning: produced different absolute Y values but same relative orderings
6. Global route offsets for parallel tracks: breakthrough visual improvement

**Key discoveries from visual evaluation:**
- The original BFS-lane metro style was aesthetically superior to "pure topology" approaches
- Routes decoupled from positioning causes zig-zag on the trunk (trunk nodes at different Y per layer)
- Scale and spacing parameters are noise — they don't change layout topology
- Energy-tuning parameters let the GA "cheat" by adjusting the scorer instead of improving the layout
- Edge overlap is the #1 unsolved visual problem (257 avg overlaps, no strategy fixes it)
- Direction changes (zig-zag) are the #2 problem

### Phase 6: Genome Cleanup + New Energy Terms (2026-04-11)

**Removed from genome (consumer constraints, not evolvable):**
- `render.scale`, `render.layerSpacing` — just zoom
- `energy.*` params — tune the scorer, not the layout

**Added energy terms:**
- `E_overlap` — penalizes edges with identical Y at both endpoints
- `E_direction_changes` — penalizes Y-direction reversals along routes

**Removed from layout:**
- `cls`-based lane assignment heuristic — layout is purely topological, styling is a rendering overlay
- `positionX` from genome — X positioning is a consumer constraint

### Phase 7: Rendering Breakthrough (2026-04-11)

**Problem:** Multiple routes through the same node were visually illegible.

**Solution — elongated stations + parallel tracks:**
1. Multi-route stations rendered as vertical pills (not circles), sized for all tracks
2. Track marks inside stations showing each platform level
3. Global Y offset per route (consistent across ALL stations)
4. Routes run perfectly parallel through shared stations — no per-node offset shifts
5. Trunk always at center (offset 0)

**Result:** COMPACT+ORDERED and COMPACT+REFINED identified as the best configurations. Tagged as `experiment-v6-parallel-tracks`.

## Key Architecture Decisions

### D1: Routes are rendering, not layout
Routes (greedy longest-path grouping) are extracted AFTER node positioning. Node positions are computed purely from topology. Routes are used only for visual grouping (colored lines through stations).

**Why:** Decoupling routes from positioning allows crossing reduction and node ordering to operate on the raw DAG topology without being constrained by route grouping.

**Tradeoff:** Lost the original BFS-lane aesthetic where all nodes on the same route shared Y. Fixed by trunk pinning and global route offsets.

### D2: X positioning is a consumer constraint
Whether X is fixed (grid), compact (neighbor-barycenter), custom (timestamps), or proportional (variable layer widths) is chosen by the consumer, not evolved by the GA.

**Why:** X mode depends on the application context (process timeline vs dependency graph vs workflow), not on what looks "best" in general.

### D3: Trunk nodes pinned at TRUNK_Y
The longest path (trunk) nodes are always positioned at TRUNK_Y in every layer. Other nodes are spaced around them.

**Why:** Without pinning, crossing-reduction orderings place trunk nodes at different Y positions per layer, creating zig-zag. The trunk should be the visual spine of the graph.

### D4: Global route offsets (not per-node)
Each route gets a fixed Y offset for its entire length. Route 0 = 0, route 1 = +gap, route 2 = -gap.

**Why:** Per-node offsets caused routes to shift Y between stations (different route counts at each node), creating unnecessary bends. Global offsets keep routes parallel.

## Benchmark Results

### Energy functional (2,220 fixtures, normalized stretch)

| Configuration | vs dagre | vs ELK |
|--------------|---------|--------|
| Original dag-map defaults | 0W / 34L | 0W / 34L |
| Evolved params only (seed 42, 50g) | 442W / 1,777L | 1,525W / 694L |
| Evolved strategies (seed 99, 200g) | 294W / 1,925L | 1,464W / 755L |
| Normalized stretch (seed 300) | 2,121W / 98L | 2,212W / 7L |
| Full strategies (seed 5000) | 2,093W / 126L | 2,206W / 13L |

### Visual quality metrics (23 fixtures, latest experiment)

| Version | Crossings | Overlaps | Dir Changes | Trunk Var |
|---------|-----------|----------|-------------|-----------|
| Original | 2.8 | 348 | 2.6 | 36 |
| Compact+Ordered | 0.4 | 349 | 2.7 | 36 |
| Compact+Spectral | 0.4 | 349 | 2.7 | 36 |
| Grid+Ordered | 0.4 | 349 | 2.7 | 36 |

Crossing reduction works (2.8 → 0.4). Overlaps remain unsolved (348 avg). Direction changes and trunk variance are stable.

## What the GA Actually Produces

The GA's output is a **configuration** — a fixed set of strategy choices + parameter values. At runtime there's no GA iteration. You apply the configuration in one deterministic pass:

```
genome = { orderNodes: 'barycenter', crossingPasses: 20, mainSpacing: 45, ... }
         ↓
layoutMetro(dag, genome)  ← one deterministic pass, same input = same output
         ↓
layout
```

The GA iterated during evolution (hundreds of generations). The result is a recipe. Some internal strategies iterate (barycenter does N passes), but that count is fixed in the genome.

## Open Questions

1. **Visual crossing detection** — we count crossings on abstract layer-to-layer edges, not rendered bezier curves. Two edges might not "cross" in the abstract model but overlap visually.

2. **Symmetry** — no metric exists. Symmetric subgraphs should look symmetric.

3. **Cluster coherence** — no metric. Heavily connected subgroups should be visually close.

4. **Angular resolution** — edges from the same node should fan out, not bunch together.

5. **Time-proportional X** — the compact X positioning is the foundation. Liminara's observation layer could map X to op execution timestamps.

6. **Matrix-based improvements** — the matrix infrastructure is built but spectral methods haven't proven visually superior to barycenter. Network simplex coordinate assignment (like dagre's) is unimplemented.

## Experiment Infrastructure

- `bench/experiments/versions.mjs` — named layout configurations
- `bench/experiments/fixtures.mjs` — standard fixture set (23 graphs, 8-40 nodes)
- `bench/experiments/compare.mjs` — runs all versions × fixtures, produces HTML + metrics
- `bench/experiments/results/<timestamp>/` — timestamped comparison outputs
- Git tags: `experiment-v6-parallel-tracks` marks the parallel tracks breakthrough

## Phase 8: Reframing — Metro-Line Crossing Minimization (2026-04-11)

Independent research revealed that we've been solving the wrong problem. dag-map's layout is NOT a general DAG drawing problem — it's a **metro-line crossing minimization** (MLCM) problem combined with **edge-path bundling**. This is a well-studied subfield with dramatically better algorithms available.

### The reframe

What we've been doing (Sugiyama thinking):
```
Pick layers → order nodes within layers → assign coordinates → extract routes → draw
```

What we should be doing (MLCM thinking):
```
X is fixed (topology or time) → assign Y-offsets per node-bucket →
  route lines through stations with minimal crossings →
  bundle same-class edges as shared tracks → draw with clean geometry
```

The key insight: **we don't need a layout algorithm that picks node positions.** Our nodes already have a natural X (topological depth or timestamp). What we need is:

1. **Track ordering at stations** — given multiple lines passing through a station, which line goes on which track?
2. **Bundle coherence** — same-class edges should travel together between stations
3. **Crossing minimization at stations** — crossings at interchange stations are the worst kind
4. **Monotonicity per line** — lines should not backtrack; monotonic flow is critical

### Key literature identified

| Paper/System | Authors | Relevance |
|-------------|---------|-----------|
| **Metro-Line Crossing Minimization (MLCM)** | Asquith, Gansner, Nöllenburg | EXACTLY our problem: given fixed node positions and line assignments, minimize line crossings at stations |
| **Edge-Path Bundling** | Wallinger, Archambault, Auber, Nöllenburg, Peltonen (IEEE TVCG 2022) | Bundles edges along shared graph paths; preserves individual edge traceability |
| **Drawing Metro Maps Using Bézier Curves** | Nöllenburg, Wolff (2011) | Octilinear metro layout with clean curve geometry |
| **Bundling-Aware Drawing** | GD 2024 (Archambault, Liotta, Nöllenburg, Piselli, Tappini, Wallinger) | Joint optimization of layout + bundling (not sequential pipeline) |
| **Confluent Drawings** | Eppstein, Goodrich, Meng | Train-track structures where edges share physical track — literally what our trunk-with-branches IS |
| **IPSep-CoLA** | Dwyer, Marriott, Wybrow (2006) | Constraint-based layout via stress majorization with separation constraints |
| **WebCola** | Dwyer et al. | JavaScript implementation of CoLA; useful for Y-subproblem with pinned X |

### Key researchers

- **Martin Nöllenburg** (TU Wien) — central figure in metro-map layout, MLCM, edge-path bundling
- **Tim Dwyer** (Monash University) — constraint-based layout, CoLA, WebCola
- **Kim Marriott** (Monash) — frequent co-author with Dwyer, constraint-based visualization
- **Michael Wybrow** (Monash) — topology-preserving constrained layout

### What this means for dag-map

1. **Stop fighting Sugiyama from the inside.** We've been adding strategies to a pipeline that fundamentally commits to the wrong abstraction (layers → node ordering → coordinates). The problem is track ordering, not node ordering.

2. **X is fixed — not evolvable, not variable.** X comes from topology (layer) or from the consumer (timestamps). This is a hard constraint, not something to optimize. Our compact-X experiments were interesting but secondary.

3. **The Y problem decomposes per X-bucket.** At each X position (layer), we have a small set of nodes. Between X positions, we have edges/lines. The Y assignment is a sequence of small constraint problems, not one big global optimization.

4. **Lines/routes are INPUT, not discovered.** For Liminara, routes correspond to execution paths (determinism classes). They're known before layout. The MLCM formulation assumes lines are given — this fits perfectly.

5. **The GA's role shifts.** Instead of evolving which Sugiyama heuristic to use, the GA should evolve parameters of the MLCM solver: crossing penalty weights, bundle coherence strength, monotonicity enforcement. Or: the GA explores different track orderings at stations and the fitness function evaluates crossing count + bundle coherence + monotonicity.

6. **Confluent drawings are the theoretical foundation for trunks.** Our trunk-with-branches-peeling-off is literally a confluent drawing primitive. The "trunk = shared track, branch = diverging at junction" concept has a formal basis.

### The question that determines the algorithm

Are routes (lines) a property of the input, or discovered from the graph?

- **Liminara models**: routes are INPUT (provided by the pack). Solve MLCM.
- **External benchmark DAGs**: routes are DISCOVERED (greedy longest-path). Solve edge-path bundling.
- **dag-map should support BOTH**: MLCM when routes are given, edge-path bundling when they're not.

### Revised objective function priorities

For the metro-map aesthetic, the research community has converged on:

1. **Crossings at stations** (worst — breaks line-following)
2. **Crossings between stations** (bad but tolerable)
3. **Total bends** (≤2 per edge is gold standard, Brandes-Köpf)
4. **Bundle coherence** (same-class edges staying together)
5. **Edge length uniformity** (variance of edge lengths)
6. **Angular resolution at junctions** (minimum angle between diverging branches)
7. **Monotonicity per line** (lines should not backtrack along the flow axis)

Note: node overlap is NOT in this list. In metro maps, stations can be close or touch — lines through them are the visual element, not the stations themselves.

## References

### Foundational
- Sugiyama, Tagawa, Toda (1981) — layered graph drawing framework
- Purchase (1997) — user studies: crossings dominate, then bends, then symmetry
- Koren (2005) — spectral graph drawing via eigenvectors

### Metro-map layout
- Nöllenburg, Wolff (2011) — "Drawing Metro Maps Using Bézier Curves"
- Asquith, Gansner, Nöllenburg — "Metro-Line Crossing Minimization Problem" (MLCM)
- Kornaropoulos, Tollis — MLCM with constraint relaxations
- GD 2024 — bundling-aware drawing (Archambault, Liotta, Nöllenburg et al.)

### Edge bundling
- Wallinger et al. (2022, IEEE TVCG) — "Edge-Path Bundling: A Less Ambiguous Edge Bundling Approach"
- Holten (2006) — hierarchical edge bundling
- Eppstein, Goodrich, Meng — confluent drawings

### Constraint-based layout
- Dwyer, Marriott, Wybrow (2006) — IPSep-CoLA
- WebCola — JavaScript implementation of CoLA

### Benchmarks and tools
- graphdrawing.org — North DAGs and Random DAGs benchmark corpora
- dagre (`@dagrejs/dagre`) — reference Sugiyama implementation
- ELK (`elkjs`) — Eclipse Layout Kernel
- Graph Drawing Symposium (GD) — annual, 32nd edition in 2024
- juliuste/transit-map — 6 metro networks in JSON (Berlin, Vienna, Stockholm, Lisbon, Nantes, Montpellier)
- GLaDOS/OSF — Rome-Lib, AT&T graph benchmarks

## Phase 9: MLCM Implementation + GA Validation (2026-04-11)

### MLCM track assignment (10 rules)

Implemented a track assignment algorithm based on MLCM literature:

| Rule | What | Validated by |
|------|------|-------------|
| R1 | Trunk at track 0 at every station | All fixtures |
| R2 | Branch proximity (most trunk overlap = closest track) | Ablation |
| R3 | No crossing at fork (greedy swap) | Ablation |
| R4 | Monotonic tracks (preserve order between stations) | Ablation |
| R5 | Symmetric branching above/below trunk | Ablation |
| R6 | Crossing minimization (local swap) | Ablation: 80% fewer crossings |
| R7 | Bundle coherence (same-class on adjacent tracks) | 100% on all fixtures |
| R8 | Terminal placement (starting/ending routes at outer tracks) | Visual |
| R9 | Bend smoothing (reduce unnecessary track changes) | Visual |
| R10 | No backtracking (hard constraint, DAG direction) | All fixtures |

### GA validation (seed 10000, 100 generations)

The GA confirmed our manual design and revealed surprising improvements:

| Parameter | GA chose | Our default | Insight |
|-----------|----------|-------------|---------|
| orderNodes | `hybrid` | `barycenter` | Spectral+barycenter blend wins |
| reduceCrossings | `none` | `barycenter` | Hybrid ordering makes crossing reduction redundant |
| assignLanes | `ordered` | `default` | Unanimous — validates MLCM approach |
| mainSpacing | ~26px | 40px | Trunk lanes should be tight |
| subSpacing | ~40px | 25px | Branches need room to spread |

**Key finding:** The GA's role is validation, not discovery. It confirmed which
of our manually-designed rules matter and which parameter values work best.
The output is an explainable algorithm, not opaque parameters.

### Ablation testing

Removing ordering + crossing reduction from the best configuration:
- Between-station crossings: 114 → 580 (5× worse)
- Total bends: 112 → 157 (40% worse)

Confirms each component contributes measurably.

## Phase 10: Visual Refinement (2026-04-11 to 2026-04-12)

### Rendering improvements
- **Elongated station pills**: multi-route stations rendered as vertical pills
  sized to span actual route offsets. Track marks inside show each platform.
- **Parallel tracks**: routes pass through stations at their track offset Y,
  running parallel between stations.
- **Global → local offsets**: route offsets computed locally per station (compact pills)
  instead of globally (oversized pills). Pill bounds from actual min/max offsets.
- **Direction-aware track assignment**: branches going above trunk get above tracks,
  branches going below get below tracks. Eliminates visual crossings at forks.
- **Adaptive layer spacing**: large layers (16+ nodes) get tighter spacing,
  capped at 300px total height.
- **Bezier variation**: hash-based perturbation prevents overlapping curves.
- **Extra edges eliminated**: auto-discovery and metro conversion both cover ALL
  DAG edges as route segments. Zero gray dashed "extra" lines.

### Structural test: pill containment
Added aesthetic test verifying all route offsets at interchange stations fall
within the pill bounds. Catches rendering/layout mismatches structurally.

### Comparison infrastructure
- Click-to-zoom modal on comparison page
- Hover tooltips showing station names
- Simplified to 5 versions (removed identical spectral/refined)
- MLCM metrics in summary table

### What we learned about straightening
Path straightening (pulling nodes toward neighbor barycenters) was attempted
and reverted — it collapsed nodes into horizontal bands, destroying vertical
separation and creating more crossings. The wiggly route problem needs
route-aware ordering, not post-processing.

### Metro network fixtures
6 real metro networks from juliuste/transit-map converted to DAG fixtures:
- Lisbon (50 stations, 4 lines), Nantes (81, 3), Montpellier (82, 4)
- Vienna (98, 5), Stockholm (99, 7), Berlin (169, 9)

Conversion uses longest-path-per-line for main routes + greedy coverage for
branches. Zero violations, zero extra edges on all networks.

### Trains vs tracks insight
Metro lines branch (e.g., Stockholm green line has 3 southern branches).
A single longest-path route can't represent a branching line — it picks one
branch and demotes the others. Fixed by extracting ALL edges per line as
routes, covering branches equally.

This connects to our layout modes research: branching networks are naturally
radial/star (Mode 3) or per-line strips (Mode 2), not linear flow (Mode 1).
Mode 1 handles them via multiple routes per line, but the visual result is
less natural than a purpose-built mode.

## Mode 1 Final State (checkpoint-mode1-complete)

### The algorithm (explainable, GA-validated)

```
1. Topological sort + layer assignment
2. Hybrid ordering (spectral + barycenter blend)
3. No crossing reduction (hybrid handles it)
4. Assign Y: trunk pinned at TRUNK_Y, others by ordering, adaptive spacing
5. Compact X positioning (neighbor barycenter pull, topological constraints)
6. MLCM track assignment at interchange stations (R1-R10)
7. Route extraction (greedy longest-path + full edge coverage)
8. Build paths: parallel tracks through pills, bezier with variation
```

### Metrics (27 fixtures)

| Category | Station crossings | Overlaps | Bends | Bundle coherence |
|----------|:-:|:-:|:-:|:-:|
| MLCM fixtures | 0 | 0 | 0-1 | 100% |
| Internal models | 0 | 0 | 0-1 | 100% |
| Metro networks | 0 | 0-1 | 1.6-4.8 | 100% |
| North DAGs | 0 | 0-1 | 0-1 | 100% |

### Tests
- 361 dag-map tests (including aesthetic property tests)
- 320 bench tests (1 skipped)
- Pill containment structural guard

### What's next (from layout-modes.md)

| Phase | Mode | Description |
|-------|------|-------------|
| B | Mode 4 | Consumer-provided XY + MLCM routing |
| C | Mode 3 | Radial/star with time-as-distance |
| D | Mode 2 | Revisit layoutFlow with MLCM metrics |
| E | Mode 5 | Time-expanded round-trip converter |
