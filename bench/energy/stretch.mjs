// E_stretch — penalizes edges longer than their ideal topological length.
//
// ideal_length(u, v) = stretch_ideal_factor * (layer_v - layer_u) * layer_spacing
// penalty(u, v)      = max(0, (actual - ideal) / ideal)^2
// E_stretch          = sum over edges
//
// The penalty is normalized by ideal length so it is scale-invariant:
// a 10% excess penalizes the same regardless of absolute edge length.

export function E_stretch(layout, cfg) {
  const factor = cfg.stretch_ideal_factor;
  const spacing = cfg.layer_spacing;
  const byId = new Map(layout.nodes.map((n) => [n.id, n]));

  let total = 0;
  for (const [fromId, toId] of layout.edges) {
    const u = byId.get(fromId);
    const v = byId.get(toId);
    if (!u || !v) {
      throw new Error(`E_stretch: unknown node in edge ${fromId}->${toId}`);
    }
    const dLayer = Math.max(0, v.layer - u.layer);
    const ideal = factor * dLayer * spacing;
    if (ideal <= 0) continue; // same-layer edge, no stretch penalty
    const dx = v.x - u.x;
    const dy = v.y - u.y;
    const actual = Math.sqrt(dx * dx + dy * dy);
    const ratio = (actual - ideal) / ideal;
    if (ratio > 0) total += ratio * ratio;
  }
  return total;
}
