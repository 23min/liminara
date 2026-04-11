// lane-model.mjs — lane-based DAG layout with GA optimization.
//
// The layout is defined by a lane assignment: each node gets a lane number.
// X = topological rank (columns). Y = lane × spacing (rows).
// Edges between same-lane nodes are horizontal. Different lanes = diagonal.
//
// The GA evolves lane assignments. Mutations swap/move nodes between lanes.
// Fitness checks the 14 quality criteria on the resulting layout.

import { buildGraph, topoSortAndRank } from '../../dag-map/src/graph-utils.js';

// ── Layout from lane assignment ──

export function buildLayout(dag, laneAssignment, { laneHeight = 50, layerSpacing = 80, margin = 50 } = {}) {
  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);
  const { rank, maxRank } = topoSortAndRank(dag.nodes, childrenOf, parentsOf);

  const positions = new Map();
  for (const nd of dag.nodes) {
    const lane = laneAssignment.get(nd.id) ?? 0;
    positions.set(nd.id, {
      x: margin + rank.get(nd.id) * layerSpacing,
      y: margin + lane * laneHeight,
    });
  }

  return { positions, rank, maxRank, childrenOf, parentsOf };
}

// ── Fitness evaluation ──

export function evaluateLaneLayout(dag, laneAssignment, weights, opts) {
  const { positions, rank, maxRank, childrenOf } = buildLayout(dag, laneAssignment, opts);
  const { edges } = dag;

  // Edge segments for crossing/overlap detection
  const segments = edges.map(([f, t]) => {
    const pf = positions.get(f), pt = positions.get(t);
    return pf && pt ? { f, t, x1: pf.x, y1: pf.y, x2: pt.x, y2: pt.y } : null;
  }).filter(Boolean);

  // ── Crossings ──
  let crossings = 0;
  for (let i = 0; i < segments.length; i++) {
    for (let j = i + 1; j < segments.length; j++) {
      if (segmentsIntersect(segments[i], segments[j])) crossings++;
    }
  }

  // ── Horizontal edges (reward, not penalty) ──
  let horizontalEdges = 0;
  for (const [f, t] of edges) {
    if (laneAssignment.get(f) === laneAssignment.get(t)) horizontalEdges++;
  }
  const nonHorizontal = edges.length - horizontalEdges;

  // ── Slope ──
  let slope = 0;
  for (const s of segments) {
    const dx = Math.abs(s.x2 - s.x1) || 1;
    const dy = Math.abs(s.y2 - s.y1);
    slope += dy / dx;
  }

  // ── Lane conflicts (two nodes, same lane, same layer) ──
  let conflicts = 0;
  const occupied = new Map(); // "layer:lane" → nodeId
  for (const nd of dag.nodes) {
    const key = `${rank.get(nd.id)}:${laneAssignment.get(nd.id)}`;
    if (occupied.has(key)) conflicts++;
    occupied.set(key, nd.id);
  }

  // ── Direction changes (zig-zag) ──
  let dirChanges = 0;
  for (const [from, to] of edges) {
    const lt = laneAssignment.get(to);
    for (const grandchild of (childrenOf.get(to) || [])) {
      const lf = laneAssignment.get(from);
      const lg = laneAssignment.get(grandchild);
      const dy1 = lt - lf;
      const dy2 = lg - lt;
      if (dy1 !== 0 && dy2 !== 0 && Math.sign(dy1) !== Math.sign(dy2)) dirChanges++;
    }
  }

  // ── Edge overlap (same start lane + end lane) ──
  const edgeKeys = new Map();
  for (const [f, t] of edges) {
    const key = `${laneAssignment.get(f)},${laneAssignment.get(t)}`;
    edgeKeys.set(key, (edgeKeys.get(key) || 0) + 1);
  }
  let overlap = 0;
  for (const count of edgeKeys.values()) {
    if (count > 1) overlap += count * (count - 1) / 2;
  }

  // ── Path straightness (A→B→C same lane = straight) ──
  let pathBend = 0;
  for (const [from, to] of edges) {
    for (const grandchild of (childrenOf.get(to) || [])) {
      const lf = laneAssignment.get(from);
      const lt = laneAssignment.get(to);
      const lg = laneAssignment.get(grandchild);
      if (lf !== lt || lt !== lg) pathBend++;
    }
  }

  // ── Vertical balance ──
  const lanes = [...laneAssignment.values()];
  const avgLane = lanes.reduce((a, b) => a + b, 0) / lanes.length;
  const maxLane = Math.max(...lanes);
  const centerLane = maxLane / 2;
  const balance = Math.abs(avgLane - centerLane) / (maxLane || 1);

  // ── Lane spread (use available lanes, don't bunch) ──
  const usedLanes = new Set(lanes);
  const spreadRatio = usedLanes.size / (maxLane + 1 || 1);
  const bunching = 1 - spreadRatio; // 0 = well spread, 1 = all in one lane

  const terms = {
    crossings,
    non_horizontal: nonHorizontal,
    slope,
    conflicts,
    direction_changes: dirChanges,
    overlap,
    path_bend: pathBend,
    balance,
    bunching,
  };

  let score = 0;
  for (const [name, val] of Object.entries(terms)) {
    score += (weights[name] ?? 0) * val;
  }

  return { score, terms, positions };
}

// ── GA ──

const DEFAULT_WEIGHTS = {
  crossings: 100,         // most important — no crossings
  non_horizontal: 15,     // prefer horizontal edges
  slope: 10,              // minimize slope
  conflicts: 500,         // hard — no two nodes in same spot
  direction_changes: 30,  // no zig-zag
  overlap: 40,            // no coinciding edges
  path_bend: 20,          // paths should be straight
  balance: 10,            // centered
  bunching: 25,           // spread across lanes
};

function createPrng(seed) {
  let s = seed;
  return {
    next() { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; },
    nextInt(max) { return Math.floor(this.next() * (max + 1)); },
  };
}

export function randomLaneAssignment(dag, numLanes, prng) {
  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);
  const { rank, maxRank } = topoSortAndRank(dag.nodes, childrenOf, parentsOf);

  const assignment = new Map();

  // Group by layer, assign lanes within each layer
  const layers = [];
  for (let r = 0; r <= maxRank; r++) layers.push([]);
  for (const nd of dag.nodes) layers[rank.get(nd.id)].push(nd.id);

  for (const layer of layers) {
    // Shuffle and distribute across lanes
    for (let i = layer.length - 1; i > 0; i--) {
      const j = prng.nextInt(i);
      const tmp = layer[i]; layer[i] = layer[j]; layer[j] = tmp;
    }
    // Spread evenly, centered
    const startLane = Math.max(0, Math.floor((numLanes - layer.length) / 2));
    for (let i = 0; i < layer.length; i++) {
      assignment.set(layer[i], startLane + i);
    }
  }

  return assignment;
}

function mutateLanes(assignment, dag, numLanes, prng, childrenOf) {
  const result = new Map(assignment);
  const nodes = dag.nodes;
  const { rank } = topoSortAndRank(nodes, childrenOf, buildGraph(nodes, dag.edges).parentsOf);

  const nodeId = nodes[prng.nextInt(nodes.length - 1)].id;
  const roll = prng.next();

  if (roll < 0.3) {
    // Move to neighbor's lane (make edge horizontal) — 30%
    const neighbors = [
      ...(childrenOf.get(nodeId) || []),
      ...(buildGraph(nodes, dag.edges).parentsOf.get(nodeId) || []),
    ];
    if (neighbors.length > 0) {
      const neighbor = neighbors[prng.nextInt(neighbors.length - 1)];
      result.set(nodeId, result.get(neighbor));
    }

  } else if (roll < 0.6) {
    // Move to random lane — 30%
    result.set(nodeId, prng.nextInt(numLanes - 1));

  } else if (roll < 0.85) {
    // Swap with another node in same layer — 25%
    const myRank = rank.get(nodeId);
    const sameLayer = nodes.filter(n => rank.get(n.id) === myRank && n.id !== nodeId);
    if (sameLayer.length > 0) {
      const other = sameLayer[prng.nextInt(sameLayer.length - 1)].id;
      const tmpLane = result.get(nodeId);
      result.set(nodeId, result.get(other));
      result.set(other, tmpLane);
    }

  } else {
    // Nudge one lane up or down — 15%
    const cur = result.get(nodeId);
    const dir = prng.next() < 0.5 ? -1 : 1;
    result.set(nodeId, Math.max(0, Math.min(numLanes - 1, cur + dir)));
  }

  return result;
}

function crossoverLanes(a, b, prng) {
  const result = new Map();
  for (const [id, laneA] of a) {
    result.set(id, prng.next() < 0.5 ? laneA : (b.get(id) ?? laneA));
  }
  return result;
}

export function runLaneGA(dag, opts = {}) {
  const {
    seed = 42,
    populationSize = 200,
    generations = 1000,
    eliteCount = 10,
    weights = DEFAULT_WEIGHTS,
    numLanes = null,
    onGeneration,
  } = opts;

  const { childrenOf } = buildGraph(dag.nodes, dag.edges);
  const { maxRank } = topoSortAndRank(dag.nodes, childrenOf, buildGraph(dag.nodes, dag.edges).parentsOf);

  // Auto-determine lane count: max nodes in any layer × 1.5
  const layers = [];
  for (let r = 0; r <= maxRank; r++) layers.push(0);
  for (const nd of dag.nodes) layers[topoSortAndRank(dag.nodes, childrenOf, buildGraph(dag.nodes, dag.edges).parentsOf).rank.get(nd.id)]++;
  const maxWidth = Math.max(...layers);
  const lanes = numLanes ?? Math.max(maxWidth + 2, Math.ceil(dag.nodes.length * 0.6));

  const prng = createPrng(seed);
  const layoutOpts = { laneHeight: 50, layerSpacing: 80, margin: 50 };

  // Initialize
  let population = [];
  for (let i = 0; i < populationSize; i++) {
    const assignment = randomLaneAssignment(dag, lanes, createPrng(seed + i * 7919));
    const { score, terms, positions } = evaluateLaneLayout(dag, assignment, weights, layoutOpts);
    population.push({ id: `g0-${i}`, assignment, score, terms, positions });
  }
  population.sort((a, b) => a.score - b.score);

  if (onGeneration) onGeneration(0, population[0], population);

  for (let gen = 1; gen <= generations; gen++) {
    const next = [];

    // Elitism
    for (let i = 0; i < eliteCount; i++) {
      next.push({ ...population[i], id: `g${gen}-e${i}` });
    }

    // Offspring
    while (next.length < populationSize) {
      const p1 = tournament(population, prng);
      const p2 = tournament(population, prng);
      let child = crossoverLanes(p1.assignment, p2.assignment, prng);

      // Multiple mutations per child for faster exploration
      const numMuts = 1 + prng.nextInt(3); // 1-4 mutations
      for (let m = 0; m < numMuts; m++) {
        child = mutateLanes(child, dag, lanes, prng, childrenOf);
      }

      const { score, terms, positions } = evaluateLaneLayout(dag, child, weights, layoutOpts);
      next.push({ id: `g${gen}-${next.length}`, assignment: child, score, terms, positions });
    }

    population = next.sort((a, b) => a.score - b.score);
    if (onGeneration) onGeneration(gen, population[0], population);
  }

  return { best: population[0], population, lanes };
}

function tournament(pop, prng) {
  let best = pop[prng.nextInt(pop.length - 1)];
  for (let i = 0; i < 4; i++) {
    const c = pop[prng.nextInt(pop.length - 1)];
    if (c.score < best.score) best = c;
  }
  return best;
}

function segmentsIntersect(a, b) {
  if (a.f === b.f || a.f === b.t || a.t === b.f || a.t === b.t) return false;
  const d1x = a.x2 - a.x1, d1y = a.y2 - a.y1;
  const d2x = b.x2 - b.x1, d2y = b.y2 - b.y1;
  const cross = d1x * d2y - d1y * d2x;
  if (Math.abs(cross) < 1e-10) return false;
  const dx = b.x1 - a.x1, dy = b.y1 - a.y1;
  const t = (dx * d2y - dy * d2x) / cross;
  const u = (dx * d1y - dy * d1x) / cross;
  return t > 0.01 && t < 0.99 && u > 0.01 && u < 0.99;
}

export { DEFAULT_WEIGHTS };
