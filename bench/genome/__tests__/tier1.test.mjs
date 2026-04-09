import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  TIER1_SCHEMA,
  TIER1_FIELDS,
  defaultTier1,
  validateTier1,
  clampTier1,
  randomTier1,
} from '../tier1.mjs';

import { createPrng } from '../../ga/prng.mjs';

test('TIER1_SCHEMA defines the 8 live continuous parameters after the sensitivity cleanup', () => {
  assert.equal(TIER1_FIELDS.length, 8, `expected exactly 8 live Tier 1 fields, got ${TIER1_FIELDS.length}`);
  // Sanity check: every field is in a known namespace.
  for (const name of TIER1_FIELDS) {
    assert.match(name, /^(render|energy)\./, `field ${name} is not under a known namespace`);
  }
});

test('every Tier 1 schema entry declares min, max, and default', () => {
  for (const [name, spec] of Object.entries(TIER1_SCHEMA)) {
    assert.equal(typeof spec.min, 'number', `${name}.min must be a number`);
    assert.equal(typeof spec.max, 'number', `${name}.max must be a number`);
    assert.equal(typeof spec.default, 'number', `${name}.default must be a number`);
    assert.ok(spec.max > spec.min, `${name}.max must be > ${name}.min`);
    assert.ok(
      spec.default >= spec.min && spec.default <= spec.max,
      `${name}.default must fall within [min, max]`,
    );
  }
});

test('defaultTier1 returns every field at its declared default', () => {
  const d = defaultTier1();
  for (const name of TIER1_FIELDS) {
    assert.equal(d[name], TIER1_SCHEMA[name].default);
  }
});

test('validateTier1 accepts a defaults-only Tier 1 dict', () => {
  validateTier1(defaultTier1()); // must not throw
});

test('validateTier1 rejects a value below min with a structured error', () => {
  const t1 = defaultTier1();
  const first = TIER1_FIELDS[0];
  t1[first] = TIER1_SCHEMA[first].min - 1;
  try {
    validateTier1(t1);
    assert.fail('validateTier1 should have thrown');
  } catch (err) {
    assert.ok(Array.isArray(err.errors));
    const e = err.errors.find((e) => e.field === first);
    assert.ok(e, `expected an error for field ${first}`);
    assert.equal(e.reason, 'out-of-range');
    assert.equal(e.min, TIER1_SCHEMA[first].min);
    assert.equal(e.max, TIER1_SCHEMA[first].max);
  }
});

test('validateTier1 rejects a value above max with a structured error', () => {
  const t1 = defaultTier1();
  const last = TIER1_FIELDS[TIER1_FIELDS.length - 1];
  t1[last] = TIER1_SCHEMA[last].max + 1;
  assert.throws(() => validateTier1(t1), (err) => {
    const e = err.errors.find((e) => e.field === last);
    assert.equal(e.reason, 'out-of-range');
    return true;
  });
});

test('validateTier1 rejects a missing field with reason "missing"', () => {
  const t1 = defaultTier1();
  const target = TIER1_FIELDS[0];
  delete t1[target];
  assert.throws(() => validateTier1(t1), (err) => {
    const e = err.errors.find((e) => e.field === target);
    assert.equal(e.reason, 'missing');
    return true;
  });
});

test('validateTier1 rejects a non-numeric value with reason "not-a-number"', () => {
  const t1 = defaultTier1();
  const target = TIER1_FIELDS[0];
  t1[target] = 'nope';
  assert.throws(() => validateTier1(t1), (err) => {
    const e = err.errors.find((e) => e.field === target);
    assert.equal(e.reason, 'not-a-number');
    return true;
  });
});

test('clampTier1 pulls out-of-range values back into their bounds', () => {
  const first = TIER1_FIELDS[0];
  const last = TIER1_FIELDS[TIER1_FIELDS.length - 1];
  const t1 = { ...defaultTier1() };
  t1[first] = TIER1_SCHEMA[first].min - 1000;
  t1[last] = TIER1_SCHEMA[last].max + 1000;
  const clamped = clampTier1(t1);
  assert.equal(clamped[first], TIER1_SCHEMA[first].min);
  assert.equal(clamped[last], TIER1_SCHEMA[last].max);
  validateTier1(clamped); // the result must itself be valid
});

test('randomTier1 produces a valid genome with every field in range', () => {
  const r = createPrng(123);
  for (let i = 0; i < 50; i++) {
    const t1 = randomTier1(r);
    validateTier1(t1);
  }
});

test('randomTier1 is deterministic for a fixed seed', () => {
  const a = randomTier1(createPrng(7));
  const b = randomTier1(createPrng(7));
  assert.deepEqual(a, b);
});
