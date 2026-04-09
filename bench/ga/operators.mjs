// operators.mjs — GA operators. Every stochastic operator takes an
// explicit PRNG argument so seeding is never implicit.
//
// Fitness convention: LOWER is better (we minimize energy). Tournament
// selection and elitism both sort ascending.

import {
  TIER1_SCHEMA,
  TIER1_FIELDS,
  clampTier1,
} from '../genome/tier1.mjs';

import {
  crossoverStrategyGenes,
  mutateStrategyGenes,
  defaultStrategyGenes,
} from '../genome/strategy-genes.mjs';

// ── tournamentSelect ─────────────────────────────────────────────────────

export function tournamentSelect(population, prng, { size = 3 } = {}) {
  if (!Array.isArray(population) || population.length === 0) {
    throw new Error('tournamentSelect: empty population');
  }
  const n = population.length;
  const effectiveSize = Math.min(size, n);

  // Sample `effectiveSize` distinct indices via partial Fisher-Yates.
  // Sampling without replacement guarantees that a size-n tournament visits
  // every individual exactly once and therefore always returns the best.
  const indices = new Array(n);
  for (let i = 0; i < n; i++) indices[i] = i;
  for (let i = 0; i < effectiveSize; i++) {
    const j = prng.nextInt(i, n - 1);
    const tmp = indices[i];
    indices[i] = indices[j];
    indices[j] = tmp;
  }

  let best = population[indices[0]];
  for (let i = 1; i < effectiveSize; i++) {
    const candidate = population[indices[i]];
    if (candidate.fitness < best.fitness) best = candidate;
  }
  return best;
}

// ── crossoverTier1 ───────────────────────────────────────────────────────
//
// Per-field arithmetic crossover: for every field, the child value is
// alpha * p1 + (1 - alpha) * p2 with alpha drawn independently per field.
// This keeps every child strictly inside the convex hull of the parents,
// so clamping is unnecessary as long as the parents are valid.

export function crossoverTier1(p1, p2, prng) {
  const out = {};
  for (const name of TIER1_FIELDS) {
    const alpha = prng.nextFloat();
    out[name] = alpha * p1[name] + (1 - alpha) * p2[name];
  }
  return out;
}

// ── mutateTier1 ──────────────────────────────────────────────────────────
//
// Gaussian mutation. Each field gets a normal perturbation with
// sigma = strength * (max - min). The result is clamped to the field's
// bounds so the output is always a valid Tier 1 dict.

export function mutateTier1(t1, prng, { strength = 0.1 } = {}) {
  const out = {};
  for (const name of TIER1_FIELDS) {
    const spec = TIER1_SCHEMA[name];
    if (strength === 0) {
      out[name] = t1[name];
      continue;
    }
    const sigma = strength * (spec.max - spec.min);
    out[name] = t1[name] + prng.nextGaussian(0, sigma);
  }
  return clampTier1(out);
}

// Tier 2 mutation was removed on 2026-04-08 together with the Tier 2
// schema. `routing_primitive` is locked to bezier in the evaluator; the
// other two Tier 2 fields were never consumed by the evaluator. If a
// future milestone re-introduces multiple routing primitives, a
// `mutateTier2` comes back with it.

// ── selectElite ──────────────────────────────────────────────────────────

export function selectElite(population, n) {
  const copy = population.slice();
  copy.sort((a, b) => a.fitness - b.fitness);
  return copy.slice(0, Math.min(n, copy.length));
}
