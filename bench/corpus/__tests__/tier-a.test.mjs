import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadTierA } from '../tier-a.mjs';

test('loadTierA returns a non-empty array of fixtures', async () => {
  const fixtures = await loadTierA();
  assert.ok(Array.isArray(fixtures));
  assert.ok(fixtures.length > 0);
});

test('loadTierA exposes the canonical fixture shape', async () => {
  const fixtures = await loadTierA();
  const f = fixtures[0];
  assert.equal(typeof f.id, 'string');
  assert.ok(f.dag);
  assert.ok(Array.isArray(f.dag.nodes));
  assert.ok(Array.isArray(f.dag.edges));
  assert.ok(Array.isArray(f.routes));
  assert.ok(f.theme);
  assert.ok(f.opts);
});

test('loadTierA is pure: two calls return the same ids in the same order', async () => {
  const a = await loadTierA();
  const b = await loadTierA();
  assert.deepEqual(a.map((f) => f.id), b.map((f) => f.id));
});

test('loadTierA includes the linear3 model as the first fixture', async () => {
  const fixtures = await loadTierA();
  assert.equal(fixtures[0].id, 'linear3');
});

test('loadTierA fails loudly with source and id when a fixture is missing a dag', async () => {
  const bad = [{ id: 'broken', theme: 'cream', opts: {} }];
  await assert.rejects(
    () => loadTierA({ models: bad, source: 'synthetic-test-source' }),
    (err) => {
      assert.ok(err instanceof Error);
      assert.match(err.message, /loadTierA/);
      assert.match(err.message, /broken/);
      assert.match(err.message, /synthetic-test-source/);
      assert.match(err.message, /dag/);
      return true;
    },
  );
});

test('loadTierA fails loudly when the source does not export an array', async () => {
  await assert.rejects(
    () => loadTierA({ models: 'not an array', source: 'broken-source' }),
    (err) => {
      assert.match(err.message, /broken-source/);
      assert.match(err.message, /array/);
      return true;
    },
  );
});
