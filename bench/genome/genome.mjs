// genome.mjs — Tier 1 genome + strategy genes with round-trip serialization
// and a projection helper for the evaluator.
//
// The schema is Tier 1 (8 continuous render/energy fields) plus strategy
// genes (3 categorical + 2 continuous). Strategy genes were added in
// M-EVOLVE-03 to enable evolutionary algorithm configuration.

import {
  defaultTier1,
  validateTier1,
  randomTier1,
  TIER1_FIELDS,
} from './tier1.mjs';

import {
  defaultStrategyGenes,
  randomStrategyGenes,
  validateStrategyGenes,
  STRATEGY_FIELDS,
} from './strategy-genes.mjs';

export function defaultGenome() {
  return { tier1: defaultTier1(), strategy: defaultStrategyGenes() };
}

export function makeGenome({ tier1, strategy } = {}) {
  const t1 = tier1 ?? defaultTier1();
  validateTier1(t1);
  const strat = strategy ?? defaultStrategyGenes();
  validateStrategyGenes(strat);
  return { tier1: { ...t1 }, strategy: { ...strat } };
}

export function randomGenome(prng) {
  return makeGenome({
    tier1: randomTier1(prng),
    strategy: randomStrategyGenes(prng),
  });
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

  // Project strategy genes into layoutMetro options
  const strat = genome.strategy || {};
  out.strategies = {
    orderNodes: strat['strategy.orderNodes'] || 'none',
    reduceCrossings: strat['strategy.reduceCrossings'] || 'none',
    assignLanes: strat['strategy.assignLanes'] || 'default',
    positionX: strat['strategy.positionX'] || 'fixed',
    refineCoordinates: strat['strategy.refineCoordinates'] || 'none',
  };
  out.strategyConfig = {
    crossingPasses: Math.round(strat['strategy.crossingPasses'] ?? 24),
    refinementIterations: Math.round(strat['strategy.refinementIterations'] ?? 12),
    compactionIterations: Math.round(strat['strategy.refinementIterations'] ?? 12),
  };

  return out;
}
