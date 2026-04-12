// permutation-ga.mjs — GA for route ordering in FlowV2.
//
// Genome = route permutation (which route at which Y position).
// Fitness = crossings + overlaps + bends on the rendered layout.
// Operators: order crossover (OX), swap/insert mutation.

import { layoutFlowV2 } from '../../dag-map/src/layout-flow-v2.js';

// ── Fitness ──

export function evaluateFitness(dag, routes, permutation) {
  // Reorder routes according to permutation
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

    // Count segment crossings between different routes
    const allSegs = [];
    for (let ri = 0; ri < layout.routePaths.length; ri++) {
      for (const seg of layout.routePaths[ri]) {
        const m = seg.d.match(/^M\s+([\d.e+-]+)\s+([\d.e+-]+)/);
        const points = seg.d.match(/[\d.e+-]+/g);
        if (m && points && points.length >= 4) {
          const x1 = parseFloat(points[0]), y1 = parseFloat(points[1]);
          // Find last coordinate pair
          const x2 = parseFloat(points[points.length - 2]);
          const y2 = parseFloat(points[points.length - 1]);
          allSegs.push({ ri, x1, y1, x2, y2 });
        }
      }
    }

    // Pairwise crossing check
    for (let i = 0; i < allSegs.length; i++) {
      for (let j = i + 1; j < allSegs.length; j++) {
        if (allSegs[i].ri === allSegs[j].ri) continue;
        if (segsCross(allSegs[i], allSegs[j])) crossings++;
      }
    }

    // Count overlaps: segments from different routes at same Y
    const yPairs = new Map();
    for (const seg of allSegs) {
      const key = `${Math.round(seg.y1)},${Math.round(seg.y2)}`;
      if (!yPairs.has(key)) yPairs.set(key, new Set());
      yPairs.get(key).add(seg.ri);
    }
    for (const routeSet of yPairs.values()) {
      if (routeSet.size > 1) overlaps += routeSet.size - 1;
    }

    // Count bends per route
    for (const route of reorderedRoutes) {
      const ys = route.nodes.map(id => {
        const p = layout.positions.get(id);
        return p ? p.y : 0;
      });
      let prevDy = 0;
      for (let k = 1; k < ys.length; k++) {
        const dy = ys[k] - ys[k - 1];
        if (Math.abs(dy) > 0.5 && Math.abs(prevDy) > 0.5) {
          if ((prevDy > 0 && dy < 0) || (prevDy < 0 && dy > 0)) bends++;
        }
        if (Math.abs(dy) > 0.5) prevDy = dy;
      }
    }

    return {
      fitness: crossings * 100 + overlaps * 10 + bends * 5,
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
  // Fisher-Yates shuffle
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
  // Copy substring from A
  for (let i = start; i <= end; i++) child[i] = parentA[i];

  // Fill remaining from B, preserving order
  const used = new Set(child.filter(x => x >= 0));
  const bOrder = parentB.filter(x => !used.has(x));
  let bi = 0;
  for (let i = 0; i < n; i++) {
    if (child[i] === -1) child[i] = bOrder[bi++];
  }
  return child;
}

export function mutateSwap(perm, rng) {
  const n = perm.length;
  const copy = [...perm];
  const i = Math.floor(rng() * n);
  const j = Math.floor(rng() * n);
  [copy[i], copy[j]] = [copy[j], copy[i]];
  return copy;
}

export function mutateInsert(perm, rng) {
  const n = perm.length;
  const copy = [...perm];
  const from = Math.floor(rng() * n);
  const to = Math.floor(rng() * n);
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
  // Seeded PRNG
  let rngState = seed;
  function rng() {
    rngState = (rngState * 1103515245 + 12345) & 0x7fffffff;
    return rngState / 0x7fffffff;
  }

  const n = routes.length;
  if (n <= 1) return { bestPermutation: [0], bestFitness: { fitness: 0, crossings: 0, overlaps: 0, bends: 0 }, history: [] };

  // Initialize population
  let population = [];
  for (let i = 0; i < populationSize; i++) {
    const perm = randomPermutation(n, rng);
    const fit = evaluateFitness(dag, routes, perm);
    population.push({ perm, ...fit });
  }
  population.sort((a, b) => a.fitness - b.fitness);

  const history = [];

  for (let gen = 0; gen < generations; gen++) {
    const nextPop = [];

    // Elitism
    for (let i = 0; i < eliteCount; i++) {
      nextPop.push(population[i]);
    }

    // Breed
    while (nextPop.length < populationSize) {
      // Tournament selection
      const p1 = tournament(population, 3, rng);
      const p2 = tournament(population, 3, rng);

      let childPerm = orderCrossover(p1.perm, p2.perm, rng);

      if (rng() < mutationRate) {
        childPerm = rng() < 0.5 ? mutateSwap(childPerm, rng) : mutateInsert(childPerm, rng);
      }

      const fit = evaluateFitness(dag, routes, childPerm);
      nextPop.push({ perm: childPerm, ...fit });
    }

    nextPop.sort((a, b) => a.fitness - b.fitness);
    population = nextPop.slice(0, populationSize);

    const best = population[0];
    history.push({ gen, fitness: best.fitness, crossings: best.crossings, overlaps: best.overlaps, bends: best.bends });

    if (onGeneration) onGeneration(gen, best, population);

    // Early termination if perfect
    if (best.fitness === 0) break;
  }

  return {
    bestPermutation: population[0].perm,
    bestFitness: population[0],
    history,
  };
}

function tournament(pop, size, rng) {
  let best = pop[Math.floor(rng() * pop.length)];
  for (let i = 1; i < size; i++) {
    const candidate = pop[Math.floor(rng() * pop.length)];
    if (candidate.fitness < best.fitness) best = candidate;
  }
  return best;
}
