// E_overlap — penalizes edges that coincide (same start+end Y positions).
//
// Two edges overlap when they share the same Y at both endpoints,
// making them visually indistinguishable. This happens when multiple
// edges pass through the same nodes at the same Y position.
//
// penalty = number of edge pairs with identical (y_start, y_end)

export function E_overlap(layout) {
  const byId = new Map(layout.nodes.map((n) => [n.id, n]));

  // Build a key for each edge based on its endpoint Y values
  const edgeKeys = new Map(); // key → count
  for (const [fromId, toId] of layout.edges) {
    const u = byId.get(fromId);
    const v = byId.get(toId);
    if (!u || !v) continue;
    // Round to 1px to catch near-coincidence
    const key = `${Math.round(u.y)},${Math.round(v.y)}`;
    edgeKeys.set(key, (edgeKeys.get(key) || 0) + 1);
  }

  // Count overlapping pairs: if 3 edges share the same key, that's 3 choose 2 = 3 pairs
  let total = 0;
  for (const count of edgeKeys.values()) {
    if (count > 1) {
      total += count * (count - 1) / 2;
    }
  }

  return total;
}
