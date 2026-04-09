// dagmap.mjs — adapter that runs dag-map's layoutMetro on a fixture and
// returns the canonical layout shape. This wraps the existing evaluator
// adapter so all three engines produce the same output shape.

import { layoutMetro } from '../../dag-map/src/layout-metro.js';
import { projectLayout } from '../evaluator/adapter.mjs';

const DEFAULT_RENDER = {
  routing: 'bezier',
  scale: 1.5,
  layerSpacing: 50,
};

/**
 * Layout a fixture using dag-map and return the canonical bench layout shape.
 * @param {Object} fixture - {id, dag, theme, opts}
 * @param {Object} [genome] - optional genome render/energy overrides
 * @returns {{ nodes, edges, routes, meta } | { error: string }}
 */
export function layoutWithDagMap(fixture, genome = {}) {
  try {
    const render = { ...DEFAULT_RENDER, ...(fixture.opts ?? {}), ...(genome.render ?? {}) };
    if (fixture.theme !== undefined) render.theme = fixture.theme;
    if (Array.isArray(fixture.routes) && fixture.routes.length > 0) {
      render.routes = fixture.routes;
    }

    const raw = layoutMetro(fixture.dag, render);
    const layout = projectLayout(fixture.dag, raw);
    return { ...layout, meta: { engine: 'dag-map' } };
  } catch (err) {
    return { error: err.message, nodes: [], edges: [], routes: [], meta: { engine: 'dag-map' } };
  }
}
