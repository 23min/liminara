import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { createPrng } from '../prng.mjs';
import {
  tournamentSelect,
  crossoverTier1,
  mutateTier1,
  selectElite,
} from '../operators.mjs';
import {
  defaultTier1,
  validateTier1,
  TIER1_SCHEMA,
  TIER1_FIELDS,
} from '../../genome/tier1.mjs';
import { defaultGenome, makeGenome } from '../../genome/genome.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function pop(items) {
  return items.map(([id, fitness]) => ({
    id,
    genome: defaultGenome(),
    fitness,
  }));
}

// ── tournamentSelect ─────────────────────────────────────────────────────

test('tournamentSelect returns an individual from the population', () => {
  const r = createPrng(1);
  const population = pop([['a', 5], ['b', 1], ['c', 3]]);
  const winner = tournamentSelect(population, r, { size: 3 });
  assert.ok(population.includes(winner));
});

test('tournamentSelect is deterministic under a fixed seed', () => {
  const population = pop([['a', 5], ['b', 1], ['c', 3], ['d', 10]]);
  const a = tournamentSelect(population, createPrng(99), { size: 2 });
  const b = tournamentSelect(population, createPrng(99), { size: 2 });
  assert.equal(a.id, b.id);
});

test('tournamentSelect with size=1 is uniform random over the population', () => {
  const r = createPrng(2);
  const population = pop([['a', 5], ['b', 1], ['c', 3], ['d', 10]]);
  const ids = new Set();
  for (let i = 0; i < 200; i++) {
    ids.add(tournamentSelect(population, r, { size: 1 }).id);
  }
  assert.equal(ids.size, 4, 'every individual should appear at least once over 200 draws');
});

test('tournamentSelect with large size strongly favors the best individual', () => {
  const r = createPrng(3);
  const population = pop([['a', 5], ['b', 1], ['c', 3], ['d', 10]]);
  let bWins = 0;
  const trials = 500;
  for (let i = 0; i < trials; i++) {
    if (tournamentSelect(population, r, { size: 4 }).id === 'b') bWins++;
  }
  // With size == population.length the best always wins.
  assert.equal(bWins, trials);
});

// ── crossoverTier1 ───────────────────────────────────────────────────────

test('crossoverTier1 of two identical parents returns identical values', () => {
  const p = defaultTier1();
  const r = createPrng(4);
  const child = crossoverTier1(p, p, r);
  for (const name of TIER1_FIELDS) {
    assert.equal(child[name], p[name]);
  }
});

test('crossoverTier1 produces fields between each parent pair (convex combination)', () => {
  const p1 = defaultTier1();
  const p2 = { ...p1 };
  for (const name of TIER1_FIELDS) {
    p2[name] = (TIER1_SCHEMA[name].min + TIER1_SCHEMA[name].max) / 2;
  }
  const r = createPrng(5);
  for (let i = 0; i < 20; i++) {
    const child = crossoverTier1(p1, p2, r);
    for (const name of TIER1_FIELDS) {
      const lo = Math.min(p1[name], p2[name]);
      const hi = Math.max(p1[name], p2[name]);
      assert.ok(
        child[name] >= lo - 1e-9 && child[name] <= hi + 1e-9,
        `field ${name} = ${child[name]} outside [${lo}, ${hi}]`,
      );
    }
  }
});

test('crossoverTier1 output is a valid Tier 1 dict', () => {
  const p1 = defaultTier1();
  const p2 = { ...p1 };
  for (const name of TIER1_FIELDS) {
    p2[name] = TIER1_SCHEMA[name].min + 0.3 * (TIER1_SCHEMA[name].max - TIER1_SCHEMA[name].min);
  }
  const child = crossoverTier1(p1, p2, createPrng(6));
  validateTier1(child);
});

test('crossoverTier1 is deterministic under a fixed seed', () => {
  const p1 = defaultTier1();
  const p2 = { ...p1 };
  for (const name of TIER1_FIELDS) {
    p2[name] = TIER1_SCHEMA[name].max;
  }
  const a = crossoverTier1(p1, p2, createPrng(77));
  const b = crossoverTier1(p1, p2, createPrng(77));
  assert.deepEqual(a, b);
});

// ── mutateTier1 ──────────────────────────────────────────────────────────

test('mutateTier1 with strength 0 leaves every field unchanged', () => {
  const t1 = defaultTier1();
  const mutated = mutateTier1(t1, createPrng(7), { strength: 0 });
  assert.deepEqual(mutated, t1);
});

test('mutateTier1 with positive strength changes at least one field', () => {
  const t1 = defaultTier1();
  const mutated = mutateTier1(t1, createPrng(8), { strength: 0.2 });
  let changed = false;
  for (const name of TIER1_FIELDS) {
    if (mutated[name] !== t1[name]) {
      changed = true;
      break;
    }
  }
  assert.ok(changed);
});

test('mutateTier1 always produces a value within bounds (clamped)', () => {
  const t1 = defaultTier1();
  for (let i = 0; i < 20; i++) {
    const mutated = mutateTier1(t1, createPrng(9 + i), { strength: 10 }); // huge sigma
    validateTier1(mutated);
  }
});

test('mutateTier1 is deterministic under a fixed seed', () => {
  const t1 = defaultTier1();
  const a = mutateTier1(t1, createPrng(55), { strength: 0.1 });
  const b = mutateTier1(t1, createPrng(55), { strength: 0.1 });
  assert.deepEqual(a, b);
});

// Tier 2 mutation operator was removed on 2026-04-08 together with the
// Tier 2 schema. See operators.mjs for the rationale.

// ── selectElite ──────────────────────────────────────────────────────────

test('selectElite returns the n lowest-fitness individuals sorted ascending', () => {
  const population = pop([
    ['a', 5],
    ['b', 1],
    ['c', 3],
    ['d', 10],
    ['e', 2],
  ]);
  const elite = selectElite(population, 3);
  assert.equal(elite.length, 3);
  assert.deepEqual(elite.map((e) => e.id), ['b', 'e', 'c']);
});

test('selectElite returns a stable copy (does not mutate the input)', () => {
  const population = pop([['a', 5], ['b', 1], ['c', 3]]);
  const before = population.map((p) => p.id);
  selectElite(population, 2);
  assert.deepEqual(population.map((p) => p.id), before);
});

test('selectElite returns fewer than n when the population is small', () => {
  const population = pop([['a', 5], ['b', 1]]);
  const elite = selectElite(population, 10);
  assert.equal(elite.length, 2);
});

// ── Math.random hygiene ──────────────────────────────────────────────────

test('operators source does not call Math.random', async () => {
  const src = await readFile(join(__dirname, '..', 'operators.mjs'), 'utf8');
  const stripped = src
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
  assert.ok(!/Math\.random\s*\(/.test(stripped), 'operators.mjs must not call Math.random');
});
