import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createPrng } from '../prng.mjs';
import {
  createIslands,
  placeIndividual,
  totalSize,
  allIndividuals,
  DEFAULT_POPULATION_KEYS,
} from '../islands.mjs';
import { advanceGeneration, selectEliteWithGuard } from '../generation.mjs';
import { defaultGenome, randomGenome } from '../../genome/genome.mjs';
import { createBestEver, updateBestEver } from '../../regression/guard.mjs';

function mkInd(id, island, fitness = 0, perFixture = {}) {
  return { id, island, genome: defaultGenome(), fitness, perFixture };
}

// ── selectEliteWithGuard ─────────────────────────────────────────────────

test('selectEliteWithGuard returns top-n when no one regresses', () => {
  // Every individual scores at or below best-ever, so none regress.
  // best-ever lin = 10. Scores 1, 3, 5 → ratios 10, 3.3, 2.0 → all kept.
  const population = [
    mkInd('a', 'pop-0', 5, { lin: 5 }),
    mkInd('b', 'pop-0', 1, { lin: 1 }),
    mkInd('c', 'pop-0', 3, { lin: 3 }),
  ];
  const be = createBestEver();
  updateBestEver(be, 'lin', 10);
  const { elite, rejected } = selectEliteWithGuard(population, 2, be, { threshold: 0.9 });
  assert.deepEqual(elite.map((e) => e.id), ['b', 'c']);
  assert.equal(rejected.length, 0);
});

test('selectEliteWithGuard filters out a regressing individual and keeps the next best', () => {
  // best-ever for lin = 10. threshold 0.9 -> ratio cutoff 0.9.
  // Individual b has lin=50, ratio 10/50 = 0.2 -> rejected.
  // Individual c has lin=11, ratio 10/11 ≈ 0.909 -> kept.
  const population = [
    mkInd('a', 'pop-0', 100, { lin: 100 }),
    mkInd('b', 'pop-0', 50, { lin: 50 }), // lowest total, but regresses lin
    mkInd('c', 'pop-0', 75, { lin: 11 }),
  ];
  const be = createBestEver();
  updateBestEver(be, 'lin', 10);
  const { elite, rejected } = selectEliteWithGuard(population, 2, be, { threshold: 0.9 });
  // b is best-by-fitness but rejected; c is kept; a is still regressing (ratio 10/100=0.1).
  assert.deepEqual(elite.map((e) => e.id), ['c']);
  const rejectedIds = rejected.map((r) => r.id);
  assert.ok(rejectedIds.includes('b'));
  assert.ok(rejectedIds.includes('a'));
});

test('selectEliteWithGuard returns an empty elite when everyone regresses', () => {
  const population = [
    mkInd('a', 'pop-0', 100, { lin: 100 }),
    mkInd('b', 'pop-0', 200, { lin: 200 }),
  ];
  const be = createBestEver();
  updateBestEver(be, 'lin', 1);
  const { elite } = selectEliteWithGuard(population, 5, be, { threshold: 0.9 });
  assert.equal(elite.length, 0);
});

// ── advanceGeneration ────────────────────────────────────────────────────

async function stubScore({ id, genome, island }) {
  // Deterministic stub: fitness is the sum of the absolute values of every
  // Tier 1 field. Keeps tests fast and fully deterministic without
  // touching dag-map.
  let fitness = 0;
  for (const v of Object.values(genome.tier1)) fitness += Math.abs(v);
  return { id, island, genome, fitness, perFixture: { stub: fitness } };
}

function seedPopulation(prng, n, islandKey) {
  const pop = [];
  for (let i = 0; i < n; i++) {
    const g = randomGenome(prng);
    const fitness = Object.values(g.tier1).reduce((a, b) => a + Math.abs(b), 0);
    pop.push({
      id: `${islandKey}-${i}`,
      island: islandKey,
      genome: g,
      fitness,
      perFixture: { stub: fitness },
    });
  }
  return pop;
}

test('advanceGeneration preserves total population size (sum across islands)', async () => {
  const prng = createPrng(101);
  const islands = createIslands(DEFAULT_POPULATION_KEYS);
  const seedPrng = createPrng(9999);
  for (const islandKey of DEFAULT_POPULATION_KEYS) {
    for (const ind of seedPopulation(seedPrng, 4, islandKey)) {
      placeIndividual(islands, ind);
    }
  }
  assert.equal(totalSize(islands), 12);

  const nextIslands = await advanceGeneration(islands, {
    prng,
    scoreChild: stubScore,
    bestEver: createBestEver(),
    config: {
      populationSize: 4,
      eliteCount: 1,
      tournamentSize: 2,
      tier1MutationStrength: 0.1,
      regressionThreshold: 0.9,
    },
    generationIndex: 1,
  });

  assert.equal(totalSize(nextIslands), 12);
});

test('advanceGeneration carries the best elite from each island unchanged', async () => {
  const prng = createPrng(202);
  const islands = createIslands(DEFAULT_POPULATION_KEYS);
  const seedPrng = createPrng(303);
  const pop = seedPopulation(seedPrng, 4, DEFAULT_POPULATION_KEYS[0]);
  // Inject a known best — very low fitness — so elitism should carry it.
  pop[0].fitness = 0.0001;
  pop[0].perFixture = { stub: 0.0001 };
  pop[0].id = 'champ';
  for (const ind of pop) placeIndividual(islands, ind);

  const nextIslands = await advanceGeneration(islands, {
    prng,
    scoreChild: stubScore,
    bestEver: createBestEver(),
    config: {
      populationSize: 4,
      eliteCount: 1,
      tournamentSize: 2,
      tier1MutationStrength: 0.1,
      regressionThreshold: 0.9,
    },
    generationIndex: 1,
  });
  const ids = allIndividuals(nextIslands).map((i) => i.id);
  assert.ok(ids.includes('champ'), 'elite champion was lost across a generation');
});

test('advanceGeneration is deterministic under a fixed seed and identical inputs', async () => {
  async function oneRun(seed) {
    const prng = createPrng(seed);
    const islands = createIslands(DEFAULT_POPULATION_KEYS);
    const seedPrng = createPrng(9999);
    for (const islandKey of DEFAULT_POPULATION_KEYS) {
      for (const ind of seedPopulation(seedPrng, 4, islandKey)) {
        placeIndividual(islands, ind);
      }
    }
    return await advanceGeneration(islands, {
      prng,
      scoreChild: stubScore,
      bestEver: createBestEver(),
      config: {
        populationSize: 4,
        eliteCount: 1,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        regressionThreshold: 0.9,
      },
      generationIndex: 1,
    });
  }

  const a = await oneRun(42);
  const b = await oneRun(42);
  const aIds = allIndividuals(a).map((i) => i.id).sort();
  const bIds = allIndividuals(b).map((i) => i.id).sort();
  assert.deepEqual(aIds, bIds);
});

test('advanceGeneration children inherit the island of their parents', async () => {
  const prng = createPrng(404);
  const islands = createIslands(['pop-0', 'pop-1']);
  const seedPrng = createPrng(505);
  for (const ind of seedPopulation(seedPrng, 4, 'pop-0')) placeIndividual(islands, ind);
  for (const ind of seedPopulation(seedPrng, 4, 'pop-1')) placeIndividual(islands, ind);

  const nextIslands = await advanceGeneration(islands, {
    prng,
    scoreChild: stubScore,
    bestEver: createBestEver(),
    config: {
      populationSize: 4,
      eliteCount: 1,
      tournamentSize: 2,
      tier1MutationStrength: 0.1,
      regressionThreshold: 0.9,
    },
    generationIndex: 1,
  });
  // Every individual in pop-0 has island = 'pop-0'; same for pop-1.
  for (const ind of nextIslands.populations.get('pop-0')) {
    assert.equal(ind.island, 'pop-0');
  }
  for (const ind of nextIslands.populations.get('pop-1')) {
    assert.equal(ind.island, 'pop-1');
  }
});
