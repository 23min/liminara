// E_bend — sum of squared turning angles along each rendered route polyline.
//
// For every interior point P of a route polyline we measure the turning angle
// between the incoming segment (prev -> P) and the outgoing segment (P -> next).
// A straight-through point has angle 0. A 90-degree corner has angle pi/2.
// We penalize the square of the angle, then sum over all interior points across
// all routes.

export function E_bend(layout, _cfg) {
  let total = 0;
  for (const route of layout.routes) {
    const pts = route.points;
    if (!pts || pts.length < 3) continue;
    for (let i = 1; i < pts.length - 1; i++) {
      const a = pts[i - 1];
      const b = pts[i];
      const c = pts[i + 1];
      const ux = b.x - a.x;
      const uy = b.y - a.y;
      const vx = c.x - b.x;
      const vy = c.y - b.y;
      const nu = Math.hypot(ux, uy);
      const nv = Math.hypot(vx, vy);
      if (nu === 0 || nv === 0) continue;
      let cos = (ux * vx + uy * vy) / (nu * nv);
      if (cos > 1) cos = 1;
      if (cos < -1) cos = -1;
      const angle = Math.acos(cos);
      total += angle * angle;
    }
  }
  return total;
}
