// E_channel — parallel-route separation between routes that run side by
// side. For every pair of segments (one from each of two different routes)
// whose x-projections overlap and whose direction vectors are roughly
// parallel, we measure the y-separation across their overlap. If the gap
// is smaller than `channel_min_separation_px`, we pay the squared deficit.
//
// The parallel-direction filter keeps this term from double-billing the
// `crossings` and `bend` terms: we only care about segments that are
// walking in roughly the same direction, which is exactly the "maze-wall"
// situation rule 8/11 worry about.

const PARALLEL_DOT = 0.9;

function dirAndLen(seg) {
  const dx = seg[1].x - seg[0].x;
  const dy = seg[1].y - seg[0].y;
  const len = Math.hypot(dx, dy);
  if (len === 0) return null;
  return { ux: dx / len, uy: dy / len, len };
}

function yAt(seg, x) {
  const x0 = seg[0].x;
  const x1 = seg[1].x;
  if (x0 === x1) return seg[0].y;
  const t = (x - x0) / (x1 - x0);
  return seg[0].y + t * (seg[1].y - seg[0].y);
}

function overlap(a, b) {
  const aMin = Math.min(a[0].x, a[1].x);
  const aMax = Math.max(a[0].x, a[1].x);
  const bMin = Math.min(b[0].x, b[1].x);
  const bMax = Math.max(b[0].x, b[1].x);
  const lo = Math.max(aMin, bMin);
  const hi = Math.min(aMax, bMax);
  if (hi <= lo) return null;
  return { lo, hi };
}

export function E_channel(layout, cfg) {
  const minGap = cfg.channel_min_separation_px;
  const routes = layout.routes;
  if (!routes || routes.length < 2) return 0;

  // Flatten to (segments, routeId) once.
  const bundles = [];
  for (const r of routes) {
    const segs = [];
    const pts = r.points;
    if (!pts) {
      bundles.push(segs);
      continue;
    }
    for (let i = 0; i < pts.length - 1; i++) {
      segs.push([pts[i], pts[i + 1]]);
    }
    bundles.push(segs);
  }

  let total = 0;
  for (let i = 0; i < bundles.length; i++) {
    for (let j = i + 1; j < bundles.length; j++) {
      for (const a of bundles[i]) {
        const da = dirAndLen(a);
        if (!da) continue;
        for (const b of bundles[j]) {
          const db = dirAndLen(b);
          if (!db) continue;
          const dot = da.ux * db.ux + da.uy * db.uy;
          if (dot < PARALLEL_DOT) continue;
          const ov = overlap(a, b);
          if (!ov) continue;
          // Sample separation at the two overlap boundaries and take the min.
          const gapLo = Math.abs(yAt(a, ov.lo) - yAt(b, ov.lo));
          const gapHi = Math.abs(yAt(a, ov.hi) - yAt(b, ov.hi));
          const gap = Math.min(gapLo, gapHi);
          if (gap < minGap) {
            const deficit = minGap - gap;
            total += deficit * deficit;
          }
        }
      }
    }
  }
  return total;
}
