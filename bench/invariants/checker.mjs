// Hard-invariant checker for rules 1, 2, 7.
//
// A rejected layout never reaches the energy function. Each rejection returns
// { rejected: true, rule, detail } so callers can surface why.
//
// - Rule 1: forward-only edges. Every edge (u, v) must satisfy
//   layer_v > layer_u AND rendered x_v > x_u.
// - Rule 2: topological X. If two nodes have different layers then their
//   x positions must agree with their layer order.
// - Rule 7: determinism. Two renders of the same genome + fixture must be
//   byte-identical; we compare JSON serializations.

export function checkInvariants(layout) {
  const byId = new Map(layout.nodes.map((n) => [n.id, n]));

  for (const [fromId, toId] of layout.edges) {
    const u = byId.get(fromId);
    const v = byId.get(toId);
    if (!u || !v) {
      return { rejected: true, rule: 'forward-only', detail: `edge references unknown node: ${fromId} -> ${toId}` };
    }
    if (!(v.layer > u.layer)) {
      return { rejected: true, rule: 'forward-only', detail: `edge ${fromId} -> ${toId} is not forward in layer (${u.layer} -> ${v.layer})` };
    }
    if (!(v.x > u.x)) {
      return { rejected: true, rule: 'forward-only', detail: `edge ${fromId} -> ${toId} is not forward in x (${u.x} -> ${v.x})` };
    }
  }

  for (let i = 0; i < layout.nodes.length; i++) {
    for (let j = i + 1; j < layout.nodes.length; j++) {
      const a = layout.nodes[i];
      const b = layout.nodes[j];
      if (a.layer === b.layer) continue;
      const layerOrder = Math.sign(b.layer - a.layer);
      const xOrder = Math.sign(b.x - a.x);
      if (xOrder !== 0 && xOrder !== layerOrder) {
        return {
          rejected: true,
          rule: 'topological-x',
          detail: `nodes ${a.id}(layer=${a.layer}, x=${a.x}) and ${b.id}(layer=${b.layer}, x=${b.x}) violate topological x order`,
        };
      }
    }
  }

  return null;
}

export function checkDeterminism(layoutA, layoutB) {
  const a = JSON.stringify(layoutA);
  const b = JSON.stringify(layoutB);
  if (a === b) return null;
  return {
    rejected: true,
    rule: 'determinism',
    detail: 'two renders of the same genome+fixture produced different layouts',
  };
}
