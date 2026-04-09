// E_monotone — penalizes non-monotone X progression along rendered route
// polylines. Each segment that retreats in x contributes the square of its
// retreat distance. Vertical or forward segments contribute 0.
//
// Rationale: the hard invariant (rule 1) already rejects layouts where an
// edge is not forward-only. Rule 2 forces topological x. This term is the
// soft counterpart: it keeps *rendered polylines* from curling back on
// themselves inside a single route, which is a different failure mode than
// an illegal edge direction.

export function E_monotone(layout, _cfg) {
  let total = 0;
  for (const route of layout.routes) {
    const pts = route.points;
    if (!pts || pts.length < 2) continue;
    for (let i = 0; i < pts.length - 1; i++) {
      const dx = pts[i + 1].x - pts[i].x;
      if (dx < 0) {
        total += dx * dx;
      }
    }
  }
  return total;
}
