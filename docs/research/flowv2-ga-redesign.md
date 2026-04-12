# FlowV2 GA Redesign — Permutation-Based Evolution

## The Problem

The GA has been evolving cosmetic parameters (spacing, scale, corner radius)
that don't change layout. The REAL layout decisions are:

1. **Route ordering** — which route is above which at shared nodes
2. **Side assignment** — which routes above trunk, which below
3. **Node ordering** — within a topological layer, which node is higher

These are permutations, not floats.

## The Genome

```
Individual = {
  routePermutation: [3, 0, 4, 1, 2],  // order of routes from top to bottom
  sideAssignment: [-1, 0, 1, -1, 1],   // -1=above, 0=trunk, 1=below
}
```

The permutation determines the Y ordering. Route at index 0 of the
permutation gets the topmost position, index N-1 gets the bottom.
The trunk is always at position 0 (or wherever sideAssignment says 0).

## Fitness Function

```
fitness = w1 * crossings       // edge-edge crossings (most important)
        + w2 * overlaps        // routes sharing the same Y at same segment
        + w3 * bends           // Y-direction reversals per route
        + w4 * sideChanges     // how often a route changes side
        + w5 * routeLength     // total edge length (prefer compact)
```

All measured on the RENDERED layout, not abstract edges.

## GA Operators

### Crossover (Order Crossover — OX)
Standard for permutation GAs:
1. Pick a random substring from parent A
2. Fill remaining positions from parent B, preserving order
3. Result is a valid permutation

### Mutation
- **Swap**: swap two routes' positions
- **Reverse**: reverse a subsequence
- **Insert**: move one route to a different position

### Selection
Tournament selection on fitness (lower = better).

## What This Means

The GA explores different route orderings and finds the one that
minimizes crossings. Each individual IS a layout — not parameters
for a layout algorithm, but the actual structural decision.

This is conceptually different from our Mode 1 GA:
- Mode 1 GA: "which algorithm should we use?" → configuration
- FlowV2 GA: "which ordering should we use?" → direct layout decision

Both are valid. The Mode 1 GA found that hybrid ordering is best —
that's an algorithm recommendation. The FlowV2 GA will find the
specific permutation that minimizes crossings for each graph —
that's a per-graph optimization.

## Implementation Plan

1. New genome type: `PermutationGenome` with route permutation + side assignment
2. New GA operators: OX crossover, swap/reverse/insert mutation
3. New fitness function: measure crossings + overlaps + bends on rendered FlowV2
4. Explorer page shows GA progress: best permutation's layout vs random
5. Per-fixture optimization (each graph gets its own best permutation)
