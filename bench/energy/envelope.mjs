// E_envelope — aspect-ratio deviation from a target ratio.
//
// We compare the log of the actual bounding-box aspect ratio to the log of
// the target ratio. Log-space keeps the penalty symmetric around the target:
// a layout that is 2x too wide and a layout that is 2x too tall receive the
// same penalty. The silhouette/diamond priorities of rules 13-14 show up in
// the *choice* of target ratio, not in this term's formula.
//
// Degenerate cases (zero width or zero height) floor the missing dimension
// at a 1-pixel minimum before computing the ratio. This produces a bounded
// but still-large log penalty instead of the 4-order-of-magnitude cliff the
// original DEGENERATE_PENALTY had, which drowned every other signal and
// broke the regression guard on the GA runner.

const MIN_DIMENSION_PX = 1;

export function E_envelope(layout, cfg) {
  if (!layout.nodes || layout.nodes.length === 0) return 0;

  let minX = Infinity,
    maxX = -Infinity,
    minY = Infinity,
    maxY = -Infinity;
  for (const n of layout.nodes) {
    if (n.x < minX) minX = n.x;
    if (n.x > maxX) maxX = n.x;
    if (n.y < minY) minY = n.y;
    if (n.y > maxY) maxY = n.y;
  }

  const width = Math.max(maxX - minX, MIN_DIMENSION_PX);
  const height = Math.max(maxY - minY, MIN_DIMENSION_PX);

  const target = cfg.envelope_target_ratio;
  const ratio = width / height;
  const diff = Math.log(ratio) - Math.log(target);
  return diff * diff;
}
