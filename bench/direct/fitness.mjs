// fitness.mjs — evaluate a direct-position layout against quality rules.
//
// Input: positions Map<nodeId, {x, y}>, edges [[from, to]]
// Output: { score, terms, violations }
//
// Every rule is a measurable criterion. The weighted sum is the fitness.
// Lower is better.

/**
 * @param {Map<string, {x: number, y: number}>} positions
 * @param {Array<[string, string]>} edges
 * @param {object} weights
 * @returns {{ score: number, terms: object, violations: string[] }}
 */
export function evaluateLayout(positions, edges, weights) {
  const violations = [];
  const byId = positions;

  // ── Hard constraint: left-to-right flow ──
  // Every edge must have dx > 0
  let flowViolations = 0;
  for (const [from, to] of edges) {
    const pf = byId.get(from), pt = byId.get(to);
    if (!pf || !pt) continue;
    if (pt.x <= pf.x) flowViolations++;
  }
  if (flowViolations > 0) {
    violations.push(`${flowViolations} edges violate left-to-right flow`);
  }

  // ── Edge crossings (actual line segment intersections) ──
  const segments = edges.map(([f, t]) => {
    const pf = byId.get(f), pt = byId.get(t);
    return pf && pt ? { x1: pf.x, y1: pf.y, x2: pt.x, y2: pt.y } : null;
  }).filter(Boolean);

  let crossings = 0;
  for (let i = 0; i < segments.length; i++) {
    for (let j = i + 1; j < segments.length; j++) {
      if (segmentsIntersect(segments[i], segments[j])) crossings++;
    }
  }

  // ── Edge overlap (edges with same Y at both endpoints) ──
  const edgeKeys = new Map();
  for (const s of segments) {
    const key = `${Math.round(s.y1)},${Math.round(s.y2)}`;
    edgeKeys.set(key, (edgeKeys.get(key) || 0) + 1);
  }
  let overlap = 0;
  for (const count of edgeKeys.values()) {
    if (count > 1) overlap += count * (count - 1) / 2;
  }

  // ── Direction changes (Y zig-zag along paths) ──
  // Build adjacency for path tracing
  const children = new Map();
  for (const [f, t] of edges) {
    if (!children.has(f)) children.set(f, []);
    children.get(f).push(t);
  }
  let directionChanges = 0;
  // For each node with multiple children, check if paths zig-zag
  for (const [from, to] of edges) {
    const pf = byId.get(from), pt = byId.get(to);
    if (!pf || !pt) continue;
    const kids = children.get(to) || [];
    for (const grandchild of kids) {
      const pg = byId.get(grandchild);
      if (!pg) continue;
      const dy1 = pt.y - pf.y;
      const dy2 = pg.y - pt.y;
      if (Math.abs(dy1) > 1 && Math.abs(dy2) > 1 && dy1 * dy2 < 0) {
        directionChanges++;
      }
    }
  }

  // ── Node separation (too close — proportional penalty) ──
  const nodeIds = [...byId.keys()];
  const minDist = 40;
  let nodeTooClose = 0;
  for (let i = 0; i < nodeIds.length; i++) {
    for (let j = i + 1; j < nodeIds.length; j++) {
      const a = byId.get(nodeIds[i]), b = byId.get(nodeIds[j]);
      const dx = a.x - b.x, dy = a.y - b.y;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d < minDist) {
        // Proportional: closer = worse (not just a count)
        nodeTooClose += (minDist - d) / minDist;
      }
    }
  }

  // ── Edge length (shorter is better, normalized) ──
  let totalEdgeLength = 0;
  for (const s of segments) {
    const dx = s.x2 - s.x1, dy = s.y2 - s.y1;
    totalEdgeLength += Math.sqrt(dx * dx + dy * dy);
  }
  const avgEdgeLength = segments.length > 0 ? totalEdgeLength / segments.length : 0;
  const edgeLengthPenalty = avgEdgeLength / 100; // normalize to ~1-5 range

  // ── Angular resolution (edges from same node should fan out) ──
  let angularPenalty = 0;
  for (const nodeId of nodeIds) {
    const p = byId.get(nodeId);
    const neighbors = [];
    for (const [f, t] of edges) {
      if (f === nodeId) neighbors.push(byId.get(t));
      if (t === nodeId) neighbors.push(byId.get(f));
    }
    if (neighbors.length < 2) continue;
    // Compute angles to all neighbors
    const angles = neighbors.filter(Boolean).map(n => Math.atan2(n.y - p.y, n.x - p.x));
    angles.sort((a, b) => a - b);
    // Check minimum angle between adjacent edges
    for (let i = 0; i < angles.length; i++) {
      const next = (i + 1) % angles.length;
      let diff = angles[next] - angles[i];
      if (i === angles.length - 1) diff += 2 * Math.PI;
      if (diff < 0.2) angularPenalty++; // less than ~11 degrees
    }
  }

  // ── Slope (prefer horizontal edges) ──
  let slopePenalty = 0;
  for (const s of segments) {
    const dx = Math.abs(s.x2 - s.x1) || 1;
    const dy = Math.abs(s.y2 - s.y1);
    slopePenalty += (dy / dx); // 0 = horizontal, 1 = 45 degrees
  }

  // ── Layer alignment: same-depth nodes should have similar X ──
  // Group nodes by topological depth and penalize X variance within groups
  const depthGroups = new Map();
  for (const [fromId, toId] of edges) {
    // Use simple edge-counting depth: sources are depth 0
    // (already computed by caller if available, fallback to X-order)
  }
  // Approximate: group by X-quartile (nodes at similar X are same "layer")
  const allX = nodeIds.map(id => byId.get(id).x).sort((a, b) => a - b);
  const xRange = (allX[allX.length - 1] - allX[0]) || 1;
  const bucketWidth = xRange / Math.max(Math.ceil(nodeIds.length / 3), 2);
  const xBuckets = new Map();
  for (const id of nodeIds) {
    const x = byId.get(id).x;
    const bucket = Math.floor((x - allX[0]) / bucketWidth);
    if (!xBuckets.has(bucket)) xBuckets.set(bucket, []);
    xBuckets.get(bucket).push(x);
  }
  let layerAlignment = 0;
  for (const [, xs] of xBuckets) {
    if (xs.length < 2) continue;
    const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
    for (const x of xs) {
      layerAlignment += Math.abs(x - mean) / xRange; // normalized
    }
  }

  // ── Path straightness: A→B→C should be close to collinear ──
  let pathBend = 0;
  for (const [from, to] of edges) {
    const pt = byId.get(to);
    if (!pt) continue;
    for (const grandchild of (children.get(to) || [])) {
      const pf = byId.get(from), pg = byId.get(grandchild);
      if (!pf || !pg) continue;
      // Angle at middle node (to): deviation from straight line
      const dx1 = pt.x - pf.x, dy1 = pt.y - pf.y;
      const dx2 = pg.x - pt.x, dy2 = pg.y - pt.y;
      const len1 = Math.sqrt(dx1 * dx1 + dy1 * dy1) || 1;
      const len2 = Math.sqrt(dx2 * dx2 + dy2 * dy2) || 1;
      // Cross product gives sin of angle — small = straight
      const cross = Math.abs((dx1 / len1) * (dy2 / len2) - (dy1 / len1) * (dx2 / len2));
      pathBend += cross;
    }
  }

  // ── Vertical balance: center of mass near vertical center ──
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const p of byId.values()) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  const centerY = (minY + maxY) / 2;
  let sumY = 0;
  for (const p of byId.values()) sumY += p.y;
  const massY = sumY / nodeIds.length;
  const verticalBalance = Math.abs(massY - centerY) / ((maxY - minY) || 1);

  // ── Edge length uniformity: low variance is better ──
  let edgeLengthVar = 0;
  if (segments.length > 1) {
    const lengths = segments.map(s => {
      const dx = s.x2 - s.x1, dy = s.y2 - s.y1;
      return Math.sqrt(dx * dx + dy * dy);
    });
    const mean = lengths.reduce((a, b) => a + b, 0) / lengths.length;
    edgeLengthVar = lengths.reduce((a, l) => a + (l - mean) ** 2, 0) / lengths.length;
    edgeLengthVar = Math.sqrt(edgeLengthVar) / (mean || 1); // coefficient of variation
  }

  // ── Compactness (area used) ──
  const area = (maxX - minX) * (maxY - minY);
  const compactness = area / (nodeIds.length * 1000);

  const terms = {
    flow_violations: flowViolations,
    crossings,
    overlap,
    direction_changes: directionChanges,
    node_too_close: nodeTooClose,
    edge_length: edgeLengthPenalty,
    angular: angularPenalty,
    slope: slopePenalty,
    layer_alignment: layerAlignment,
    path_bend: pathBend,
    vertical_balance: verticalBalance,
    edge_uniformity: edgeLengthVar,
    compactness,
  };

  let score = 0;
  for (const [name, val] of Object.entries(terms)) {
    score += (weights[name] ?? 0) * val;
  }

  return { score, terms, violations };
}

function segmentsIntersect(a, b) {
  // Skip shared endpoints
  if ((Math.abs(a.x1 - b.x1) < 0.5 && Math.abs(a.y1 - b.y1) < 0.5) ||
      (Math.abs(a.x1 - b.x2) < 0.5 && Math.abs(a.y1 - b.y2) < 0.5) ||
      (Math.abs(a.x2 - b.x1) < 0.5 && Math.abs(a.y2 - b.y1) < 0.5) ||
      (Math.abs(a.x2 - b.x2) < 0.5 && Math.abs(a.y2 - b.y2) < 0.5)) {
    return false;
  }

  const d1x = a.x2 - a.x1, d1y = a.y2 - a.y1;
  const d2x = b.x2 - b.x1, d2y = b.y2 - b.y1;
  const cross = d1x * d2y - d1y * d2x;
  if (Math.abs(cross) < 1e-10) return false;

  const dx = b.x1 - a.x1, dy = b.y1 - a.y1;
  const t = (dx * d2y - dy * d2x) / cross;
  const u = (dx * d1y - dy * d1x) / cross;

  return t > 0.01 && t < 0.99 && u > 0.01 && u < 0.99;
}
