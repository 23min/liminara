import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createPrng } from '../prng.mjs';
import {
  createIslands,
  placeIndividual,
  allIndividuals,
  DEFAULT_POPULATION_KEYS,
} from '../islands.mjs';
import { migrateRing, shouldMigrate } from '../migration.mjs';
import { defaultGenome } from '../../genome/genome.mjs';

function mkInd(id, island, fitness) {
  return { id, island, genome: defaultGenome(), fitness, perFixture: {} };
}

function seedIslands(keys, perIsland, fitnessBase = 0) {
  const islands = createIslands(keys);
  for (const k of keys) {
    for (let i = 0; i < perIsland; i++) {
      placeIndividual(islands, mkInd(`${k}-${i}`, k, fitnessBase + i));
    }
  }
  return islands;
}

// ── shouldMigrate ───────────────────────────────────────────────────────

test('shouldMigrate returns true exactly on multiples of migrationInterval', () => {
  const cfg = { migrationInterval: 10 };
  assert.equal(shouldMigrate(0, cfg), false, 'gen 0 is not a migration event');
  assert.equal(shouldMigrate(9, cfg), false);
  assert.equal(shouldMigrate(10, cfg), true);
  assert.equal(shouldMigrate(11, cfg), false);
  assert.equal(shouldMigrate(20, cfg), true);
});

test('shouldMigrate returns false when migrationInterval is 0 or missing', () => {
  assert.equal(shouldMigrate(10, { migrationInterval: 0 }), false);
  assert.equal(shouldMigrate(10, {}), false);
  assert.equal(shouldMigrate(10, { migrationInterval: null }), false);
});

// ── migrateRing ─────────────────────────────────────────────────────────

test('migrateRing moves migrants from each island into the next island on a ring', () => {
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  // Give each island's individual 0 a distinct low fitness so tournament
  // picks them.
  islands.populations.get('pop-0')[0].fitness = -100;
  islands.populations.get('pop-1')[0].fitness = -200;
  islands.populations.get('pop-2')[0].fitness = -300;

  const prng = createPrng(1);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 0.25, tournamentSize: 4 });
  assert.equal(migrations.length, 3);

  // pop-0 -> pop-1 -> pop-2 -> pop-0 ring
  const migratedIds = migrations.map((m) => ({ from: m.from, to: m.to, id: m.individual.id }));
  assert.deepEqual(
    migratedIds.sort((a, b) => (a.from < b.from ? -1 : 1)),
    [
      { from: 'pop-0', to: 'pop-1', id: 'pop-0-0' },
      { from: 'pop-1', to: 'pop-2', id: 'pop-1-0' },
      { from: 'pop-2', to: 'pop-0', id: 'pop-2-0' },
    ],
  );
});

test('migrateRing updates the migrated individual\'s island field to the target', () => {
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  islands.populations.get('pop-0')[0].fitness = -100;
  const prng = createPrng(2);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 0.25, tournamentSize: 4 });
  const from0 = migrations.find((m) => m.from === 'pop-0');
  assert.equal(from0.individual.island, 'pop-1');
});

test('migrateRing places migrants into the target islands (total size invariant)', () => {
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  const prng = createPrng(3);
  migrateRing(islands, prng, { migrationRate: 1, tournamentSize: 2 });
  // Each island had 4 + lost 1 (migrant out) + gained 1 (migrant in from neighbor) = 4.
  for (const k of ['pop-0', 'pop-1', 'pop-2']) {
    assert.equal(islands.populations.get(k).length, 4);
  }
  // Every individual has a valid island matching its location.
  for (const k of DEFAULT_POPULATION_KEYS) {
    for (const ind of islands.populations.get(k)) {
      assert.equal(ind.island, k, `individual ${ind.id} in ${k} has island=${ind.island}`);
    }
  }
});

test('migrateRing is a no-op when there is only one island (ring of size 1)', () => {
  const islands = seedIslands(['solo'], 5);
  const prng = createPrng(4);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 1, tournamentSize: 2 });
  assert.equal(migrations.length, 0);
  assert.equal(islands.populations.get('solo').length, 5);
});

test('migrateRing with migrationRate=0 is a no-op', () => {
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  const prng = createPrng(5);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 0, tournamentSize: 2 });
  assert.equal(migrations.length, 0);
});

test('migrateRing picks migrants via tournament selection (best individuals migrate)', () => {
  // With tournament size = population size, the best (lowest-fitness)
  // individual always wins.
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  islands.populations.get('pop-0')[2].fitness = -1000; // lowest in pop-0
  const prng = createPrng(6);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 0.25, tournamentSize: 4 });
  const from0 = migrations.find((m) => m.from === 'pop-0');
  assert.equal(from0.individual.id, 'pop-0-2');
});

test('migrateRing removes migrants from their source island', () => {
  const islands = seedIslands(['pop-0', 'pop-1', 'pop-2'], 4);
  const prng = createPrng(7);
  const { migrations } = migrateRing(islands, prng, { migrationRate: 0.25, tournamentSize: 4 });
  // Each island lost one individual (the migrant out) and gained one (from
  // its predecessor in the ring). Every original individual either stayed
  // on its home island or is now on the next island.
  const allIds = allIndividuals(islands).map((i) => i.id).sort();
  // Total count unchanged, but every ID still exists exactly once.
  const uniq = new Set(allIds);
  assert.equal(uniq.size, allIds.length);
  assert.equal(allIds.length, 12);
});
