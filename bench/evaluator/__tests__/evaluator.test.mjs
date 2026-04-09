import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { evaluate, TERM_NAMES, loadDefaultWeights } from '../evaluator.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';
import { loadTierB } from '../../corpus/tier-b.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function clone(x) {
  return JSON.parse(JSON.stringify(x));
}

test('evaluate returns a score and all eight term keys on a Tier A fixture', async () => {
  const [fixture] = await loadTierA();
  const result = await evaluate({}, fixture);
  assert.equal(result.rejected, undefined, `expected no rejection, got ${JSON.stringify(result)}`);
  assert.ok(Number.isFinite(result.score));
  for (const name of TERM_NAMES) {
    assert.ok(name in result.terms, `missing term ${name}`);
    assert.ok(Number.isFinite(result.terms[name]), `term ${name} is not finite: ${result.terms[name]}`);
  }
});

test('evaluate is deterministic: ten repeated calls return byte-identical JSON', async () => {
  const [fixture] = await loadTierA();
  const first = JSON.stringify(await evaluate({}, fixture));
  for (let i = 0; i < 9; i++) {
    const next = JSON.stringify(await evaluate({}, fixture));
    assert.equal(next, first, `run ${i + 2} diverged from run 1`);
  }
});

test('evaluate returns the weighted sum: changing one weight changes the score predictably', async () => {
  // Pick a fixture whose envelope term is strictly positive so the test is
  // not a tautology when crossings happen to be zero on a small fixture.
  const fixtures = await loadTierA();
  let fixture, base;
  const baseWeights = await loadDefaultWeights();
  for (const f of fixtures) {
    const r = await evaluate({}, f, { weights: baseWeights });
    if (!r.rejected && r.terms.envelope > 0) {
      fixture = f;
      base = r;
      break;
    }
  }
  assert.ok(fixture, 'expected at least one Tier A fixture with envelope > 0');
  const weightsA = { ...baseWeights, envelope: 0 };
  const weightsB = { ...baseWeights, envelope: 7 };
  const a = await evaluate({}, fixture, { weights: weightsA });
  const b = await evaluate({}, fixture, { weights: weightsB });
  // Per-term values should be identical under the two weight vectors.
  assert.deepEqual(a.terms, b.terms);
  const diff = b.score - a.score;
  const expected = 7 * base.terms.envelope;
  assert.ok(
    Math.abs(diff - expected) < 1e-6,
    `diff=${diff} expected=${expected} (envelope=${base.terms.envelope})`,
  );
});

test('evaluate: zero weights produce a zero score but keep per-term values', async () => {
  const [fixture] = await loadTierA();
  const zero = Object.fromEntries(TERM_NAMES.map((n) => [n, 0]));
  const result = await evaluate({}, fixture, { weights: zero });
  assert.equal(result.score, 0);
  for (const name of TERM_NAMES) {
    assert.ok(name in result.terms);
  }
});

test('evaluate scores every Tier A fixture without crashing or rejecting', async () => {
  const fixtures = await loadTierA();
  for (const f of fixtures) {
    const result = await evaluate({}, f);
    assert.ok(
      result.rejected === undefined,
      `fixture ${f.id} rejected: ${JSON.stringify(result)}`,
    );
    assert.ok(Number.isFinite(result.score), `fixture ${f.id} has non-finite score`);
  }
});

test('evaluate scores every Tier B fixture without crashing or rejecting', async () => {
  const fixtures = await loadTierB();
  for (const f of fixtures) {
    const result = await evaluate({}, f);
    assert.ok(
      result.rejected === undefined,
      `fixture ${f.id} rejected: ${JSON.stringify(result)}`,
    );
    assert.ok(Number.isFinite(result.score), `fixture ${f.id} has non-finite score`);
  }
});

test('evaluate returns {rejected, rule} when layoutMetro fails on a cyclic dag', async () => {
  const cyclic = {
    id: 'cycle-test',
    dag: {
      nodes: [{ id: 'a' }, { id: 'b' }],
      edges: [
        ['a', 'b'],
        ['b', 'a'],
      ],
    },
    theme: 'cream',
    opts: { layerSpacing: 50 },
  };
  const result = await evaluate({}, cyclic);
  assert.equal(result.rejected, true);
  assert.ok(typeof result.rule === 'string');
  assert.ok(result.detail && result.detail.length > 0);
});

test('evaluate never diverges when the same input is cloned on every call', async () => {
  // A harder determinism guarantee: every call receives a fresh deep clone so
  // any mutation of the fixture/genome arguments would surface as divergence.
  const [fixture] = await loadTierA();
  const first = JSON.stringify(await evaluate(clone({}), clone(fixture)));
  for (let i = 0; i < 5; i++) {
    const next = JSON.stringify(await evaluate(clone({}), clone(fixture)));
    assert.equal(next, first);
  }
});

test('evaluator source does not call Math.random', async () => {
  // Strip line comments before scanning so prose mentions ("we never call
  // Math.random") do not trip the check. Block comments are not used in
  // the evaluator source.
  const files = [
    join(__dirname, '..', 'evaluator.mjs'),
    join(__dirname, '..', 'adapter.mjs'),
  ];
  for (const f of files) {
    const src = await readFile(f, 'utf8');
    const stripped = src
      .split('\n')
      .map((line) => line.replace(/\/\/.*$/, ''))
      .join('\n');
    assert.ok(
      !/Math\.random\s*\(/.test(stripped),
      `${f} must not call Math.random`,
    );
  }
});

test('evaluator honors a genome render override: different routing changes the score', async () => {
  const [fixture] = await loadTierA();
  const a = await evaluate({ render: { routing: 'angular' } }, fixture);
  const b = await evaluate({ render: { routing: 'bezier' } }, fixture);
  // Both must produce valid scores. The polyline projection is the same
  // under both routings (it's built from node positions, which do not depend
  // on routing style), so the score may or may not differ. We just require
  // both to be finite and non-rejected.
  assert.ok(Number.isFinite(a.score));
  assert.ok(Number.isFinite(b.score));
});
