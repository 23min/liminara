# MLCM-Based Layout Algorithm — Design Plan

## Checkpoint: pre-mlcm (2026-04-11)
**Tag:** `checkpoint-pre-mlcm`

### Where we are

We have a working Sugiyama-variant pipeline with:
- Pluggable strategies (ordering, crossing reduction, X positioning, Y assignment)
- Parallel tracks through elongated stations (v6 breakthrough)
- Trunk pinning, global route offsets, bezier variation
- Experiment framework for systematic comparison
- GA + Tinder infrastructure for validation

**Best result so far:** COMPACT+ORDERED and COMPACT+REFINED from `experiment-v6-parallel-tracks`

### What we're about to do

Redesign the core layout algorithm around **Metro-Line Crossing Minimization (MLCM)** instead of Sugiyama node ordering. This is a fundamental shift in approach.

## The MLCM Algorithm Design

### Problem statement

Given:
- A DAG with nodes and edges
- X-coordinates fixed (by topological rank or consumer timestamps)
- Lines/routes (either provided or auto-discovered)

Produce:
- Y-coordinate per node
- Track assignment per line at each station
- Edge routing between stations

Minimizing:
1. Line crossings at stations
2. Line crossings between stations
3. Bends per line
4. Bundle incoherence (same-class edges diverging unnecessarily)

Subject to:
- Monotonicity (lines don't backtrack along X axis)
- Minimum station separation
- Trunk stability (longest path stays straight)

### Algorithm phases (proposed)

```
Phase 1: TOPOLOGY
  - Topological sort, layer assignment
  - X assignment (fixed grid or consumer-provided)

Phase 2: LINE DISCOVERY (if routes not provided)
  - Trunk extraction (longest path)
  - Branch extraction (greedy coverage of remaining edges)
  - Line = sequence of consecutive edges sharing a path

Phase 3: TRACK ASSIGNMENT (the MLCM core)
  - For each station with multiple lines:
    - Assign each line a track (Y-offset)
    - Trunk always on track 0
    - Minimize crossings between adjacent stations
  - Global optimization: propagate track assignments to minimize total crossings

Phase 4: Y POSITIONING
  - Station Y = TRUNK_Y + track * spacing
  - Nodes without lines get Y from neighbor barycenter

Phase 5: RENDERING
  - Elongated station pills at multi-line stations
  - Parallel tracks through stations
  - Bezier curves between stations (with variation for disambiguation)
```

### Explicit rules (to be validated)

Each rule has a rationale and will be tested by ablation (remove it, measure damage).

```
R1: TRUNK FIRST
    The longest path gets track 0 at every station.
    Rationale: visual spine, anchor for the reader's eye.

R2: BRANCH PROXIMITY
    Branches that share more stations with the trunk get tracks closer to 0.
    Rationale: related lines should be visually close.

R3: NO CROSSING AT FORK
    At a fork (one line splits into two), the lines should not cross.
    Rationale: forks are where readers need clarity most.

R4: MONOTONIC TRACKS
    A line's track assignment should change as little as possible between
    stations. If it's on track +1 at station A, it should stay on track +1
    at station B unless forced to move.
    Rationale: track changes create visual noise.

R5: SYMMETRIC BRANCHING
    At a station where K lines diverge from the trunk, spread them
    symmetrically: K/2 above, K/2 below.
    Rationale: visual balance, matches metro map convention.

R6: CROSSING MINIMIZATION (local)
    Between adjacent stations, if swapping two lines' tracks reduces
    crossings without creating a new crossing at the next station, swap them.
    Rationale: greedy local improvement.

R7: BUNDLE COHERENCE
    Lines of the same class that travel together between stations should
    be on adjacent tracks.
    Rationale: visual grouping, edge-path bundling principle.

R8: TERMINAL PLACEMENT
    Lines that START at a station should enter from the edge (top or bottom
    track), not from the middle.
    Rationale: reduces visual congestion at the trunk.

R9: MINIMUM BEND
    When a line must change track, do it in one smooth curve, not a staircase.
    Rationale: Brandes-Köpf ≤2 bends per edge.

R10: NO BACKTRACKING
    A line must never move left (negative X direction).
    Hard constraint, not negotiable.
    Rationale: flow direction must be preserved.
```

### Fixtures plan

- **Standard MLCM benchmarks** from the literature (to be acquired — research in progress)
- **Real metro networks** (Vienna U-Bahn, London Tube subsets — for visual validation)
- **Liminara models** (internal, with provided routes)
- **North DAGs** (external, routes auto-discovered — regression testing)

### Validation method

1. **Implement each rule as a toggleable function**
2. **Experiment framework** compares: all rules ON vs each rule removed (ablation)
3. **Metrics**: station crossings, between-station crossings, bends, bundle coherence, monotonicity violations
4. **Tinder**: human aesthetic validation after algorithmic validation
5. **Benchmark comparison** against dagre and the v6-parallel-tracks baseline

### Milestones

```
CP-1: Acquire MLCM benchmark fixtures + implement metrics
CP-2: Implement Phase 3 (track assignment) with rules R1-R5
CP-3: Implement rules R6-R10 + ablation testing
CP-4: Full experiment comparison + Tinder validation
CP-5: Document final algorithm with per-rule validation results
```

Each checkpoint gets a git tag and an experiment comparison HTML.

## Success criteria

- [ ] Algorithm is documented as numbered rules with rationale
- [ ] Each rule validated by ablation (removing it makes things measurably worse)
- [ ] Station crossings ≤ dagre on benchmark fixtures
- [ ] Visual quality preferred over v6 and dagre in Tinder evaluation
- [ ] Algorithm is deterministic (same input → same output)
- [ ] Works for both provided routes (MLCM) and auto-discovered routes (bundling)
