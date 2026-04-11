// mlcm-metrics.mjs — MLCM-specific layout quality metrics.
//
// These measure what the metro-map literature cares about:
// station crossings, between-station crossings, bundle coherence,
// and monotonicity per line.

/**
 * Compute MLCM metrics from a layoutMetro result.
 *
 * @param {object} dag - { nodes, edges }
 * @param {object} layout - layoutMetro result (must include routes, positions)
 * @returns {object} MLCM metrics
 */
export function computeMLCMMetrics(dag, layout) {
  const { positions, routes, nodeRoute } = layout;
  if (!routes || routes.length === 0) return { stationCrossings: 0, betweenCrossings: 0, bundleCoherence: 1, monotonicityViolations: 0, bendsPerLine: 0 };

  const metrics = {};

  // 1. Station crossings — at a shared station, do lines cross?
  // Two lines cross at a station if their track order reverses
  // compared to an adjacent station.
  let stationCrossings = 0;
  const stationRoutes = new Map(); // nodeId → [routeIdx] sorted by Y offset
  for (const nd of dag.nodes) {
    const nodeId = nd.id;
    const routesThrough = [];
    for (let ri = 0; ri < routes.length; ri++) {
      if (routes[ri].nodes.includes(nodeId)) {
        const pos = positions.get(nodeId);
        routesThrough.push({ ri, y: pos?.y ?? 0 });
      }
    }
    if (routesThrough.length > 1) {
      routesThrough.sort((a, b) => a.y - b.y);
      stationRoutes.set(nodeId, routesThrough.map(r => r.ri));
    }
  }

  // Count inversions between adjacent shared stations
  const sharedStations = [...stationRoutes.keys()];
  for (let i = 0; i < sharedStations.length - 1; i++) {
    const orderA = stationRoutes.get(sharedStations[i]);
    const orderB = stationRoutes.get(sharedStations[i + 1]);
    if (!orderA || !orderB) continue;

    // Find common routes
    const common = orderA.filter(r => orderB.includes(r));
    if (common.length < 2) continue;

    // Count inversions in the ordering of common routes
    const posA = new Map(common.map((r, idx) => [r, orderA.indexOf(r)]));
    const posB = new Map(common.map((r, idx) => [r, orderB.indexOf(r)]));

    for (let j = 0; j < common.length; j++) {
      for (let k = j + 1; k < common.length; k++) {
        const ra = common[j], rb = common[k];
        if ((posA.get(ra) - posA.get(rb)) * (posB.get(ra) - posB.get(rb)) < 0) {
          stationCrossings++;
        }
      }
    }
  }
  metrics.stationCrossings = stationCrossings;

  // 2. Between-station crossings — do line segments cross between stations?
  let betweenCrossings = 0;
  const segments = []; // { ri, x1, y1, x2, y2 }
  for (let ri = 0; ri < routes.length; ri++) {
    const nodes = routes[ri].nodes;
    for (let i = 0; i < nodes.length - 1; i++) {
      const p = positions.get(nodes[i]);
      const q = positions.get(nodes[i + 1]);
      if (p && q) segments.push({ ri, x1: p.x, y1: p.y, x2: q.x, y2: q.y });
    }
  }
  for (let i = 0; i < segments.length; i++) {
    for (let j = i + 1; j < segments.length; j++) {
      if (segments[i].ri === segments[j].ri) continue;
      if (segmentsCross(segments[i], segments[j])) betweenCrossings++;
    }
  }
  metrics.betweenCrossings = betweenCrossings;

  // 3. Bundle coherence — same-class lines should be on adjacent tracks
  // Measured as: for each pair of same-class lines sharing a station,
  // are they on adjacent tracks?
  let coherentPairs = 0, totalPairs = 0;
  for (const [nodeId, order] of stationRoutes) {
    for (let j = 0; j < order.length; j++) {
      for (let k = j + 1; k < order.length; k++) {
        const clsA = routes[order[j]]?.cls;
        const clsB = routes[order[k]]?.cls;
        if (clsA && clsB && clsA === clsB) {
          totalPairs++;
          if (Math.abs(j - k) === 1) coherentPairs++;
        }
      }
    }
  }
  metrics.bundleCoherence = totalPairs > 0 ? coherentPairs / totalPairs : 1;

  // 4. Monotonicity violations — lines that move backward along X
  let monotonicityViolations = 0;
  for (const route of routes) {
    for (let i = 1; i < route.nodes.length; i++) {
      const prev = positions.get(route.nodes[i - 1]);
      const curr = positions.get(route.nodes[i]);
      if (prev && curr && curr.x <= prev.x) monotonicityViolations++;
    }
  }
  metrics.monotonicityViolations = monotonicityViolations;

  // 5. Bends per line — Y-direction reversals per route
  let totalBends = 0;
  for (const route of routes) {
    const ys = route.nodes.map(id => positions.get(id)?.y ?? 0);
    let prevDy = 0;
    for (let i = 1; i < ys.length; i++) {
      const dy = ys[i] - ys[i - 1];
      if (Math.abs(dy) > 0.5 && Math.abs(prevDy) > 0.5) {
        if ((prevDy > 0 && dy < 0) || (prevDy < 0 && dy > 0)) totalBends++;
      }
      if (Math.abs(dy) > 0.5) prevDy = dy;
    }
  }
  metrics.bendsPerLine = routes.length > 0 ? totalBends / routes.length : 0;
  metrics.totalBends = totalBends;

  return metrics;
}

function segmentsCross(s1, s2) {
  // Check if line segments (x1,y1)-(x2,y2) cross
  const d1 = direction(s2.x1, s2.y1, s2.x2, s2.y2, s1.x1, s1.y1);
  const d2 = direction(s2.x1, s2.y1, s2.x2, s2.y2, s1.x2, s1.y2);
  const d3 = direction(s1.x1, s1.y1, s1.x2, s1.y2, s2.x1, s2.y1);
  const d4 = direction(s1.x1, s1.y1, s1.x2, s1.y2, s2.x2, s2.y2);

  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) return true;

  return false;
}

function direction(ax, ay, bx, by, cx, cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}
