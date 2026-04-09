// graphml.mjs — parses GraphML files into the bench fixture shape
// {id, dag: {nodes, edges}, theme, opts}. Cyclic graphs are skipped.
//
// Uses a lightweight regex-based parser — GraphML from graphdrawing.org
// uses a simple flat structure without nested graphs or complex attributes.

import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

/**
 * Parse a GraphML XML string into a fixture, or return null if cyclic/invalid.
 * @param {string} xml - GraphML content
 * @param {string} id - fixture identifier (typically filename without extension)
 * @returns {{ id, dag: {nodes, edges}, theme, opts } | null}
 */
export function parseGraphML(xml, id) {
  // Check edge direction from graph element
  const graphMatch = xml.match(/<graph[^>]*edgedefault\s*=\s*"([^"]+)"/);
  if (!graphMatch || graphMatch[1] !== 'directed') {
    return null; // undirected or missing — not a DAG
  }

  // Extract nodes
  const nodeRegex = /<node\s+id\s*=\s*"([^"]+)"\s*\/?>/g;
  const nodes = [];
  const nodeIds = new Set();
  let m;
  while ((m = nodeRegex.exec(xml)) !== null) {
    const nodeId = m[1];
    if (!nodeIds.has(nodeId)) {
      nodeIds.add(nodeId);
      nodes.push({ id: nodeId, label: nodeId });
    }
  }

  if (nodes.length === 0) return null;

  // Extract edges
  const edgeRegex = /<edge\s+[^>]*source\s*=\s*"([^"]+)"\s+target\s*=\s*"([^"]+)"/g;
  const edges = [];
  while ((m = edgeRegex.exec(xml)) !== null) {
    edges.push([m[1], m[2]]);
  }

  // Check for cycles using topological sort (Kahn's algorithm)
  if (!isAcyclic(nodes, edges)) return null;

  return {
    id,
    dag: { nodes, edges },
    theme: 'cream',
    opts: {},
  };
}

function isAcyclic(nodes, edges) {
  const inDegree = new Map();
  const adj = new Map();
  for (const n of nodes) {
    inDegree.set(n.id, 0);
    adj.set(n.id, []);
  }
  for (const [s, t] of edges) {
    if (!inDegree.has(s) || !inDegree.has(t)) return false;
    inDegree.set(t, inDegree.get(t) + 1);
    adj.get(s).push(t);
  }

  const queue = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) queue.push(id);
  }

  let visited = 0;
  while (queue.length > 0) {
    const cur = queue.shift();
    visited++;
    for (const next of adj.get(cur)) {
      const newDeg = inDegree.get(next) - 1;
      inDegree.set(next, newDeg);
      if (newDeg === 0) queue.push(next);
    }
  }

  return visited === nodes.length;
}

/**
 * Load all .graphml files from a directory, skip cyclic graphs, return in
 * lexicographic filename order.
 * @param {string} dir - directory containing .graphml files
 * @param {{ onSkip?: (id: string, reason: string) => void }} opts
 * @returns {Promise<Array<{id, dag, theme, opts}>>}
 */
export async function loadGraphMLDir(dir, { onSkip } = {}) {
  const entries = await readdir(dir);
  const files = entries.filter((f) => f.endsWith('.graphml')).sort();

  const fixtures = [];
  for (const file of files) {
    const path = join(dir, file);
    const xml = await readFile(path, 'utf8');
    const id = file.replace(/\.graphml$/, '');
    const fixture = parseGraphML(xml, id);

    if (fixture === null) {
      if (onSkip) onSkip(id, 'cyclic, undirected, or empty graph');
      continue;
    }

    fixtures.push(fixture);
  }

  return fixtures;
}
