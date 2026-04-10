// strategy-genes.mjs — categorical strategy genes for the extended genome.
// Each gene selects a strategy for a pipeline slot. Integer parameters
// (crossingPasses, refinementIterations) are treated as continuous genes
// that get rounded at evaluation time.

export const STRATEGY_SCHEMA = {
  'strategy.orderNodes': {
    type: 'categorical',
    values: ['none', 'barycenter', 'median'],
    default: 'none',
  },
  'strategy.reduceCrossings': {
    type: 'categorical',
    values: ['none', 'barycenter', 'greedy'],
    default: 'none',
  },
  'strategy.assignLanes': {
    type: 'categorical',
    values: ['default', 'ordered'],
    default: 'default',
  },
  'strategy.positionX': {
    type: 'categorical',
    values: ['fixed', 'compact'],
    default: 'fixed',
  },
  'strategy.refineCoordinates': {
    type: 'categorical',
    values: ['none', 'barycenter'],
    default: 'none',
  },
  // Continuous parameters for strategies
  'strategy.crossingPasses': {
    type: 'continuous',
    min: 1,
    max: 50,
    default: 24,
  },
  'strategy.refinementIterations': {
    type: 'continuous',
    min: 1,
    max: 20,
    default: 12,
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
      out[name] = spec.min + prng.nextFloat() * (spec.max - spec.min);
    }
  }
  return out;
}

export function crossoverStrategyGenes(p1, p2, prng) {
  const out = {};
  for (const name of STRATEGY_FIELDS) {
    const spec = STRATEGY_SCHEMA[name];
    if (spec.type === 'categorical') {
      // Pick from one parent randomly
      out[name] = prng.nextFloat() < 0.5 ? p1[name] : p2[name];
    } else {
      // Arithmetic blend (same as tier1)
      const alpha = prng.nextFloat();
      out[name] = alpha * p1[name] + (1 - alpha) * p2[name];
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
        // Pick a different value
        const others = spec.values.filter((v) => v !== out[name]);
        if (others.length > 0) {
          const idx = Math.floor(prng.nextFloat() * others.length);
          out[name] = others[Math.min(idx, others.length - 1)];
        }
      }
    } else {
      const sigma = continuousStrength * (spec.max - spec.min);
      let v = out[name] + prng.nextGaussian(0, sigma);
      if (v < spec.min) v = spec.min;
      if (v > spec.max) v = spec.max;
      out[name] = v;
    }
  }
  return out;
}

export function validateStrategyGenes(genes) {
  if (!genes || typeof genes !== 'object') return; // absent = defaults, ok
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
