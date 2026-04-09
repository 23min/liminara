// elk.mjs — adapter that runs ELK (Eclipse Layout Kernel) on a bench
// fixture and returns the canonical layout shape {nodes, edges, routes, meta}.
//
// ELK is async. The JS port (elkjs) runs the layout in a worker-like
// environment. We use the synchronous/bundled variant for determinism.

import ELK from 'elkjs/lib/elk.bundled.js';

const elk = new ELK();

/**
 * Layout a fixture using ELK and return the canonical bench layout shape.
 * Returns an error object instead of throwing on failure.
 * @param {Object} fixture - {id, dag: {nodes, edges}, theme, opts}
 * @returns {Promise<{ nodes, edges, routes, meta } | { error: string }>}
 */
export async function layoutWithELK(fixture) {
  try {
    return await _layout(fixture);
  } catch (err) {
    return { error: err.message, nodes: [], edges: [], routes: [], meta: { engine: 'elk' } };
  }
}

async function _layout(fixture) {
  const { dag } = fixture;

  const graph = {
    id: 'root',
    layoutOptions: {
      'elk.algorithm': 'layered',
      'elk.direction': 'RIGHT',
      'elk.layered.spacing.nodeNodeBetweenLayers': '50',
      'elk.spacing.nodeNode': '30',
    },
    children: dag.nodes.map((n) => ({
      id: n.id,
      width: 40,
      height: 20,
    })),
    edges: dag.edges.map(([s, t], i) => ({
      id: `e${i}`,
      sources: [s],
      targets: [t],
    })),
  };

  const result = await elk.layout(graph);

  // Compute layers via topological rank (Kahn's algorithm)
  const layerMap = computeLayers(dag.nodes, dag.edges);

  const nodes = result.children.map((c) => ({
    id: c.id,
    x: c.x + c.width / 2,   // ELK gives top-left; center for consistency
    y: c.y + c.height / 2,
    layer: layerMap.get(c.id) ?? 0,
  }));

  const edges = dag.edges.map(([s, t]) => [s, t]);

  const posMap = new Map(nodes.map((n) => [n.id, { x: n.x, y: n.y }]));
  const routes = edges.map(([s, t], i) => ({
    id: `e${i}`,
    nodes: [s, t],
    points: [posMap.get(s), posMap.get(t)],
  }));

  return { nodes, edges, routes, meta: { engine: 'elk' } };
}

function computeLayers(nodes, edges) {
  const inDegree = new Map();
  const adj = new Map();
  for (const n of nodes) {
    inDegree.set(n.id, 0);
    adj.set(n.id, []);
  }
  for (const [s, t] of edges) {
    if (!inDegree.has(s) || !inDegree.has(t)) continue;
    inDegree.set(t, inDegree.get(t) + 1);
    adj.get(s).push(t);
  }

  const layer = new Map();
  const queue = [];
  for (const [id, deg] of inDegree) {
    if (deg === 0) {
      queue.push(id);
      layer.set(id, 0);
    }
  }

  while (queue.length > 0) {
    const cur = queue.shift();
    const curLayer = layer.get(cur);
    for (const next of adj.get(cur)) {
      const newDeg = inDegree.get(next) - 1;
      inDegree.set(next, newDeg);
      layer.set(next, Math.max(layer.get(next) ?? 0, curLayer + 1));
      if (newDeg === 0) queue.push(next);
    }
  }

  return layer;
}
