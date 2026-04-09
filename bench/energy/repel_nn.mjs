// E_repel_nn — node-node repulsion. For every pair of nodes (i, j) whose
// Euclidean distance d is strictly less than `repel_threshold_px`, we add
// ((threshold - d) / threshold)^2. That is 0 at d = threshold and 1 at
// d = 0, strictly monotone in d (and equivalently in 1/d over the active
// range), and BOUNDED at 1 per pair — so the whole term never exceeds
// n*(n-1)/2 and the GA's scalar fitness stays in a comparable range to
// the other quadratic terms even when nodes end up coincident.
//
// Earlier versions used (threshold/d - 1)^2, which has a 1/d singularity
// at d=0 that the epsilon floor turned into a ~1e15 spike whenever dag-map
// placed two nodes at the same point. That cliff dominated the scalar sum
// and broke the regression guard on the GA runner.

export function E_repel_nn(layout, cfg) {
  const threshold = cfg.repel_threshold_px;
  const nodes = layout.nodes;
  if (!nodes || nodes.length < 2) return 0;

  let total = 0;
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i];
      const b = nodes[j];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const d = Math.hypot(dx, dy);
      if (d >= threshold) continue;
      const deficit = (threshold - d) / threshold;
      total += deficit * deficit;
    }
  }
  return total;
}
