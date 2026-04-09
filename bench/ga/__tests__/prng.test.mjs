import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { createPrng } from '../prng.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// A deterministic, splittable PRNG is the foundation of every GA operator.
// The contract the GA relies on:
//
//   - Same seed => same sequence
//   - clone() => independent stream, same current state
//   - fork(label) => new stream seeded from (seed, label), still deterministic
//   - getState/setState => snapshot + resume round-trip
//   - No calls to Math.random anywhere in the PRNG source

test('createPrng with the same seed produces the same uint32 sequence', () => {
  const a = createPrng(42);
  const b = createPrng(42);
  for (let i = 0; i < 16; i++) {
    assert.equal(a.next(), b.next());
  }
});

test('createPrng with different seeds produces different first draws', () => {
  const a = createPrng(1);
  const b = createPrng(2);
  assert.notEqual(a.next(), b.next());
});

test('nextFloat returns values strictly in [0, 1)', () => {
  const r = createPrng(7);
  for (let i = 0; i < 1000; i++) {
    const v = r.nextFloat();
    assert.ok(v >= 0 && v < 1, `nextFloat out of range: ${v}`);
  }
});

test('nextInt(min, max) is inclusive and stays within bounds', () => {
  const r = createPrng(11);
  let sawMin = false;
  let sawMax = false;
  for (let i = 0; i < 2000; i++) {
    const v = r.nextInt(3, 7);
    assert.ok(Number.isInteger(v));
    assert.ok(v >= 3 && v <= 7);
    if (v === 3) sawMin = true;
    if (v === 7) sawMax = true;
  }
  assert.ok(sawMin, 'nextInt never hit its minimum');
  assert.ok(sawMax, 'nextInt never hit its maximum');
});

test('nextGaussian returns finite numbers and has roughly zero mean, unit variance with mu=0 sigma=1', () => {
  const r = createPrng(13);
  const n = 5000;
  let sum = 0;
  let sumSq = 0;
  for (let i = 0; i < n; i++) {
    const v = r.nextGaussian(0, 1);
    assert.ok(Number.isFinite(v), `nextGaussian not finite: ${v}`);
    sum += v;
    sumSq += v * v;
  }
  const mean = sum / n;
  const variance = sumSq / n - mean * mean;
  // Loose bounds — this is a statistical check, not a property test.
  assert.ok(Math.abs(mean) < 0.1, `mean too far from 0: ${mean}`);
  assert.ok(Math.abs(variance - 1) < 0.15, `variance too far from 1: ${variance}`);
});

test('clone() produces an independent PRNG with the same current output', () => {
  const a = createPrng(99);
  a.next(); // advance
  a.next();
  const b = a.clone();
  // Both must emit the same next value.
  assert.equal(a.next(), b.next());
  // After that, advancing one must not move the other.
  const aPeek = a.next();
  const bPeekBefore = b.getState();
  a.next();
  a.next();
  assert.deepEqual(b.getState(), bPeekBefore);
  // And b's own next call must equal what a emitted at the same logical step.
  assert.equal(b.next(), aPeek);
});

test('getState() + setState() round-trip restores the exact stream', () => {
  const r = createPrng(17);
  for (let i = 0; i < 5; i++) r.next();
  const snapshot = r.getState();
  const a = r.next();
  const b = r.next();
  r.setState(snapshot);
  assert.equal(r.next(), a);
  assert.equal(r.next(), b);
});

test('fork(label) is deterministic: same seed + same label => same stream', () => {
  const a = createPrng(5).fork('selection');
  const b = createPrng(5).fork('selection');
  for (let i = 0; i < 8; i++) {
    assert.equal(a.next(), b.next());
  }
});

test('fork(label) is independent across labels: different label => different stream', () => {
  const a = createPrng(5).fork('selection');
  const b = createPrng(5).fork('mutation');
  // First draw should differ — if it doesn't, the label hashing is broken.
  assert.notEqual(a.next(), b.next());
});

test('fork(label) is independent from its parent: advancing the parent does not move the forked stream', () => {
  const parent = createPrng(21);
  const child = parent.fork('op');
  const snapshotChild = child.getState();
  for (let i = 0; i < 10; i++) parent.next();
  assert.deepEqual(child.getState(), snapshotChild);
});

test('pick(array) returns an element from the array and never out-of-bounds', () => {
  const r = createPrng(33);
  const arr = ['a', 'b', 'c', 'd'];
  for (let i = 0; i < 200; i++) {
    const v = r.pick(arr);
    assert.ok(arr.includes(v));
  }
});

test('pick(array) on a single-element array always returns that element', () => {
  const r = createPrng(33);
  assert.equal(r.pick(['only']), 'only');
});

test('pick(array) throws on an empty array', () => {
  const r = createPrng(33);
  assert.throws(() => r.pick([]), /empty/);
});

test('PRNG source does not call Math.random', async () => {
  const src = await readFile(join(__dirname, '..', 'prng.mjs'), 'utf8');
  const stripped = src
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
  assert.ok(!/Math\.random\s*\(/.test(stripped), 'prng.mjs must not call Math.random');
});
