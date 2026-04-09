import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadTierB } from '../tier-b.mjs';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// Default-directory smoke tests use the real snapshot files in
// dag-map/bench/fixtures/tier-b/. Loud-failure tests use a throwaway
// temp dir so they can deliberately inject malformed fixtures without
// polluting the snapshot set.

test('loadTierB returns the snapshot fixtures in lexicographic order', async () => {
  const fixtures = await loadTierB();
  assert.ok(Array.isArray(fixtures));
  assert.ok(fixtures.length >= 2, 'expected at least 2 snapshot fixtures');
  const ids = fixtures.map((f) => f.id);
  assert.deepEqual(ids, ['radar-branching', 'radar-mini']);
});

test('loadTierB exposes the canonical fixture shape with no routes', async () => {
  const fixtures = await loadTierB();
  for (const f of fixtures) {
    assert.equal(typeof f.id, 'string');
    assert.ok(f.dag);
    assert.ok(Array.isArray(f.dag.nodes));
    assert.ok(Array.isArray(f.dag.edges));
    assert.equal(f.routes, undefined, 'Tier B fixtures must not carry routes');
    assert.ok(f.theme);
    assert.ok(f.opts);
  }
});

test('loadTierB is pure: two calls return the same ids in the same order', async () => {
  const a = await loadTierB();
  const b = await loadTierB();
  assert.deepEqual(a.map((f) => f.id), b.map((f) => f.id));
});

test('loadTierB fails loudly with the path when the directory does not exist', async () => {
  const bogus = join(tmpdir(), 'dag-map-bench-tier-b-does-not-exist-xyz');
  await assert.rejects(
    () => loadTierB({ dir: bogus }),
    (err) => {
      assert.ok(err instanceof Error);
      assert.match(err.message, /loadTierB/);
      assert.ok(err.message.includes(bogus), `error should mention path, got: ${err.message}`);
      return true;
    },
  );
});

test('loadTierB fails loudly with the path when a fixture file is malformed JSON', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-tier-b-'));
  try {
    const bad = join(dir, 'broken.json');
    await writeFile(bad, '{ not valid json', 'utf8');
    await assert.rejects(
      () => loadTierB({ dir }),
      (err) => {
        assert.ok(err instanceof Error);
        assert.match(err.message, /malformed JSON/);
        assert.ok(err.message.includes(bad), `error should mention path, got: ${err.message}`);
        return true;
      },
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('loadTierB fails loudly when a fixture is missing a required field', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-tier-b-'));
  try {
    const missing = join(dir, 'missing-dag.json');
    await writeFile(
      missing,
      JSON.stringify({ id: 'x', theme: 'cream', opts: {} }),
      'utf8',
    );
    await assert.rejects(
      () => loadTierB({ dir }),
      (err) => {
        assert.ok(err instanceof Error);
        assert.match(err.message, /missing dag/);
        assert.ok(err.message.includes(missing));
        return true;
      },
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('loadTierB rejects a Tier B fixture that carries routes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-tier-b-'));
  try {
    const offender = join(dir, 'with-routes.json');
    await writeFile(
      offender,
      JSON.stringify({
        id: 'x',
        dag: { nodes: [], edges: [] },
        routes: [],
        theme: 'cream',
        opts: {},
      }),
      'utf8',
    );
    await assert.rejects(
      () => loadTierB({ dir }),
      /must not carry routes/,
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
