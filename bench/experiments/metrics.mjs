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

  // 2. Route segment overlap — two routes traversing the same edge at the
  // same effective Y (accounting for track offsets at interchange stations).
  let overlaps = 0;
  if (layout.routes && layout.nodeRoutes && layout.lineGap) {
    const lineGap = layout.lineGap;
    const ta = layout.trackAssignment;

    // For each pair of consecutive nodes in each route, compute the
    // effective Y at both endpoints (node Y + track offset)
    const segKeys = new Map(); // "roundedY1,roundedY2" → count
    for (let ri = 0; ri < layout.routes.length; ri++) {
      const route = layout.routes[ri];
      for (let ni = 0; ni < route.nodes.length - 1; ni++) {
        const fromId = route.nodes[ni], toId = route.nodes[ni + 1];
        const u = positions.get(fromId), v = positions.get(toId);
        if (!u || !v) continue;

        // Compute offset at each node (same logic as path builder)
        function getOffset(nodeId) {
          const nr = layout.nodeRoutes.get(nodeId);
          if (!nr || nr.size <= 1) return 0;
          const stationTracks = ta?.get(nodeId);
          if (stationTracks && stationTracks.has(ri)) {
            return stationTracks.get(ri) * lineGap;
          }
          const sorted = [...nr].sort((a, b) => a - b);
          const trunkIdx = sorted.indexOf(0);
          const myIdx = sorted.indexOf(ri);
          if (myIdx === -1) return 0;
          if (trunkIdx >= 0) return (myIdx - trunkIdx) * lineGap;
          return (myIdx - (sorted.length - 1) / 2) * lineGap;
        }

        const y1 = Math.round(u.y + getOffset(fromId));
        const y2 = Math.round(v.y + getOffset(toId));
        const key = `${y1},${y2}`;
        if (!segKeys.has(key)) segKeys.set(key, new Set());
        segKeys.get(key).add(ri); // track which ROUTES, not segment count
      }
    }
    for (const routeSet of segKeys.values()) {
      const count = routeSet.size; // number of DIFFERENT routes at this Y pair
      if (count > 1) overlaps += count * (count - 1) / 2;
    }
  } else {
    // Fallback: count by DAG edges at same node Y
    const edgeKeys = new Map();
    for (const [fromId, toId] of dag.edges) {
      const u = positions.get(fromId), v = positions.get(toId);
      if (!u || !v) continue;
      const key = `${Math.round(u.y)},${Math.round(v.y)}`;
      edgeKeys.set(key, (edgeKeys.get(key) || 0) + 1);
    }
    for (const count of edgeKeys.values()) {
      if (count > 1) overlaps += count * (count - 1) / 2;
    }
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
