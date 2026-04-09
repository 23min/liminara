// islands.mjs — population-per-island container.
//
// The island model holds N independent subpopulations that evolve mostly
// in isolation, with rare migration events between neighbouring islands
// (introgression — see migration.mjs in Commit B). Each individual
// carries an explicit `island` field identifying which subpopulation it
// belongs to; `placeIndividual` uses that field to route it into the
// right bucket.
//
// Prior to 2026-04-08 the islands were keyed by `routing_primitive` (one
// island per value of the Tier 2 routing_primitive field). That schema
// was removed when Tier 2 collapsed. Islands are now generic
// subpopulations, initialised with random genomes and kept separate
// primarily to preserve long-lineage diversity across the run.

export const DEFAULT_POPULATION_KEYS = ['pop-0', 'pop-1', 'pop-2'];

export function createIslands(keys = DEFAULT_POPULATION_KEYS) {
  const populations = new Map();
  for (const k of keys) {
    populations.set(k, []);
  }
  return { populations };
}

export function placeIndividual(islands, individual) {
  const key = individual.island;
  if (key === undefined) {
    throw new Error(`placeIndividual: individual ${individual.id ?? '<no id>'} has no island field`);
  }
  const pop = islands.populations.get(key);
  if (!pop) {
    throw new Error(`no island "${key}" in this container`);
  }
  pop.push(individual);
}

export function islandKeys(islands) {
  return [...islands.populations.keys()];
}

export function totalSize(islands) {
  let s = 0;
  for (const pop of islands.populations.values()) s += pop.length;
  return s;
}

export function allIndividuals(islands) {
  const out = [];
  for (const pop of islands.populations.values()) {
    for (const ind of pop) out.push(ind);
  }
  return out;
}
