// elk.mjs — adapter that runs ELK (Eclipse Layout Kernel) on a bench
// fixture and returns the canonical layout shape {nodes, edges, routes, meta}.
//
// Uses ELK's actual edge routing (sections with bend points) for a fair
// comparison against dag-map's routed polylines.

import ELK from 'elkjs/lib/elk.bundled.js';

const elk = new ELK();

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

  const layerMap = computeLayers(dag.nodes, dag.edges);

  const nodes = result.children.map((c) => ({
    id: c.id,
    x: c.x + c.width / 2,
    y: c.y + c.height / 2,
    layer: layerMap.get(c.id) ?? 0,
  }));

  const edges = dag.edges.map(([s, t]) => [s, t]);

  // Build node position map for fallback
  const posMap = new Map(nodes.map((n) => [n.id, { x: n.x, y: n.y }]));

  // Build routes using ELK's actual edge sections with bend points
  const routes = result.edges.map((e, i) => {
    const [s, t] = dag.edges[i];
    const points = [];

    if (e.sections && e.sections.length > 0) {
      for (const section of e.sections) {
        points.push({ x: section.startPoint.x, y: section.startPoint.y });
        if (section.bendPoints) {
          for (const bp of section.bendPoints) {
            points.push({ x: bp.x, y: bp.y });
          }
        }
        points.push({ x: section.endPoint.x, y: section.endPoint.y });
      }
    } else {
      // Fallback to straight line
      points.push(posMap.get(s));
      points.push(posMap.get(t));
    }

    return {
      id: `e${i}`,
      nodes: [s, t],
      points,
    };
  });

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
