// genome.mjs — Tier 1 genome with round-trip serialization and a
// projection helper for the evaluator.
//
// The schema is Tier 1 only as of 2026-04-08 (sensitivity-cleanup chore).
// Tier 2 was removed entirely: `routing_primitive` is hardcoded to
// `'bezier'` in the evaluator's DEFAULT_RENDER, and `route_extraction` /
// `convergence_style` were never consumed by the evaluator in the first
// place. If the bench ever grows a second routing primitive, Tier 2 and
// the multi-island-per-primitive semantics come back together.

import {
  defaultTier1,
  validateTier1,
  randomTier1,
  TIER1_FIELDS,
} from './tier1.mjs';

export function defaultGenome() {
  return { tier1: defaultTier1() };
}

export function makeGenome({ tier1 } = {}) {
  const t1 = tier1 ?? defaultTier1();
  validateTier1(t1);
  return { tier1: { ...t1 } };
}

export function randomGenome(prng) {
  return makeGenome({ tier1: randomTier1(prng) });
}

export function serialize(genome) {
  return JSON.stringify(genome);
}

export function parse(str) {
  const obj = JSON.parse(str);
  return makeGenome(obj);
}

export function toEvaluatorGenome(genome) {
  const out = { render: {}, energy: {} };
  for (const name of TIER1_FIELDS) {
    const [ns, field] = name.split('.');
    if (!out[ns]) out[ns] = {};
    out[ns][field] = genome.tier1[name];
  }
  return out;
}
