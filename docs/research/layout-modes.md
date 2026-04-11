# Layout Modes — Research & Experimentation Plan

## Context

dag-map currently supports one layout paradigm: left-to-right DAG flow (layoutMetro).
But different use cases need fundamentally different spatial encodings. The Stockholm
metro analysis revealed that a single LTR flow can't represent networks where lines
radiate in all directions from a center.

This document identifies distinct layout modes, each serving different contexts, and
proposes an experimentation plan to explore them.

## The Core Tension

Every DAG layout must assign two coordinates per node. The question is: what does
each axis MEAN?

| Axis | Possible meanings |
|------|------------------|
| **X** | Topological depth, timestamp, geographic longitude, distance from center |
| **Y** | Crossing-optimized, determinism class, geographic latitude, line identity |

Different contexts demand different assignments. A "mode" is a specific assignment
of meaning to axes, plus the routing/rendering strategy that fits it.

## Five Layout Modes

### Mode 1: Linear Flow (current layoutMetro)

```
X = topological depth (or time)
Y = crossing-optimized ordering
Flow: left to right
```

**Best for:** Execution DAGs, pipelines, CI/CD, Liminara observation layer.
**Character:** Metro map aesthetic. Trunk = main execution path. Branches fan out
above/below. Parallel tracks at interchanges.
**Status:** Implemented. COMPACT+ORDERED is our best variant.

### Mode 2: Per-Line Strips (dag-map's layoutFlow)

```
Each line/route gets its own horizontal strip
X = time/distance along the line
Y = line identity (one row per line)
Interchanges shown as vertical connections between strips
```

**Best for:** Process mining, multi-object workflows, comparing parallel processes.
**Character:** Swimlane diagram. Each lane is one entity type's journey. Cards at
stations show data. Edges between lanes show handoffs.
**Status:** Already exists as layoutFlow in dag-map. Not part of the bench
evolution work yet.

**Key insight:** This is where time-as-distance is EXPLICIT. Each strip can have
different lengths — a slow process gets a wider strip. The visual length of an edge
directly represents duration. dag-map's layoutFlow already does this with
`metadata.time` on edges. We should not forget this mode — it's the most natural
for Liminara's Radar pack where each op has a known execution time.

### Mode 3: Radial / Star (new)

```
Center = hub station (or start of computation)
Distance from center = time elapsed (or topological depth)
Angle = line identity (each line radiates outward)
```

**Best for:** Networks with a central hub (Stockholm's T-Centralen, a main()
function, a root task). Shows "how far from the center" each station is.
**Character:** Sunburst or spider diagram. Lines radiate like clock hands.
Interchanges are arcs connecting lines at the same distance from center.

**Time as distance:** This is the user's insight. If Stockholm Central is at the
center, distance outward = travel time from center. Farsta Strand (25 min south)
is further out than Gamla Stan (3 min). The visual distance IS time.

**Status:** Not implemented. Would need a radial coordinate system + circular
edge routing.

### Mode 4: Consumer-Provided XY (new)

```
X = consumer-provided (geographic longitude, schematized, or time)
Y = consumer-provided (geographic latitude, category, or custom)
Algorithm controls only: edge routing, track assignment, crossing minimization
```

**Best for:** Geographic networks (metro maps), custom visualizations where the
consumer knows where nodes should be and just needs clean edge routing.
**Character:** Depends entirely on the consumer's coordinate assignment.
The algorithm becomes a pure MLCM routing engine.

**Status:** Partially implemented. `positionX: 'custom'` exists. Need to add
`positionY: 'custom'` for full consumer control. The MLCM track assignment
algorithm (R1-R10) would operate on top of fixed positions.

### Mode 5: Time-Expanded Round-Trip (new, conceptual)

```
X = time (chronological)
Y = physical entity (station, resource, actor)
Same physical entity appears at multiple X positions
```

**Best for:** Schedules, repeated processes, daily operations (Radar pack runs
the same pipeline every day — each day is a new X column).

**Modeling:** A→B→A becomes A₁→B₂→A₃ where subscripts are time indices.
Metro round-trip: depart Stockholm Central 08:00, arrive Farsta 08:25,
return Stockholm Central 08:50. Three DAG nodes at X=0, X=25, X=50.

**Status:** Conceptual. Fits naturally into Mode 1 (linear flow) if the consumer
provides time-expanded input. No new layout algorithm needed — just a different
way of constructing the input DAG.

## The Round-Trip Insight

Bidirectional networks (metro, roads) CAN be modeled as DAGs by unrolling time:

```
Physical:  A ←→ B ←→ C
Time-expanded DAG:  A₁ → B₂ → C₃ → B₄ → A₅
```

This transforms ANY undirected graph into a DAG. The X axis becomes time,
Y becomes physical location. This is well-studied in transportation research
as "time-expanded graphs" and in computer science as "event-activity networks."

For dag-map, this means we don't need special bidirectional support — the consumer
unrolls time in the input, and Mode 1 (linear flow) handles the rest.

## Relationship Between Modes

```
                    Consumer provides:
                    X only    X and Y    Neither
                    ──────    ───────    ───────
DAG structure?  Yes  Mode 1    Mode 4     Mode 1
                No   Mode 3    Mode 4     Mode 3
                
Per-line strips?     Mode 2    Mode 2     Mode 2
```

Mode 2 (per-line strips / layoutFlow) is orthogonal — it's a different visual
paradigm, not just a different coordinate assignment.

## Connection to Existing dag-map Engines

dag-map already has THREE layout engines:

| Engine | Mode | Status |
|--------|------|--------|
| `layoutMetro` | Mode 1 (linear flow) | Active development (this research) |
| `layoutFlow` | Mode 2 (per-line strips) | Exists, not part of bench work |
| `layoutHasse` | Sugiyama lattice | Exists, used for partial orders |

The MLCM track assignment algorithm (R1-R10) should be designed to work
across modes — at minimum Mode 1 and Mode 4. The track assignment problem
(which line goes on which track at an interchange) is the same regardless
of how node positions are determined.

## Experimentation Plan

### Phase A: Validate Mode 1 (current focus)
- CP-2: Implement MLCM track assignment rules R1-R5
- CP-3: Rules R6-R10 + ablation testing
- CP-4: Full experiment comparison + Tinder validation
- CP-5: Document final algorithm

### Phase B: Explore Mode 4 (consumer-provided XY)
- Add `positionY: 'custom'` to the pipeline
- Test with Stockholm metro using geographic coordinates as input
- MLCM track assignment on fixed positions
- Compare against Nöllenburg's published results

### Phase C: Explore Mode 3 (radial)
- Radial coordinate system for hub-centric networks
- Time-as-distance from center
- Circular edge routing
- Test with Stockholm (T-Centralen as hub)

### Phase D: Revisit Mode 2 (layoutFlow)
- Connect layoutFlow to the bench evolution infrastructure
- Apply MLCM metrics to flow layouts
- Time-as-distance is already built into layoutFlow via edge metadata

### Phase E: Mode 5 (time-expanded round-trip)
- Build a converter: undirected network + schedule → time-expanded DAG
- Render with Mode 1
- Test with a simple metro timetable

## Key Design Principle

The modes share infrastructure:
- **MLCM track assignment** works across all modes (the crossing minimization
  problem is the same regardless of how positions are determined)
- **Rendering** (pills, parallel tracks, bezier curves) is mode-independent
- **Metrics** (crossings, overlaps, bends, coherence) are mode-independent

The modes differ in:
- **Coordinate assignment** (how X and Y are determined)
- **Edge routing geometry** (straight, octilinear, circular)
- **Visual convention** (LTR flow vs radial vs swimlane)
