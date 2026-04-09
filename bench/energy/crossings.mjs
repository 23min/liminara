// E_crossings — number of proper edge-edge crossings among all rendered
// route polyline segments.
//
// Segments that share an endpoint are NOT counted (they merely touch, they
// do not cross). Consecutive segments inside the same route always share an
// endpoint, so they are automatically excluded.
//
// This is O(S^2) in the total number of segments which is fine for bench
// fixtures up to a few hundred segments.

function cross(ox, oy, ax, ay, bx, by) {
  return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox);
}

function samePoint(p, q) {
  return p.x === q.x && p.y === q.y;
}

function segmentsProperlyIntersect(p1, p2, p3, p4) {
  if (samePoint(p1, p3) || samePoint(p1, p4) || samePoint(p2, p3) || samePoint(p2, p4)) {
    return false;
  }
  const d1 = cross(p3.x, p3.y, p4.x, p4.y, p1.x, p1.y);
  const d2 = cross(p3.x, p3.y, p4.x, p4.y, p2.x, p2.y);
  const d3 = cross(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
  const d4 = cross(p1.x, p1.y, p2.x, p2.y, p4.x, p4.y);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
         ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

export function E_crossings(layout, _cfg) {
  const segs = [];
  for (const route of layout.routes) {
    const pts = route.points;
    if (!pts) continue;
    for (let i = 0; i < pts.length - 1; i++) {
      segs.push([pts[i], pts[i + 1]]);
    }
  }
  let count = 0;
  for (let i = 0; i < segs.length; i++) {
    for (let j = i + 1; j < segs.length; j++) {
      if (segmentsProperlyIntersect(segs[i][0], segs[i][1], segs[j][0], segs[j][1])) {
        count++;
      }
    }
  }
  return count;
}
