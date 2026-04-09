import { test } from 'node:test';
import assert from 'node:assert/strict';

import { route_fidelity } from '../route_fidelity.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';
import { loadTierB } from '../../corpus/tier-b.mjs';
import { evaluate, TERM_NAMES } from '../../evaluator/evaluator.mjs';

test('route_fidelity is applicable on every Tier A fixture', async () => {
  const fixtures = await loadTierA();
  for (const f of fixtures) {
    const diag = await route_fidelity({}, f);
    assert.equal(diag.applicable, true, `fixture ${f.id} should be applicable`);
    assert.ok(typeof diag.fidelity === 'number');
    assert.ok(diag.fidelity >= 0 && diag.fidelity <= 1, `fidelity out of range for ${f.id}: ${diag.fidelity}`);
  }
});

test('route_fidelity is not applicable on Tier B fixtures', async () => {
  const fixtures = await loadTierB();
  for (const f of fixtures) {
    const diag = await route_fidelity({}, f);
    assert.equal(diag.applicable, false);
    assert.equal(diag.fidelity, null);
  }
});

test('route_fidelity returns a per-route breakdown with an id for each authored route', async () => {
  const [fixture] = await loadTierA();
  const diag = await route_fidelity({}, fixture);
  assert.ok(Array.isArray(diag.perRoute));
  assert.equal(diag.perRoute.length, fixture.routes.length);
  for (const entry of diag.perRoute) {
    assert.ok(typeof entry.fidelity === 'number');
    assert.ok(entry.fidelity >= 0 && entry.fidelity <= 1);
  }
});

test('evaluate never exposes a fidelity or route_fidelity key in its return shape', async () => {
  const [fixture] = await loadTierA();
  const result = await evaluate({}, fixture);
  assert.equal(result.rejected, undefined);
  assert.equal('route_fidelity' in result, false);
  assert.equal('fidelity' in result, false);
  assert.equal('route_fidelity' in result.terms, false);
  assert.equal('fidelity' in result.terms, false);
  // Sanity: the known term names are exactly the eight energy terms — no
  // diagnostic leaked in.
  assert.deepEqual(
    Object.keys(result.terms).sort(),
    [...TERM_NAMES].sort(),
  );
});

test('route_fidelity on a Tier A fixture whose authored routes are passed through is ~1.0', async () => {
  // Since the evaluator passes `fixture.routes` into layoutMetro, dag-map
  // preserves the authored routes. Fidelity should therefore be exactly 1.0
  // on any fixture where the authored routes cover every authored node.
  const [fixture] = await loadTierA();
  const diag = await route_fidelity({}, fixture);
  assert.ok(diag.fidelity >= 0.999, `expected near-perfect fidelity, got ${diag.fidelity}`);
});
