import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  makeGenome,
  defaultGenome,
  serialize,
  parse,
  toEvaluatorGenome,
  randomGenome,
} from '../genome.mjs';
import { createPrng } from '../../ga/prng.mjs';
import { evaluate } from '../../evaluator/evaluator.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';

test('defaultGenome has a tier1 section and no tier2', () => {
  const g = defaultGenome();
  assert.ok(g.tier1);
  assert.equal(g.tier2, undefined);
  makeGenome(g); // must not throw
});

test('serialize / parse round-trip: parse(serialize(g)) deep-equals g', () => {
  const g = defaultGenome();
  const s = serialize(g);
  const g2 = parse(s);
  assert.deepEqual(g2, g);
});

test('randomGenome is valid and deterministic under a fixed seed', () => {
  const a = randomGenome(createPrng(42));
  const b = randomGenome(createPrng(42));
  assert.deepEqual(a, b);
  makeGenome(a);
});

test('makeGenome rejects a genome that fails Tier 1 validation', () => {
  const g = defaultGenome();
  const first = Object.keys(g.tier1)[0];
  g.tier1[first] = -1e9;
  assert.throws(() => makeGenome(g));
});

test('toEvaluatorGenome shapes the genome into {render, energy} namespaces only', () => {
  const g = defaultGenome();
  const ev = toEvaluatorGenome(g);
  assert.ok(ev.render);
  assert.ok(ev.energy);
  // No `lane` namespace any more (dead fields removed).
  assert.equal(ev.lane, undefined);
  // No `routing` set by the genome — that now comes from the evaluator's
  // DEFAULT_RENDER and is locked to 'bezier'.
  assert.equal(ev.render.routing, undefined);
});

test('toEvaluatorGenome output is accepted by the evaluator and scores a Tier A fixture', async () => {
  const [fixture] = await loadTierA();
  const g = defaultGenome();
  const ev = toEvaluatorGenome(g);
  const result = await evaluate(ev, fixture);
  assert.equal(result.rejected, undefined, `unexpected rejection: ${JSON.stringify(result)}`);
  assert.ok(Number.isFinite(result.score));
});

test('parse rejects serialized JSON whose tier1 is poisoned', () => {
  const g = defaultGenome();
  const first = Object.keys(g.tier1)[0];
  g.tier1[first] = -1e9;
  const poisoned = JSON.stringify(g);
  assert.throws(() => parse(poisoned));
});

test('the evaluator honors bezier as the default routing regardless of genome content', async () => {
  // After the cleanup, the evaluator's DEFAULT_RENDER locks routing to bezier.
  // Scoring a fixture should succeed without any genome setting routing.
  const [fixture] = await loadTierA();
  const g = defaultGenome();
  const ev = toEvaluatorGenome(g);
  assert.equal(ev.render.routing, undefined, 'genome must not set routing');
  const result = await evaluate(ev, fixture);
  assert.equal(result.rejected, undefined);
});
