// dag-map-bundle.js — auto-generated, do not edit
(function() {
// --- route-bezier.js ---
// ================================================================
// route-bezier.js — Bezier S-curve routing (v5 style)
// ================================================================
// Cubic bezier S-curves for smooth, organic edge routing.
// Depart horizontal, curve through a C-shaped bend, arrive horizontal.
// The departure/arrival horizontal run length adapts to the dy/dx ratio.

/**
 * Generate a bezier S-curve path segment from (px, py) to (qx, qy).
 *
 * @param {number} px - source x
 * @param {number} py - source y
 * @param {number} qx - destination x
 * @param {number} qy - destination y
 * @param {number} _routeIdx - (unused, kept for API consistency with angularPath)
 * @param {number} _segIdx - (unused)
 * @param {number} _refY - (unused)
 * @returns {string} SVG path data (without leading M)
 */
function bezierPath(px, py, qx, qy, _routeIdx, _segIdx, _refY) {
  const dx = qx - px, dy = qy - py;
  if (Math.abs(dy) < 0.5) {
    return `L ${qx} ${qy}`;
  }

  const absDy = Math.abs(dy);
  const ratio = absDy / Math.max(dx, 1);

  let departLen, arriveLen;
  if (ratio < 0.4) {
    departLen = dx * 0.30;
    arriveLen = dx * 0.30;
  } else if (ratio < 0.8) {
    departLen = dx * 0.20;
    arriveLen = dx * 0.20;
  } else {
    departLen = dx * 0.12;
    arriveLen = dx * 0.12;
  }

  const x1 = px + departLen;
  const x2 = qx - arriveLen;

  // Cubic bezier: smooth S-curve
  const cp1x = x1 + (x2 - x1) * 0.45;
  const cp1y = py;
  const cp2x = x1 + (x2 - x1) * 0.55;
  const cp2y = qy;

  return `L ${x1} ${py} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${x2} ${qy} L ${qx} ${qy}`;
}


// --- route-angular.js ---
// ================================================================
// route-angular.js — Angular progressive routing (R9/R10 style)
// ================================================================
// Interchange-aware angular routing with progressive curves.
// Convergence edges steepen toward the reference line.
// Divergence edges flatten away from it.
// Deterministic per-route variation via hash-based departure/arrival fractions.

/**
 * Progressive curve generator.
 *
 * For convergence (isConvergence=true): the edge is returning toward the
 * reference line (trunk or parent route). The curve STARTS flat (large
 * horizontal run) and ENDS steep (small horizontal run) — "steepening."
 *   Weights: (nSegs - i)^power — first segment gets the most X.
 *
 * For divergence (isConvergence=false): the edge is departing from the
 * reference line. The curve STARTS steep and ENDS flat — "flattening."
 *   Weights: (i + 1)^power — first segment gets the least X.
 *
 * @param {number} startX
 * @param {number} startY
 * @param {number} endX
 * @param {number} endY
 * @param {boolean} isConvergence
 * @param {number} [power=2.2]
 * @returns {string} SVG path data (L segments, no leading M)
 */
function progressiveCurve(startX, startY, endX, endY, isConvergence, power = 2.2) {
  const totalDx = endX - startX;
  const totalDy = endY - startY;
  if (Math.abs(totalDy) < 1) return `L ${endX} ${endY}`;
  if (totalDx < 3) return `L ${endX} ${endY}`;

  // Number of segments based on Y distance
  // ~1 segment per 18px of vertical distance, minimum 2, maximum 5
  const nSegs = Math.max(2, Math.min(5, Math.round(Math.abs(totalDy) / 18)));

  // X distribution: power curve
  const weights = [];
  for (let i = 0; i < nSegs; i++) {
    if (isConvergence) {
      // Convergence: first segments are flat (more X), last are steep (less X)
      weights.push(Math.pow(nSegs - i, power));
    } else {
      // Divergence: first segments are steep (less X), last are flat (more X)
      weights.push(Math.pow(i + 1, power));
    }
  }
  const totalWeight = weights.reduce((a, b) => a + b, 0);

  // Y is distributed EVENLY across segments
  const segDy = totalDy / nSegs;

  // Build path segments
  let d = '';
  let cx = startX;
  let cy = startY;

  for (let i = 0; i < nSegs; i++) {
    const segDx = totalDx * (weights[i] / totalWeight);
    cx += segDx;
    cy += segDy;
    d += `L ${cx.toFixed(1)} ${cy.toFixed(1)} `;
  }

  return d;
}

/**
 * Angular path with interchange-aware direction detection.
 *
 * Route segments determine convergence/divergence by ROLE, not distance:
 *   - FORK segment (src is interchange): always DIVERGENCE
 *   - RETURN segment (dst is interchange): always CONVERGENCE
 *   - INTERNAL segment (both own): use trunk Y fallback
 *
 * @param {number} px - source x
 * @param {number} py - source y
 * @param {number} qx - destination x
 * @param {number} qy - destination y
 * @param {number} routeIdx - route index (used for deterministic variation)
 * @param {number} segIdx - segment index within route
 * @param {number} refY - reference Y for convergence/divergence detection
 * @param {object} [options]
 * @param {number} [options.progressivePower=2.2]
 * @returns {string} SVG path data (without leading M)
 */
function angularPath(px, py, qx, qy, routeIdx, segIdx, refY, options = {}) {
  const power = options.progressivePower ?? 2.2;
  const dx = qx - px, dy = qy - py;
  if (Math.abs(dy) < 1) return `L ${qx} ${qy}`; // horizontal
  if (dx < 3) return `L ${qx} ${qy}`; // too tight

  const srcDistFromRef = Math.abs(py - refY);
  const dstDistFromRef = Math.abs(qy - refY);

  const isConvergence = srcDistFromRef > dstDistFromRef + 0.5;
  const isDivergence = srcDistFromRef + 0.5 < dstDistFromRef;

  // Per-route variation for departure/arrival horizontal runs
  const hash = ((routeIdx * 7 + segIdx * 13) % 17) / 17;

  if (isConvergence) {
    // Long horizontal at branch level (35-45%), then progressive curve to trunk
    const departFrac = 0.35 + hash * 0.10;
    const departX = px + dx * departFrac;
    const remainDx = qx - departX;

    if (remainDx < 5) return `L ${qx} ${qy}`;

    let d = `L ${departX.toFixed(1)} ${py} `; // horizontal at branch level
    d += progressiveCurve(departX, py, qx, qy, true, power); // progressive curve
    return d;

  } else if (isDivergence) {
    // Progressive curve from trunk, then long horizontal at branch level (35-45%)
    const arriveFrac = 0.35 + hash * 0.10;
    const arriveX = qx - dx * arriveFrac;
    const curveDx = arriveX - px;

    if (curveDx < 5) return `L ${qx} ${qy}`;

    let d = progressiveCurve(px, py, arriveX, qy, false, power); // progressive curve
    d += `L ${qx} ${qy}`; // horizontal at branch level
    return d;

  } else {
    // Same level — symmetric
    const departFrac = 0.18 + hash * 0.08;
    const arriveFrac = 0.18 + ((hash * 7) % 1) * 0.08;
    const departX = px + dx * departFrac;
    const arriveX = qx - dx * arriveFrac;
    if (arriveX <= departX + 2) return `L ${qx} ${qy}`;
    return `L ${departX.toFixed(1)} ${py} L ${arriveX.toFixed(1)} ${qy} L ${qx} ${qy}`;
  }
}


// --- route-metro.js ---
// ================================================================
// route-metro.js — Metro-style right-angle routing with rounded elbows
// ================================================================
// Produces clean H-V-H or V-H-V paths with quadratic bezier corners.
// Designed for parallel-line layouts where visual clarity is paramount.
//
// For LTR layouts: horizontal → rounded elbow → vertical → rounded elbow → horizontal
// For TTB layouts: vertical → rounded elbow → horizontal → rounded elbow → vertical

/**
 * Rounded elbow path between two points using right-angle bends.
 *
 * @param {number} px - source x
 * @param {number} py - source y
 * @param {number} qx - destination x
 * @param {number} qy - destination y
 * @param {number} routeIdx - route index (for deterministic midpoint variation)
 * @param {number} segIdx - segment index within route
 * @param {number} refY - reference Y (not used, kept for API compat)
 * @param {object} [options]
 * @param {number} [options.cornerRadius=8] - corner radius in px (before scale)
 * @param {'h-first'|'v-first'|'auto'} [options.bendStyle='auto'] - which axis to run first
 * @returns {string} SVG path data (without leading M)
 */
function metroPath(px, py, qx, qy, routeIdx, segIdx, refY, options = {}) {
  const cornerRadius = options.cornerRadius ?? 8;
  const bendStyle = options.bendStyle ?? 'auto';
  const dx = qx - px, dy = qy - py;

  // Straight horizontal or vertical — no bend needed
  if (Math.abs(dy) < 1) return `L ${qx} ${qy}`;
  if (Math.abs(dx) < 1) return `L ${qx} ${qy}`;

  // Clamp radius so it doesn't exceed available space
  const r = Math.min(cornerRadius, Math.abs(dx) / 2, Math.abs(dy) / 2);

  if (r < 1) return `L ${qx} ${qy}`; // too small for rounded corners

  // Determine bend direction
  const useHFirst = bendStyle === 'h-first' ||
    (bendStyle === 'auto' && Math.abs(dx) >= Math.abs(dy));

  if (useHFirst) {
    // H-V path: horizontal run → rounded corner → vertical run
    const midFrac = options.midFrac ?? (0.45 + (((routeIdx * 7 + segIdx * 13) % 17) / 17) * 0.10);
    const midX = px + dx * midFrac;

    return hvPath(px, py, midX, qx, qy, r);
  } else {
    // V-H path: vertical run → rounded corner → horizontal run
    const midFrac = options.midFrac ?? (0.45 + (((routeIdx * 7 + segIdx * 13) % 17) / 17) * 0.10);
    const midY = py + dy * midFrac;

    return vhPath(px, py, midY, qx, qy, r);
  }
}

/**
 * H-V-H path: horizontal → corner → vertical → corner → horizontal
 */
function hvPath(px, py, midX, qx, qy, r) {
  const dy = qy - py;
  const sy = Math.sign(dy); // +1 down, -1 up

  // First elbow: at (midX, py) turning toward qy
  const e1x = midX - r;        // approach point
  const e1cx = midX;            // corner control point
  const e1cy = py;
  const e1ex = midX;            // exit point
  const e1ey = py + sy * r;

  // Second elbow: at (midX, qy) turning toward qx
  const e2x = midX;             // approach point
  const e2y = qy - sy * r;
  const e2cx = midX;            // corner control point
  const e2cy = qy;
  const e2ex = midX + r * Math.sign(qx - midX); // exit toward qx
  const e2ey = qy;

  let d = '';
  d += `L ${e1x.toFixed(1)} ${py} `;                      // horizontal to first elbow approach
  d += `Q ${e1cx.toFixed(1)} ${e1cy} ${e1ex.toFixed(1)} ${e1ey.toFixed(1)} `; // rounded corner
  d += `L ${e2x.toFixed(1)} ${e2y.toFixed(1)} `;          // vertical run
  d += `Q ${e2cx.toFixed(1)} ${e2cy} ${e2ex.toFixed(1)} ${e2ey.toFixed(1)} `; // rounded corner
  d += `L ${qx} ${qy}`;                                    // horizontal to destination

  return d;
}

/**
 * V-H-V path: vertical → corner → horizontal → corner → vertical
 */
function vhPath(px, py, midY, qx, qy, r) {
  const dx = qx - px;
  const sx = Math.sign(dx); // +1 right, -1 left
  const dy = qy - py;
  const sy = Math.sign(dy);

  // First elbow: at (px, midY) turning toward qx
  const e1y = midY - sy * r;
  const e1cx = px;
  const e1cy = midY;
  const e1ex = px + sx * r;
  const e1ey = midY;

  // Second elbow: at (qx, midY) turning toward qy
  const e2x = qx - sx * r;
  const e2y = midY;
  const e2cx = qx;
  const e2cy = midY;
  const e2ex = qx;
  const e2ey = midY + sy * r;

  let d = '';
  d += `L ${px} ${e1y.toFixed(1)} `;                       // vertical to first elbow
  d += `Q ${e1cx.toFixed(1)} ${e1cy.toFixed(1)} ${e1ex.toFixed(1)} ${e1ey.toFixed(1)} `; // rounded corner
  d += `L ${e2x.toFixed(1)} ${e2y.toFixed(1)} `;           // horizontal run
  d += `Q ${e2cx.toFixed(1)} ${e2cy.toFixed(1)} ${e2ex.toFixed(1)} ${e2ey.toFixed(1)} `; // rounded corner
  d += `L ${qx} ${qy}`;                                     // vertical to destination

  return d;
}


// --- graph-utils.js ---
// ================================================================
// graph-utils.js — Shared graph primitives for dag-map layout engines
// ================================================================
// Adjacency map construction and Kahn's algorithm topological sort
// with longest-path rank assignment. Used by all three layout engines.

/**
 * Build adjacency maps from nodes and edges.
 * @param {Array<{id: string}>} nodes
 * @param {Array<[string, string]>} edges
 * @returns {{ nodeMap: Map, childrenOf: Map, parentsOf: Map }}
 */
function buildGraph(nodes, edges) {
  const nodeMap = new Map(nodes.map(n => [n.id, n]));
  const childrenOf = new Map();
  const parentsOf = new Map();
  nodes.forEach(n => { childrenOf.set(n.id, []); parentsOf.set(n.id, []); });
  edges.forEach(([f, t], edgeIdx) => {
    const srcChildren = childrenOf.get(f);
    const dstParents = parentsOf.get(t);
    if (!srcChildren || !dstParents) {
      const parts = [];
      if (!srcChildren) parts.push(`source "${f}"`);
      if (!dstParents) parts.push(`target "${t}"`);
      throw new Error(`buildGraph: edge[${edgeIdx}] references unknown ${parts.join(' and ')}`);
    }
    srcChildren.push(t);
    dstParents.push(f);
  });
  return { nodeMap, childrenOf, parentsOf };
}

/**
 * Topological sort via Kahn's algorithm with longest-path rank assignment.
 * @param {Array<{id: string}>} nodes
 * @param {Map} childrenOf
 * @param {Map} parentsOf
 * @returns {{ topo: string[], rank: Map<string, number>, maxRank: number }}
 */
function topoSortAndRank(nodes, childrenOf, parentsOf) {
  const rank = new Map();
  const inDeg = new Map();
  nodes.forEach(nd => inDeg.set(nd.id, parentsOf.get(nd.id).length));

  const queue = nodes.filter(nd => inDeg.get(nd.id) === 0).map(nd => nd.id);
  queue.forEach(id => rank.set(id, 0));

  const topo = [];
  while (queue.length) {
    const u = queue.shift();
    topo.push(u);
    for (const v of childrenOf.get(u)) {
      rank.set(v, Math.max(rank.get(v) || 0, rank.get(u) + 1));
      inDeg.set(v, inDeg.get(v) - 1);
      if (inDeg.get(v) === 0) queue.push(v);
    }
  }

  const maxRank = topo.length > 0 ? Math.max(...topo.map(id => rank.get(id))) : 0;
  return { topo, rank, maxRank };
}

/**
 * Validate a DAG definition and return warnings for common issues.
 * Non-throwing — returns an array of human-readable warning strings.
 * @param {Array<{id: string}>} nodes
 * @param {Array<[string, string]>} edges
 * @returns {string[]} warnings (empty if valid)
 */
function validateDag(nodes, edges) {
  const warnings = [];
  const ids = new Set();

  // Duplicate node IDs
  for (const n of nodes) {
    if (ids.has(n.id)) warnings.push(`Duplicate node ID: "${n.id}"`);
    ids.add(n.id);
  }

  // Edges referencing unknown nodes
  for (const [f, t] of edges) {
    if (!ids.has(f)) warnings.push(`Edge source "${f}" is not a known node`);
    if (!ids.has(t)) warnings.push(`Edge target "${t}" is not a known node`);
  }

  // Cycle detection via topo sort
  if (warnings.length === 0 && nodes.length > 0) {
    const { childrenOf, parentsOf } = buildGraph(nodes, edges);
    const { topo } = topoSortAndRank(nodes, childrenOf, parentsOf);
    if (topo.length < nodes.length) {
      const missing = nodes.filter(n => !topo.includes(n.id)).map(n => n.id);
      warnings.push(`Cycle detected — ${missing.length} node(s) unreachable: ${missing.join(', ')}`);
    }
  }

  return warnings;
}

/**
 * Validate a DAG definition and throw with a useful message if invalid.
 * @param {Array<{id: string}>} nodes
 * @param {Array<[string, string]>} edges
 * @param {string} [context='DAG']
 */
function assertValidDag(nodes, edges, context = 'DAG') {
  const warnings = validateDag(nodes, edges);
  if (warnings.length > 0) {
    throw new Error(`${context}: invalid DAG input. ${warnings.join('; ')}`);
  }
}

// ================================================================
// SVG path coordinate swap (X↔Y) for orientation transforms
// ================================================================

// How many coordinate values each SVG command consumes per repetition.
// Commands that take (x,y) pairs: values are swapped pairwise.
// H↔V are single-axis and swap command letter instead.
// A (arc) is not supported — its 7-param layout doesn't pair-swap cleanly.
const CMD_PARAMS = {
  M: 2, L: 2, T: 2,      // 1 pair
  Q: 4, S: 4,             // 2 pairs
  C: 6,                   // 3 pairs
  H: 1, V: 1,             // single axis — letter swaps
  Z: 0,                   // no params
};

/**
 * Swap X↔Y coordinates in an SVG path string.
 * Handles M, L, C, Q, S, T, H, V, Z (both absolute and relative).
 * Throws on A/a (arc) — arc parameter layout requires special handling.
 *
 * @param {string} d - SVG path data string
 * @returns {string} path with all X and Y coordinates swapped
 */
function swapPathXY(d) {
  if (!d) return '';

  // Tokenize: split into command + numbers sequences.
  // Regex captures a command letter followed by its numeric arguments.
  const tokens = [];
  const re = /([MLCSQTHVZAmlcsqthvza])\s*([^MLCSQTHVZAmlcsqthvza]*)/g;
  let m;
  while ((m = re.exec(d)) !== null) {
    const cmd = m[1];
    const argStr = m[2].trim();
    const nums = argStr.length > 0 ? argStr.split(/[\s,]+/).map(Number) : [];
    tokens.push({ cmd, nums });
  }

  const parts = [];
  for (const { cmd, nums } of tokens) {
    const upper = cmd.toUpperCase();

    if (upper === 'A') {
      throw new Error('swapPathXY: arc commands (A/a) are not supported');
    }

    if (upper === 'Z') {
      parts.push(cmd);
      continue;
    }

    if (upper === 'H') {
      // H x → V x (swap command letter, keep value)
      parts.push((cmd === 'H' ? 'V' : 'v') + ' ' + nums.join(' '));
      continue;
    }

    if (upper === 'V') {
      // V y → H y
      parts.push((cmd === 'V' ? 'H' : 'h') + ' ' + nums.join(' '));
      continue;
    }

    // Pair-swapping commands: swap every (x, y) → (y, x)
    const swapped = [];
    for (let i = 0; i < nums.length; i += 2) {
      swapped.push(nums[i + 1], nums[i]);
    }
    parts.push(cmd + ' ' + swapped.join(' '));
  }

  return parts.join(' ');
}


// --- themes.js ---
// ================================================================
// themes.js — Theme definitions for dag-map
// ================================================================
// Five built-in themes plus custom theme support via resolveTheme().
//
// The class names (pure, recordable, side_effecting, gate) are defaults.
// Users can use any string keys they want — just pass matching keys in
// the node `cls` field and in a custom theme's `classes` object.

const THEMES = {
  cream: {
    paper: '#F5F0E8', ink: '#2C2C2C', muted: '#8C8680', border: '#D4CFC7',
    classes: { pure: '#2B8A8E', recordable: '#E8846B', side_effecting: '#D4944C', gate: '#C45B4A', pending: '#B0AAA0' }
  },
  light: {
    paper: '#FAFAFA', ink: '#333333', muted: '#999999', border: '#E0E0E0',
    classes: { pure: '#0077B6', recordable: '#E36414', side_effecting: '#6C757D', gate: '#DC3545', pending: '#BDBDBD' }
  },
  dark: {
    paper: '#1E1E2E', ink: '#CDD6F4', muted: '#6C7086', border: '#313244',
    classes: { pure: '#94E2D5', recordable: '#F38BA8', side_effecting: '#F9E2AF', gate: '#EBA0AC', pending: '#45475A' }
  },
  blueprint: {
    paper: '#1B2838', ink: '#E0E8F0', muted: '#5A7A9A', border: '#2A4060',
    classes: { pure: '#4FC3F7', recordable: '#FF8A65', side_effecting: '#FFD54F', gate: '#EF5350', pending: '#3D5A7A' }
  },
  mono: {
    paper: '#FFFFFF', ink: '#1A1A1A', muted: '#888888', border: '#CCCCCC',
    classes: { pure: '#444444', recordable: '#777777', side_effecting: '#999999', gate: '#333333', pending: '#AAAAAA' }
  },
  metro: {
    paper: '#FFFFFF', ink: '#1A1A1A', muted: '#9E9E9E', border: '#D4EAF7',
    classes: { pure: '#0078C8', recordable: '#E3242B', side_effecting: '#F5A623', gate: '#6A2D8E', pending: '#BDBDBD' },
    lineOpacity: 1.4
  }
};

/**
 * Resolve a theme option to a full theme object.
 *
 * @param {string|object} [themeOption] - theme name string, custom theme object, or undefined
 * @returns {object} resolved theme with paper, ink, muted, border, and classes
 */
function resolveTheme(themeOption) {
  if (!themeOption || themeOption === 'cream') return THEMES.cream;
  if (typeof themeOption === 'string') return THEMES[themeOption] || THEMES.cream;
  // Custom theme object — merge with cream defaults
  return { ...THEMES.cream, ...themeOption, classes: { ...THEMES.cream.classes, ...(themeOption.classes || {}) } };
}


// --- color-scales.js ---
// ================================================================
// color-scales.js — Curated color scales for heatmap mode
// ================================================================
// Each scale is a function (t: 0..1) => "rgb(r,g,b)"
// 0 = low/cool/good, 1 = high/hot/bad

/**
 * Palette scale — teal → amber → red.
 * Matches the cream theme's accent colors.
 * Default scale used by renderSVG when no colorScale is provided.
 */
function palette(t) {
  const c = Math.max(0, Math.min(1, t));
  let r, g, b;
  if (c < 0.5) {
    const u = c * 2;
    r = Math.round(0x2B + (0xD4 - 0x2B) * u);
    g = Math.round(0x8A + (0x94 - 0x8A) * u);
    b = Math.round(0x8E + (0x4C - 0x8E) * u);
  } else {
    const u = (c - 0.5) * 2;
    r = Math.round(0xD4 + (0xC4 - 0xD4) * u);
    g = Math.round(0x94 + (0x5B - 0x94) * u);
    b = Math.round(0x4C + (0x4A - 0x4C) * u);
  }
  return `rgb(${r},${g},${b})`;
}

/**
 * Thermal scale — steel blue → warm salmon.
 * Good contrast on both light and dark backgrounds.
 */
function thermal(t) {
  const c = Math.max(0, Math.min(1, t));
  // Steel blue #4682B4 → muted lavender #9B7FB4 → warm salmon #D4796B
  let r, g, b;
  if (c < 0.5) {
    const u = c * 2;
    r = Math.round(70 + 85 * u);    // 70 → 155
    g = Math.round(130 - 3 * u);    // 130 → 127
    b = Math.round(180 + 0 * u);    // 180 → 180
  } else {
    const u = (c - 0.5) * 2;
    r = Math.round(155 + 57 * u);   // 155 → 212
    g = Math.round(127 - 6 * u);    // 127 → 121
    b = Math.round(180 - 73 * u);   // 180 → 107
  }
  return `rgb(${r},${g},${b})`;
}

/**
 * Mono scale — light gray → dark charcoal.
 * Theme-neutral, works everywhere.
 */
function mono(t) {
  const c = Math.max(0, Math.min(1, t));
  const v = Math.round(200 - 150 * c); // 200 → 50
  return `rgb(${v},${v},${v})`;
}

const colorScales = { palette, thermal, mono };


// --- layout-metro.js ---
// ================================================================
// layout.js — Shared layout engine for dag-map
// ================================================================
// Topological sort, route extraction via greedy longest-path,
// Y-position assignment with occupancy tracking, node positioning,
// and route/extra-edge path building with pluggable routing.






/**
 * Determine the dominant node class among a set of node IDs.
 * @param {string[]} nodeIds
 * @param {Map} nodeMap - Map from id to node object
 * @returns {string}
 */
function dominantClass(nodeIds, nodeMap) {
  const counts = {};
  nodeIds.forEach(id => {
    const cls = nodeMap.get(id)?.cls || 'pure';
    counts[cls] = (counts[cls] || 0) + 1;
  });
  let best = 'pure', bestCount = 0;
  for (const [cls, count] of Object.entries(counts)) {
    if (count > bestCount) { best = cls; bestCount = count; }
  }
  return best;
}

/**
 * Compute the full metro-map layout for a DAG.
 *
 * @param {object} dag - { nodes: [{id, label, cls}], edges: [[from, to]] }
 * @param {object} [options]
 * @param {'bezier'|'angular'} [options.routing='bezier'] - routing style
 * @param {number} [options.trunkY=160] - absolute Y for trunk route
 * @param {number} [options.mainSpacing=34] - px between depth-1 branch lanes
 * @param {number} [options.subSpacing=16] - px between depth-2+ sub-branch lanes
 * @param {number} [options.layerSpacing=38] - px between topological layers
 * @param {number} [options.progressivePower=2.2] - power for progressive curves
 * @param {number} [options.scale=1.5] - scale multiplier for all spatial values
 * @param {'ltr'|'ttb'} [options.direction='ltr'] - layout direction
 * @returns {object} { positions, routePaths, extraEdges, width, height, routes, ... }
 */
function layoutMetro(dag, options = {}) {
  const routing = options.routing || 'bezier';
  const direction = options.direction || 'ltr';
  const isTTB = direction === 'ttb';
  const theme = resolveTheme(options.theme);
  // Build classColor from all theme classes (not just hardcoded four)
  const classColor = { ...theme.classes };
  const s = options.scale ?? 1.5;
  const TRUNK_Y = (options.trunkY ?? 160) * s;
  const MAIN_SPACING = (options.mainSpacing ?? 34) * s;
  const SUB_SPACING = (options.subSpacing ?? 16) * s;
  const layerSpacing = (options.layerSpacing ?? 38) * s;
  const progressivePower = options.progressivePower ?? 2.2;
  const cornerRadius = (options.cornerRadius ?? 8) * s;
  const dimOpacity = options.dimOpacity ?? 0.25;
  const maxLanes = options.maxLanes ?? null;
  const hasProvidedRoutes = !!(options.routes && options.routes.length > 0);

  const { nodes, edges } = dag;
  assertValidDag(nodes, edges, 'layoutMetro');
  const { nodeMap, childrenOf, parentsOf } = buildGraph(nodes, edges);

  // ── STEP 1: Topological sort + layer assignment ──
  const { topo, rank: layer, maxRank: maxLayer } = topoSortAndRank(nodes, childrenOf, parentsOf);

  // ── STEP 2: Extract routes ──
  // Either use consumer-provided routes or auto-discover via greedy longest-path.
  // lineGap is set after route discovery (needs route count)

  function longestPathIn(nodeSet) {
    const dist = new Map(), prev = new Map();
    nodeSet.forEach(id => { dist.set(id, 0); prev.set(id, null); });
    for (const u of topo) {
      if (!nodeSet.has(u)) continue;
      for (const v of childrenOf.get(u)) {
        if (!nodeSet.has(v)) continue;
        if (dist.get(u) + 1 > dist.get(v)) {
          dist.set(v, dist.get(u) + 1); prev.set(v, u);
        }
      }
    }
    let best = -1, end = null;
    nodeSet.forEach(id => { if (dist.get(id) > best) { best = dist.get(id); end = id; } });
    if (end === null) return [];
    const path = [];
    for (let c = end; c !== null; c = prev.get(c)) path.unshift(c);
    return path;
  }

  const routes = [];
  const assigned = new Set();
  const nodeRoute = new Map();
  const nodeRoutes = new Map(); // node → Set<routeIdx> (all routes through this node)
  nodes.forEach(nd => nodeRoutes.set(nd.id, new Set()));

  if (options.routes && options.routes.length > 0) {
    // ── Consumer-provided routes ──
    // Sort by length descending — longest route becomes trunk
    const provided = options.routes
      .map((r, i) => ({ ...r, originalIndex: i }))
      .sort((a, b) => b.nodes.length - a.nodes.length);

    provided.forEach((pr, i) => {
      // Determine parent route: the earlier route that shares the most nodes
      let parentRouteIdx = -1;
      let bestOverlap = 0;
      const prNodeSet = new Set(pr.nodes);
      for (let j = 0; j < i; j++) {
        const overlap = routes[j].nodes.filter(id => prNodeSet.has(id)).length;
        if (overlap > bestOverlap) { bestOverlap = overlap; parentRouteIdx = j; }
      }
      if (i === 0) parentRouteIdx = -1;
      const depth = parentRouteIdx >= 0 ? routes[parentRouteIdx].depth + 1 : 0;

      routes.push({
        nodes: pr.nodes,
        lane: 0,
        parentRoute: parentRouteIdx >= 0 ? parentRouteIdx : (i === 0 ? -1 : 0),
        depth,
        cls: pr.cls || null,
        id: pr.id || null,
      });

      const ri = routes.length - 1;
      pr.nodes.forEach(id => {
        if (!assigned.has(id)) { assigned.add(id); nodeRoute.set(id, ri); }
        nodeRoutes.get(id)?.add(ri);
      });
    });

    // Any nodes not in any route get assigned to route 0
    nodes.forEach(nd => {
      if (!assigned.has(nd.id)) {
        assigned.add(nd.id);
        nodeRoute.set(nd.id, 0);
      }
    });
  } else {
    // ── Auto-discover routes via greedy longest-path ──
    const trunk = longestPathIn(new Set(topo));
    routes.push({ nodes: trunk, lane: 0, parentRoute: -1, depth: 0 });
    trunk.forEach(id => { assigned.add(id); nodeRoute.set(id, 0); nodeRoutes.get(id)?.add(0); });

    let safety = 0;
    while (assigned.size < nodes.length && safety++ < 300) {
      const unassigned = [];
      nodes.forEach(nd => { if (!assigned.has(nd.id)) unassigned.push(nd.id); });
      if (unassigned.length === 0) break;

      const unassignedSet = new Set(unassigned);
      let bestPath = longestPathIn(unassignedSet);
      if (bestPath.length === 0) {
        unassigned.forEach(id => { assigned.add(id); nodeRoute.set(id, 0); });
        break;
      }

      const firstNode = bestPath[0];
      const assignedParents = parentsOf.get(firstNode).filter(p => assigned.has(p));
      let parentRouteIdx = 0;
      if (assignedParents.length > 0) {
        bestPath.unshift(assignedParents[0]);
        parentRouteIdx = nodeRoute.get(assignedParents[0]) ?? 0;
      }

      const lastNode = bestPath[bestPath.length - 1];
      const assignedChildren = childrenOf.get(lastNode).filter(c => assigned.has(c));
      if (assignedChildren.length > 0) {
        bestPath.push(assignedChildren[0]);
      }

      const ri = routes.length;
      const parentDepth = routes[parentRouteIdx]?.depth ?? 0;
      routes.push({ nodes: bestPath, lane: 0, parentRoute: parentRouteIdx, depth: parentDepth + 1 });
      bestPath.forEach(id => {
        if (!assigned.has(id)) { assigned.add(id); nodeRoute.set(id, ri); }
        nodeRoutes.get(id)?.add(ri);
      });
    }
  }

  // ── Build shared segment map for parallel offset rendering ──
  // segmentRoutes: "A→B" → [routeIdx, ...] (ordered)
  const segmentRoutes = new Map();
  routes.forEach((route, ri) => {
    for (let i = 1; i < route.nodes.length; i++) {
      const key = `${route.nodes[i - 1]}\u2192${route.nodes[i]}`;
      if (!segmentRoutes.has(key)) segmentRoutes.set(key, []);
      segmentRoutes.get(key).push(ri);
    }
  });

  // lineGap: perpendicular gap between parallel lines at shared nodes.
  // Only non-zero when consumer provides multiple routes (visible parallel lines).
  // Auto-discovered routes are internal — they don't need visual separation.
  const lineGap = (options.lineGap ?? (hasProvidedRoutes && routes.length > 1 ? 5 : 0)) * s;

  // ── STEP 3: Y-position assignment with occupancy tracking ──
  const routeChildren = new Map();
  routes.forEach((_, i) => routeChildren.set(i, []));
  for (let ri = 1; ri < routes.length; ri++) {
    const pi = routes[ri].parentRoute;
    if (routeChildren.has(pi)) routeChildren.get(pi).push(ri);
    else routeChildren.set(pi, [ri]);
  }

  const routeLayerRange = routes.map(route => {
    let min = Infinity, max = -Infinity;
    route.nodes.forEach(id => {
      const l = layer.get(id);
      if (l < min) min = l;
      if (l > max) max = l;
    });
    return [min, max];
  });

  const routeOwnLength = routes.map((route, ri) => {
    return route.nodes.filter(id => nodeRoute.get(id) === ri).length;
  });

  const routeDomClass = routes.map((route, ri) => {
    const ownNodes = route.nodes.filter(id => nodeRoute.get(id) === ri);
    return dominantClass(ownNodes, nodeMap);
  });

  // Y occupancy tracker: tracks used Y ranges per layer range
  const yOccupancy = []; // [{y, sL, eL}]
  function canUseY(y, sL, eL, minGap) {
    for (const occ of yOccupancy) {
      if (sL <= occ.eL + 1 && eL >= occ.sL - 1) {
        if (Math.abs(y - occ.y) < minGap) return false;
      }
    }
    return true;
  }
  function claimY(y, sL, eL) {
    yOccupancy.push({ y, sL, eL });
  }

  // Assign trunk
  const routeY = new Map();
  routeY.set(0, TRUNK_Y);
  claimY(TRUNK_Y, routeLayerRange[0][0], routeLayerRange[0][1]);

  // BFS from trunk
  const laneQueue = [0];
  const assignedRoutes = new Set([0]);

  while (laneQueue.length > 0) {
    const pi = laneQueue.shift();
    const parentY = routeY.get(pi);
    const children = routeChildren.get(pi) || [];

    // With provided routes, keep route order (gives consumer control over above/below).
    // With auto-discovered routes, sort longest first.
    if (!hasProvidedRoutes) {
      children.sort((a, b) => routeOwnLength[b] - routeOwnLength[a]);
    }

    let childAbove = 0, childBelow = 0;

    for (const ci of children) {
      if (assignedRoutes.has(ci)) continue;
      const [sL, eL] = routeLayerRange[ci];
      const cls = routeDomClass[ci];
      const depth = routes[ci].depth;
      const ownLength = routeOwnLength[ci];

      // Spacing depends on depth and route length
      const spacing = (depth <= 1 && ownLength > 2) ? MAIN_SPACING : SUB_SPACING;

      // With provided routes, alternate strictly: first child above, second below, etc.
      // With auto-discovered routes, use class-based heuristics.
      let preferBelow;
      if (hasProvidedRoutes) {
        preferBelow = childBelow <= childAbove;
      } else if (cls === 'side_effecting') {
        preferBelow = true;
      } else if (cls === 'recordable' && depth === 1) {
        preferBelow = false;
      } else {
        preferBelow = childBelow <= childAbove;
      }

      // Search for an available Y position
      const maxDist = maxLanes ? maxLanes : 8;
      let y = null;
      for (let dist = 1; dist <= maxDist; dist++) {
        const tryY = parentY + (preferBelow ? dist * spacing : -dist * spacing);
        if (canUseY(tryY, sL, eL, spacing * 0.8)) {
          y = tryY; break;
        }
        const tryAlt = parentY + (preferBelow ? -dist * spacing : dist * spacing);
        if (canUseY(tryAlt, sL, eL, spacing * 0.8)) {
          y = tryAlt; break;
        }
      }
      if (y === null) {
        y = parentY + (preferBelow ? (childBelow + 1) * spacing : -(childAbove + 1) * spacing);
      }

      routeY.set(ci, y);
      claimY(y, sL, eL);
      assignedRoutes.add(ci);
      laneQueue.push(ci);

      if (y > parentY) childBelow++;
      else childAbove++;
    }
  }

  // ── STEP 4: Position nodes ──
  const margin = { top: 0, left: 50 * s, bottom: 0, right: 40 * s };

  // Each node's Y comes from its route's Y
  const nodeYDirect = new Map();
  nodes.forEach(nd => {
    const ri = nodeRoute.get(nd.id);
    nodeYDirect.set(nd.id, (ri !== undefined) ? routeY.get(ri) : TRUNK_Y);
  });

  // Find Y bounds
  let minY = Infinity, maxY = -Infinity;
  nodes.forEach(nd => {
    const y = nodeYDirect.get(nd.id);
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  });

  // Add padding
  const topPad = 50 * s;
  const bottomPad = 80 * s;

  const positions = new Map();
  nodes.forEach(nd => {
    positions.set(nd.id, {
      x: margin.left + layer.get(nd.id) * layerSpacing,
      y: topPad + (nodeYDirect.get(nd.id) - minY),
    });
  });

  const width = margin.left + (maxLayer + 1) * layerSpacing + margin.right;
  const height = topPad + (maxY - minY) + bottomPad;

  // Compute screen Y for each route (after topPad/minY shift)
  const routeYScreen = new Map();
  for (const [ri, y] of routeY.entries()) {
    routeYScreen.set(ri, topPad + (y - minY));
  }
  const trunkYScreen = topPad + (TRUNK_Y - minY);

  // ── STEP 5: Build route paths ──
  const pathFn = routing === 'metro' ? metroPath : routing === 'bezier' ? bezierPath : angularPath;
  const opBoost = theme.lineOpacity ?? 1.0;

  const routePaths = routes.map((route, ri) => {
    const pts = route.nodes.map(id => ({ ...positions.get(id), id }));
    const ownNodes = route.nodes.filter(id => nodeRoute.get(id) === ri);

    // Route color: use route's cls if provided, else dominant class
    const routeCls = route.cls || dominantClass(ownNodes, nodeMap);
    const color = classColor[routeCls] || classColor.pure || Object.values(classColor)[0];

    let thickness, opacity;
    if (hasProvidedRoutes) {
      // With provided routes, all lines are equal weight
      thickness = 3 * s;
      opacity = Math.min(0.55 * opBoost, 1);
    } else if (ri === 0) {
      thickness = 5 * s;
      opacity = Math.min(0.6 * opBoost, 1);
    } else if (ownNodes.length > 5) {
      thickness = 3.5 * s;
      opacity = Math.min(0.45 * opBoost, 1);
    } else if (ownNodes.length > 2) {
      thickness = 2.5 * s;
      opacity = Math.min(0.35 * opBoost, 1);
    } else {
      thickness = 2 * s;
      opacity = Math.min(0.28 * opBoost, 1);
    }

    // Precompute per-node offset for this route.
    // At each node, find all routes passing through it and assign a consistent
    // slot so the line enters and exits at the same Y-offset.
    const nodeOffsetY = new Map();
    for (const id of route.nodes) {
      const nr = nodeRoutes.get(id);
      if (nr && nr.size > 1) {
        const allRoutes = [...nr].sort((a, b) => a - b); // stable order
        const idx = allRoutes.indexOf(ri);
        const n = allRoutes.length;
        nodeOffsetY.set(id, (idx - (n - 1) / 2) * lineGap);
      } else {
        nodeOffsetY.set(id, 0);
      }
    }

    const segments = [];
    for (let i = 1; i < pts.length; i++) {
      const p = pts[i - 1], q = pts[i];

      // Use node-based offsets for continuity through stations
      const offPy = nodeOffsetY.get(p.id) || 0;
      const offQy = nodeOffsetY.get(q.id) || 0;

      const px = p.x, py = p.y + offPy;
      const qx = q.x, qy = q.y + offQy;

      // Segment color: use route color for provided routes, else source node class
      const srcNode = nodeMap.get(p.id);
      const segColor = hasProvidedRoutes ? color : (classColor[srcNode?.cls] || color);
      const segDashed = srcNode?.cls === 'gate' || route.cls === 'gate';

      // Determine reference Y for convergence/divergence detection
      let segRefY;
      if (routing === 'angular') {
        const srcIsOwn = nodeRoute.get(p.id) === ri;
        const dstIsOwn = nodeRoute.get(q.id) === ri;

        if (!srcIsOwn && dstIsOwn) {
          segRefY = py;
        } else if (srcIsOwn && !dstIsOwn) {
          segRefY = qy;
        } else {
          segRefY = trunkYScreen;
        }
      } else {
        segRefY = trunkYScreen;
      }

      const d = `M ${px} ${py} ` + pathFn(px, py, qx, qy, ri, i, segRefY, { progressivePower, cornerRadius, bendStyle: isTTB ? 'v-first' : 'h-first' });
      const dstNode = nodeMap.get(q.id);
      const srcDim = srcNode?.dim === true;
      const dstDim = dstNode?.dim === true;
      const segOpacity = (srcDim || dstDim) ? Math.min(opacity, dimOpacity * 0.48) : opacity;
      segments.push({ d, color: segColor, thickness, opacity: segOpacity, dashed: segDashed });
    }
    return segments;
  });

  // ── STEP 6: Extra edges (cross-route connections) ──
  const routeEdgeSet = new Set();
  routes.forEach(route => {
    for (let i = 1; i < route.nodes.length; i++)
      routeEdgeSet.add(`${route.nodes[i - 1]}\u2192${route.nodes[i]}`);
  });

  const extraEdges = [];
  edges.forEach(([f, t]) => {
    if (routeEdgeSet.has(`${f}\u2192${t}`)) return;
    const p = positions.get(f), q = positions.get(t);
    if (!p || !q) return;
    const srcNode = nodeMap.get(f);
    const color = classColor[srcNode?.cls] || classColor.pure;
    const extraIdx = (f.length * 3 + t.length * 7) % 17;

    // Extra edges always use trunkScreenY as reference
    const refY = trunkYScreen;

    const d = `M ${p.x} ${p.y} ` + pathFn(p.x, p.y, q.x, q.y, extraIdx, 0, refY, { progressivePower, cornerRadius, bendStyle: isTTB ? 'v-first' : 'h-first' });
    const dstNode = nodeMap.get(t);
    const extraDim = srcNode?.dim === true || dstNode?.dim === true;
    const extraOpacity = extraDim ? Math.min(dimOpacity * 0.32, Math.min(0.22 * opBoost, 1)) : Math.min(0.22 * opBoost, 1);
    extraEdges.push({ d, color, thickness: 1.8 * s, opacity: extraOpacity, dashed: srcNode?.cls === 'gate' });
  });

  // Node lane info (for compatibility)
  const nodeLane = new Map();
  nodes.forEach(nd => {
    const ri = nodeRoute.get(nd.id);
    nodeLane.set(nd.id, ri !== undefined ? routes[ri].lane : 0);
  });

  if (direction === 'ttb') {
    // Swap X↔Y in all positions
    for (const [id, pos] of positions) {
      positions.set(id, { x: pos.y, y: pos.x });
    }

    // Rewrite SVG path data: swap all coordinate pairs
    for (const segments of routePaths) {
      for (const seg of segments) {
        seg.d = swapPathXY(seg.d);
      }
    }
    for (const seg of extraEdges) {
      seg.d = swapPathXY(seg.d);
    }

    return {
      positions,
      routePaths,
      extraEdges,
      width: height,
      height: width,
      maxLayer,
      routes,
      nodeLane,
      nodeRoute,
      nodeRoutes,
      segmentRoutes,
      laneSpacing: MAIN_SPACING,
      layerSpacing,
      minY,
      maxY,
      routeYScreen,
      trunkYScreen,
      scale: s,
      theme,
      orientation: 'ttb',
    };
  }

  return {
    positions,
    routePaths,
    extraEdges,
    width,
    height,
    maxLayer,
    routes,
    nodeLane,
    nodeRoute,
    nodeRoutes,
    segmentRoutes,
    laneSpacing: MAIN_SPACING,
    layerSpacing,
    minY,
    maxY,
    routeYScreen,
    trunkYScreen,
    scale: s,
    theme,
  };
}


// --- layout-hasse.js ---
// ================================================================
// layout-hasse.js — Hasse diagram layout engine for dag-map
// ================================================================
// Sugiyama-style layered layout for partial orders / lattices.
// Top-to-bottom: ⊤ (top) at the top, ⊥ (bottom) at the bottom.
// Edges represent covering relations pointing downward.
//
// Algorithm phases:
//   1. Rank assignment (longest path from sources)
//   2. Virtual node insertion for long edges
//   3. Crossing reduction (barycenter heuristic, multi-pass)
//   4. X-coordinate assignment (barycenter positioning + spacing)
//   5. Y-coordinate assignment (rank × spacing)
//   6. Edge path generation



// ================================================================
// PHASE 2: Virtual node insertion
// ================================================================

function insertVirtualNodes(edges, rank, childrenOf, parentsOf) {
  const virtualNodes = []; // { id, rank }
  const expandedEdges = []; // all edges after splitting
  const virtualChains = new Map(); // original edge key -> [virtual node ids]

  for (const [from, to] of edges) {
    const rFrom = rank.get(from);
    const rTo = rank.get(to);
    const span = rTo - rFrom;

    if (span <= 1) {
      expandedEdges.push([from, to]);
      continue;
    }

    // Insert virtual nodes at each intermediate rank
    const chain = [];
    let prev = from;
    for (let r = rFrom + 1; r < rTo; r++) {
      const vid = `__v_${from}_${to}_${r}`;
      virtualNodes.push({ id: vid, rank: r });
      chain.push(vid);
      expandedEdges.push([prev, vid]);

      // Register in adjacency
      if (!childrenOf.has(vid)) childrenOf.set(vid, []);
      if (!parentsOf.has(vid)) parentsOf.set(vid, []);
      childrenOf.get(prev).push(vid);
      parentsOf.get(vid).push(prev);

      prev = vid;
    }
    expandedEdges.push([prev, to]);
    childrenOf.get(prev).push(to);
    parentsOf.get(to).push(prev);

    virtualChains.set(`${from}->${to}`, chain);
  }

  // Update rank map for virtual nodes
  for (const vn of virtualNodes) {
    rank.set(vn.id, vn.rank);
  }

  return { virtualNodes, expandedEdges, virtualChains };
}

// ================================================================
// PHASE 3: Crossing reduction (barycenter heuristic)
// ================================================================

function buildLayers(nodeIds, rank, maxRank) {
  const layers = [];
  for (let r = 0; r <= maxRank; r++) layers.push([]);
  for (const id of nodeIds) {
    const r = rank.get(id);
    if (r !== undefined) layers[r].push(id);
  }
  return layers;
}

function countCrossings(layers, childrenOf) {
  let total = 0;
  for (let r = 0; r < layers.length - 1; r++) {
    const upper = layers[r];
    const lower = layers[r + 1];
    const posInLower = new Map();
    lower.forEach((id, i) => posInLower.set(id, i));

    // Collect edges as (upper_pos, lower_pos) pairs
    const edgePairs = [];
    for (let ui = 0; ui < upper.length; ui++) {
      const children = childrenOf.get(upper[ui]) || [];
      for (const child of children) {
        const li = posInLower.get(child);
        if (li !== undefined) edgePairs.push([ui, li]);
      }
    }

    // Count inversions
    for (let i = 0; i < edgePairs.length; i++) {
      for (let j = i + 1; j < edgePairs.length; j++) {
        if ((edgePairs[i][0] - edgePairs[j][0]) * (edgePairs[i][1] - edgePairs[j][1]) < 0) {
          total++;
        }
      }
    }
  }
  return total;
}

function barycenterSort(layer, getNeighborPositions) {
  const barycenters = new Map();
  for (const id of layer) {
    const positions = getNeighborPositions(id);
    if (positions.length > 0) {
      const avg = positions.reduce((a, b) => a + b, 0) / positions.length;
      barycenters.set(id, avg);
    } else {
      barycenters.set(id, Infinity); // keep original position
    }
  }

  // Stable sort by barycenter
  const indexed = layer.map((id, i) => ({ id, bc: barycenters.get(id), orig: i }));
  indexed.sort((a, b) => {
    if (a.bc !== b.bc) return a.bc - b.bc;
    return a.orig - b.orig; // stable tie-break
  });
  return indexed.map(e => e.id);
}

function reduceCrossings(layers, childrenOf, parentsOf, passes) {
  let best = layers.map(l => [...l]);
  let bestCrossings = countCrossings(best, childrenOf);

  const current = layers.map(l => [...l]);

  for (let pass = 0; pass < passes; pass++) {
    if (pass % 2 === 0) {
      // Top-down sweep
      for (let r = 1; r < current.length; r++) {
        const upperPos = new Map();
        current[r - 1].forEach((id, i) => upperPos.set(id, i));

        current[r] = barycenterSort(current[r], (id) => {
          const parents = parentsOf.get(id) || [];
          return parents.map(p => upperPos.get(p)).filter(p => p !== undefined);
        });
      }
    } else {
      // Bottom-up sweep
      for (let r = current.length - 2; r >= 0; r--) {
        const lowerPos = new Map();
        current[r + 1].forEach((id, i) => lowerPos.set(id, i));

        current[r] = barycenterSort(current[r], (id) => {
          const children = childrenOf.get(id) || [];
          return children.map(c => lowerPos.get(c)).filter(c => c !== undefined);
        });
      }
    }

    const crossings = countCrossings(current, childrenOf);
    if (crossings < bestCrossings) {
      bestCrossings = crossings;
      for (let r = 0; r < current.length; r++) best[r] = [...current[r]];
    }
  }

  return best;
}

// ================================================================
// PHASE 4: X-coordinate assignment
// ================================================================

function assignXCoordinates(layers, childrenOf, parentsOf, nodeSpacing) {
  const x = new Map();

  // Initialize: evenly spaced within each layer
  for (const layer of layers) {
    layer.forEach((id, i) => {
      x.set(id, i * nodeSpacing);
    });
  }

  // Iterative refinement: move each node toward the barycenter of its neighbors
  for (let iter = 0; iter < 12; iter++) {
    // Top-down pass
    for (let r = 1; r < layers.length; r++) {
      for (const id of layers[r]) {
        const parents = (parentsOf.get(id) || []).filter(p => x.has(p));
        const children = (childrenOf.get(id) || []).filter(c => x.has(c));
        const neighbors = [...parents, ...children];
        if (neighbors.length > 0) {
          const avg = neighbors.reduce((sum, n) => sum + x.get(n), 0) / neighbors.length;
          x.set(id, avg);
        }
      }
      // Enforce minimum spacing
      enforceSpacing(layers[r], x, nodeSpacing);
    }

    // Bottom-up pass
    for (let r = layers.length - 2; r >= 0; r--) {
      for (const id of layers[r]) {
        const parents = (parentsOf.get(id) || []).filter(p => x.has(p));
        const children = (childrenOf.get(id) || []).filter(c => x.has(c));
        const neighbors = [...parents, ...children];
        if (neighbors.length > 0) {
          const avg = neighbors.reduce((sum, n) => sum + x.get(n), 0) / neighbors.length;
          x.set(id, avg);
        }
      }
      enforceSpacing(layers[r], x, nodeSpacing);
    }
  }

  // Center all layers around the same midpoint
  centerLayers(layers, x);

  return x;
}

function enforceSpacing(layer, x, minSpacing) {
  // Sort layer by current x position (maintain layer order)
  const sorted = [...layer].sort((a, b) => x.get(a) - x.get(b));

  // Left-to-right sweep: push right if too close
  for (let i = 1; i < sorted.length; i++) {
    const prev = x.get(sorted[i - 1]);
    const curr = x.get(sorted[i]);
    if (curr - prev < minSpacing) {
      x.set(sorted[i], prev + minSpacing);
    }
  }

  // Right-to-left sweep: push left if too close (balance)
  for (let i = sorted.length - 2; i >= 0; i--) {
    const next = x.get(sorted[i + 1]);
    const curr = x.get(sorted[i]);
    if (next - curr < minSpacing) {
      x.set(sorted[i], next - minSpacing);
    }
  }
}

function centerLayers(layers, x) {
  // Find the global center
  let globalMin = Infinity, globalMax = -Infinity;
  for (const layer of layers) {
    for (const id of layer) {
      const val = x.get(id);
      if (val < globalMin) globalMin = val;
      if (val > globalMax) globalMax = val;
    }
  }
  const globalCenter = (globalMin + globalMax) / 2;

  // Center each layer
  for (const layer of layers) {
    if (layer.length === 0) continue;
    let layerMin = Infinity, layerMax = -Infinity;
    for (const id of layer) {
      const val = x.get(id);
      if (val < layerMin) layerMin = val;
      if (val > layerMax) layerMax = val;
    }
    const layerCenter = (layerMin + layerMax) / 2;
    const shift = globalCenter - layerCenter;
    for (const id of layer) {
      x.set(id, x.get(id) + shift);
    }
  }
}

// ================================================================
// PHASE 5+6: Edge path generation
// ================================================================

function hasseEdgePath(points, edgeStyle) {
  if (points.length < 2) return '';

  if (points.length === 2) {
    const [p, q] = points;
    const dx = Math.abs(q.x - p.x);

    if (edgeStyle === 'straight' || dx < 2) {
      return `M ${p.x} ${p.y} L ${q.x} ${q.y}`;
    }

    // Gentle vertical cubic bezier
    const dy = q.y - p.y;
    const cp1y = p.y + dy * 0.4;
    const cp2y = p.y + dy * 0.6;
    return `M ${p.x} ${p.y} C ${p.x} ${cp1y}, ${q.x} ${cp2y}, ${q.x} ${q.y}`;
  }

  // Multi-segment through virtual nodes
  if (edgeStyle === 'straight') {
    let d = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
      d += ` L ${points[i].x} ${points[i].y}`;
    }
    return d;
  }

  // Smooth multi-segment: cubic bezier through control points
  // Use Catmull-Rom-like approach: bezier between consecutive points
  let d = `M ${points[0].x} ${points[0].y}`;
  for (let i = 1; i < points.length; i++) {
    const p = points[i - 1];
    const q = points[i];
    const dy = q.y - p.y;
    const cp1y = p.y + dy * 0.4;
    const cp2y = p.y + dy * 0.6;
    d += ` C ${p.x} ${cp1y}, ${q.x} ${cp2y}, ${q.x} ${q.y}`;
  }
  return d;
}

// ================================================================
// PUBLIC API
// ================================================================

/**
 * Compute a Hasse diagram layout for a DAG (lattice / partial order).
 *
 * Edges point downward: [a, b] means a ≥ b (a covers b).
 * Layout is top-to-bottom: rank 0 at top, max rank at bottom.
 *
 * @param {object} dag - { nodes: [{id, label, cls}], edges: [[from, to]] }
 * @param {object} [options]
 * @param {number} [options.rankSpacing=80] - vertical distance between layers (before scale)
 * @param {number} [options.nodeSpacing=60] - horizontal distance between nodes (before scale)
 * @param {number} [options.scale=1.5] - global size multiplier
 * @param {number} [options.crossingPasses=24] - barycenter sweep iterations
 * @param {'straight'|'bezier'} [options.edgeStyle='bezier'] - edge rendering style
 * @param {string|object} [options.theme='mono'] - theme name or custom object
 * @returns {object} layout compatible with renderSVG()
 */
function layoutHasse(dag, options = {}) {
  const theme = resolveTheme(options.theme ?? 'mono');
  const s = options.scale ?? 1.5;
  const rankSpacing = (options.rankSpacing ?? 80) * s;
  const nodeSpacing = (options.nodeSpacing ?? 60) * s;
  const crossingPasses = options.crossingPasses ?? 24;
  const edgeStyle = options.edgeStyle ?? 'bezier';

  const { nodes, edges } = dag;
  assertValidDag(nodes, edges, 'layoutHasse');
  const { nodeMap, childrenOf, parentsOf } = buildGraph(nodes, edges);

  // Phase 1: Rank assignment
  const { topo, rank, maxRank } = topoSortAndRank(nodes, childrenOf, parentsOf);

  // Phase 2: Virtual nodes for long edges
  // Work on copies of adjacency so we don't mutate the originals
  const expandedChildren = new Map();
  const expandedParents = new Map();
  for (const [k, v] of childrenOf) expandedChildren.set(k, [...v]);
  for (const [k, v] of parentsOf) expandedParents.set(k, [...v]);

  const { virtualNodes, expandedEdges, virtualChains } =
    insertVirtualNodes(edges, rank, expandedChildren, expandedParents);

  // All node IDs (real + virtual) for layering
  const allIds = [...topo, ...virtualNodes.map(v => v.id)];

  // Phase 3: Crossing reduction
  let layers = buildLayers(allIds, rank, maxRank);
  layers = reduceCrossings(layers, expandedChildren, expandedParents, crossingPasses);

  // Phase 4: X-coordinate assignment
  const xCoord = assignXCoordinates(layers, expandedChildren, expandedParents, nodeSpacing);

  // Phase 5: Compute positions
  const topPad = 50 * s;
  const leftPad = 50 * s;

  // Shift X so minimum is at leftPad
  let minX = Infinity;
  for (const id of allIds) {
    const val = xCoord.get(id);
    if (val < minX) minX = val;
  }
  const xShift = leftPad - minX;

  const allPositions = new Map(); // includes virtual nodes
  for (const id of allIds) {
    allPositions.set(id, {
      x: xCoord.get(id) + xShift,
      y: topPad + rank.get(id) * rankSpacing,
    });
  }

  // Real node positions only (for renderSVG)
  const positions = new Map();
  for (const nd of nodes) {
    const pos = allPositions.get(nd.id);
    if (pos) positions.set(nd.id, pos);
  }

  // Compute dimensions
  let maxX = 0, maxY = 0, layoutMinY = Infinity, layoutMaxY = -Infinity;
  for (const nd of nodes) {
    const pos = positions.get(nd.id);
    if (!pos) continue;
    if (pos.x > maxX) maxX = pos.x;
    if (pos.y > maxY) maxY = pos.y;
    if (pos.y < layoutMinY) layoutMinY = pos.y;
    if (pos.y > layoutMaxY) layoutMaxY = pos.y;
  }
  const rightPad = 50 * s;
  const bottomPad = 80 * s;
  const width = maxX + rightPad;
  const height = maxY + bottomPad;

  // Phase 6: Build edge paths
  // Hasse diagrams use uniform edge color (the structure IS the information)
  const edgeColor = theme.ink;
  const opBoost = theme.lineOpacity ?? 1.0;
  const edgeThickness = 2.2 * s;
  const edgeOpacity = Math.min(0.35 * opBoost, 1);

  // Build one segment per original edge
  const segments = [];
  for (const [from, to] of edges) {
    // Collect path points: source -> virtual nodes -> target
    const chainKey = `${from}->${to}`;
    const chain = virtualChains.get(chainKey);

    let pathPoints;
    if (chain) {
      pathPoints = [
        allPositions.get(from),
        ...chain.map(vid => allPositions.get(vid)),
        allPositions.get(to),
      ];
    } else {
      pathPoints = [allPositions.get(from), allPositions.get(to)];
    }

    const d = hasseEdgePath(pathPoints, edgeStyle);
    segments.push({ d, color: edgeColor, thickness: edgeThickness, opacity: edgeOpacity, dashed: false });
  }

  // Package as routePaths: single route containing all segments
  const routePaths = [segments];

  // Route metadata for renderSVG compatibility
  const routes = [{ nodes: topo, lane: 0, parentRoute: -1, depth: 0 }];
  const nodeRoute = new Map();
  const nodeLane = new Map();
  for (const nd of nodes) {
    nodeRoute.set(nd.id, 0);
    nodeLane.set(nd.id, 0);
  }

  const centerY = (layoutMinY + layoutMaxY) / 2;

  return {
    positions,
    routePaths,
    extraEdges: [],
    width,
    height,
    maxLayer: maxRank,
    routes,
    nodeLane,
    nodeRoute,
    laneSpacing: nodeSpacing,
    layerSpacing: rankSpacing,
    minY: layoutMinY,
    maxY: layoutMaxY,
    routeYScreen: new Map([[0, centerY]]),
    trunkYScreen: centerY,
    scale: s,
    theme,
    orientation: 'ttb',
  };
}


// --- occupancy.js ---
// ================================================================
// occupancy.js — Spatial occupancy tracker for collision detection
// ================================================================
// Tracks placed rectangles in 2D space. Used by layoutFlow to
// detect and avoid collisions between tracks, cards, and labels.
//
// Uses a simple array of axis-aligned bounding boxes (AABBs).
// For our graph sizes (<100 items), brute-force AABB checks are fast enough.

/**
 * @typedef {Object} Rect
 * @property {number} x - left edge
 * @property {number} y - top edge
 * @property {number} w - width
 * @property {number} h - height
 * @property {string} [type] - 'card'|'track'|'badge'|'dot'
 * @property {string} [owner] - node/edge/route id
 */

class OccupancyGrid {
  constructor(padding = 2) {
    /** @type {Rect[]} */
    this.items = [];
    this.padding = padding;
  }

  /**
   * Check if a rect can be placed without collision.
   * @param {Rect} rect
   * @param {string|Set<string>} [ignoreOwner] - ignore items with this owner (string or Set)
   * @returns {boolean}
   */
  canPlace(rect, ignoreOwner) {
    const p = this.padding;
    for (const item of this.items) {
      if (this._ignored(item, ignoreOwner)) continue;
      if (this._overlaps(rect, item, p)) return false;
    }
    return true;
  }

  /**
   * Place a rect in the grid.
   * @param {Rect} rect
   */
  place(rect) {
    this.items.push(rect);
  }

  /**
   * Place if no collision, return success.
   * @param {Rect} rect
   * @param {string} [ignoreOwner]
   * @returns {boolean}
   */
  tryPlace(rect, ignoreOwner) {
    if (this.canPlace(rect, ignoreOwner)) {
      this.place(rect);
      return true;
    }
    return false;
  }

  /**
   * Find all items that overlap with a given rect.
   * @param {Rect} rect
   * @returns {Rect[]}
   */
  query(rect) {
    const p = this.padding;
    return this.items.filter(item => this._overlaps(rect, item, p));
  }

  /**
   * Count overlaps for a candidate rect (for scoring).
   * @param {Rect} rect
   * @param {string|Set<string>} [ignoreOwner]
   * @returns {number}
   */
  overlapCount(rect, ignoreOwner) {
    const p = this.padding;
    let count = 0;
    for (const item of this.items) {
      if (this._ignored(item, ignoreOwner)) continue;
      if (this._overlaps(rect, item, p)) count++;
    }
    return count;
  }

  /**
   * Register a line segment as a thin rectangle in the grid.
   * @param {number} x1
   * @param {number} y1
   * @param {number} x2
   * @param {number} y2
   * @param {number} thickness
   * @param {string} [owner]
   */
  placeLine(x1, y1, x2, y2, thickness, owner) {
    const t = thickness / 2;
    const rect = {
      x: Math.min(x1, x2) - t,
      y: Math.min(y1, y2) - t,
      w: Math.abs(x2 - x1) + thickness,
      h: Math.abs(y2 - y1) + thickness,
      type: 'track',
      owner,
    };
    this.items.push(rect);
  }

  /**
   * Remove all items with a given owner.
   * @param {string} owner
   */
  removeOwner(owner) {
    this.items = this.items.filter(item => item.owner !== owner);
  }

  /** @private */
  _ignored(item, ignoreOwner) {
    if (!ignoreOwner || !item.owner) return false;
    if (typeof ignoreOwner === 'string') return item.owner === ignoreOwner;
    return ignoreOwner.has(item.owner);
  }

  /**
   * @private
   */
  _overlaps(a, b, padding) {
    return !(
      a.x + a.w + padding <= b.x ||
      b.x + b.w + padding <= a.x ||
      a.y + a.h + padding <= b.y ||
      b.y + b.h + padding <= a.y
    );
  }
}


// --- layout-flow.js ---
// ================================================================
// layout-flow.js — Obstacle-aware process flow layout
// ================================================================
//
// Lays down routes one at a time, trunk-first with obstacle avoidance.
// Each element (track segment, station card, edge label) is placed
// into an occupancy grid. Subsequent elements route around obstacles.
//
// Algorithm:
//   1. Topological sort, layer assignment, column assignment (topo sort + layers)
//   2. Order routes by length (longest = trunk, laid first)
//   3. For each route:
//      a. Place station dots + cards (try RIGHT, then LEFT, then fallback)
//      b. Route segments between stations (V-H-V with collision avoidance)
//      c. Place edge labels on straight runs
//   4. Tracks that share stations maintain neighbor adjacency
//
// Routes to the RIGHT of the trunk stay right. Parallel tracks through
// shared stations maintain their relative order.




function layoutFlow(dag, options = {}) {
  const { nodes, edges } = dag;
  const theme = resolveTheme(options.theme);
  const s = options.scale ?? 1.5;
  const layerSpacing = (options.layerSpacing ?? 55) * s;
  const columnSpacing = (options.columnSpacing ?? 90) * s;
  const dotSpacing = (options.dotSpacing ?? 12) * s;
  const cornerRadius = (options.cornerRadius ?? 5) * s;
  const lineThickness = (options.lineThickness ?? 3) * s;
  const lineOpacity = Math.min((theme.lineOpacity ?? 1.0) * 0.7, 1);
  const labelSize = (options.labelSize ?? 3.6) * s;  // station card label font size
  const routes = options.routes;
  const direction = options.direction || 'ttb';
  const cardSide = options.cardSide ?? 'right'; // default card placement
  if (!Array.isArray(routes) || routes.length === 0) {
    throw new Error('layoutFlow: routes is required and must contain at least one route');
  }

  // ── Orientation abstraction ──
  // CK = column key (secondary/spread axis): 'x' for TTB, 'y' for LTR
  // LK = layer key (primary/flow axis): 'y' for TTB, 'x' for LTR
  const isLTR = direction === 'ltr';
  const CK = isLTR ? 'y' : 'x';  // column key
  const LK = isLTR ? 'x' : 'y';  // layer key

  assertValidDag(nodes, edges, 'layoutFlow');
  const { nodeMap, childrenOf, parentsOf } = buildGraph(nodes, edges);
  const classColor = {};
  for (const [cls, hex] of Object.entries(theme.classes)) classColor[cls] = hex;

  // ── STEP 1: Topological sort + layers ──
  const { topo, rank: layer } = topoSortAndRank(nodes, childrenOf, parentsOf);

  // ── STEP 2: Route membership + primary type ──
  const nodeRoutes = new Map();
  nodes.forEach(n => nodeRoutes.set(n.id, new Set()));
  routes.forEach((route, ri) => {
    route.nodes.forEach(id => nodeRoutes.get(id)?.add(ri));
  });

  const nodePrimary = new Map();
  nodes.forEach(nd => {
    const memberRoutes = nodeRoutes.get(nd.id);
    if (memberRoutes.size === 0) { nodePrimary.set(nd.id, 0); return; }
    if (memberRoutes.size === 1) { nodePrimary.set(nd.id, [...memberRoutes][0]); return; }
    // Primary = route with most edges through this node
    const routeEdgeCount = new Map();
    routes.forEach((route, ri) => {
      if (!memberRoutes.has(ri)) return;
      const idx = route.nodes.indexOf(nd.id);
      if (idx >= 0) {
        let count = 0;
        if (idx > 0) count++;
        if (idx < route.nodes.length - 1) count++;
        routeEdgeCount.set(ri, (routeEdgeCount.get(ri) || 0) + count);
      }
    });
    let bestRi = [...memberRoutes][0], bestCount = -1;
    for (const [ri, count] of routeEdgeCount) {
      if (count > bestCount || (count === bestCount && ri < bestRi)) {
        bestRi = ri; bestCount = count;
      }
    }
    nodePrimary.set(nd.id, bestRi);
  });

  // ── STEP 3: Topology-based column assignment ──
  // Instead of assigning columns by route membership, position nodes
  // based on DAG structure: the backbone (longest path) gets X=0,
  // and other nodes offset based on their distance from the backbone.

  // 3a. Find the DAG backbone — longest path from any source to any sink
  const backbone = [];
  {
    // Dynamic programming: for each node, compute longest path ending there
    const longestTo = new Map(); // nodeId → { length, prev }
    for (const id of topo) {
      const parents = parentsOf.get(id);
      if (parents.length === 0) {
        longestTo.set(id, { length: 0, prev: null });
      } else {
        let best = { length: -1, prev: null };
        for (const p of parents) {
          const pl = longestTo.get(p);
          if (pl && pl.length > best.length) best = { length: pl.length, prev: p };
        }
        longestTo.set(id, { length: best.length + 1, prev: best.prev });
      }
    }
    // Find the sink with longest path
    let endNode = topo[0], maxLen = -1;
    for (const [id, info] of longestTo) {
      if (info.length > maxLen) { maxLen = info.length; endNode = id; }
    }
    // Trace back to build backbone
    let cur = endNode;
    while (cur) {
      backbone.unshift(cur);
      cur = longestTo.get(cur)?.prev;
    }
  }
  const backboneSet = new Set(backbone);

  // 3b. Route-based columns (same as before) but with a width cap
  const columns = routes.map(() => []);
  nodes.forEach(nd => columns[nodePrimary.get(nd.id)]?.push(nd.id));
  columns.forEach(col => col.sort((a, b) => layer.get(a) - layer.get(b)));

  const activeColumns = [];
  columns.forEach((col, ri) => { if (col.length > 0) activeColumns.push({ ri, nodes: col }); });
  const nCols = activeColumns.length;
  const columnCol = new Map(); // column-axis value per route
  activeColumns.forEach((col, ci) => columnCol.set(col.ri, (ci - (nCols - 1) / 2) * columnSpacing));

  // 3c. Adaptive layer spacing — detect congested gaps, give them more room
  const maxLayer = Math.max(...[...layer.values()], 0);
  const layerPos = new Array(maxLayer + 1); // layer-axis positions
  {
    // For each gap between layer L and L+1, count complexity:
    // - routes that pass through (have nodes in both layers or straddle)
    // - routes that bend (different column at source vs dest)
    // - nodes that merge (multiple parents) or fork (multiple children)
    const layerNodeIds = new Map(); // layer → [nodeId]
    nodes.forEach(nd => {
      const l = layer.get(nd.id);
      if (!layerNodeIds.has(l)) layerNodeIds.set(l, []);
      layerNodeIds.get(l).push(nd.id);
    });

    // Compute raw column-axis value per node for congestion analysis (before positions exist)
    const rawCol = new Map();
    nodes.forEach(nd => {
      const memberRoutes = nodeRoutes.get(nd.id);
      let col;
      if (memberRoutes.size <= 1) {
        col = columnCol.get(nodePrimary.get(nd.id)) ?? 0;
      } else {
        const colVals = [...memberRoutes].map(ri => columnCol.get(ri)).filter(v => v !== undefined);
        const uniqueVals = [...new Set(colVals)];
        col = uniqueVals.length > 0 ? uniqueVals.reduce((a, b) => a + b, 0) / uniqueVals.length : 0;
      }
      rawCol.set(nd.id, col);
    });

    layerPos[0] = 0;
    for (let l = 0; l < maxLayer; l++) {
      const topNodes = layerNodeIds.get(l) || [];
      const botNodes = layerNodeIds.get(l + 1) || [];

      // Count routes that cross this gap (have a node in layer l and l+1)
      const topRouteSet = new Set();
      const botRouteSet = new Set();
      topNodes.forEach(id => nodeRoutes.get(id)?.forEach(ri => topRouteSet.add(ri)));
      botNodes.forEach(id => nodeRoutes.get(id)?.forEach(ri => botRouteSet.add(ri)));
      const crossingRoutes = [...topRouteSet].filter(ri => botRouteSet.has(ri));

      // Count bending routes (different column value at top vs bottom of this gap)
      let benders = 0;
      for (const ri of crossingRoutes) {
        const route = routes[ri];
        for (let i = 1; i < route.nodes.length; i++) {
          const fId = route.nodes[i - 1], tId = route.nodes[i];
          const fL = layer.get(fId), tL = layer.get(tId);
          if (fL === l && tL === l + 1) {
            const fc = rawCol.get(fId) ?? 0, tc = rawCol.get(tId) ?? 0;
            if (Math.abs(tc - fc) > dotSpacing) benders++;
          }
        }
      }

      // Count merge/fork complexity at bottom layer nodes
      let mergeFork = 0;
      for (const id of botNodes) {
        const pCount = parentsOf.get(id)?.length ?? 0;
        if (pCount > 1) mergeFork += pCount - 1;
      }
      for (const id of topNodes) {
        const cCount = childrenOf.get(id)?.length ?? 0;
        if (cCount > 1) mergeFork += cCount - 1;
      }

      // Compute multiplier: base 1.0, +0.25 per bender, +0.15 per merge/fork, capped at 2.0
      const multiplier = Math.min(2.0, 1.0 + benders * 0.25 + mergeFork * 0.15);
      layerPos[l + 1] = layerPos[l] + layerSpacing * multiplier;
    }
  }

  // 3d. Compute raw positions (centroid-based) with adaptive layer positions
  const positions = new Map();
  nodes.forEach(nd => {
    const memberRoutes = nodeRoutes.get(nd.id);
    let colVal;
    if (memberRoutes.size <= 1) {
      colVal = columnCol.get(nodePrimary.get(nd.id)) ?? 0;
    } else {
      const colVals = [...memberRoutes].map(ri => columnCol.get(ri)).filter(v => v !== undefined);
      const uniqueVals = [...new Set(colVals)];
      colVal = uniqueVals.length > 0 ? uniqueVals.reduce((a, b) => a + b, 0) / uniqueVals.length : 0;
    }
    const layerVal = layerPos[layer.get(nd.id)] ?? (layer.get(nd.id) * layerSpacing);
    positions.set(nd.id, { [CK]: colVal, [LK]: layerVal });
  });

  // 3d. Pull backbone nodes toward their spine (reduces drift)
  if (backbone.length >= 3) {
    const boneCols = backbone.map(id => positions.get(id)?.[CK]).filter(v => v !== undefined);
    const boneSpan = Math.max(...boneCols) - Math.min(...boneCols);
    if (boneSpan > columnSpacing * 1.5) {
      boneCols.sort((a, b) => a - b);
      const spineCol = boneCols[Math.floor(boneCols.length / 2)];
      // Pull strength proportional to how badly it drifts
      const pull = Math.min(0.6, boneSpan / (columnSpacing * 8));
      for (const id of backbone) {
        const pos = positions.get(id);
        if (!pos) continue;
        pos[CK] = pos[CK] * (1 - pull) + spineCol * pull;
      }
    }
  }

  // ── STEP 4: Separate same-layer nodes that overlap in column axis ──
  const layerNodes = new Map();
  nodes.forEach(nd => {
    const l = layer.get(nd.id);
    if (!layerNodes.has(l)) layerNodes.set(l, []);
    layerNodes.get(l).push(nd.id);
  });
  for (const [, ids] of layerNodes) {
    if (ids.length < 2) continue;
    ids.sort((a, b) => positions.get(a)[CK] - positions.get(b)[CK]);
    for (let i = 1; i < ids.length; i++) {
      const prev = positions.get(ids[i - 1]);
      const curr = positions.get(ids[i]);
      const minGap = columnSpacing * 0.5;
      if (curr[CK] - prev[CK] < minGap) {
        curr[CK] = prev[CK] + minGap;
      }
    }
  }

  // Normalize — margins are orientation-aware
  const margin = isLTR
    ? { top: 80 * s, left: 50 * s, bottom: 140 * s, right: 40 * s }
    : { top: 50 * s, left: 80 * s, bottom: 40 * s, right: 140 * s };
  let minCK = Infinity, maxCK = -Infinity, minLK = Infinity, maxLK = -Infinity;
  positions.forEach(pos => {
    if (pos[CK] < minCK) minCK = pos[CK]; if (pos[CK] > maxCK) maxCK = pos[CK];
    if (pos[LK] < minLK) minLK = pos[LK]; if (pos[LK] > maxLK) maxLK = pos[LK];
  });
  // For CK (column axis): shift by left margin (TTB) or top margin (LTR)
  // For LK (layer axis): shift by top margin (TTB) or left margin (LTR)
  const ckShift = -minCK + (isLTR ? margin.top : margin.left);
  const lkShift = -minLK + (isLTR ? margin.left : margin.top);
  positions.forEach(pos => { pos[CK] += ckShift; pos[LK] = pos[LK] - minLK + (isLTR ? margin.left : margin.top); });

  // ── STEP 5: Flow layout — sequential, obstacle-aware ──
  const grid = new OccupancyGrid(2);        // tracks + cards + dots
  const badgeGrid = new OccupancyGrid(2);   // edge labels only (don't block routes)

  // Sort routes: longest first (trunk gets best placement)
  const routeOrder = routes.map((_, ri) => ri)
    .sort((a, b) => routes[b].nodes.length - routes[a].nodes.length);

  // Track waypoint column for each route at each node (for parallel adjacency)
  const waypointX = new Map(); // "nodeId:routeIdx" → column value

  // Track card placements
  const cardPlacements = new Map(); // nodeId → { rect, side }
  const placedNodes = new Set();

  // For each route at a node, compute the average column-axis value of
  // neighboring nodes in that route (prev + next). Used to order dots
  // so lines don't cross.
  function neighborCol(nodeId, ri) {
    const route = routes[ri];
    if (!route) return positions.get(nodeId)?.[CK] ?? 0;
    const idx = route.nodes.indexOf(nodeId);
    if (idx < 0) return positions.get(nodeId)?.[CK] ?? 0;
    let sum = 0, count = 0;
    if (idx > 0) {
      const p = positions.get(route.nodes[idx - 1]);
      if (p) { sum += p[CK]; count++; }
    }
    if (idx < route.nodes.length - 1) {
      const p = positions.get(route.nodes[idx + 1]);
      if (p) { sum += p[CK]; count++; }
    }
    return count > 0 ? sum / count : (positions.get(nodeId)?.[CK] ?? 0);
  }

  // Global side assignment: each non-trunk route gets a FIXED side
  // (left or right of the trunk) that it maintains at every node.
  // This prevents crossings — once a route is on the left, it stays left.
  const trunkRi = routeOrder[0]; // longest route

  // Compute the trunk's average column value as the spine reference
  const trunkAvgCol = (() => {
    const cols = routes[trunkRi].nodes.map(id => positions.get(id)?.[CK]).filter(v => v !== undefined);
    return cols.length > 0 ? cols.reduce((a, b) => a + b, 0) / cols.length : 0;
  })();

  // For each non-trunk route, determine its side by where its nodes
  // tend to be relative to the trunk spine.
  const routeSide = new Map(); // ri → -1 (left) | 0 (on trunk) | 1 (right)
  routeSide.set(trunkRi, 0);

  routes.forEach((route, ri) => {
    if (ri === trunkRi) return;
    // Compute avg column of this route's nodes that are NOT shared with trunk
    const trunkNodeSet = new Set(routes[trunkRi].nodes);
    const uniqueNodes = route.nodes.filter(id => !trunkNodeSet.has(id));
    let avgCol;
    if (uniqueNodes.length > 0) {
      const cols = uniqueNodes.map(id => positions.get(id)?.[CK]).filter(v => v !== undefined);
      avgCol = cols.length > 0 ? cols.reduce((a, b) => a + b, 0) / cols.length : trunkAvgCol;
    } else {
      // All nodes shared with trunk — use neighbor direction at first shared node
      const firstShared = route.nodes.find(id => trunkNodeSet.has(id));
      avgCol = firstShared ? neighborCol(firstShared, ri) : trunkAvgCol;
    }
    routeSide.set(ri, avgCol < trunkAvgCol - 1 ? -1 : avgCol > trunkAvgCol + 1 ? 1 : 1);
  });

  // Assign a global sort key: left routes get negative keys, trunk=0, right=positive
  // Within same side, sort by route index for consistency
  const routeSortKey = new Map();
  {
    const leftRoutes = [...routeSide.entries()].filter(([, s]) => s < 0).map(([ri]) => ri).sort((a, b) => a - b);
    const rightRoutes = [...routeSide.entries()].filter(([, s]) => s > 0).map(([ri]) => ri).sort((a, b) => a - b);
    leftRoutes.forEach((ri, i) => routeSortKey.set(ri, -(leftRoutes.length - i)));
    routeSortKey.set(trunkRi, 0);
    rightRoutes.forEach((ri, i) => routeSortKey.set(ri, i + 1));
  }

  const dotOrderCache = new Map();
  function getDotOrder(nodeId) {
    if (dotOrderCache.has(nodeId)) return dotOrderCache.get(nodeId);
    const memberRoutes = nodeRoutes.get(nodeId);
    if (!memberRoutes || memberRoutes.size <= 1) {
      const list = memberRoutes ? [...memberRoutes] : [];
      dotOrderCache.set(nodeId, list);
      return list;
    }

    // Sort by global side assignment — consistent at every node
    const sorted = [...memberRoutes].sort((a, b) => {
      const ka = routeSortKey.get(a) ?? a;
      const kb = routeSortKey.get(b) ?? b;
      return ka !== kb ? ka - kb : a - b;
    });

    dotOrderCache.set(nodeId, sorted);
    return sorted;
  }

  // Precompute trunk's ABSOLUTE column position: propagate from node to node
  // so the trunk forms a perfectly straight spine. At single-route nodes
  // the trunk is at pos[CK]. Once established, the absolute column propagates
  // forward regardless of column changes at merge/fork points.
  const trunkAbsCol = new Map(); // nodeId → absolute column for trunk dot
  {
    let prevAbsCol = null;
    for (const nodeId of routes[trunkRi].nodes) {
      const pos = positions.get(nodeId);
      if (!pos) continue;
      const memberRoutes = nodeRoutes.get(nodeId);

      if (!memberRoutes || memberRoutes.size <= 1) {
        // Single-route node: trunk at node center
        const absCol = pos[CK];
        trunkAbsCol.set(nodeId, absCol);
        prevAbsCol = absCol;
      } else if (prevAbsCol !== null) {
        // Propagate previous absolute column — trunk stays straight
        trunkAbsCol.set(nodeId, prevAbsCol);
      } else {
        // First multi-route node: compute default position
        const sorted = getDotOrder(nodeId);
        const localIdx = sorted.indexOf(trunkRi);
        const n = sorted.length;
        const absCol = pos[CK] + (localIdx - (n - 1) / 2) * dotSpacing;
        trunkAbsCol.set(nodeId, absCol);
        prevAbsCol = absCol;
      }
    }
  }

  // Precompute dot positions for all routes at each node.
  // The trunk gets its propagated fixed position. Other routes are
  // spaced evenly around it, maintaining consistent dotSpacing.
  const nodeDotPositions = new Map(); // nodeId → Map<ri, columnValue>

  for (const [nodeId, memberRoutes] of nodeRoutes) {
    const pos = positions.get(nodeId);
    if (!pos) continue;
    const dotMap = new Map();

    if (memberRoutes.size <= 1) {
      for (const ri of memberRoutes) dotMap.set(ri, pos[CK]);
    } else {
      const sorted = getDotOrder(nodeId);
      const hasTrunk = sorted.includes(trunkRi) && trunkAbsCol.has(nodeId);

      const trunkCol = trunkAbsCol.get(nodeId);
      if (hasTrunk && trunkCol !== undefined) {
        // Anchor: trunk at its fixed absolute position. Pack others around it.
        const trunkIdx = sorted.indexOf(trunkRi);
        for (let i = 0; i < sorted.length; i++) {
          dotMap.set(sorted[i], trunkCol + (i - trunkIdx) * dotSpacing);
        }
      } else {
        // No trunk — standard dense centering
        const n = sorted.length;
        const center = (n - 1) / 2;
        for (let i = 0; i < sorted.length; i++) {
          dotMap.set(sorted[i], pos[CK] + (i - center) * dotSpacing);
        }
      }
    }

    nodeDotPositions.set(nodeId, dotMap);
  }

  // dotCol returns the column-axis coordinate of a dot
  function dotCol(nodeId, ri) {
    const dotMap = nodeDotPositions.get(nodeId);
    if (dotMap && dotMap.has(ri)) return dotMap.get(ri);
    return positions.get(nodeId)?.[CK] ?? 0;
  }

  // dotX returns the X-coordinate of a dot (regardless of orientation)
  function dotX(nodeId, ri) {
    if (isLTR) {
      // In LTR: column axis is Y, layer axis is X
      // dotX should return the X-coordinate, which is the layer position
      return positions.get(nodeId)?.x ?? 0;
    }
    // In TTB: column axis is X, so dotCol = X
    return dotCol(nodeId, ri);
  }

  // dotPos returns {x, y} for a dot — the actual screen coordinates
  function dotPos(nodeId, ri) {
    const dc = dotCol(nodeId, ri);
    const pos = positions.get(nodeId);
    if (!pos) return { x: 0, y: 0 };
    if (isLTR) {
      return { x: pos.x, y: dc };
    } else {
      return { x: dc, y: pos.y };
    }
  }

  // Place a station card, trying multiple positions
  function placeCard(nodeId, fsLabel, fsData) {
    if (placedNodes.has(nodeId)) return;
    placedNodes.add(nodeId);

    const nd = nodeMap.get(nodeId);
    const pos = positions.get(nodeId);
    if (!nd || !pos) return;

    const memberRoutes = nodeRoutes.get(nodeId);
    const routeIndices = [...memberRoutes].sort((a, b) => a - b);
    const n = routeIndices.length;

    // Compute dots span (in column-axis)
    const dcs = routeIndices.map(ri => dotCol(nodeId, ri));
    const rightmostDot = Math.max(...dcs);
    const leftmostDot = Math.min(...dcs);
    const dotR = 3.2 * s;

    // Card dimensions (always in screen w/h)
    const labelW = nd.label.length * fsLabel * 0.52;
    const indicatorW = n * 5 * s;
    const metricValue = nd.times ?? nd.count;
    const metricText = metricValue === undefined || metricValue === null ? '' : String(metricValue);
    const dataW = metricText.length * fsData * 0.55;
    const contentW = Math.max(labelW, indicatorW + dataW + 4 * s);
    const cardPadX = 5 * s;
    const cardPadY = 3 * s;
    const cardW = contentW + cardPadX * 2;
    const cardH = fsLabel + fsData + cardPadY * 2 + 3 * s;
    const cardGap = 4 * s;

    let candidates;
    if (isLTR) {
      // LTR: cards above/below dots (column axis is Y), centered at pos.x
      const baseAbove = leftmostDot - dotR - cardGap - cardH;
      const baseBelow = rightmostDot + dotR + cardGap;
      const xCenter = pos.x - cardW / 2;
      const xShiftAmt = cardW + 4 * s;
      candidates = [
        { side: 'right', x: xCenter, y: baseBelow },     // below
        { side: 'left',  x: xCenter, y: baseAbove },     // above
        { side: 'right', x: xCenter - xShiftAmt, y: baseBelow },  // below, left
        { side: 'right', x: xCenter + xShiftAmt, y: baseBelow },  // below, right
        { side: 'left',  x: xCenter - xShiftAmt, y: baseAbove },  // above, left
        { side: 'left',  x: xCenter + xShiftAmt, y: baseAbove },  // above, right
      ];
    } else {
      // TTB: cards to right/left of dots (column axis is X), centered at pos.y
      const baseRight = rightmostDot + dotR + cardGap;
      const baseLeft = leftmostDot - dotR - cardGap - cardW;
      const yCenter = pos.y - cardH / 2;
      const yShift = cardH + 4 * s;
      candidates = [
        { side: 'right', x: baseRight, y: yCenter },
        { side: 'left',  x: baseLeft,  y: yCenter },
        { side: 'right', x: baseRight, y: yCenter - yShift },
        { side: 'right', x: baseRight, y: yCenter + yShift },
        { side: 'left',  x: baseLeft,  y: yCenter - yShift },
        { side: 'left',  x: baseLeft,  y: yCenter + yShift },
      ];
    }

    let placed = false;
    for (const c of candidates) {
      const rect = { x: c.x, y: c.y, w: cardW, h: cardH, type: 'card', owner: `card_${nodeId}` };
      if (grid.tryPlace(rect)) {
        cardPlacements.set(nodeId, { rect, side: c.side, cardW, cardH, cardPadX, cardPadY });
        placed = true;
        break;
      }
    }

    // Fallback: place first candidate regardless of collision (better than nothing)
    if (!placed) {
      const c = candidates[0];
      const rect = { x: c.x, y: c.y, w: cardW, h: cardH, type: 'card', owner: `card_${nodeId}` };
      grid.place(rect);
      cardPlacements.set(nodeId, { rect, side: candidates[0].side, cardW, cardH, cardPadX, cardPadY });
    }
  }

  // Build route path string with rounded elbows — orientation-aware
  // TTB: V-H-V paths. LTR: H-V-H paths.
  // px,py,qx,qy are always screen coordinates.
  // midFrac applies to the primary axis (layer axis).
  function buildRoute(px, py, qx, qy, midFrac, r) {
    const dx = qx - px, dy = qy - py;
    // "same column" check: column-axis difference < 1
    const colDiff = isLTR ? Math.abs(dy) : Math.abs(dx);
    const layerDiff = isLTR ? Math.abs(dx) : Math.abs(dy);
    if (colDiff < 1) return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
    if (layerDiff < 1) return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };

    if (isLTR) {
      // H-V-H path: horizontal run → vertical jog at midX → horizontal run
      const cr = Math.min(r, Math.abs(dy) / 2, Math.abs(dx) / 2);
      const midX = px + dx * midFrac;
      const sx = Math.sign(dx), sy = Math.sign(dy);

      // First elbow at (midX, py)
      const e1x = midX - sx * cr;
      const e1ey = py + sy * cr;
      // Second elbow at (midX, qy)
      const e2y = qy - sy * cr;
      const e2ex = midX + sx * cr;

      let d = `M ${px.toFixed(1)} ${py.toFixed(1)} `;
      d += `L ${e1x.toFixed(1)} ${py.toFixed(1)} `;
      d += `Q ${midX.toFixed(1)} ${py.toFixed(1)} ${midX.toFixed(1)} ${e1ey.toFixed(1)} `;
      d += `L ${midX.toFixed(1)} ${e2y.toFixed(1)} `;
      d += `Q ${midX.toFixed(1)} ${qy.toFixed(1)} ${e2ex.toFixed(1)} ${qy.toFixed(1)} `;
      d += `L ${qx.toFixed(1)} ${qy.toFixed(1)}`;

      return { d, jogPos: midX };
    } else {
      // V-H-V path: vertical run → horizontal jog at midY → vertical run
      const cr = Math.min(r, Math.abs(dx) / 2, Math.abs(dy) / 2);
      const midY = py + dy * midFrac;
      const sy = Math.sign(dy), sx = Math.sign(dx);

      // First elbow at (px, midY)
      const e1y = midY - sy * cr;
      const e1ex = px + sx * cr;
      // Second elbow at (qx, midY)
      const e2x = qx - sx * cr;
      const e2ey = midY + sy * cr;

      let d = `M ${px.toFixed(1)} ${py.toFixed(1)} `;
      d += `L ${px.toFixed(1)} ${e1y.toFixed(1)} `;
      d += `Q ${px.toFixed(1)} ${midY.toFixed(1)} ${e1ex.toFixed(1)} ${midY.toFixed(1)} `;
      d += `L ${e2x.toFixed(1)} ${midY.toFixed(1)} `;
      d += `Q ${qx.toFixed(1)} ${midY.toFixed(1)} ${qx.toFixed(1)} ${e2ey.toFixed(1)} `;
      d += `L ${qx.toFixed(1)} ${qy.toFixed(1)}`;

      return { d, jogPos: midY };
    }
  }

  // Check collision for all 3 segments of a route path — orientation-aware
  function scoreRoute(px, py, qx, qy, jogPos, ignore) {
    const t = lineThickness;
    if (isLTR) {
      // H-V-H: horiz run 1, vert jog, horiz run 2
      const h1 = { x: Math.min(px, jogPos) - t, y: py - t * 2, w: Math.abs(jogPos - px) + t * 2, h: t * 4, type: 'track' };
      const vj = { x: jogPos - t, y: Math.min(py, qy), w: t * 2, h: Math.abs(qy - py), type: 'track' };
      const h2 = { x: Math.min(jogPos, qx) - t, y: qy - t * 2, w: Math.abs(qx - jogPos) + t * 2, h: t * 4, type: 'track' };
      return grid.overlapCount(h1, ignore) + grid.overlapCount(vj, ignore) + grid.overlapCount(h2, ignore);
    } else {
      // V-H-V: vert run 1, horiz jog, vert run 2
      const v1 = { x: px - t, y: Math.min(py, jogPos), w: t * 2, h: Math.abs(jogPos - py), type: 'track' };
      const hj = { x: Math.min(px, qx) - t, y: jogPos - t * 2, w: Math.abs(qx - px) + t * 2, h: t * 4, type: 'track' };
      const v2 = { x: qx - t, y: Math.min(jogPos, qy), w: t * 2, h: Math.abs(qy - jogPos), type: 'track' };
      return grid.overlapCount(v1, ignore) + grid.overlapCount(hj, ignore) + grid.overlapCount(v2, ignore);
    }
  }

  // Register all 3 segments of a route path in the grid — orientation-aware
  function registerRoute(px, py, qx, qy, jogPos, owner) {
    if (isLTR) {
      // H-V-H
      grid.placeLine(px, py, jogPos, py, lineThickness, owner);
      grid.placeLine(jogPos, py, jogPos, qy, lineThickness, owner);
      grid.placeLine(jogPos, qy, qx, qy, lineThickness, owner);
    } else {
      // V-H-V
      grid.placeLine(px, py, px, jogPos, lineThickness, owner);
      grid.placeLine(px, jogPos, qx, jogPos, lineThickness, owner);
      grid.placeLine(qx, jogPos, qx, qy, lineThickness, owner);
    }
  }

  // Route a segment with collision avoidance.
  // Returns { d, jogPos } — jogPos is the jog coordinate on the primary axis (null for straight).
  // ignore: Set of owners to ignore in collision checks (segment + endpoint nodes)
  function routeSegment(px, py, qx, qy, ri, owner, ignore, assignedMidFrac) {
    const r = cornerRadius;

    // "Same column" check: column-axis difference < 1
    const colDiff = isLTR ? Math.abs(qy - py) : Math.abs(qx - px);
    const layerDiff = isLTR ? Math.abs(qx - px) : Math.abs(qy - py);

    // Straight along primary axis — check for card collisions (excluding endpoint nodes)
    if (colDiff < 1) {
      // Shrink along layer axis by lineThickness at each end to avoid false positives
      const shrink = lineThickness;
      if (isLTR) {
        // Straight horizontal line (same Y)
        const checkX = Math.min(px, qx) + shrink;
        const checkW = Math.abs(qx - px) - 2 * shrink;
        if (checkW <= 0) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }
        const hRect = { x: checkX, y: py - lineThickness, w: checkW, h: lineThickness * 2, type: 'track' };
        const collisions = grid.overlapCount(hRect, ignore);

        if (collisions === 0) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }

        // Straight horizontal segment hits obstacle — detour up/down
        const detourDist = 15 * s;
        const upY = py - detourDist;
        const downY = py + detourDist;

        const upScore = scoreRoute(px, py, qx, upY, (px + qx) / 2, ignore)
          + scoreRoute(qx, upY, qx, qy, (px + qx) * 0.7, ignore);
        const downScore = scoreRoute(px, py, qx, downY, (px + qx) / 2, ignore)
          + scoreRoute(qx, downY, qx, qy, (px + qx) * 0.7, ignore);

        const detourY = upScore <= downScore ? upY : downY;
        const midX1 = px + (qx - px) * 0.3;
        const midX2 = px + (qx - px) * 0.7;

        const cr = Math.min(r, detourDist / 2, Math.abs(midX1 - px) / 2);
        if (cr < 1) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }

        // H-V-H-V-H detour path
        const sx = Math.sign(qx - px);
        const sy = Math.sign(detourY - py);
        let d = `M ${px.toFixed(1)} ${py.toFixed(1)} `;
        d += `L ${(midX1 - sx * cr).toFixed(1)} ${py.toFixed(1)} `;
        d += `Q ${midX1.toFixed(1)} ${py.toFixed(1)} ${midX1.toFixed(1)} ${(py + sy * cr).toFixed(1)} `;
        d += `L ${midX1.toFixed(1)} ${(detourY - sy * cr).toFixed(1)} `;
        d += `Q ${midX1.toFixed(1)} ${detourY.toFixed(1)} ${(midX1 + sx * cr).toFixed(1)} ${detourY.toFixed(1)} `;
        d += `L ${(midX2 - sx * cr).toFixed(1)} ${detourY.toFixed(1)} `;
        d += `Q ${midX2.toFixed(1)} ${detourY.toFixed(1)} ${midX2.toFixed(1)} ${(detourY - sy * cr).toFixed(1)} `;
        d += `L ${midX2.toFixed(1)} ${(qy + sy * cr).toFixed(1)} `;
        d += `Q ${midX2.toFixed(1)} ${qy.toFixed(1)} ${(midX2 + sx * cr).toFixed(1)} ${qy.toFixed(1)} `;
        d += `L ${qx.toFixed(1)} ${qy.toFixed(1)}`;

        grid.placeLine(px, py, midX1, py, lineThickness, owner);
        grid.placeLine(midX1, py, midX1, detourY, lineThickness, owner);
        grid.placeLine(midX1, detourY, midX2, detourY, lineThickness, owner);
        grid.placeLine(midX2, detourY, midX2, qy, lineThickness, owner);
        grid.placeLine(midX2, qy, qx, qy, lineThickness, owner);
        return { d, jogPos: midX1 };
      } else {
        // TTB: Straight vertical line (same X)
        const checkY = Math.min(py, qy) + shrink;
        const checkH = Math.abs(qy - py) - 2 * shrink;
        if (checkH <= 0) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }
        const vRect = { x: px - lineThickness, y: checkY, w: lineThickness * 2, h: checkH, type: 'track' };
        const collisions = grid.overlapCount(vRect, ignore);

        if (collisions === 0) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }

        // Vertical segment hits a real obstacle — detour left/right
        const detourDist = 15 * s;
        const leftX = px - detourDist;
        const rightX = px + detourDist;

        const leftScore = scoreRoute(px, py, leftX, qy, (py + qy) / 2, ignore)
          + scoreRoute(leftX, (py + qy) / 2, qx, qy, (py + qy) * 0.7, ignore);
        const rightScore = scoreRoute(px, py, rightX, qy, (py + qy) / 2, ignore)
          + scoreRoute(rightX, (py + qy) / 2, qx, qy, (py + qy) * 0.7, ignore);

        const detourX = leftScore <= rightScore ? leftX : rightX;
        const midY1 = py + (qy - py) * 0.3;
        const midY2 = py + (qy - py) * 0.7;

        const cr = Math.min(r, detourDist / 2, Math.abs(midY1 - py) / 2);
        if (cr < 1) {
          grid.placeLine(px, py, qx, qy, lineThickness, owner);
          return { d: `M ${px.toFixed(1)} ${py.toFixed(1)} L ${qx.toFixed(1)} ${qy.toFixed(1)}`, jogPos: null };
        }

        // V-H-V-H-V detour path
        const sx = Math.sign(detourX - px);
        const sy = Math.sign(qy - py);
        let d = `M ${px.toFixed(1)} ${py.toFixed(1)} `;
        d += `L ${px.toFixed(1)} ${(midY1 - sy * cr).toFixed(1)} `;
        d += `Q ${px.toFixed(1)} ${midY1.toFixed(1)} ${(px + sx * cr).toFixed(1)} ${midY1.toFixed(1)} `;
        d += `L ${(detourX - sx * cr).toFixed(1)} ${midY1.toFixed(1)} `;
        d += `Q ${detourX.toFixed(1)} ${midY1.toFixed(1)} ${detourX.toFixed(1)} ${(midY1 + sy * cr).toFixed(1)} `;
        d += `L ${detourX.toFixed(1)} ${(midY2 - sy * cr).toFixed(1)} `;
        d += `Q ${detourX.toFixed(1)} ${midY2.toFixed(1)} ${(detourX - sx * cr).toFixed(1)} ${midY2.toFixed(1)} `;
        d += `L ${(qx + sx * cr).toFixed(1)} ${midY2.toFixed(1)} `;
        d += `Q ${qx.toFixed(1)} ${midY2.toFixed(1)} ${qx.toFixed(1)} ${(midY2 + sy * cr).toFixed(1)} `;
        d += `L ${qx.toFixed(1)} ${qy.toFixed(1)}`;

        grid.placeLine(px, py, px, midY1, lineThickness, owner);
        grid.placeLine(px, midY1, detourX, midY1, lineThickness, owner);
        grid.placeLine(detourX, midY1, detourX, midY2, lineThickness, owner);
        grid.placeLine(detourX, midY2, qx, midY2, lineThickness, owner);
        grid.placeLine(qx, midY2, qx, qy, lineThickness, owner);
        return { d, jogPos: midY1 };
      }
    }

    // Non-straight: try multiple midFrac values, score ALL segments.
    // For small column diff (dot centering shifts), prefer extreme midFrac to push
    // the jog close to a node — makes the short cross run less visible.
    const dotR = 3.2 * s;
    const hiddenFrac = layerDiff > 0 ? Math.max(0.5, 1 - dotR / layerDiff) : 0.5;
    // Use pre-assigned staggered midFrac first (crossing avoidance),
    // then fall back to defaults
    const baseFracs = colDiff <= dotSpacing
      ? [hiddenFrac, 1 - hiddenFrac, 0.85, 0.15]
      : [0.5, 0.35, 0.65, 0.25, 0.75, 0.15, 0.85];
    const midFracs = assignedMidFrac !== undefined
      ? [assignedMidFrac, ...baseFracs.filter(f => Math.abs(f - assignedMidFrac) > 0.05)]
      : baseFracs;
    let bestD = null;
    let bestMf = 0.5;
    let bestCollisions = Infinity;

    for (const mf of midFracs) {
      const { d, jogPos } = buildRoute(px, py, qx, qy, mf, r);
      if (jogPos === null) return { d, jogPos: null };

      const collisions = scoreRoute(px, py, qx, qy, jogPos, ignore);
      if (collisions === 0) {
        registerRoute(px, py, qx, qy, jogPos, owner);
        return { d, jogPos };
      }
      if (collisions < bestCollisions) {
        bestCollisions = collisions;
        bestD = d;
        bestMf = mf;
      }
    }

    // Register the best option even if it has collisions
    // Compute jogPos from midFrac along the primary axis
    const bestJogPos = isLTR
      ? px + (qx - px) * bestMf
      : py + (qy - py) * bestMf;
    registerRoute(px, py, qx, qy, bestJogPos, owner);
    return { d: bestD, jogPos: bestJogPos };
  }

  // ── STEP 6: Lay routes sequentially ──
  const fsLabel = labelSize;
  const fsData = labelSize * 0.78;  // data text slightly smaller than label
  const routePaths = routes.map(() => []);
  const edgeLabelPositions = new Map(); // "from→to" → {x, y, color}

  // Phase A: Register all dots + place ALL cards BEFORE routing.
  // This ensures routes will avoid all cards.
  const dotR = 3.2 * s;
  for (const ri of routeOrder) {
    for (const nodeId of routes[ri].nodes) {
      if (!placedNodes.has(nodeId)) {
        const dcs = [...nodeRoutes.get(nodeId)].map(r => dotCol(nodeId, r));
        dcs.forEach(dc => {
          const pos = positions.get(nodeId);
          if (!pos) return;
          const dotRect = isLTR
            ? { x: pos.x - dotR, y: dc - dotR, w: dotR * 2, h: dotR * 2, type: 'dot', owner: nodeId }
            : { x: dc - dotR, y: pos.y - dotR, w: dotR * 2, h: dotR * 2, type: 'dot', owner: nodeId };
          grid.place(dotRect);
        });
        placedNodes.add(nodeId);
      }
    }
  }
  placedNodes.clear(); // reset for card placement
  for (const ri of routeOrder) {
    for (const nodeId of routes[ri].nodes) {
      placeCard(nodeId, fsLabel, fsData);
    }
  }

  // Pre-compute staggered jog assignments for crossing avoidance.
  // For each layer gap, routes that bend are assigned different midFrac
  // values so their horizontal jogs don't overlap.
  const jogAssignments = new Map(); // "fromLayer→toLayer" → Map<ri, midFrac>
  {
    const gapBenders = new Map(); // "layerA→layerB" → [{ri, fromCol, toCol}]
    routes.forEach((route, ri) => {
      for (let i = 1; i < route.nodes.length; i++) {
        const fromId = route.nodes[i - 1], toId = route.nodes[i];
        const fromPos = positions.get(fromId), toPos = positions.get(toId);
        if (!fromPos || !toPos) continue;
        const fromLayer = layer.get(fromId), toLayer = layer.get(toId);
        const fc = dotCol(fromId, ri), tc = dotCol(toId, ri);
        if (Math.abs(tc - fc) < 1) continue; // straight, no bend
        const gapKey = `${fromLayer}\u2192${toLayer}`;
        if (!gapBenders.has(gapKey)) gapBenders.set(gapKey, []);
        gapBenders.get(gapKey).push({ ri, fromCol: fc, toCol: tc });
      }
    });
    for (const [gapKey, benders] of gapBenders) {
      if (benders.length < 2) continue;

      // Only stagger when routes bend in OPPOSITE directions.
      // Routes going the same direction should stay parallel.
      const hasLeft = benders.some(b => b.toCol < b.fromCol);
      const hasRight = benders.some(b => b.toCol > b.fromCol);
      if (!hasLeft || !hasRight) continue; // all same direction — skip

      // Sort by destination column: leftmost dest jogs near source,
      // rightmost dest jogs near destination. This prevents crossings.
      benders.sort((a, b) => a.toCol - b.toCol);
      const n = benders.length;
      const assignment = new Map();
      benders.forEach((b, i) => {
        const frac = n === 1 ? 0.5 : 0.25 + (i / (n - 1)) * 0.5;
        assignment.set(b.ri, frac);
      });
      jogAssignments.set(gapKey, assignment);
    }
  }

  // Phase B: Route ALL segments (grid has dots + cards as obstacles)
  for (const ri of routeOrder) {
    const route = routes[ri];
    const color = classColor[route.cls] || Object.values(classColor)[0];
    const waypoints = route.nodes.map(id => {
      const pos = positions.get(id);
      if (!pos) return null;
      const dc = dotCol(id, ri);
      // Waypoint in screen coordinates
      if (isLTR) {
        return { id, x: pos.x, y: dc };
      } else {
        return { id, x: dc, y: pos.y };
      }
    }).filter(Boolean);

    const routeOwner = `route${ri}`;
    const segments = [];
    for (let i = 1; i < waypoints.length; i++) {
      const p = waypoints[i - 1], q = waypoints[i];
      // "small column diff" check uses the column-axis distance
      const smallColDiff = isLTR ? Math.abs(q.y - p.y) <= dotSpacing : Math.abs(q.x - p.x) <= dotSpacing;
      const ignoreSet = smallColDiff
        ? new Set([routeOwner, p.id, q.id, `card_${p.id}`, `card_${q.id}`])
        : new Set([routeOwner, p.id, q.id]);

      // Use pre-assigned staggered midFrac for crossing avoidance
      const fromLayer = layer.get(p.id), toLayer = layer.get(q.id);
      const gapKey = `${fromLayer}\u2192${toLayer}`;
      const gapAssign = jogAssignments.get(gapKey);
      const assignedMidFrac = gapAssign?.get(ri);

      const result = routeSegment(p.x, p.y, q.x, q.y, ri, routeOwner, ignoreSet, assignedMidFrac);
      const srcDim = nodeMap.get(p.id)?.dim === true;
      const dstDim = nodeMap.get(q.id)?.dim === true;
      const segOpacity = (srcDim || dstDim) ? Math.min(lineOpacity, 0.12) : lineOpacity;
      segments.push({ d: result.d, color, thickness: lineThickness, opacity: segOpacity, dashed: false });

      // Try to place edge label — per route, on straight runs along the primary axis
      const edgeKey = `${ri}:${p.id}\u2192${q.id}`;
      if (!edgeLabelPositions.has(edgeKey)) {
        const fs = 2.4 * s;
        const tw = 12 * s;
        const th = fs + 2.5 * s;

        const candidates = [];
        if (result.jogPos !== null) {
          if (isLTR) {
            // H-V-H: straight runs are horizontal
            const jp = result.jogPos; // midX
            candidates.push({ x: (p.x + jp) / 2, y: p.y - th / 2 });    // on first horiz run
            candidates.push({ x: (jp + q.x) / 2, y: q.y - th / 2 });    // on second horiz run
            candidates.push({ x: jp - tw / 2, y: (p.y + q.y) / 2 - th / 2 }); // on vertical jog
          } else {
            // V-H-V: straight runs are vertical
            const jp = result.jogPos; // midY
            candidates.push({ x: p.x, y: (p.y + jp) / 2 - th / 2 });
            candidates.push({ x: q.x, y: (jp + q.y) / 2 - th / 2 });
            candidates.push({ x: (p.x + q.x) / 2, y: jp - th / 2 });
          }
        } else {
          if (isLTR) {
            candidates.push({ x: (p.x + q.x) / 2, y: p.y - th / 2 });
          } else {
            candidates.push({ x: p.x, y: (p.y + q.y) / 2 - th / 2 });
          }
        }

        let placed = false;
        for (const c of candidates) {
          const labelY = c.y + th / 2;
          const rect = { x: c.x - tw / 2, y: c.y, w: tw, h: th, type: 'badge', owner: edgeKey };
          if (badgeGrid.tryPlace(rect)) {
            edgeLabelPositions.set(edgeKey, { x: c.x, y: labelY, color });
            placed = true;
            break;
          }
        }
        if (!placed) {
          const c = candidates[0];
          edgeLabelPositions.set(edgeKey, { x: c.x, y: c.y + th / 2, color });
        }
      }
    }

    routePaths[ri] = segments;
  }

  // ── STEP 7: Extra edges (DAG edges not covered by any route) ──
  const routeEdgeSet = new Set();
  routes.forEach(route => {
    for (let i = 1; i < route.nodes.length; i++)
      routeEdgeSet.add(`${route.nodes[i - 1]}\u2192${route.nodes[i]}`);
  });

  // For each node, track how many extra-edge slots have been assigned.
  // Extra dots go on the "left" side (lower column value) of route dots.
  const extraSlotCount = new Map();
  function extraDotCol(nodeId) {
    const pos = positions.get(nodeId);
    if (!pos) return 0;
    const memberRoutes = nodeRoutes.get(nodeId);
    if (!memberRoutes || memberRoutes.size === 0) return pos[CK];
    const leftmost = Math.min(...[...memberRoutes].map(ri => dotCol(nodeId, ri)));
    const slotIdx = extraSlotCount.get(nodeId) || 0;
    extraSlotCount.set(nodeId, slotIdx + 1);
    return leftmost - (slotIdx + 1) * dotSpacing;
  }

  const extraEdges = [];
  const extraDotPositions = new Map(); // "from→to" → {fromX, fromY, toX, toY}
  edges.forEach(([f, t]) => {
    if (routeEdgeSet.has(`${f}\u2192${t}`)) return;
    const pBase = positions.get(f), qBase = positions.get(t);
    if (!pBase || !qBase) return;
    const fc = extraDotCol(f), tc = extraDotCol(t);
    // Convert to screen coordinates
    let fx, fy, tx, ty;
    if (isLTR) {
      fx = pBase.x; fy = fc;
      tx = qBase.x; ty = tc;
    } else {
      fx = fc; fy = pBase.y;
      tx = tc; ty = qBase.y;
    }
    const extraOwner = `extra_${f}_${t}`;
    const result = routeSegment(fx, fy, tx, ty, 999, extraOwner, new Set([extraOwner, f, t]));
    extraEdges.push({ d: result.d, color: theme.muted, thickness: 1.5 * s, opacity: 0.3, dashed: true });
    extraDotPositions.set(`${f}\u2192${t}`, { fromX: fx, fromY: fy, toX: tx, toY: ty });
  });

  // Compute bounds from actual positions for width/height
  let actualMinX = Infinity, actualMaxX = -Infinity, actualMinY = Infinity, actualMaxY = -Infinity;
  positions.forEach(pos => {
    if (pos.x < actualMinX) actualMinX = pos.x;
    if (pos.x > actualMaxX) actualMaxX = pos.x;
    if (pos.y < actualMinY) actualMinY = pos.y;
    if (pos.y > actualMaxY) actualMaxY = pos.y;
  });

  const width = (actualMaxX - actualMinX) + margin.left + margin.right;
  const height = (actualMaxY - actualMinY) + margin.top + margin.bottom;

  // Compute minY/maxY on the layer axis for scroll/viewport logic
  const lkMarginStart = isLTR ? margin.left : margin.top;
  const finalMaxLayerPos = layerPos[maxLayer] ?? maxLayer * layerSpacing;
  const minLayerScreen = lkMarginStart;
  const maxLayerScreen = lkMarginStart + finalMaxLayerPos;

  return {
    positions,
    routePaths,
    extraEdges,
    width,
    height,
    routes,
    nodeRoute: new Map([...nodes.map(nd => [nd.id, nodePrimary.get(nd.id)])]),
    nodeRoutes,
    nodePrimary,
    dotSpacing,
    dotX,
    dotPos,
    cardPlacements,
    edgeLabelPositions,
    extraDotPositions,
    scale: s,
    labelSize,
    theme,
    orientation: direction,
    minY: isLTR ? actualMinY : minLayerScreen,
    maxY: isLTR ? actualMaxY : maxLayerScreen,
  };
}


// --- render-flow-station.js ---
// ================================================================
// render-flow-station.js — Station card + edge label renderers
// ================================================================
// Reusable renderers for the flow layout's Celonis-style visuals:
// punched-out dots on the line, rich cards to the side, on-line badges.

/** Escape user-supplied strings for safe SVG/XML interpolation. */
function esc(s) {
  if (typeof s !== 'string') return s;
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/**
 * Create a station (node) renderer for flow layouts.
 * @param {object} layout - result from layoutFlow()
 * @param {Array} routes - route definitions [{id, cls, nodes}]
 * @returns {function} renderNode(node, pos, ctx) => SVG string
 */
function createStationRenderer(layout, routes) {
  return function renderStation(node, pos, ctx) {
    const s = ctx.scale;
    const dotR = 3.2 * s;
    const fsLabel = layout.labelSize || 3.6 * s;
    const fsData = fsLabel * 0.78;
    const isDim = node.dim === true;
    const dimOp = isDim ? 0.25 : 1;
    let svg = '';

    const routeIndices = [];
    routes.forEach((route, ri) => {
      if (route.nodes.includes(node.id)) routeIndices.push(ri);
    });

    const dotCoords = routeIndices.map(ri =>
      layout.dotPos ? layout.dotPos(node.id, ri) : { x: layout.dotX(node.id, ri), y: pos.y }
    );

    // Punched-out dots ON the line
    routeIndices.forEach((ri, i) => {
      const col = ctx.theme.classes[routes[ri].cls];
      if (!col) return;
      svg += `<circle cx="${dotCoords[i].x}" cy="${dotCoords[i].y}" r="${dotR}" fill="${col}"${isDim ? ` opacity="${dimOp}"` : ''}/>`;
      svg += `<circle cx="${dotCoords[i].x}" cy="${dotCoords[i].y}" r="${dotR * 0.35}" fill="${ctx.theme.paper}"${isDim ? ` opacity="${dimOp}"` : ''}/>`;
    });

    // Card from layout's obstacle-aware placement
    const cp = layout.cardPlacements?.get(node.id);
    if (cp) {
      const { rect, cardPadX, cardPadY } = cp;

      svg += `<rect x="${rect.x}" y="${rect.y}" width="${rect.w}" height="${rect.h}" rx="${2.5 * s}" `;
      svg += `fill="${ctx.theme.paper}" stroke="${ctx.theme.muted}" stroke-width="${0.7 * s}"${isDim ? ` opacity="${dimOp}"` : ''}/>`;

      const labelY = rect.y + cardPadY + fsLabel * 0.85;
      svg += `<text x="${rect.x + cardPadX}" y="${labelY}" font-size="${fsLabel}" fill="${ctx.theme.ink}" text-anchor="start" font-weight="500"${isDim ? ` opacity="${dimOp * 0.8}"` : ''}>${esc(node.label)}</text>`;

      const dataY = labelY + fsData + 3 * s;
      let dx = rect.x + cardPadX;
      routeIndices.forEach(ri => {
        const col = ctx.theme.classes[routes[ri].cls];
        if (!col) return;
        svg += `<rect x="${dx}" y="${dataY - fsData * 0.7}" width="${3.5 * s}" height="${3.5 * s}" rx="${0.5 * s}" fill="${col}"${isDim ? ` opacity="${dimOp}"` : ''}/>`;
        dx += 5 * s;
      });
      const metricValue = node.times ?? node.count;
      if (metricValue !== undefined && metricValue !== null) {
        svg += `<text x="${dx + 2 * s}" y="${dataY}" font-size="${fsData}" fill="${ctx.theme.muted}" text-anchor="start"${isDim ? ` opacity="${dimOp * 0.8}"` : ''}>${esc(String(metricValue))}</text>`;
      }
    }

    return svg;
  };
}

/**
 * Create an edge renderer that draws route paths + on-line volume badges.
 * @param {object} layout - result from layoutFlow()
 * @param {Map<string,string>} [edgeVolumes] - per-route volumes: "ri:from→to" → label
 * @returns {function} renderEdge(edge, segment, ctx) => SVG string
 */
function createEdgeRenderer(layout, edgeVolumes) {
  return function renderEdge(edge, segment, ctx) {
    const s = ctx.scale;
    let svg = '';

    svg += `<path d="${segment.d}" stroke="${segment.color}" stroke-width="${segment.thickness}" fill="none" `;
    svg += `stroke-linecap="round" stroke-linejoin="round" opacity="${segment.opacity}"`;
    if (segment.dashed) svg += ` stroke-dasharray="${4 * s},${3 * s}"`;
    svg += `/>`;

    // Extra edges: draw station-sized dots at start and end
    if (ctx.isExtraEdge && layout.extraDotPositions) {
      // Find matching extra edge positions
      for (const [key, pos] of layout.extraDotPositions) {
        // Match by checking if this segment's path starts at the expected position
        const startM = segment.d.match(/^M\s+(-?[\d.]+)\s+(-?[\d.]+)/);
        if (!startM) continue;
        const mx = parseFloat(startM[1]), my = parseFloat(startM[2]);
        if (Math.abs(mx - pos.fromX) < 1 && Math.abs(my - pos.fromY) < 1) {
          const dotR = 3.2 * s;
          // Punched-out dots matching route station style, but in muted color
          svg += `<circle cx="${pos.fromX}" cy="${pos.fromY}" r="${dotR}" fill="${ctx.theme.muted}"/>`;
          svg += `<circle cx="${pos.fromX}" cy="${pos.fromY}" r="${dotR * 0.35}" fill="${ctx.theme.paper}"/>`;
          svg += `<circle cx="${pos.toX}" cy="${pos.toY}" r="${dotR}" fill="${ctx.theme.muted}"/>`;
          svg += `<circle cx="${pos.toX}" cy="${pos.toY}" r="${dotR * 0.35}" fill="${ctx.theme.paper}"/>`;
          break;
        }
      }
    }

    if (edgeVolumes && !ctx.isExtraEdge && edge && ctx.routeIndex !== undefined) {
      const ri = ctx.routeIndex;
      const routeEdgeKey = `${ri}:${edge.from}\u2192${edge.to}`;
      const vol = edgeVolumes.get(routeEdgeKey);

      if (vol) {
        const labelPos = layout.edgeLabelPositions?.get(routeEdgeKey);
        if (labelPos) {
          const fs = (layout.labelSize || 3.6 * s) * 0.67;
          const tw = vol.length * fs * 0.55 + 3.5 * s;
          const th = fs + 2.5 * s;

          svg += `<rect x="${labelPos.x - tw / 2}" y="${labelPos.y - th / 2}" width="${tw}" height="${th}" rx="${1.5 * s}" `;
          svg += `fill="${ctx.theme.paper}" stroke="${labelPos.color}" stroke-width="${0.5 * s}" opacity="0.9"/>`;
          svg += `<text x="${labelPos.x}" y="${labelPos.y + fs * 0.35}" font-size="${fs}" fill="${labelPos.color}" text-anchor="middle" opacity="0.9">${esc(vol)}</text>`;
        }
      }
    }

    return svg;
  };
}


// --- render.js ---
// ================================================================
// render.js — SVG rendering for dag-map
// ================================================================
// Renders a DAG layout into an SVG string.
// Supports horizontal and diagonal label modes.
// Colors are driven by layout.theme (from the theme system).
//
// Two color modes:
//   cssVars: false (default) — inline hex colors, portable SVG
//   cssVars: true — CSS var() references, themeable from CSS



/** Escape user-supplied strings for safe SVG/XML interpolation. */
function esc(s) {
  if (typeof s !== 'string') return s;
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/** Escape values interpolated into quoted XML attributes. */
function escAttr(v) {
  return esc(String(v ?? ''));
}

/**
 * Render a DAG layout as an SVG string.
 *
 * @param {object} dag - { nodes: [{id, label, cls}], edges: [[from, to]] }
 * @param {object} layout - result from layoutMetro()
 * @param {object} [options]
 * @param {string} [options.title] - title displayed at top of SVG
 * @param {string|null} [options.subtitle] - subtitle text (null to hide)
 * @param {string} [options.font] - font-family for SVG text
 * @param {boolean} [options.diagonalLabels=false] - tube-map style diagonal labels
 * @param {number} [options.labelAngle=45] - angle in degrees for diagonal labels (0-90)
 * @param {boolean} [options.showLegend=true] - show legend at bottom
 * @param {object} [options.legendLabels] - custom legend labels per class
 * @param {boolean} [options.cssVars=false] - use CSS var() references instead of inline colors
 * @param {number} [options.labelSize=5] - label font size multiplier (before scale)
 * @param {number} [options.titleSize=10] - title font size multiplier (before scale)
 * @param {number} [options.subtitleSize=6.5] - subtitle font size multiplier (before scale)
 * @param {number} [options.legendSize=6.5] - legend text font size multiplier (before scale)
 * @param {function} [options.renderNode] - custom node renderer: (node, pos, ctx) => SVG string
 * @param {function} [options.renderEdge] - custom edge renderer: (edge, segment, ctx) => SVG string
 * @returns {string} SVG markup
 */
function renderSVG(dag, layout, options = {}) {
  const {
    title,
    subtitle,
    diagonalLabels = false,
    labelAngle = 45,
    showLegend = true,
    cssVars = false,
    labelSize = 5,
    titleSize = 10,
    subtitleSize = 6.5,
    legendSize = 6.5,
    dimOpacity = 0.25,
    renderNode,
    renderEdge,
    metrics,
    edgeMetrics,
    colorScale: userColorScale,
  } = options;

  const colorScale = userColorScale || colorScales.palette;

  const font = options.font || "'IBM Plex Mono', 'Courier New', monospace";

  const defaultLegendLabels = {
    pure: 'Primary',
    recordable: 'Secondary',
    side_effecting: 'Tertiary',
    gate: 'Control',
  };
  const legendLabels = { ...defaultLegendLabels, ...(options.legendLabels || {}) };

  // Resolve colors from theme (with backward-compat fallback)
  const theme = layout.theme || resolveTheme('cream');

  // Color resolver: either inline hex or CSS var() reference
  const clsVar = (cls) => `var(--dm-cls-${cls.replace(/_/g, '-')})`;
  const col = cssVars ? {
    paper:  'var(--dm-paper)',
    ink:    'var(--dm-ink)',
    muted:  'var(--dm-muted)',
    border: 'var(--dm-border)',
    cls:    (cls) => clsVar(cls),
  } : {
    paper:  theme.paper,
    ink:    theme.ink,
    muted:  theme.muted,
    border: theme.border,
    cls:    (cls) => theme.classes[cls] || theme.classes.pure,
  };

  const { positions, routePaths, extraEdges, width, height, routes, nodeRoute, nodeRoutes } = layout;
  const s = layout.scale || 1;
  const nodeMap = new Map(dag.nodes.map(n => [n.id, n]));
  const inDeg = new Map(), outDeg = new Map();
  dag.nodes.forEach(nd => { inDeg.set(nd.id, 0); outDeg.set(nd.id, 0); });
  dag.edges.forEach(([f, t]) => { outDeg.set(f, outDeg.get(f) + 1); inDeg.set(t, inDeg.get(t) + 1); });

  const displayTitle = title || `DAG (${dag.nodes.length} OPS)`;
  const displaySubtitle = subtitle !== undefined ? subtitle : 'Topological layout. Colored lines = execution paths by node class.';

  // Computed sizes in SVG coordinate units
  const sz = {
    title: titleSize * s,
    subtitle: subtitleSize * s,
    label: labelSize * s,
    legend: legendSize * s,
    stats: (legendSize - 0.5) * s,
  };

  // Size resolver: either inline value or CSS var() reference
  const fs = cssVars ? {
    title:    `var(--dm-title-size, ${sz.title})`,
    subtitle: `var(--dm-subtitle-size, ${sz.subtitle})`,
    label:    `var(--dm-label-size, ${sz.label})`,
    legend:   `var(--dm-legend-size, ${sz.legend})`,
    stats:    `var(--dm-stats-size, ${sz.stats})`,
  } : sz;

  let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" font-family="${font}">\n`;

  if (cssVars) {
    svg += `<style>\n`;
    svg += `  svg { --dm-title-size: ${sz.title}; --dm-subtitle-size: ${sz.subtitle}; --dm-label-size: ${sz.label}; --dm-legend-size: ${sz.legend}; --dm-stats-size: ${sz.stats}; }\n`;
    svg += `</style>\n`;
  }

  svg += `<rect width="${width}" height="${height}" fill="${col.paper}"/>\n`;

  // In cssVars mode, use style= (CSS property) so var() works; otherwise use font-size= (SVG attribute)
  const fsAttr = (cls, size) => cssVars
    ? `style="font-size: ${size}"`
    : `font-size="${size}"`;

  svg += `<text class="dm-title" x="${24 * s}" y="${22 * s}" ${fsAttr('title', fs.title)} fill="${col.ink}" letter-spacing="0.06em" opacity="0.5">${esc(displayTitle)}</text>\n`;
  if (displaySubtitle) {
    svg += `<text class="dm-subtitle" x="${24 * s}" y="${34 * s}" ${fsAttr('subtitle', fs.subtitle)} fill="${col.muted}">${esc(displaySubtitle)}</text>\n`;
  }

  // Route lines — extra edges first (behind)
  // Note: route/edge colors come from layout (already resolved to hex).
  // In cssVars mode, we need to map them back to CSS var references.
  function segColor(hexColor) {
    if (!cssVars) return hexColor;
    // Find which class this hex color belongs to
    for (const [cls, clsHex] of Object.entries(theme.classes)) {
      if (clsHex === hexColor) return clsVar(cls);
    }
    return hexColor; // fallback to hex if no match
  }

  // Build edge lookup for data attributes
  const edgeIndex = new Map();
  dag.edges.forEach(([f, t], i) => { edgeIndex.set(`${f}\u2192${t}`, i); });

  // Extra edges (cross-route connections)
  extraEdges.forEach((seg, i) => {
    if (renderEdge) {
      const ctx = { theme, scale: s, isExtraEdge: true, index: i };
      svg += renderEdge(null, { ...seg, color: segColor(seg.color) }, ctx);
      svg += '\n';
    } else {
      svg += `<path d="${seg.d}" stroke="${segColor(seg.color)}" stroke-width="${seg.thickness}" fill="none" `;
      svg += `stroke-linecap="round" stroke-linejoin="round" opacity="${seg.opacity}"`;
      if (seg.dashed) svg += ` stroke-dasharray="${4 * s},${3 * s}"`;
      svg += ` data-edge-extra="true"`;
      svg += `/>\n`;
    }
  });

  // Route edges
  routes.forEach((route, ri) => {
    const segments = routePaths[ri];
    if (!segments) return;
    segments.forEach((seg, si) => {
      const fromId = route.nodes[si];
      const toId = route.nodes[si + 1];

      // Check for edge-level metric
      const edgeKey = fromId && toId ? `${fromId}\u2192${toId}` : null;
      const edgeMetric = edgeKey && edgeMetrics && edgeMetrics.get ? edgeMetrics.get(edgeKey) : undefined;
      const hasEdgeMetric = edgeMetric !== undefined && edgeMetric !== null;
      const edgeColor = hasEdgeMetric ? colorScale(edgeMetric.value) : segColor(seg.color);
      const edgeOpacity = hasEdgeMetric ? Math.max(seg.opacity, 0.8) : seg.opacity;

      if (renderEdge) {
        const edge = fromId && toId ? { from: fromId, to: toId } : null;
        const ctx = { theme, scale: s, isExtraEdge: false, routeIndex: ri, segmentIndex: si, edgeMetric };
        svg += renderEdge(edge, { ...seg, color: edgeColor }, ctx);
        svg += '\n';
      } else {
        svg += `<path d="${seg.d}" stroke="${edgeColor}" stroke-width="${seg.thickness}" fill="none" `;
        svg += `stroke-linecap="round" stroke-linejoin="round" opacity="${edgeOpacity}"`;
        if (seg.dashed) svg += ` stroke-dasharray="${4 * s},${3 * s}"`;
        if (fromId && toId) {
          svg += ` data-edge-from="${escAttr(fromId)}" data-edge-to="${escAttr(toId)}" data-route="${ri}"`;
        }
        svg += `/>\n`;
      }
    });
  });

  // Stations (nodes)
  dag.nodes.forEach(nd => {
    const pos = positions.get(nd.id);
    if (!pos) return;
    const metric = metrics && metrics.get ? metrics.get(nd.id) : undefined;
    const hasMetric = metric !== undefined && metric !== null;
    const baseColor = col.cls(nd.cls || 'pure');
    const color = hasMetric ? colorScale(metric.value) : baseColor;
    const isInterchange = (inDeg.get(nd.id) > 1 || outDeg.get(nd.id) > 1);
    const isGate = nd.cls === 'gate';

    const ri = nodeRoute.get(nd.id);
    const depth = (ri !== undefined && routes[ri]) ? routes[ri].depth : 0;

    // Compute route info for this node
    const nRoutes = nodeRoutes ? nodeRoutes.get(nd.id) : null;
    const routeCount = nRoutes ? nRoutes.size : 1;
    const routeClasses = nRoutes
      ? [...nRoutes].map(idx => routes[idx]?.cls).filter(Boolean)
      : [];

    const metricAttr = hasMetric ? ` data-metric-value="${metric.value}"` : '';

    if (renderNode) {
      const ctx = {
        theme,
        scale: s,
        isInterchange,
        depth,
        inDegree: inDeg.get(nd.id),
        outDegree: outDeg.get(nd.id),
        color,
        routeIndex: ri,
        routeCount,
        routeClasses,
        orientation: layout.orientation || 'ltr',
        laneX: layout.laneX || null,
        metric,
      };
      svg += `<g data-node-id="${escAttr(nd.id)}" data-node-cls="${escAttr(nd.cls || 'pure')}"${metricAttr}>`;
      svg += renderNode(nd, pos, ctx);
      svg += `</g>\n`;
    } else {
      let r;
      if (isInterchange) {
        r = 5.5 * s;
      } else if (depth <= 1) {
        r = 3.5 * s;
      } else {
        r = 3 * s;
      }

      const isDim = nd.dim === true;
      const dO = dimOpacity;
      const nodeOpacity = isDim ? dO : 1;

      svg += `<g data-node-id="${escAttr(nd.id)}" data-node-cls="${escAttr(nd.cls || 'pure')}"${metricAttr}>`;

      svg += `<circle data-id="${escAttr(nd.id)}" cx="${pos.x.toFixed(1)}" cy="${pos.y.toFixed(1)}" r="${r}" `;
      svg += `fill="${col.paper}" stroke="${color}" stroke-width="${(isGate ? 2 : 1.6) * s}"`;
      if (isGate) svg += ` stroke-dasharray="${2 * s},${1.5 * s}"`;
      if (isDim) svg += ` opacity="${nodeOpacity}"`;
      svg += `/>`;

      if (isInterchange && !isGate) {
        svg += `<circle cx="${pos.x.toFixed(1)}" cy="${pos.y.toFixed(1)}" r="${2 * s}" fill="${color}" opacity="${isDim ? dO * 0.4 : 0.3}"/>`;
      }
      if (isGate) {
        svg += `<circle cx="${pos.x.toFixed(1)}" cy="${pos.y.toFixed(1)}" r="${2.2 * s}" fill="${col.cls('gate')}" opacity="${isDim ? dO * 0.6 : 0.4}"/>`;
      }

      // Metric label (rendered above the node)
      if (hasMetric && metric.label) {
        svg += `<text class="dm-metric-label" x="${pos.x.toFixed(1)}" y="${(pos.y - r - 2 * s).toFixed(1)}" `;
        svg += `font-size="${labelSize * 0.9 * s}" fill="${color}" text-anchor="middle" font-weight="600" opacity="${isDim ? dO * 0.8 : 0.9}">${esc(metric.label)}</text>`;
      }

      const lfs = sz.label;  // label font size in SVG units (for positioning)
      const lfsCss = fs.label;  // label font size value (inline or var())
      const labelOpacity = isDim ? dO * 0.8 : 0.55;
      if (diagonalLabels) {
        const tickLen = 6 * s;
        const angle = -labelAngle;
        const rad = angle * Math.PI / 180;
        const tickEndX = pos.x + Math.cos(rad) * tickLen;
        const tickEndY = pos.y + Math.sin(rad) * tickLen;
        svg += `<line x1="${pos.x.toFixed(1)}" y1="${(pos.y - r).toFixed(1)}" `;
        svg += `x2="${tickEndX.toFixed(1)}" y2="${(tickEndY - r).toFixed(1)}" `;
        svg += `stroke="${col.ink}" stroke-width="${0.6 * s}" opacity="${isDim ? dO * 0.4 : 0.3}"/>`;
        const textX = tickEndX + 1 * s;
        const textY = tickEndY - r - 1 * s;
        svg += `<text class="dm-label" x="${textX.toFixed(1)}" y="${textY.toFixed(1)}" `;
        svg += `${fsAttr('label', lfs * 0.9)} fill="${col.ink}" text-anchor="start" opacity="${labelOpacity}" `;
        svg += `transform="rotate(${angle} ${textX.toFixed(1)} ${textY.toFixed(1)})">${esc(nd.label)}</text>`;
      } else if (layout.orientation === 'ttb') {
        const labelX = pos.x + r + 4 * s;
        const labelY = pos.y + lfs * 0.35;
        svg += `<text class="dm-label" x="${labelX.toFixed(1)}" y="${labelY.toFixed(1)}" `;
        svg += `${fsAttr('label', lfsCss)} fill="${col.ink}" text-anchor="start" opacity="${labelOpacity}">${esc(nd.label)}</text>`;
      } else {
        const labelY = pos.y + r + 8 * s;
        svg += `<text class="dm-label" x="${pos.x.toFixed(1)}" y="${labelY.toFixed(1)}" `;
        svg += `${fsAttr('label', lfsCss)} fill="${col.ink}" text-anchor="middle" opacity="${labelOpacity}">${esc(nd.label)}</text>`;
      }

      svg += `</g>\n`;
    }
  });

  // Legend
  if (showLegend) {
    const ly = height - 55 * s;
    svg += `<line x1="${24 * s}" y1="${ly}" x2="${width - 24 * s}" y2="${ly}" stroke="${col.border}" stroke-width="${0.3 * s}"/>\n`;

    // Derive legend entries from theme classes
    const classKeys = Object.keys(theme.classes);
    classKeys.forEach((cls, i) => {
      const label = legendLabels[cls] || cls;
      const color = col.cls(cls);
      const x = 24 * s + i * 160 * s;
      svg += `<line x1="${x}" y1="${ly + 16 * s}" x2="${x + 22 * s}" y2="${ly + 16 * s}" stroke="${color}" stroke-width="${3.5 * s}" opacity="0.5" stroke-linecap="round"`;
      if (cls === 'gate') svg += ` stroke-dasharray="${4 * s},${3 * s}"`;
      svg += `/>\n`;
      svg += `<text class="dm-legend-text" x="${x + 28 * s}" y="${ly + 19 * s}" ${fsAttr('legend', fs.legend)} fill="${col.muted}">${esc(label)}</text>\n`;
    });

    const vertSpread = layout.maxY - layout.minY;
    svg += `<text class="dm-stats" x="${24 * s}" y="${ly + 38 * s}" ${fsAttr('stats', fs.stats)} fill="${col.muted}">${dag.nodes.length} ops | ${dag.edges.length} edges | ${routes.length} routes | spread: ${vertSpread.toFixed(0)}px | scale: ${s}x</text>\n`;
  }

  svg += `</svg>`;
  return svg;
}


  window.DagMap = {
    layoutMetro: layoutMetro,
    layoutHasse: layoutHasse,
    layoutFlow: layoutFlow,
    renderSVG: renderSVG,
    resolveTheme: resolveTheme,
    THEMES: THEMES,
    dominantClass: dominantClass,
    validateDag: validateDag,
    swapPathXY: swapPathXY,
    colorScales: colorScales,
    createStationRenderer: createStationRenderer,
    createEdgeRenderer: createEdgeRenderer,
  };
})();
