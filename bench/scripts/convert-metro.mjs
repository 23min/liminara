#!/usr/bin/env node
// convert-metro.mjs — convert juliuste/transit-map JSON to dag-map fixture format.
//
// Input: { nodes, edges, lines } with edges having metadata.lines
// Output: { id, dag: {nodes, edges}, routes, theme, opts }
//
// Routes are built by tracing each line through its edges.

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

  // Build adjacency for route tracing
  const adj = new Map(); // nodeId → [{neighbor, lines}]
  for (const nd of raw.nodes) {
    adj.set(nd.id, []);
  }
  for (const edge of raw.edges) {
    const lines = edge.metadata?.lines || [];
    adj.get(edge.source)?.push({ neighbor: edge.target, lines });
    adj.get(edge.target)?.push({ neighbor: edge.source, lines });
  }

  // Build DAG edges — use geographic X to determine direction (left to right)
  const nodeX = new Map();
  for (const nd of raw.nodes) {
    nodeX.set(nd.id, nd.metadata?.x ?? 0);
  }

  const dagEdges = [];
  const edgeSet = new Set();
  for (const edge of raw.edges) {
    const sx = nodeX.get(edge.source) ?? 0;
    const tx = nodeX.get(edge.target) ?? 0;
    // Direction: left to right (higher X = later)
    let from = edge.source, to = edge.target;
    if (sx > tx) { from = edge.target; to = edge.source; }
    // Avoid duplicate edges
    const key = `${from}→${to}`;
    if (!edgeSet.has(key)) {
      edgeSet.add(key);
      dagEdges.push([from, to]);
    }
  }

  // Build routes by tracing each line through its edges
  const routes = [];
  for (const line of raw.lines) {
    // Find all edges belonging to this line
    const lineEdges = raw.edges.filter(e => e.metadata?.lines?.includes(line.id));
    if (lineEdges.length === 0) continue;

    // Build adjacency for this line only
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

    // Find endpoints (degree 1 in this line's subgraph)
    const endpoints = [...lineNodes].filter(id => (lineAdj.get(id)?.length ?? 0) === 1);

    if (endpoints.length >= 2) {
      // Trace from leftmost endpoint
      endpoints.sort((a, b) => (nodeX.get(a) ?? 0) - (nodeX.get(b) ?? 0));
      const start = endpoints[0];
      const path = [start];
      const visited = new Set([start]);
      let current = start;
      while (true) {
        const neighbors = (lineAdj.get(current) || []).filter(n => !visited.has(n));
        if (neighbors.length === 0) break;
        current = neighbors[0];
        visited.add(current);
        path.push(current);
      }

      routes.push({
        id: line.id,
        cls: line.id.toLowerCase().replace(/\s+/g, '_'),
        nodes: path,
      });
    }
  }

  // Build fixture
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
  console.log(`✓ ${slug}: ${fixture.dag.nodes.length} stations, ${fixture.dag.edges.length} edges, ${routes.length} lines → ${outPath}`);
}
