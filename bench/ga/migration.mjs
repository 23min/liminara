// migration.mjs — ring-topology introgression between island subpopulations.
//
// Evolutionary-algorithm term: "coarse-grained parallel GA with sparse
// migration." Biological analogue: allopatric speciation with rare
// introgression — populations evolve in isolation most of the time, but
// occasionally a single individual crosses the barrier and leaves genes
// in the neighbouring population. Neanderthal × Sapiens is the textbook
// example; our bench is less dramatic but the shape is the same.
//
// Topology: ring. Island i sends to island (i+1) mod N where N is the
// number of islands. This gives slow cross-population gene flow without
// any single island dominating the whole system.
//
// Migration event: called every `migrationInterval` generations. From
// each island, we pick `migrationCount` migrants via tournament selection
// (best individuals win), remove them from the source, and append them to
// the target with their `island` field rewritten.
//
// `migrationCount = round(migrationRate * populationSize)`, clamped to
// `[0, populationSize]`. A migration rate of 0.05 on a 20-sized island
// means 1 migrant per event.
//
// This module is intentionally minimal: no special selection logic, no
// topology options, no replacement policy. When we need more, extend.

import { tournamentSelect } from './operators.mjs';
import { islandKeys } from './islands.mjs';

export function shouldMigrate(generationIndex, config) {
  const interval = config?.migrationInterval;
  if (!interval || interval <= 0) return false;
  if (generationIndex === 0) return false;
  return generationIndex % interval === 0;
}

export function migrateRing(
  islands,
  prng,
  { migrationRate = 0.05, tournamentSize = 3 } = {},
) {
  const keys = islandKeys(islands);
  if (keys.length < 2) {
    return { migrations: [] };
  }
  if (migrationRate <= 0) {
    return { migrations: [] };
  }

  // Phase 1: pick migrants from every island in a single pass, BEFORE
  // we start moving them. Otherwise a migrant added to island j would be
  // eligible to migrate on to island j+1 in the same event, which isn't
  // the semantics we want (we want one hop per event).
  const migrations = [];
  for (let i = 0; i < keys.length; i++) {
    const from = keys[i];
    const to = keys[(i + 1) % keys.length];
    const source = islands.populations.get(from);
    if (!source || source.length === 0) continue;

    const count = Math.min(
      source.length,
      Math.max(0, Math.round(migrationRate * source.length)),
    );
    if (count === 0) continue;

    // Pick `count` distinct migrants via tournament. Because the source
    // population may be small, re-run tournament and skip already-picked
    // individuals.
    const picked = new Set();
    for (let c = 0; c < count; c++) {
      // Build the tournament pool excluding already-picked individuals.
      const available = source.filter((_, idx) => !picked.has(idx));
      if (available.length === 0) break;
      const winner = tournamentSelect(available, prng, {
        size: Math.min(tournamentSize, available.length),
      });
      const idx = source.indexOf(winner);
      picked.add(idx);
      migrations.push({ from, to, individual: winner });
    }
  }

  // Phase 2: apply migrations. Remove each migrant from its source
  // (by identity) and append to the target with `island` rewritten.
  for (const m of migrations) {
    const source = islands.populations.get(m.from);
    const target = islands.populations.get(m.to);
    const idx = source.indexOf(m.individual);
    if (idx >= 0) source.splice(idx, 1);
    m.individual.island = m.to;
    target.push(m.individual);
  }

  return { migrations };
}
