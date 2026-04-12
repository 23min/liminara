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

    // Cover ALL DAG edges belonging to this line.
    // Build DAG adjacency within this line, then extract paths from
    // every source to every sink to cover all branches.
    const lineDagAdj = new Map();
    const lineDagIn = new Map();
    for (const id of lineNodes) { lineDagAdj.set(id, []); lineDagIn.set(id, 0); }
    const lineDagEdges = new Set();
    for (const [from, to] of dagEdges) {
      if (lineNodes.has(from) && lineNodes.has(to)) {
        lineDagAdj.get(from).push(to);
        lineDagIn.set(to, lineDagIn.get(to) + 1);
        lineDagEdges.add(`${from}→${to}`);
      }
    }

    // Find sources (in-degree 0) and extract paths greedily
    const coveredEdges = new Set();
    const sources = [...lineNodes].filter(id => lineDagIn.get(id) === 0);
    sources.sort((a, b) => (nodeX.get(a) ?? 0) - (nodeX.get(b) ?? 0));

    // Greedy: from each source, follow the longest uncovered path
    for (const src of sources) {
      let current = src;
      const path = [current];

      while (true) {
        const children = (lineDagAdj.get(current) || [])
          .filter(c => !coveredEdges.has(`${current}→${c}`));
        if (children.length === 0) break;
        // Prefer uncovered children, then any child
        const next = children[0];
        coveredEdges.add(`${current}→${next}`);
        path.push(next);
        current = next;
      }

      if (path.length >= 2) {
        const routeId = routes.filter(r => r.cls === line.id.toLowerCase().replace(/\s+/g, '_')).length > 0
          ? `${line.id}-${routes.length}`
          : line.id;
        routes.push({
          id: routeId,
          cls: line.id.toLowerCase().replace(/\s+/g, '_'),
          nodes: path,
        });
      }
    }

    // Cover any remaining uncovered edges as short routes
    for (const edgeKey of lineDagEdges) {
      if (coveredEdges.has(edgeKey)) continue;
      const [from, to] = edgeKey.split('→');
      const routeId = `${line.id}-${routes.length}`;
      routes.push({
        id: routeId,
        cls: line.id.toLowerCase().replace(/\s+/g, '_'),
        nodes: [from, to],
      });
      coveredEdges.add(edgeKey);
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
