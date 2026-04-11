// ga.mjs — direct-position genetic algorithm.
//
// Each individual is a complete set of (x, y) positions for every node.
// Mutation moves nodes. Crossover picks node positions from either parent.
// Fitness evaluates all quality rules on the straight-line layout.
//
// Deterministic: seeded PRNG throughout.

import { evaluateLayout } from './fitness.mjs';
import { buildGraph, topoSortAndRank } from '../../dag-map/src/graph-utils.js';

const DEFAULT_WEIGHTS = {
  flow_violations: 1000,  // hard — reject backward edges
  crossings: 50,          // very important — no edge crossings
  overlap: 40,            // edges shouldn't coincide
  direction_changes: 20,  // no Y zig-zag
  node_too_close: 80,     // prevent crowding
  edge_length: 5,         // shorter edges
  slope: 20,              // prefer horizontal edges
  angular: 15,            // fan out from nodes
  layer_alignment: 30,    // same-depth nodes at similar X
  path_bend: 25,          // A→B→C should be straight
  vertical_balance: 15,   // centered vertically
  edge_uniformity: 10,    // uniform edge lengths
  compactness: 3,         // don't waste space
};

/**
 * Create a seeded PRNG.
 */
function createPrng(seed) {
  let s = seed;
  function next() {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  }
  function nextGaussian() {
    // Box-Muller
    const u1 = next() || 0.0001;
    const u2 = next();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  }
  return { next, nextGaussian };
}

/**
 * Generate a random layout respecting topological X ordering.
 */
function randomLayout(dag, prng, { width = 800, height = 500 } = {}) {
  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);
  const { rank, maxRank } = topoSortAndRank(dag.nodes, childrenOf, parentsOf);

  const positions = new Map();
  const margin = 50;
  const layerSpacing = (width - margin * 2) / Math.max(maxRank, 1);
  const nodeSpacing = 45;

  // Group nodes by layer, then shuffle Y order within each layer
  const layers = [];
  for (let r = 0; r <= maxRank; r++) layers.push([]);
  for (const nd of dag.nodes) {
    layers[rank.get(nd.id)].push(nd.id);
  }

  // Shuffle each layer's Y order (this is the variation between individuals)
  for (const layer of layers) {
    for (let i = layer.length - 1; i > 0; i--) {
      const j = Math.floor(prng.next() * (i + 1));
      const tmp = layer[i]; layer[i] = layer[j]; layer[j] = tmp;
    }
  }

  // Assign positions: X from layer (column-aligned), Y from shuffled order
  for (let r = 0; r <= maxRank; r++) {
    const layer = layers[r];
    const n = layer.length;
    const totalHeight = (n - 1) * nodeSpacing;
    const centerY = height / 2;
    for (let i = 0; i < n; i++) {
      positions.set(layer[i], {
        x: margin + r * layerSpacing,
        y: centerY - totalHeight / 2 + i * nodeSpacing,
      });
    }
  }

  return positions;
}

/**
 * Mutate a layout using a mix of operators.
 * X stays mostly column-aligned — mutations focus on Y (node ordering).
 * - Random Y move (exploration)
 * - Y-align: move node Y toward neighbor average (flatten edges)
 * - Y-match: copy Y from a connected node (make one edge horizontal)
 */
function mutate(positions, edges, childrenOf, parentsOf, prng, { moveSigmaX = 20, moveSigmaY = 30 } = {}) {
  const result = new Map();
  for (const [id, pos] of positions) result.set(id, { ...pos });

  const nodeIds = [...positions.keys()];

  for (const id of nodeIds) {
    const roll = prng.next();

    if (roll < 0.20) {
      // Random Y move only — keep X column-aligned (20% chance)
      const p = result.get(id);
      p.y += prng.nextGaussian() * moveSigmaY;

    } else if (roll < 0.55) {
      // Y-align: move Y toward average Y of neighbors (30% chance)
      // This is the key operator for horizontal edges
      const neighbors = [];
      for (const c of (childrenOf?.get(id) || [])) {
        const p = result.get(c);
        if (p) neighbors.push(p.y);
      }
      for (const p of (parentsOf?.get(id) || [])) {
        const pp = result.get(p);
        if (pp) neighbors.push(pp.y);
      }
      if (neighbors.length > 0) {
        const avgY = neighbors.reduce((a, b) => a + b, 0) / neighbors.length;
        const p = result.get(id);
        // Move 50-90% toward neighbor average
        const blend = 0.5 + prng.next() * 0.4;
        p.y = p.y * (1 - blend) + avgY * blend;
      }

    } else if (roll < 0.65) {
      // Y-match: copy Y from a random neighbor (10% chance)
      const allNeighbors = [
        ...(childrenOf?.get(id) || []),
        ...(parentsOf?.get(id) || []),
      ];
      if (allNeighbors.length > 0) {
        const neighbor = allNeighbors[Math.floor(prng.next() * allNeighbors.length)];
        const np = result.get(neighbor);
        if (np) {
          const p = result.get(id);
          p.y = np.y + prng.nextGaussian() * 5;
        }
      }

    } else if (roll < 0.75) {
      // Y-swap: swap Y with another node in same column (10% chance)
      // This is the most powerful structural change
      const p = result.get(id);
      const sameColumn = nodeIds.filter(oid => oid !== id && Math.abs(result.get(oid).x - p.x) < 10);
      if (sameColumn.length > 0) {
        const other = sameColumn[Math.floor(prng.next() * sameColumn.length)];
        const op = result.get(other);
        const tmpY = p.y;
        p.y = op.y;
        op.y = tmpY;
      }

    } else if (roll < 0.90) {
      // Y-spread: push apart from nearest same-column neighbor (15% chance)
      const p = result.get(id);
      let nearestDy = Infinity;
      let nearestId = null;
      for (const otherId of nodeIds) {
        if (otherId === id) continue;
        const op = result.get(otherId);
        if (Math.abs(p.x - op.x) > 20) continue;
        const dy = Math.abs(p.y - op.y);
        if (dy < nearestDy) { nearestDy = dy; nearestId = otherId; }
      }
      if (nearestId && nearestDy < 40) {
        const op = result.get(nearestId);
        const push = (40 - nearestDy) / 2 + 5;
        if (p.y < op.y) { p.y -= push; op.y += push; }
        else { p.y += push; op.y -= push; }
      }
    }
    // else: 15% — no mutation
  }

  return result;
}

/**
 * Crossover: for each node, pick position from parent A or B.
 */
function crossover(posA, posB, prng) {
  const result = new Map();
  for (const [id, pA] of posA) {
    const pB = posB.get(id);
    if (pB && prng.next() < 0.5) {
      result.set(id, { ...pB });
    } else {
      result.set(id, { ...pA });
    }
  }
  return result;
}

/**
 * Repair flow violations: nudge nodes right if they violate x(u) < x(v).
 */
function repairFlow(positions, edges) {
  const minGap = 25;
  // Multiple passes to propagate
  for (let pass = 0; pass < 5; pass++) {
    for (const [from, to] of edges) {
      const pf = positions.get(from), pt = positions.get(to);
      if (!pf || !pt) continue;
      if (pt.x <= pf.x + minGap) {
        pt.x = pf.x + minGap;
      }
    }
  }
}

/**
 * Run the direct-position GA for a single graph.
 *
 * @param {object} dag - { nodes, edges }
 * @param {object} opts
 * @param {number} opts.seed
 * @param {number} opts.populationSize - total population
 * @param {number} opts.generations
 * @param {number} opts.eliteCount
 * @param {object} [opts.weights] - fitness weights
 * @param {function} [opts.onGeneration] - callback(gen, best, population)
 * @returns {{ best, population, history }}
 */
export function runDirectGA(dag, opts) {
  const {
    seed = 42,
    populationSize = 200,
    generations = 100,
    eliteCount = 10,
    weights = DEFAULT_WEIGHTS,
    onGeneration,
  } = opts;

  const prng = createPrng(seed);
  const { edges } = dag;
  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);

  // Initialize population
  let population = [];
  for (let i = 0; i < populationSize; i++) {
    const positions = randomLayout(dag, createPrng(seed + i * 7919));
    repairFlow(positions, edges);
    const { score, terms, violations } = evaluateLayout(positions, edges, weights);
    population.push({ id: `g0-${i}`, positions, score, terms, violations });
  }

  population.sort((a, b) => a.score - b.score);
  const history = [{ gen: 0, bestScore: population[0].score }];

  if (onGeneration) onGeneration(0, population[0], population);

  // Evolve
  for (let gen = 1; gen <= generations; gen++) {
    const next = [];

    // Elitism: keep top N
    for (let i = 0; i < eliteCount; i++) {
      next.push({ ...population[i], id: `g${gen}-elite-${i}` });
    }

    // Fill rest with offspring
    while (next.length < populationSize) {
      // Tournament selection
      const p1 = tournament(population, prng, 5);
      const p2 = tournament(population, prng, 5);

      // Crossover
      let child = crossover(p1.positions, p2.positions, prng);

      // Smart mutation: Y-align (flatten edges) + Y-match (horizontal edges) + random
      child = mutate(child, edges, childrenOf, parentsOf, prng, {
        moveSigmaX: 25 + 15 * (1 - gen / generations),
        moveSigmaY: 40 + 20 * (1 - gen / generations),
      });

      // Repair flow violations
      repairFlow(child, edges);

      const { score, terms, violations } = evaluateLayout(child, edges, weights);
      next.push({ id: `g${gen}-${next.length}`, positions: child, score, terms, violations });
    }

    population = next.sort((a, b) => a.score - b.score);
    history.push({ gen, bestScore: population[0].score });

    if (onGeneration) onGeneration(gen, population[0], population);
  }

  return { best: population[0], population, history };
}

function tournament(population, prng, size) {
  let best = population[Math.floor(prng.next() * population.length)];
  for (let i = 1; i < size; i++) {
    const candidate = population[Math.floor(prng.next() * population.length)];
    if (candidate.score < best.score) best = candidate;
  }
  return best;
}

export { DEFAULT_WEIGHTS, randomLayout, evaluateLayout, mutate };
