// metrics.mjs — compute layout quality metrics from a layoutMetro result.

import { buildGraph, topoSortAndRank } from '../../dag-map/src/graph-utils.js';
import { countCrossings, buildLayers } from '../../dag-map/src/strategies/crossing-utils.js';

/**
 * Compute metrics for a layout result.
 *
 * @param {object} dag - { nodes, edges }
 * @param {object} layout - layoutMetro result
 * @returns {object} metrics
 */
export function computeMetrics(dag, layout) {
  const positions = layout.positions;
  const metrics = {};

  // 1. Crossing count (on node positions, between layers)
  const { childrenOf, parentsOf } = buildGraph(dag.nodes, dag.edges);
  const { rank, maxRank } = topoSortAndRank(dag.nodes, childrenOf, parentsOf);
  const layers = buildLayers(dag.nodes.map(n => n.id), rank, maxRank);
  // Sort layers by actual Y position
  for (const layerNodes of layers) {
    layerNodes.sort((a, b) => (positions.get(a)?.y ?? 0) - (positions.get(b)?.y ?? 0));
  }
  metrics.crossings = countCrossings(layers, childrenOf);

  // 2. Edge overlap (edges sharing identical rounded Y at both endpoints)
  const edgeKeys = new Map();
  for (const [fromId, toId] of dag.edges) {
    const u = positions.get(fromId);
    const v = positions.get(toId);
    if (!u || !v) continue;
    const key = `${Math.round(u.y)},${Math.round(v.y)}`;
    edgeKeys.set(key, (edgeKeys.get(key) || 0) + 1);
  }
  let overlaps = 0;
  for (const count of edgeKeys.values()) {
    if (count > 1) overlaps += count * (count - 1) / 2;
  }
  metrics.overlaps = overlaps;

  // 3. Direction changes (Y-reversals along routes)
  let dirChanges = 0;
  if (layout.routes) {
    for (const route of layout.routes) {
      const ys = route.nodes.map(id => positions.get(id)?.y ?? 0);
      let prevDy = 0;
      for (let i = 1; i < ys.length; i++) {
        const dy = ys[i] - ys[i - 1];
        if (Math.abs(dy) > 0.5 && Math.abs(prevDy) > 0.5) {
          if ((prevDy > 0 && dy < 0) || (prevDy < 0 && dy > 0)) {
            dirChanges++;
          }
        }
        if (Math.abs(dy) > 0.5) prevDy = dy;
      }
    }
  }
  metrics.directionChanges = dirChanges;

  // 4. Trunk straightness (Y variance of trunk nodes)
  if (layout.routes && layout.routes[0]) {
    const trunkYs = layout.routes[0].nodes.map(id => positions.get(id)?.y ?? 0);
    const mean = trunkYs.reduce((a, b) => a + b, 0) / trunkYs.length;
    const variance = trunkYs.reduce((a, y) => a + (y - mean) ** 2, 0) / trunkYs.length;
    metrics.trunkVariance = Math.round(variance * 100) / 100;
  } else {
    metrics.trunkVariance = 0;
  }

  // 5. Total edge length
  let totalEdgeLen = 0;
  for (const [fromId, toId] of dag.edges) {
    const u = positions.get(fromId);
    const v = positions.get(toId);
    if (!u || !v) continue;
    totalEdgeLen += Math.sqrt((v.x - u.x) ** 2 + (v.y - u.y) ** 2);
  }
  metrics.totalEdgeLength = Math.round(totalEdgeLen);

  // 6. Bounding box area
  metrics.width = Math.round(layout.width);
  metrics.height = Math.round(layout.height);
  metrics.area = metrics.width * metrics.height;

  return metrics;
}
