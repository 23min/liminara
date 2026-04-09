import { test } from 'node:test';
import assert from 'node:assert/strict';

import { scoreIndividual } from '../individual.mjs';
import { defaultGenome, randomGenome } from '../../genome/genome.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';
import { loadDefaultWeights, TERM_NAMES } from '../../evaluator/evaluator.mjs';
import { createPrng } from '../prng.mjs';

test('scoreIndividual returns an Individual record with id, genome, fitness, and perFixture', async () => {
  const fixtures = (await loadTierA()).slice(0, 2);
  const weights = await loadDefaultWeights();
  const genome = defaultGenome();
  const individual = await scoreIndividual({
    id: 'ind-0',
    genome,
    fixtures,
    weights,
  });
  assert.equal(individual.id, 'ind-0');
  assert.deepEqual(individual.genome, genome);
  assert.ok(Number.isFinite(individual.fitness));
  assert.ok(individual.perFixture);
  for (const f of fixtures) {
    assert.ok(f.id in individual.perFixture);
    assert.ok(Number.isFinite(individual.perFixture[f.id]));
  }
});

test('scoreIndividual fitness equals the sum of its perFixture scores', async () => {
  const fixtures = (await loadTierA()).slice(0, 3);
  const weights = await loadDefaultWeights();
  const individual = await scoreIndividual({
    id: 'ind-1',
    genome: defaultGenome(),
    fixtures,
    weights,
  });
  const sum = Object.values(individual.perFixture).reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(individual.fitness - sum) < 1e-9);
});

test('scoreIndividual is deterministic: same genome + same fixtures + same weights => same fitness', async () => {
  const fixtures = (await loadTierA()).slice(0, 3);
  const weights = await loadDefaultWeights();
  const genome = randomGenome(createPrng(42));
  const a = await scoreIndividual({ id: 'a', genome, fixtures, weights });
  const b = await scoreIndividual({ id: 'b', genome, fixtures, weights });
  assert.equal(a.fitness, b.fitness);
  assert.deepEqual(a.perFixture, b.perFixture);
});

test('scoreIndividual aggregates per-term totals across fixtures into termTotals', async () => {
  // termTotals is needed by the M-03 BT refit so it can compute term
  // differences between paired individuals without re-scoring.
  const fixtures = (await loadTierA()).slice(0, 3);
  const weights = await loadDefaultWeights();
  const individual = await scoreIndividual({
    id: 'ind-terms',
    genome: defaultGenome(),
    fixtures,
    weights,
  });
  assert.ok(individual.termTotals, 'expected termTotals on the scored individual');
  for (const name of TERM_NAMES) {
    assert.ok(name in individual.termTotals, `missing term ${name} in termTotals`);
    assert.ok(Number.isFinite(individual.termTotals[name]));
  }
  // Sanity: fitness must equal sum of weighted termTotals.
  const recomputed = TERM_NAMES.reduce(
    (a, n) => a + (weights[n] ?? 0) * individual.termTotals[n],
    0,
  );
  assert.ok(Math.abs(individual.fitness - recomputed) < 1e-6);
});

test('scoreIndividual sets rejected=true on a genome whose evaluator returns a rejection', async () => {
  // Construct a fixture whose dag is cyclic; the evaluator will reject it.
  const fixtures = [
    {
      id: 'cyclic',
      dag: {
        nodes: [{ id: 'a' }, { id: 'b' }],
        edges: [
          ['a', 'b'],
          ['b', 'a'],
        ],
      },
      theme: 'cream',
      opts: { layerSpacing: 50 },
    },
  ];
  const weights = await loadDefaultWeights();
  const individual = await scoreIndividual({
    id: 'rej',
    genome: defaultGenome(),
    fixtures,
    weights,
  });
  assert.equal(individual.rejected, true);
  assert.ok(individual.rejectionRule);
});
