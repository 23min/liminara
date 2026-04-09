// generation.mjs — one-generation advance for the island GA.
//
// Each generation, per island:
//   1. Take the top-N by fitness, filtered by the regression guard, as elite.
//      Elite carry forward unchanged.
//   2. Fill the remaining slots with children via tournament selection,
//      Tier 1 arithmetic crossover, and Tier 1 Gaussian mutation.
//   3. Score each child via a caller-supplied `scoreChild` function.
//   4. Place each child in the next-generation islands by inheriting the
//      parent's `island` field.
//
// The caller supplies `scoreChild` so tests can stub scoring without
// touching dag-map's render path, and so production code can swap in a
// worker-thread pool later without touching this module.
//
// Tier 2 mutation was removed on 2026-04-08 when the Tier 2 schema
// collapsed (see operators.mjs). Children now inherit their origin
// island directly from the first parent; the introgression migration
// (Commit B) is the only mechanism for cross-island movement.

import { makeGenome } from '../genome/genome.mjs';
import {
  crossoverTier1,
  mutateTier1,
  tournamentSelect,
} from './operators.mjs';
import {
  crossoverStrategyGenes,
  mutateStrategyGenes,
} from '../genome/strategy-genes.mjs';
import { createIslands, islandKeys, placeIndividual } from './islands.mjs';
import { regressionGuard } from '../regression/guard.mjs';

export function selectEliteWithGuard(population, n, bestEver, { threshold = 0.9 } = {}) {
  const sorted = population.slice().sort((a, b) => a.fitness - b.fitness);
  const elite = [];
  const rejected = [];
  for (const ind of sorted) {
    if (elite.length >= n) break;
    const result = regressionGuard(bestEver, ind.perFixture ?? {}, { threshold });
    if (result.rejected) {
      rejected.push({ id: ind.id, reasons: result.reasons });
    } else {
      elite.push(ind);
    }
  }
  // Keep reporting any sorted individuals past the elite slots if they're
  // rejected — useful for logging.
  for (let i = elite.length + rejected.length; i < sorted.length; i++) {
    const ind = sorted[i];
    const result = regressionGuard(bestEver, ind.perFixture ?? {}, { threshold });
    if (result.rejected) {
      rejected.push({ id: ind.id, reasons: result.reasons });
    }
  }
  return { elite, rejected };
}

export async function advanceGeneration(islands, ctx) {
  const {
    prng,
    scoreChild,
    bestEver,
    config,
    generationIndex,
  } = ctx;

  const keys = islandKeys(islands);
  const next = createIslands(keys);
  let childCounter = 0;

  for (const islandKey of keys) {
    const population = islands.populations.get(islandKey);
    if (!population || population.length === 0) continue;

    // Elitism first — these bypass the rest of the generation work.
    const { elite } = selectEliteWithGuard(population, config.eliteCount, bestEver, {
      threshold: config.regressionThreshold,
    });
    for (const e of elite) {
      placeIndividual(next, e);
    }

    const target = Math.max(0, config.populationSize - elite.length);
    for (let i = 0; i < target; i++) {
      const p1 = tournamentSelect(population, prng, { size: config.tournamentSize });
      const p2 = tournamentSelect(population, prng, { size: config.tournamentSize });
      const childTier1Raw = crossoverTier1(p1.genome.tier1, p2.genome.tier1, prng);
      const mutatedTier1 = mutateTier1(childTier1Raw, prng, {
        strength: config.tier1MutationStrength,
      });
      const childStrategyRaw = crossoverStrategyGenes(
        p1.genome.strategy || {},
        p2.genome.strategy || {},
        prng,
      );
      const mutatedStrategy = mutateStrategyGenes(childStrategyRaw, prng, {
        categoricalRate: config.strategyCategoricalRate ?? 0.1,
        continuousStrength: config.tier1MutationStrength,
      });
      const childGenome = makeGenome({ tier1: mutatedTier1, strategy: mutatedStrategy });
      const id = `g${generationIndex}-${islandKey}-${childCounter++}`;
      const scored = await scoreChild({ id, genome: childGenome, island: islandKey });
      // scoreChild may or may not set `island` on the returned object;
      // ensure it is set so placeIndividual can route it.
      if (scored.island === undefined) scored.island = islandKey;
      placeIndividual(next, scored);
    }
  }

  return next;
}
