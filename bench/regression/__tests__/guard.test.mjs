import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  createBestEver,
  updateBestEver,
  regressionGuard,
  saveBestEver,
  loadBestEver,
} from '../guard.mjs';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-regression-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test('createBestEver returns an empty tracker', () => {
  const be = createBestEver();
  assert.deepEqual(be.bestEver, {});
});

test('updateBestEver records a new fixture score', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  assert.equal(be.bestEver.linear3, 100);
});

test('updateBestEver only lowers the best-ever (does not raise on worse scores)', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  updateBestEver(be, 'linear3', 50);
  assert.equal(be.bestEver.linear3, 50);
  updateBestEver(be, 'linear3', 75); // worse, ignored
  assert.equal(be.bestEver.linear3, 50);
});

test('regressionGuard returns rejected=false when there is no prior best-ever', () => {
  const be = createBestEver();
  const result = regressionGuard(be, { linear3: 100 });
  assert.equal(result.rejected, false);
});

test('regressionGuard returns rejected=false when the score equals the best-ever', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  const result = regressionGuard(be, { linear3: 100 });
  assert.equal(result.rejected, false);
});

test('regressionGuard returns rejected=false when the score is strictly better than best-ever', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  const result = regressionGuard(be, { linear3: 50 });
  assert.equal(result.rejected, false);
});

test('regressionGuard rejects when any fixture score drops below the quality threshold', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  updateBestEver(be, 'diamond', 200);
  // 100 / 0.9 ≈ 111.11 — a score of 120 is well below the 90% quality floor.
  const result = regressionGuard(be, { linear3: 120, diamond: 210 });
  assert.equal(result.rejected, true);
  assert.ok(Array.isArray(result.reasons));
  const offender = result.reasons.find((r) => r.fixtureId === 'linear3');
  assert.ok(offender, 'expected a rejection reason for linear3');
  assert.equal(offender.score, 120);
  assert.equal(offender.bestEver, 100);
});

test('regressionGuard respects a custom threshold', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  // At threshold 0.99, 100 / 0.99 ≈ 101.01 — a score of 102 is just over.
  const strict = regressionGuard(be, { linear3: 102 }, { threshold: 0.99 });
  assert.equal(strict.rejected, true);
  // At threshold 0.5, 100 / 0.5 = 200 — a score of 102 is fine.
  const loose = regressionGuard(be, { linear3: 102 }, { threshold: 0.5 });
  assert.equal(loose.rejected, false);
});

test('regressionGuard skips fixtures that are not in best-ever (brand new fixture, no prior data)', () => {
  const be = createBestEver();
  updateBestEver(be, 'linear3', 100);
  // diamond has never been seen — its score cannot regress.
  const result = regressionGuard(be, { linear3: 95, diamond: 99999 });
  assert.equal(result.rejected, false);
});

test('saveBestEver + loadBestEver round-trip', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'best-ever.json');
    const be = createBestEver();
    updateBestEver(be, 'linear3', 100);
    updateBestEver(be, 'diamond', 200);
    await saveBestEver(path, be);
    const loaded = await loadBestEver(path);
    assert.deepEqual(loaded.bestEver, be.bestEver);
  });
});

test('loadBestEver returns an empty tracker when the file does not exist', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'missing.json');
    const loaded = await loadBestEver(path);
    assert.deepEqual(loaded.bestEver, {});
  });
});

test('loadBestEver throws on a corrupt file, does not silently reset', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'corrupt.json');
    await writeFile(path, '{ not valid', 'utf8');
    await assert.rejects(() => loadBestEver(path), /best-ever/);
  });
});

test('regressionGuard rejection reasons include every offending fixture', () => {
  const be = createBestEver();
  updateBestEver(be, 'a', 100);
  updateBestEver(be, 'b', 100);
  updateBestEver(be, 'c', 100);
  const result = regressionGuard(be, { a: 200, b: 200, c: 50 });
  assert.equal(result.rejected, true);
  const ids = result.reasons.map((r) => r.fixtureId).sort();
  assert.deepEqual(ids, ['a', 'b']);
});
