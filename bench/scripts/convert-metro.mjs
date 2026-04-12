#!/usr/bin/env node
// convert-metro.mjs — convert juliuste/transit-map JSON to dag-map fixture format.
//
// Input: { nodes, edges, lines } with edges having metadata.lines
// Output: { id, dag: {nodes, edges}, routes, theme, opts }
//
// Routes are built by tracing each line through its edges, then
// filtering to only include segments that exist as DAG edges.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const INPUT_DIR = join(__dirname, '..', 'fixtures', 'metro-networks');
const OUTPUT_DIR = join(__dirname, '..', 'fixtures', 'metro');

import { mkdirSync } from 'node:fs';
mkdirSync(OUTPUT_DIR, { recursive: true });

const NAMES = {
  'bvg': 'Berlin U-Bahn',
  'wien': 'Vienna U-Bahn',
  'stockholm': 'Stockholm Tunnelbana',
  'nantes': 'Nantes Tramway',
  'montpellier': 'Montpellier Tramway',
  'lisboa': 'Lisbon Metro',
};

for (const file of readdirSync(INPUT_DIR).filter(f => f.endsWith('.json'))) {
  const slug = basename(file, '.input.json');
  const raw = JSON.parse(readFileSync(join(INPUT_DIR, file), 'utf8'));

  // Build geographic X for DAG direction
  const nodeX = new Map();
  for (const nd of raw.nodes) {
    nodeX.set(nd.id, nd.metadata?.x ?? 0);
  }

  // Build DAG edges: orient by geographic X (left to right)
  const dagEdgeSet = new Set();
  const dagEdges = [];
  for (const edge of raw.edges) {
    const sx = nodeX.get(edge.source) ?? 0;
    const tx = nodeX.get(edge.target) ?? 0;
    let from = edge.source, to = edge.target;
    if (sx > tx) { from = edge.target; to = edge.source; }
    // Same X: use node ID as tiebreaker for determinism
    if (sx === tx && from > to) { from = edge.target; to = edge.source; }
    const key = `${from}→${to}`;
    if (!dagEdgeSet.has(key)) {
      dagEdgeSet.add(key);
      dagEdges.push([from, to]);
    }
  }

  // Build routes: trace each line, then filter to DAG-direction segments only
  const routes = [];
  for (const line of raw.lines) {
    const lineEdges = raw.edges.filter(e => e.metadata?.lines?.includes(line.id));
    if (lineEdges.length === 0) continue;

    // Build undirected adjacency for this line
    const lineAdj = new Map();
    const lineNodes = new Set();
    for (const e of lineEdges) {
      lineNodes.add(e.source);
      lineNodes.add(e.target);
      if (!lineAdj.has(e.source)) lineAdj.set(e.source, []);
      if (!lineAdj.has(e.target)) lineAdj.set(e.target, []);
      lineAdj.get(e.source).push(e.target);
      lineAdj.get(e.target).push(e.source);
    }

    // Find endpoints (degree 1)
    const endpoints = [...lineNodes].filter(id => (lineAdj.get(id)?.length ?? 0) === 1);
    if (endpoints.length < 2) continue;

    // Trace from leftmost endpoint
    endpoints.sort((a, b) => (nodeX.get(a) ?? 0) - (nodeX.get(b) ?? 0));
    const start = endpoints[0];
    const fullPath = [start];
    const visited = new Set([start]);
    let current = start;
    while (true) {
      const neighbors = (lineAdj.get(current) || []).filter(n => !visited.has(n));
      if (neighbors.length === 0) break;
      current = neighbors[0];
      visited.add(current);
      fullPath.push(current);
    }

    // Build route by topologically sorting this line's nodes,
    // then keeping only consecutive pairs that have DAG edges.
    const lineNodeList = [...lineNodes];
    lineNodeList.sort((a, b) => (nodeX.get(a) ?? 0) - (nodeX.get(b) ?? 0));

    // Build DAG adjacency within this line
    const lineDagAdj = new Map();
    for (const id of lineNodeList) lineDagAdj.set(id, []);
    for (const [from, to] of dagEdges) {
      if (lineNodes.has(from) && lineNodes.has(to)) {
        lineDagAdj.get(from)?.push(to);
      }
    }

    // Find longest path in this line's DAG subgraph
    const dist = new Map(), prev = new Map();
    for (const id of lineNodeList) { dist.set(id, 0); prev.set(id, null); }
    for (const u of lineNodeList) {
      for (const v of (lineDagAdj.get(u) || [])) {
        if (dist.get(u) + 1 > dist.get(v)) {
          dist.set(v, dist.get(u) + 1);
          prev.set(v, u);
        }
      }
    }
    let bestDist = -1, bestEnd = null;
    for (const [id, d] of dist) { if (d > bestDist) { bestDist = d; bestEnd = id; } }

    if (bestEnd && bestDist > 0) {
      const path = [];
      for (let c = bestEnd; c !== null; c = prev.get(c)) path.unshift(c);
      routes.push({
        id: line.id,
        cls: line.id.toLowerCase().replace(/\s+/g, '_'),
        nodes: path,
      });
    }
  }

  // Verify: every route segment must exist as a DAG edge
  let violations = 0;
  for (const route of routes) {
    for (let i = 1; i < route.nodes.length; i++) {
      if (!dagEdgeSet.has(`${route.nodes[i-1]}→${route.nodes[i]}`)) {
        violations++;
      }
    }
  }

  const fixture = {
    id: `metro-${slug}`,
    name: NAMES[slug] || slug,
    source: 'juliuste/transit-map',
    dag: {
      nodes: raw.nodes.map(nd => ({ id: nd.id, label: nd.label })),
      edges: dagEdges,
    },
    routes,
    theme: 'cream',
    opts: {},
  };

  const outPath = join(OUTPUT_DIR, `${slug}.json`);
  writeFileSync(outPath, JSON.stringify(fixture, null, 2));
  const routeSegs = routes.reduce((a, r) => a + r.nodes.length - 1, 0);
  console.log(`✓ ${slug}: ${fixture.dag.nodes.length} stations, ${dagEdges.length} edges, ${routes.length} routes (${routeSegs} segments), ${violations} violations`);
}
