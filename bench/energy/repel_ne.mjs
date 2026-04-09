// E_repel_ne — node-edge repulsion as a label-crowding proxy. For every
// (node, rendered segment) pair where the node is NOT one of that segment's
// endpoints, we compute the closest-point distance d from the node to the
// segment. If d < `repel_threshold_px`, add ((threshold - d) / threshold)^2.
//
// Same bounded quadratic form as `repel_nn`: saturates at 1 per pair when
// the node sits directly on the segment. The earlier `1/d`-based formula
// produced a ~1e15 spike on coincident points that drowned every other
// term and broke the regression guard on the GA runner.
//
// Endpoint-touching pairs are skipped on purpose: an edge legitimately
// meets its endpoint nodes, and penalizing that would make every layout
// bad.

function samePoint(a, b) {
  return a.x === b.x && a.y === b.y;
}

function closestDistanceToSegment(px, py, s0, s1) {
  const vx = s1.x - s0.x;
  const vy = s1.y - s0.y;
  const wx = px - s0.x;
  const wy = py - s0.y;
  const vv = vx * vx + vy * vy;
  if (vv === 0) {
    return Math.hypot(wx, wy);
  }
  let t = (wx * vx + wy * vy) / vv;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  const cx = s0.x + t * vx;
  const cy = s0.y + t * vy;
  return Math.hypot(px - cx, py - cy);
}

export function E_repel_ne(layout, cfg) {
  const threshold = cfg.repel_threshold_px;
  const nodes = layout.nodes;
  const routes = layout.routes;
  if (!nodes || nodes.length === 0 || !routes || routes.length === 0) return 0;

  const segs = [];
  for (const r of routes) {
    const pts = r.points;
    if (!pts) continue;
    for (let i = 0; i < pts.length - 1; i++) {
      segs.push([pts[i], pts[i + 1]]);
    }
  }
  if (segs.length === 0) return 0;

  let total = 0;
  for (const n of nodes) {
    const np = { x: n.x, y: n.y };
    for (const [s0, s1] of segs) {
      if (samePoint(np, s0) || samePoint(np, s1)) continue;
      const d = closestDistanceToSegment(n.x, n.y, s0, s1);
      if (d >= threshold) continue;
      const deficit = (threshold - d) / threshold;
      total += deficit * deficit;
    }
  }
  return total;
}
