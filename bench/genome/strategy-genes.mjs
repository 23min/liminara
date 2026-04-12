// strategy-genes.mjs — categorical strategy genes for the extended genome.
//
// ONLY layout-affecting genes. Scale, energy tuning, force/stress Y
// params removed — they didn't produce visible layout differences.

export const STRATEGY_SCHEMA = {
  'strategy.orderNodes': {
    type: 'categorical',
    values: ['none', 'barycenter', 'median', 'spectral', 'hybrid', 'shuffle'],
    default: 'none',
  },
  'strategy.reduceCrossings': {
    type: 'categorical',
    values: ['none', 'barycenter', 'greedy', 'route-aware'],
    default: 'none',
  },
  'strategy.assignLanes': {
    type: 'categorical',
    values: ['default', 'ordered', 'direct'],
    default: 'default',
  },
  'strategy.refineCoordinates': {
    type: 'categorical',
    values: ['none', 'barycenter'],
    default: 'none',
  },
  // Continuous parameters that affect layout
  'strategy.shuffleSeed': {
    type: 'integer-random',  // special: mutation = completely new random value
    min: 1,
    max: 100000,
    default: 42,
  },
  'strategy.spectralBlend': {
    type: 'continuous',
    min: 0.0,
    max: 1.0,
    default: 0.5,
  },
  'strategy.crossingPasses': {
    type: 'continuous',
    min: 1,
    max: 50,
    default: 24,
  },
};

export const STRATEGY_FIELDS = Object.keys(STRATEGY_SCHEMA);
export const CATEGORICAL_FIELDS = STRATEGY_FIELDS.filter(
  (f) => STRATEGY_SCHEMA[f].type === 'categorical'
);
export const CONTINUOUS_STRATEGY_FIELDS = STRATEGY_FIELDS.filter(
  (f) => STRATEGY_SCHEMA[f].type === 'continuous'
);

export function defaultStrategyGenes() {
  const out = {};
  for (const name of STRATEGY_FIELDS) {
    out[name] = STRATEGY_SCHEMA[name].default;
  }
  return out;
}

export function randomStrategyGenes(prng) {
  const out = {};
  for (const name of STRATEGY_FIELDS) {
    const spec = STRATEGY_SCHEMA[name];
    if (spec.type === 'categorical') {
      const idx = Math.floor(prng.nextFloat() * spec.values.length);
      out[name] = spec.values[Math.min(idx, spec.values.length - 1)];
    } else {
      const v = spec.min + prng.nextFloat() * (spec.max - spec.min);
      out[name] = spec.type === 'integer-random' ? Math.floor(v) : v;
    }
  }
  return out;
}

export function crossoverStrategyGenes(p1, p2, prng) {
  const out = {};
  for (const name of STRATEGY_FIELDS) {
    const spec = STRATEGY_SCHEMA[name];
    if (spec.type === 'categorical') {
      out[name] = prng.nextFloat() < 0.5 ? p1[name] : p2[name];
    } else if (spec.type === 'integer-random') {
      // Don't blend — pick one parent's value randomly
      out[name] = prng.nextFloat() < 0.5 ? (p1[name] ?? spec.default) : (p2[name] ?? spec.default);
    } else {
      const alpha = prng.nextFloat();
      out[name] = alpha * (p1[name] ?? spec.default) + (1 - alpha) * (p2[name] ?? spec.default);
    }
  }
  return out;
}

export function mutateStrategyGenes(genes, prng, { categoricalRate = 0.1, continuousStrength = 0.1 } = {}) {
  const out = { ...genes };
  for (const name of STRATEGY_FIELDS) {
    const spec = STRATEGY_SCHEMA[name];
    if (spec.type === 'categorical') {
      if (prng.nextFloat() < categoricalRate) {
        const others = spec.values.filter((v) => v !== out[name]);
        if (others.length > 0) {
          const idx = Math.floor(prng.nextFloat() * others.length);
          out[name] = others[Math.min(idx, others.length - 1)];
        }
      }
    } else if (spec.type === 'integer-random') {
      // High mutation rate (50%) with completely new random value
      // This keeps the population diverse — seeds don't converge
      if (prng.nextFloat() < 0.5) {
        out[name] = Math.floor(spec.min + prng.nextFloat() * (spec.max - spec.min));
      }
    } else {
      const sigma = continuousStrength * (spec.max - spec.min);
      let v = (out[name] ?? spec.default) + prng.nextGaussian(0, sigma);
      if (v < spec.min) v = spec.min;
      if (v > spec.max) v = spec.max;
      out[name] = v;
    }
  }
  return out;
}

export function validateStrategyGenes(genes) {
  if (!genes || typeof genes !== 'object') return;
  for (const name of STRATEGY_FIELDS) {
    if (!(name in genes)) continue;
    const spec = STRATEGY_SCHEMA[name];
    if (spec.type === 'categorical') {
      if (!spec.values.includes(genes[name])) {
        throw new Error(`Invalid strategy gene ${name}: "${genes[name]}". Valid: ${spec.values.join(', ')}`);
      }
    }
  }
}
