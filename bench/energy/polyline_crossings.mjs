// E_polyline_crossings — counts actual line segment intersections
// on the projected layout polylines (straight-line routes between
// node positions). This is the real visual crossing count, not the
// abstract layer-model crossing count.

/**
 * Test if two line segments (p1→p2) and (p3→p4) intersect.
 * Uses the cross-product orientation test.
 */
function segmentsIntersect(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y) {
  const d1x = p2x - p1x, d1y = p2y - p1y;
  const d2x = p4x - p3x, d2y = p4y - p3y;

  const cross = d1x * d2y - d1y * d2x;
  if (Math.abs(cross) < 1e-10) return false; // parallel

  const dx = p3x - p1x, dy = p3y - p1y;
  const t = (dx * d2y - dy * d2x) / cross;
  const u = (dx * d1y - dy * d1x) / cross;

  // Proper intersection: both parameters strictly between 0 and 1
  // (excludes shared endpoints)
  return t > 0.001 && t < 0.999 && u > 0.001 && u < 0.999;
}

/**
 * Count actual polyline crossings in the layout.
 *
 * @param {object} layout - { nodes, edges, routes }
 * @returns {number} crossing count
 */
export function E_polyline_crossings(layout) {
  const byId = new Map(layout.nodes.map(n => [n.id, n]));

  // Build all line segments from edges
  const segments = [];
  for (const [fromId, toId] of layout.edges) {
    const u = byId.get(fromId);
    const v = byId.get(toId);
    if (!u || !v) continue;
    segments.push({ x1: u.x, y1: u.y, x2: v.x, y2: v.y, edge: `${fromId}->${toId}` });
  }

  // Also include route polyline segments (if routes have intermediate points)
  for (const route of layout.routes) {
    if (!route.points || route.points.length < 2) continue;
    for (let i = 0; i < route.points.length - 1; i++) {
      const p = route.points[i];
      const q = route.points[i + 1];
      segments.push({ x1: p.x, y1: p.y, x2: q.x, y2: q.y, edge: `route-${route.id}-seg${i}` });
    }
  }

  // Count pairwise intersections
  let crossings = 0;
  for (let i = 0; i < segments.length; i++) {
    for (let j = i + 1; j < segments.length; j++) {
      const a = segments[i], b = segments[j];

      // Skip segments that share an endpoint (same node)
      if ((Math.abs(a.x1 - b.x1) < 0.1 && Math.abs(a.y1 - b.y1) < 0.1) ||
          (Math.abs(a.x1 - b.x2) < 0.1 && Math.abs(a.y1 - b.y2) < 0.1) ||
          (Math.abs(a.x2 - b.x1) < 0.1 && Math.abs(a.y2 - b.y1) < 0.1) ||
          (Math.abs(a.x2 - b.x2) < 0.1 && Math.abs(a.y2 - b.y2) < 0.1)) {
        continue;
      }

      if (segmentsIntersect(a.x1, a.y1, a.x2, a.y2, b.x1, b.y1, b.x2, b.y2)) {
        crossings++;
      }
    }
  }

  return crossings;
}
