// permutation-ga.mjs — GA for route ordering in FlowV2.
//
// Genome = route permutation (which route at which Y position).
// Fitness = visual crossings + visual overlaps + bends.
// Measured on actual dot positions from the layout, not SVG paths.

import { layoutFlowV2 } from '../../dag-map/src/layout-flow-v2.js';

// ── Fitness ──

export function evaluateFitness(dag, routes, permutation) {
  const reorderedRoutes = permutation.map(i => routes[i]);

  try {
    const layout = layoutFlowV2(dag, {
      routes: reorderedRoutes,
      scale: 1.5,
      dotSpacing: 12,
      trackSpread: 2,
    });

    let crossings = 0;
    let overlaps = 0;
    let bends = 0;

    // Build actual route paths as sequences of (x, y) from dot positions.
    // This is what the user SEES, not abstract endpoints.
    const routePoints = []; // ri → [{x, y}, ...]
    for (let ri = 0; ri < reorderedRoutes.length; ri++) {
      const pts = [];
      for (const nodeId of reorderedRoutes[ri].nodes) {
        const dp = layout.dotPositions.get(`${nodeId}:${ri}`);
        const pos = dp || layout.positions.get(nodeId);
        if (pos) pts.push({ x: pos.x, y: pos.y });
      }
      routePoints.push(pts);
    }

    // Visual crossings: for each pair of route segments, check if
    // the straight lines between consecutive dots cross.
    const allSegs = [];
    for (let ri = 0; ri < routePoints.length; ri++) {
      const pts = routePoints[ri];
      for (let k = 0; k < pts.length - 1; k++) {
        allSegs.push({ ri, x1: pts[k].x, y1: pts[k].y, x2: pts[k + 1].x, y2: pts[k + 1].y });
      }
    }

    for (let i = 0; i < allSegs.length; i++) {
      for (let j = i + 1; j < allSegs.length; j++) {
        if (allSegs[i].ri === allSegs[j].ri) continue;
        if (segsCross(allSegs[i], allSegs[j])) crossings++;
      }
    }

    // Visual overlaps: two DIFFERENT routes at the same Y between
    // the same pair of X coordinates (nodes at same layer).
    // Check each dot position: if two different routes have dots
    // within 1px of the same Y at the same X, they overlap.
    const dotKeys = new Map(); // "roundX,roundY" → Set<ri>
    for (let ri = 0; ri < routePoints.length; ri++) {
      for (const pt of routePoints[ri]) {
        const key = `${Math.round(pt.x)},${Math.round(pt.y)}`;
        if (!dotKeys.has(key)) dotKeys.set(key, new Set());
        dotKeys.get(key).add(ri);
      }
    }
    for (const routeSet of dotKeys.values()) {
      if (routeSet.size > 1) overlaps += routeSet.size - 1;
    }

    // Also check segment overlaps: segments from different routes
    // traveling at the same Y (parallel overlay)
    for (let i = 0; i < allSegs.length; i++) {
      for (let j = i + 1; j < allSegs.length; j++) {
        if (allSegs[i].ri === allSegs[j].ri) continue;
        // Same Y at both endpoints AND overlapping X range
        if (Math.abs(allSegs[i].y1 - allSegs[j].y1) < 1.5 &&
            Math.abs(allSegs[i].y2 - allSegs[j].y2) < 1.5) {
          // Check X overlap
          const minX1 = Math.min(allSegs[i].x1, allSegs[i].x2);
          const maxX1 = Math.max(allSegs[i].x1, allSegs[i].x2);
          const minX2 = Math.min(allSegs[j].x1, allSegs[j].x2);
          const maxX2 = Math.max(allSegs[j].x1, allSegs[j].x2);
          if (minX1 < maxX2 && minX2 < maxX1) overlaps++;
        }
      }
    }

    // Bends: Y-direction reversals per route (using dot positions)
    for (const pts of routePoints) {
      let prevDy = 0;
      for (let k = 1; k < pts.length; k++) {
        const dy = pts[k].y - pts[k - 1].y;
        if (Math.abs(dy) > 0.5 && Math.abs(prevDy) > 0.5) {
          if ((prevDy > 0 && dy < 0) || (prevDy < 0 && dy > 0)) bends++;
        }
        if (Math.abs(dy) > 0.5) prevDy = dy;
      }
    }

    return {
      fitness: crossings * 100 + overlaps * 20 + bends * 5,
      crossings,
      overlaps,
      bends,
    };
  } catch (e) {
    return { fitness: Infinity, crossings: 999, overlaps: 999, bends: 999, error: e.message };
  }
}

function segsCross(a, b) {
  const d1 = dir(b.x1, b.y1, b.x2, b.y2, a.x1, a.y1);
  const d2 = dir(b.x1, b.y1, b.x2, b.y2, a.x2, a.y2);
  const d3 = dir(a.x1, a.y1, a.x2, a.y2, b.x1, b.y1);
  const d4 = dir(a.x1, a.y1, a.x2, a.y2, b.x2, b.y2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
         ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

function dir(ax, ay, bx, by, cx, cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

// ── Operators ──

export function randomPermutation(n, rng) {
  const perm = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [perm[i], perm[j]] = [perm[j], perm[i]];
  }
  return perm;
}

export function orderCrossover(parentA, parentB, rng) {
  const n = parentA.length;
  const start = Math.floor(rng() * n);
  const end = start + Math.floor(rng() * (n - start));
  const child = new Array(n).fill(-1);
  for (let i = start; i <= end; i++) child[i] = parentA[i];
  const used = new Set(child.filter(x => x >= 0));
  const bOrder = parentB.filter(x => !used.has(x));
  let bi = 0;
  for (let i = 0; i < n; i++) {
    if (child[i] === -1) child[i] = bOrder[bi++];
  }
  return child;
}

export function mutateSwap(perm, rng) {
  const copy = [...perm];
  const i = Math.floor(rng() * copy.length);
  const j = Math.floor(rng() * copy.length);
  [copy[i], copy[j]] = [copy[j], copy[i]];
  return copy;
}

export function mutateInsert(perm, rng) {
  const copy = [...perm];
  const from = Math.floor(rng() * copy.length);
  const to = Math.floor(rng() * copy.length);
  const item = copy.splice(from, 1)[0];
  copy.splice(to, 0, item);
  return copy;
}

// ── GA Runner ──

export function evolveRouteOrder(dag, routes, {
  populationSize = 30,
  generations = 100,
  eliteCount = 3,
  mutationRate = 0.3,
  seed = 42,
  onGeneration = null,
} = {}) {
  let rngState = seed;
  function rng() {
    rngState = (rngState * 1103515245 + 12345) & 0x7fffffff;
    return rngState / 0x7fffffff;
  }

  const n = routes.length;
  if (n <= 1) return { bestPermutation: [0], bestFitness: { fitness: 0, crossings: 0, overlaps: 0, bends: 0 }, history: [] };

  let population = [];
  // Include the default order as one of the initial population
  const defaultPerm = Array.from({ length: n }, (_, i) => i);
  population.push({ perm: defaultPerm, ...evaluateFitness(dag, routes, defaultPerm) });

  for (let i = 1; i < populationSize; i++) {
    const perm = randomPermutation(n, rng);
    population.push({ perm, ...evaluateFitness(dag, routes, perm) });
  }
  population.sort((a, b) => a.fitness - b.fitness);

  const history = [];

  for (let gen = 0; gen < generations; gen++) {
    const nextPop = [];
    for (let i = 0; i < eliteCount; i++) nextPop.push(population[i]);

    while (nextPop.length < populationSize) {
      const p1 = tournament(population, 3, rng);
      const p2 = tournament(population, 3, rng);
      let childPerm = orderCrossover(p1.perm, p2.perm, rng);
      if (rng() < mutationRate) {
        childPerm = rng() < 0.5 ? mutateSwap(childPerm, rng) : mutateInsert(childPerm, rng);
      }
      nextPop.push({ perm: childPerm, ...evaluateFitness(dag, routes, childPerm) });
    }

    nextPop.sort((a, b) => a.fitness - b.fitness);
    population = nextPop.slice(0, populationSize);

    const best = population[0];
    history.push({ gen, fitness: best.fitness, crossings: best.crossings, overlaps: best.overlaps, bends: best.bends });
    if (onGeneration) onGeneration(gen, best, population);
    if (best.fitness === 0) break;
  }

  return { bestPermutation: population[0].perm, bestFitness: population[0], history };
}

function tournament(pop, size, rng) {
  let best = pop[Math.floor(rng() * pop.length)];
  for (let i = 1; i < size; i++) {
    const c = pop[Math.floor(rng() * pop.length)];
    if (c.fitness < best.fitness) best = c;
  }
  return best;
}
