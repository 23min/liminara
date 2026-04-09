import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { runBaseline } from '../baseline.js';

async function withTmpRoot(fn) {
  const root = await mkdtemp(join(tmpdir(), 'dag-map-bench-baseline-'));
  try {
    return await fn(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test('runBaseline writes scores.json under a timestamped directory', async () => {
  await withTmpRoot(async (root) => {
    const { outPath, payload } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T12:34:56.789Z'),
    });
    assert.ok(outPath.startsWith(root));
    assert.match(outPath, /scores\.json$/);
    const raw = await readFile(outPath, 'utf8');
    const parsed = JSON.parse(raw);
    assert.equal(parsed.timestamp, '2026-04-07T12:34:56.789Z');
    assert.equal(parsed.fixtures.length, payload.fixtures.length);
    assert.ok(parsed.fixtures.length > 0);
  });
});

test('runBaseline covers both Tier A and Tier B fixtures', async () => {
  await withTmpRoot(async (root) => {
    const { payload } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    const tiers = new Set(payload.fixtures.map((f) => f.tier));
    assert.ok(tiers.has('A'), 'expected Tier A fixtures');
    assert.ok(tiers.has('B'), 'expected Tier B fixtures');
  });
});

test('runBaseline includes per-term breakdowns and a total score per fixture', async () => {
  await withTmpRoot(async (root) => {
    const { payload } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    for (const f of payload.fixtures) {
      if (f.result.rejected) continue;
      assert.ok(typeof f.result.score === 'number');
      assert.ok(f.result.terms);
      for (const name of ['stretch', 'bend', 'crossings', 'monotone', 'envelope', 'channel', 'repel_nn', 'repel_ne']) {
        assert.ok(name in f.result.terms, `fixture ${f.id} missing term ${name}`);
      }
    }
  });
});

test('runBaseline is reproducible: two runs with the same fixtures and weights produce identical per-fixture scores', async () => {
  await withTmpRoot(async (root) => {
    const { payload: a } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    const { payload: b } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T01:00:00.000Z'),
    });
    assert.notEqual(a.timestamp, b.timestamp);
    assert.equal(a.fixtures.length, b.fixtures.length);
    for (let i = 0; i < a.fixtures.length; i++) {
      assert.equal(a.fixtures[i].id, b.fixtures[i].id);
      assert.equal(a.fixtures[i].tier, b.fixtures[i].tier);
      assert.deepEqual(a.fixtures[i].result, b.fixtures[i].result);
    }
  });
});

test('runBaseline sorts fixtures deterministically: Tier A first, then Tier B, each in loader order', async () => {
  await withTmpRoot(async (root) => {
    const { payload } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    let sawB = false;
    for (const f of payload.fixtures) {
      if (f.tier === 'B') sawB = true;
      if (sawB) {
        assert.equal(f.tier, 'B', `tier A fixture ${f.id} appeared after a tier B fixture`);
      }
    }
  });
});

test('runBaseline writes route-fidelity.json alongside scores.json', async () => {
  await withTmpRoot(async (root) => {
    const { outPath, fidelityPath, fidelityPayload } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    assert.notEqual(outPath, fidelityPath);
    assert.match(fidelityPath, /route-fidelity\.json$/);
    const raw = await readFile(fidelityPath, 'utf8');
    const parsed = JSON.parse(raw);
    assert.deepEqual(parsed, fidelityPayload);
    assert.ok(parsed.fixtures.some((f) => f.tier === 'A' && f.applicable === true));
    assert.ok(parsed.fixtures.some((f) => f.tier === 'B' && f.applicable === false));
  });
});

test('runBaseline scores.json never contains a fidelity or route_fidelity key', async () => {
  await withTmpRoot(async (root) => {
    const { outPath } = await runBaseline({
      outRoot: root,
      now: new Date('2026-04-07T00:00:00.000Z'),
    });
    const raw = await readFile(outPath, 'utf8');
    assert.ok(!/"route_fidelity"/.test(raw), 'scores.json must not carry route_fidelity');
    assert.ok(!/"fidelity"/.test(raw), 'scores.json must not carry fidelity');
  });
});
