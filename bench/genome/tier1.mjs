// tier1.mjs — Tier 1 continuous genome schema.
//
// ONLY layout-affecting parameters belong here. Scale, spacing, and
// energy-tuning parameters are consumer constraints, not evolvable.
// Cleaned up in E-MATRIX epic: removed render.* and energy.* params
// that just zoom the layout or tune the scorer without changing
// node placement.

export const TIER1_SCHEMA = {
  // Vertical spacing between routes (affects node separation)
  'render.mainSpacing': { min: 20, max: 80, default: 40 },
  'render.subSpacing': { min: 10, max: 50, default: 25 },
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
