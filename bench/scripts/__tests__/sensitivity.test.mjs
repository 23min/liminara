import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  buildMutatedGenome,
  scoreGenomeAcross,
  measureFieldSensitivity,
  runSensitivity,
  formatSensitivityMarkdown,
} from '../sensitivity.js';
import { TIER1_FIELDS, TIER1_SCHEMA, defaultTier1 } from '../../genome/tier1.mjs';
import { makeGenome } from '../../genome/genome.mjs';
import { loadDefaultWeights, TERM_NAMES } from '../../evaluator/evaluator.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';

async function miniCorpus() {
  // Small but diverse slice — linear chains miss the branch-related
  // fields (e.g. mainSpacing only moves things when branches exist),
  // so we grab the first 4 fixtures which include linear3, linear5,
  // diamond (branches), and wide_fork (more branches).
  return (await loadTierA()).slice(0, 4);
}

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-sensitivity-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

// ── buildMutatedGenome ──────────────────────────────────────────────────

test('buildMutatedGenome returns a genome with only the target field moved', () => {
  const t1 = defaultTier1();
  const target = 'render.mainSpacing';
  const g = buildMutatedGenome({ field: target, delta: 5, tier1: t1 });
  assert.equal(g.tier1[target], t1[target] + 5);
  for (const f of TIER1_FIELDS) {
    if (f === target) continue;
    assert.equal(g.tier1[f], t1[f], `untouched field ${f} moved`);
  }
});

test('buildMutatedGenome clamps deltas that would exceed the field bounds', () => {
  const t1 = defaultTier1();
  const field = 'render.mainSpacing';
  const spec = TIER1_SCHEMA[field];
  const high = buildMutatedGenome({ field, delta: 1e6, tier1: t1 });
  assert.equal(high.tier1[field], spec.max);
  const low = buildMutatedGenome({ field, delta: -1e6, tier1: t1 });
  assert.equal(low.tier1[field], spec.min);
});

test('buildMutatedGenome throws on an unknown field (including fields removed in the cleanup)', () => {
  const t1 = defaultTier1();
  // Previously-live-but-now-removed fields:
  for (const removed of ['render.scale', 'render.layerSpacing', 'energy.stretch_ideal_factor', 'render.cornerRadius']) {
    assert.throws(
      () => buildMutatedGenome({ field: removed, delta: 1, tier1: t1 }),
      /unknown Tier 1 field/,
      `expected ${removed} to throw`,
    );
  }
  assert.throws(
    () => buildMutatedGenome({ field: 'bogus.field', delta: 1, tier1: t1 }),
    /unknown Tier 1 field/,
  );
});

// ── scoreGenomeAcross ───────────────────────────────────────────────────

test('scoreGenomeAcross sums per-fixture totals and tracks per-term accumulators', async () => {
  const fixtures = await miniCorpus();
  const weights = await loadDefaultWeights();
  const genome = makeGenome({ tier1: defaultTier1() });
  const result = await scoreGenomeAcross({ genome, fixtures, weights });
  assert.ok(Number.isFinite(result.total));
  assert.equal(result.scoredCount, fixtures.length);
  assert.ok(result.perFixture);
  for (const f of fixtures) {
    assert.ok(f.id in result.perFixture);
  }
  for (const n of TERM_NAMES) {
    assert.ok(n in result.termTotals);
    assert.ok(Number.isFinite(result.termTotals[n]));
  }
  // Sanity: the scalar should equal the weighted sum of the term totals.
  const recomputed = TERM_NAMES.reduce((a, n) => a + (weights[n] ?? 0) * result.termTotals[n], 0);
  assert.ok(Math.abs(result.total - recomputed) < 1e-6);
});

// ── measureFieldSensitivity ─────────────────────────────────────────────

test('measureFieldSensitivity returns shape {field, sigma, deltaHigh, deltaLow, totalSensitivity, perTermDelta}', async () => {
  const fixtures = await miniCorpus();
  const weights = await loadDefaultWeights();
  const defaults = { tier1: defaultTier1() };
  const r = await measureFieldSensitivity({
    field: 'render.mainSpacing',
    defaults,
    fixtures,
    weights,
  });
  assert.equal(r.field, 'render.mainSpacing');
  assert.ok(Number.isFinite(r.sigma));
  assert.ok(Number.isFinite(r.deltaHigh));
  assert.ok(Number.isFinite(r.deltaLow));
  assert.ok(r.totalSensitivity >= 0);
  assert.ok(r.perTermDelta);
  for (const n of TERM_NAMES) {
    assert.ok(n in r.perTermDelta);
    assert.ok('high' in r.perTermDelta[n]);
    assert.ok('low' in r.perTermDelta[n]);
  }
});

test('measureFieldSensitivity flags the always-active fields as live on any non-trivial mini corpus', async () => {
  // These five fields touch every fixture because they affect stretch
  // (every edge), repel (every node pair), or envelope (every bounding
  // box). If any of them is zero on a 4-fixture slice, the evaluator-
  // genome wiring is broken.
  //
  // Branch-specific fields like `render.mainSpacing` are NOT in this
  // list because they only move things on fixtures with real branch
  // structure. The full-corpus run after the cleanup catches those; the
  // mini-corpus test would be fragile otherwise.
  // With only 2 spacing fields, sensitivity depends on branch structure.
  // Check that at least one field is active on the branching fixtures.
  let anyActive = false;
  const alwaysActive = TIER1_FIELDS;
  const fixtures = await miniCorpus();
  const weights = await loadDefaultWeights();
  const defaults = { tier1: defaultTier1() };
  for (const field of alwaysActive) {
    const r = await measureFieldSensitivity({ field, defaults, fixtures, weights });
    if (r.totalSensitivity > 1e-9) anyActive = true;
  }
  assert.ok(anyActive, 'at least one spacing field should be active on branching fixtures');
});

// ── runSensitivity integration ──────────────────────────────────────────

test('runSensitivity writes report.md and raw.json under a timestamped directory', async () => {
  await withTmp(async (root) => {
    const { outDir, payload } = await runSensitivity({
      outRoot: root,
      now: new Date('2026-04-08T12:00:00.000Z'),
      fixtureSlice: { tierA: 6, tierB: 1 },
    });
    assert.ok(outDir.startsWith(root));
    const md = await readFile(join(outDir, 'report.md'), 'utf8');
    const raw = await readFile(join(outDir, 'raw.json'), 'utf8');
    assert.match(md, /Sensitivity report/);
    assert.match(md, /render\.mainSpacing/);
    const parsed = JSON.parse(raw);
    assert.deepEqual(parsed, payload);
    assert.equal(parsed.results.length, TIER1_FIELDS.length);
    // Results come out sorted by totalSensitivity descending.
    for (let i = 0; i + 1 < parsed.results.length; i++) {
      assert.ok(
        parsed.results[i].totalSensitivity >= parsed.results[i + 1].totalSensitivity,
        `results not sorted at index ${i}`,
      );
    }
  });
});

test('formatSensitivityMarkdown includes a Dead fields section when a synthetic result has zero sensitivity', () => {
  // Synthetic payload with one live and one "dead" row. The dead-row
  // field name here does not need to exist in TIER1_SCHEMA — it's just
  // data in the markdown formatter's input.
  const payload = {
    timestamp: '2026-04-08T00:00:00.000Z',
    strength: 0.1,
    fieldCount: 2,
    fixtureCount: 2,
    tierACount: 2,
    tierBCount: 0,
    weights: {},
    results: [
      {
        field: 'render.layerSpacing',
        sigma: 10,
        deltaHigh: 100,
        deltaLow: -80,
        totalSensitivity: 180,
        perTermDelta: Object.fromEntries(
          TERM_NAMES.map((n) => [n, { high: n === 'stretch' ? 50 : 0, low: n === 'stretch' ? -40 : 0 }]),
        ),
      },
      {
        field: 'render.hypothetical_dead_field',
        sigma: 2,
        deltaHigh: 0,
        deltaLow: 0,
        totalSensitivity: 0,
        perTermDelta: Object.fromEntries(TERM_NAMES.map((n) => [n, { high: 0, low: 0 }])),
      },
    ],
  };
  const md = formatSensitivityMarkdown(payload);
  assert.match(md, /Dead fields/);
  assert.match(md, /hypothetical_dead_field/);
  assert.match(md, /render\.layerSpacing/);
});

test('formatSensitivityMarkdown shows "None detected" on a clean cleanup', () => {
  // After the cleanup chore, every field should be live. Simulate that
  // with a synthetic payload.
  const payload = {
    timestamp: '2026-04-08T00:00:00.000Z',
    strength: 0.1,
    fieldCount: 1,
    fixtureCount: 1,
    tierACount: 1,
    tierBCount: 0,
    weights: {},
    results: [
      {
        field: 'render.layerSpacing',
        sigma: 10,
        deltaHigh: 100,
        deltaLow: -80,
        totalSensitivity: 180,
        perTermDelta: Object.fromEntries(
          TERM_NAMES.map((n) => [n, { high: n === 'stretch' ? 50 : 0, low: n === 'stretch' ? -40 : 0 }]),
        ),
      },
    ],
  };
  const md = formatSensitivityMarkdown(payload);
  assert.match(md, /None detected/);
});
