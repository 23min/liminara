// tier2.mjs — Tier 2 discrete genome schema.
//
// Tier 2 parameters cannot participate in arithmetic crossover — they
// mutate by categorical resampling only. The `routing_primitive` field is
// the key driver of the island model: each island holds one population
// per value. The other Tier 2 fields ride along.
//
// `routing_primitive` values are locked to the set dag-map's layout engine
// actually switches on (`bezier`, `angular`, `metro`). The original epic
// spec listed `progressive`, but that is a curve-styling variant inside
// `angular`, not a separate routing primitive — so the GA would have no
// way to realize it. Locked to the three dag-map values.

export const TIER2_SCHEMA = {
  route_extraction: {
    values: ['longest_path', 'max_flow', 'depth_balanced'],
    default: 'longest_path',
  },
  routing_primitive: {
    values: ['bezier', 'angular', 'metro'],
    default: 'angular',
  },
  convergence_style: {
    values: ['exclusive', 'inclusive', 'hybrid'],
    default: 'exclusive',
  },
};

export const TIER2_FIELDS = Object.keys(TIER2_SCHEMA);

export function defaultTier2() {
  const out = {};
  for (const name of TIER2_FIELDS) {
    out[name] = TIER2_SCHEMA[name].default;
  }
  return out;
}

export function validateTier2(values) {
  const errors = [];
  if (!values || typeof values !== 'object') {
    throw new Error('validateTier2: values must be an object');
  }
  for (const name of TIER2_FIELDS) {
    if (!(name in values)) {
      errors.push({ field: name, reason: 'missing' });
      continue;
    }
    const v = values[name];
    const spec = TIER2_SCHEMA[name];
    if (!spec.values.includes(v)) {
      errors.push({ field: name, value: v, reason: 'unknown-value', allowed: spec.values.slice() });
    }
  }
  if (errors.length > 0) {
    const err = new Error(`Tier2 validation failed: ${errors.length} error(s)`);
    err.errors = errors;
    throw err;
  }
}

export function randomTier2(prng) {
  const out = {};
  for (const name of TIER2_FIELDS) {
    out[name] = prng.pick(TIER2_SCHEMA[name].values);
  }
  return out;
}
