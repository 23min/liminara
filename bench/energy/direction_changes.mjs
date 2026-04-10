// E_direction_changes — penalizes Y-direction reversals along routes.
//
// A route path that goes up-down-up has 2 direction changes. Straight
// paths have 0. Fewer direction changes = cleaner, more readable layout.
//
// For each route, count the number of times the Y-direction reverses
// between consecutive segments.

export function E_direction_changes(layout) {
  let total = 0;

  for (const route of layout.routes) {
    if (route.points.length < 3) continue;

    let prevDy = route.points[1].y - route.points[0].y;
    for (let i = 2; i < route.points.length; i++) {
      const dy = route.points[i].y - route.points[i - 1].y;
      // Direction change: sign of dy flips (and both are non-trivial)
      if (Math.abs(prevDy) > 0.5 && Math.abs(dy) > 0.5) {
        if ((prevDy > 0 && dy < 0) || (prevDy < 0 && dy > 0)) {
          total++;
        }
      }
      if (Math.abs(dy) > 0.5) prevDy = dy;
    }
  }

  return total;
}
