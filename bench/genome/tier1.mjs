// tier1.mjs — Tier 1 continuous genome schema.
//
// These are the real-valued knobs the GA is allowed to mutate and crossover.
// Field names use a `namespace.field` convention so the genome can be
// projected cleanly into the evaluator shape (`render.*`, `energy.*`)
// without reshuffling logic at operator time.
//
// Every field declares its {min, max, default}. Validation is strict:
// out-of-range, non-numeric, and missing values all surface as structured
// errors the GA can log.
//
// The schema was cut from 15 to 8 fields after an empirical sensitivity
// analysis on 2026-04-08 found 7 fields that produced zero scalar fitness
// delta when mutated by ±1σ (see work/gaps.md and the sensitivity report
// at bench/run/sensitivity/). The removed fields were:
//
//   render.trunkY              - translation-invariant in the energy
//                                 function (every term measures relative
//                                 distances, so a uniform y shift is a
//                                 no-op). Also a quietly dead option in
//                                 dag-map's layoutMetro.
//   render.progressivePower    - affects SVG curve shape only; the
//                                 adapter uses straight-line polylines
//                                 between route waypoints.
//   render.cornerRadius        - same reason as progressivePower.
//   lane.weight_pure/recordable/pinned_env/side_effecting
//                              - wired into toEvaluatorGenome's output
//                                 but never consumed by dag-map or the
//                                 energy terms. Pure dead weight.

export const TIER1_SCHEMA = {
  // --- dag-map render knobs ---
  'render.layerSpacing': { min: 20, max: 120, default: 50 },
  'render.mainSpacing': { min: 15, max: 60, default: 34 },
  'render.subSpacing': { min: 8, max: 40, default: 16 },
  'render.scale': { min: 0.8, max: 2.5, default: 1.5 },

  // --- energy-term tuning ---
  'energy.stretch_ideal_factor': { min: 0.5, max: 2.0, default: 1.0 },
  'energy.repel_threshold_px': { min: 10, max: 100, default: 40 },
  'energy.channel_min_separation_px': { min: 5, max: 60, default: 20 },
  'energy.envelope_target_ratio': { min: 0.8, max: 3.0, default: 2.0 },
};

export const TIER1_FIELDS = Object.keys(TIER1_SCHEMA);

export function defaultTier1() {
  const out = {};
  for (const name of TIER1_FIELDS) {
    out[name] = TIER1_SCHEMA[name].default;
  }
  return out;
}

export function validateTier1(values) {
  const errors = [];
  if (!values || typeof values !== 'object') {
    throw new Error('validateTier1: values must be an object');
  }
  for (const name of TIER1_FIELDS) {
    if (!(name in values)) {
      errors.push({ field: name, reason: 'missing' });
      continue;
    }
    const v = values[name];
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      errors.push({ field: name, value: v, reason: 'not-a-number' });
      continue;
    }
    const spec = TIER1_SCHEMA[name];
    if (v < spec.min || v > spec.max) {
      errors.push({ field: name, value: v, reason: 'out-of-range', min: spec.min, max: spec.max });
    }
  }
  if (errors.length > 0) {
    const err = new Error(`Tier1 validation failed: ${errors.length} error(s)`);
    err.errors = errors;
    throw err;
  }
}

export function clampTier1(values) {
  const out = {};
  for (const name of TIER1_FIELDS) {
    const spec = TIER1_SCHEMA[name];
    let v = values[name];
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      v = spec.default;
    }
    if (v < spec.min) v = spec.min;
    if (v > spec.max) v = spec.max;
    out[name] = v;
  }
  return out;
}

export function randomTier1(prng) {
  const out = {};
  for (const name of TIER1_FIELDS) {
    const spec = TIER1_SCHEMA[name];
    out[name] = spec.min + prng.nextFloat() * (spec.max - spec.min);
  }
  return out;
}
