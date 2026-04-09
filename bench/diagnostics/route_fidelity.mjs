// route_fidelity — Tier A diagnostic.
//
// Given a fixture with hand-authored routes, measure how well the rendered
// layout preserves those routes. Fidelity is per-route Jaccard similarity
// between the authored node set and the best-matching rendered route's node
// set, averaged over authored routes.
//
// This output is a diagnostic only. It is deliberately NOT part of the
// energy scalar returned by `evaluate` — folding author intent into the
// fitness would overfit the GA to hand-authored routes on Tier A and leak
// "route authoring" as a hidden objective (Epic constraint).
//
//   { applicable: false, fidelity: null }            // no authored routes
//   { applicable: true, fidelity, perRoute: [...] }  // Tier A fixture

import { layoutMetro } from '../../dag-map/src/layout-metro.js';

function jaccard(a, b) {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  const union = a.size + b.size - inter;
  return union === 0 ? 1 : inter / union;
}

function buildRenderOpts(genome, fixture) {
  const render = { ...(fixture.opts ?? {}), ...(genome.render ?? {}) };
  if (fixture.theme !== undefined) render.theme = fixture.theme;
  if (Array.isArray(fixture.routes) && fixture.routes.length > 0) {
    render.routes = fixture.routes;
  }
  return render;
}

export async function route_fidelity(genome, fixture) {
  if (!Array.isArray(fixture.routes) || fixture.routes.length === 0) {
    return { applicable: false, fidelity: null };
  }

  const render = buildRenderOpts(genome, fixture);
  let raw;
  try {
    raw = layoutMetro(fixture.dag, render);
  } catch (err) {
    return { applicable: true, fidelity: 0, error: err.message, perRoute: [] };
  }

  const renderedSets = raw.routes.map((r) => new Set(r.nodes));
  const perRoute = [];
  let sum = 0;
  for (const authored of fixture.routes) {
    const authoredSet = new Set(authored.nodes);
    let best = 0;
    let matchIndex = -1;
    for (let i = 0; i < renderedSets.length; i++) {
      const s = jaccard(authoredSet, renderedSets[i]);
      if (s > best) {
        best = s;
        matchIndex = i;
      }
    }
    perRoute.push({ id: authored.id, fidelity: best, matchIndex });
    sum += best;
  }
  const fidelity = perRoute.length === 0 ? 1 : sum / perRoute.length;
  return { applicable: true, fidelity, perRoute };
}
