// dagre.mjs — adapter that runs dagre on a bench fixture and returns
// the canonical layout shape {nodes, edges, routes, meta} that the
// energy function expects.
//
// Dagre is synchronous and deterministic for the same input.

import dagre from '@dagrejs/dagre';

/**
 * Layout a fixture using dagre and return the canonical bench layout shape.
 * Returns an error object instead of throwing on failure.
 * @param {Object} fixture - {id, dag: {nodes, edges}, theme, opts}
 * @returns {{ nodes, edges, routes, meta } | { error: string }}
 */
export function layoutWithDagre(fixture) {
  try {
    return _layout(fixture);
  } catch (err) {
    return { error: err.message, nodes: [], edges: [], routes: [], meta: { engine: 'dagre' } };
  }
}

function _layout(fixture) {
  const { dag } = fixture;
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', nodesep: 30, ranksep: 50 });
  g.setDefaultEdgeLabel(() => ({}));

  for (const n of dag.nodes) {
    g.setNode(n.id, { label: n.label || n.id, width: 40, height: 20 });
  }

  for (const [s, t] of dag.edges) {
    g.setEdge(s, t);
  }

  dagre.layout(g);

  // Build canonical nodes with layer from dagre rank
  const nodes = dag.nodes.map((n) => {
    const info = g.node(n.id);
    return {
      id: n.id,
      x: info.x,
      y: info.y,
      layer: info.rank ?? 0,
    };
  });

  const edges = dag.edges.map(([s, t]) => [s, t]);

  // Build routes — one route per edge with start/end points
  const posMap = new Map(nodes.map((n) => [n.id, { x: n.x, y: n.y }]));
  const routes = edges.map(([s, t], i) => ({
    id: `e${i}`,
    nodes: [s, t],
    points: [posMap.get(s), posMap.get(t)],
  }));

  return { nodes, edges, routes, meta: { engine: 'dagre' } };
}
