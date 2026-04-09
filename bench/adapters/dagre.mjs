// dagre.mjs — adapter that runs dagre on a bench fixture and returns
// the canonical layout shape {nodes, edges, routes, meta} that the
// energy function expects.
//
// Uses dagre's actual edge routing points (not just straight lines)
// for a fair comparison against dag-map's routed polylines.

import dagre from '@dagrejs/dagre';

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

  // Build routes using dagre's actual edge bend points
  const routes = edges.map(([s, t], i) => {
    const edgeInfo = g.edge(s, t);
    const points = edgeInfo?.points
      ? edgeInfo.points.map((p) => ({ x: p.x, y: p.y }))
      : [
          { x: g.node(s).x, y: g.node(s).y },
          { x: g.node(t).x, y: g.node(t).y },
        ];
    return {
      id: `e${i}`,
      nodes: [s, t],
      points,
    };
  });

  return { nodes, edges, routes, meta: { engine: 'dagre' } };
}
