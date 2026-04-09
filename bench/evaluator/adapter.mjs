// adapter.mjs — projects dag-map's `layoutMetro` output into the canonical
// bench layout shape `{nodes, edges, routes, meta}` that every energy term
// and the hard-invariant checker consume.
//
// Layers come from longest-path topological rank using dag-map's own
// `topoSortAndRank`, so node layer values always match the semantics dag-map
// uses internally. Route polylines are built from the per-route node
// positions — the bench scores straight-line polylines between route
// waypoints, not the curved svg path strings, which keeps the projection
// deterministic and parser-free.

import { buildGraph, topoSortAndRank } from '../../dag-map/src/graph-utils.js';

export function projectLayout(dag, raw) {
  const { positions, routes } = raw;

  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);
  const { rank } = topoSortAndRank(dag.nodes, childrenOf, parentsOf);

  const nodes = dag.nodes.map((n) => {
    const p = positions.get(n.id);
    if (!p) {
      throw new Error(`projectLayout: dag-map layout is missing position for node "${n.id}"`);
    }
    return { id: n.id, x: p.x, y: p.y, layer: rank.get(n.id) ?? 0 };
  });

  const edges = dag.edges.map(([f, t]) => [f, t]);

  const routeShapes = routes.map((r, i) => {
    const points = r.nodes.map((id) => {
      const p = positions.get(id);
      if (!p) {
        throw new Error(`projectLayout: route "${r.id ?? i}" references unknown node "${id}"`);
      }
      return { x: p.x, y: p.y };
    });
    return { id: r.id ?? `r${i}`, nodes: r.nodes.slice(), points };
  });

  return { nodes, edges, routes: routeShapes, meta: {} };
}
