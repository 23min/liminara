// Tier A fixture loader.
//
// Tier A reuses dag-map's own visual test corpus at dag-map/test/models.js.
// The models already carry {id, dag, routes, theme, opts}, so this loader is
// a thin wrapper that returns them in a stable order.
//
// The `models` parameter exists for tests that want to exercise the loud-
// failure path without mutating dag-map's real corpus. In normal use, leave
// it undefined and the loader reads from dag-map/test/models.js.

import { models as realModels } from '../../dag-map/test/models.js';

const TIER_A_SOURCE = 'dag-map/test/models.js';

export async function loadTierA({ models = realModels, source = TIER_A_SOURCE } = {}) {
  if (!Array.isArray(models)) {
    throw new Error(`loadTierA: ${source} did not export a models array`);
  }
  for (const m of models) {
    if (!m || typeof m.id !== 'string') {
      throw new Error(`loadTierA: fixture at ${source} is missing a string id`);
    }
    if (!m.dag || !Array.isArray(m.dag.nodes) || !Array.isArray(m.dag.edges)) {
      throw new Error(`loadTierA: fixture "${m.id}" at ${source} is missing a valid dag`);
    }
    if (!m.theme) {
      throw new Error(`loadTierA: fixture "${m.id}" at ${source} is missing theme`);
    }
    if (!m.opts) {
      throw new Error(`loadTierA: fixture "${m.id}" at ${source} is missing opts`);
    }
  }
  return models;
}
