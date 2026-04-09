import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  TIER2_SCHEMA,
  TIER2_FIELDS,
  defaultTier2,
  validateTier2,
  randomTier2,
} from '../tier2.mjs';

import { createPrng } from '../../ga/prng.mjs';

test('TIER2_SCHEMA defines route_extraction, routing_primitive, and convergence_style', () => {
  assert.deepEqual(TIER2_FIELDS.sort(), ['convergence_style', 'route_extraction', 'routing_primitive']);
});

test('each Tier 2 schema entry declares values and a default in values', () => {
  for (const [name, spec] of Object.entries(TIER2_SCHEMA)) {
    assert.ok(Array.isArray(spec.values), `${name}.values must be an array`);
    assert.ok(spec.values.length >= 2, `${name} must have >=2 possible values`);
    assert.ok(spec.values.includes(spec.default), `${name}.default must be in values`);
  }
});

test('routing_primitive values match dag-map supported routings', () => {
  // dag-map supports: bezier, angular, metro. If the GA ever emits a fourth
  // value, the evaluator would crash. Lock this.
  assert.deepEqual(TIER2_SCHEMA.routing_primitive.values.sort(), ['angular', 'bezier', 'metro']);
});

test('defaultTier2 returns every field at its declared default', () => {
  const d = defaultTier2();
  for (const name of TIER2_FIELDS) {
    assert.equal(d[name], TIER2_SCHEMA[name].default);
  }
});

test('validateTier2 accepts a defaults-only Tier 2 dict', () => {
  validateTier2(defaultTier2());
});

test('validateTier2 rejects an unknown value with a structured error', () => {
  const t2 = defaultTier2();
  t2.routing_primitive = 'spline'; // not a supported value
  assert.throws(() => validateTier2(t2), (err) => {
    const e = err.errors.find((e) => e.field === 'routing_primitive');
    assert.equal(e.reason, 'unknown-value');
    assert.deepEqual(e.allowed.sort(), ['angular', 'bezier', 'metro']);
    return true;
  });
});

test('validateTier2 rejects a missing field with reason "missing"', () => {
  const t2 = defaultTier2();
  delete t2.convergence_style;
  assert.throws(() => validateTier2(t2), (err) => {
    const e = err.errors.find((e) => e.field === 'convergence_style');
    assert.equal(e.reason, 'missing');
    return true;
  });
});

test('randomTier2 produces a valid Tier 2 dict every call', () => {
  const r = createPrng(99);
  for (let i = 0; i < 50; i++) {
    const t2 = randomTier2(r);
    validateTier2(t2);
  }
});

test('randomTier2 is deterministic for a fixed seed', () => {
  const a = randomTier2(createPrng(7));
  const b = randomTier2(createPrng(7));
  assert.deepEqual(a, b);
});
