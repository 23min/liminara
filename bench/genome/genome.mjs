// genome.mjs — Tier 1 genome + strategy genes with round-trip serialization
// and a projection helper for the evaluator.
//
// Stripped to layout-affecting parameters only. Scale, layerSpacing, and
// energy-tuning params are fixed consumer constraints, not evolvable.

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
  // Fixed consumer constraints (not evolvable)
  const out = {
    render: {
      scale: 1.5,
      layerSpacing: 50,
      mainSpacing: genome.tier1['render.mainSpacing'] ?? 40,
      subSpacing: genome.tier1['render.subSpacing'] ?? 25,
    },
    energy: {
      stretch_ideal_factor: 1.0,
      repel_threshold_px: 40,
      channel_min_separation_px: 20,
      envelope_target_ratio: 2.0,
    },
  };

  // Project strategy genes into layoutMetro options
  const strat = genome.strategy || {};
  out.strategies = {
    orderNodes: strat['strategy.orderNodes'] || 'none',
    reduceCrossings: strat['strategy.reduceCrossings'] || 'none',
    assignLanes: strat['strategy.assignLanes'] || 'default',
    refineCoordinates: strat['strategy.refineCoordinates'] || 'none',
  };
  out.strategyConfig = {
    crossingPasses: Math.round(strat['strategy.crossingPasses'] ?? 24),
    refinementIterations: Math.round(strat['strategy.refinementIterations'] ?? 12),
    spectralBlend: strat['strategy.spectralBlend'] ?? 0.5,
    shuffleSeed: Math.round(strat['strategy.shuffleSeed'] ?? 42),
  };

  return out;
}
