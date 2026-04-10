// evaluator.mjs — single-individual evaluator.
//
//   evaluate(genome, fixture, { weights? }) ->
//     { rejected: true, rule, detail }
//     | { score, terms: { stretch, bend, crossings, monotone, envelope,
//                         channel, repel_nn, repel_ne } }
//
// The evaluator is deterministic for fixed (genome, fixture, weights). It
// never reads Math.random and never touches the clock. All randomness in
// the GA lives outside this function — the evaluator is a pure scoring
// surface.

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { layoutMetro } from '../../dag-map/src/layout-metro.js';

import { E_stretch } from '../energy/stretch.mjs';
import { E_bend } from '../energy/bend.mjs';
import { E_crossings } from '../energy/crossings.mjs';
import { E_monotone } from '../energy/monotone.mjs';
import { E_envelope } from '../energy/envelope.mjs';
import { E_channel } from '../energy/channel.mjs';
import { E_repel_nn } from '../energy/repel_nn.mjs';
import { E_repel_ne } from '../energy/repel_ne.mjs';
import { E_overlap } from '../energy/overlap.mjs';
import { E_direction_changes } from '../energy/direction_changes.mjs';
import { E_polyline_crossings } from '../energy/polyline_crossings.mjs';

import { checkInvariants } from '../invariants/checker.mjs';
import { projectLayout } from './adapter.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_WEIGHTS_PATH = join(__dirname, '..', 'config', 'default-weights.json');

let cachedDefaultWeights = null;
export async function loadDefaultWeights() {
  if (cachedDefaultWeights) return cachedDefaultWeights;
  const raw = await readFile(DEFAULT_WEIGHTS_PATH, 'utf8');
  cachedDefaultWeights = JSON.parse(raw);
  return cachedDefaultWeights;
}

export const TERM_NAMES = [
  'stretch',
  'bend',
  'crossings',
  'monotone',
  'envelope',
  'channel',
  'repel_nn',
  'overlap',
  'direction_changes',
  'polyline_crossings',
  'repel_ne',
];

const DEFAULT_ENERGY_CFG = {
  stretch_ideal_factor: 1.0,
  repel_threshold_px: 40,
  channel_min_separation_px: 20,
  envelope_target_ratio: 2.0,
};

// Routing is locked to bezier for the bench's current scope. Tier 2 was
// removed from the genome on 2026-04-08 (sensitivity-cleanup chore); if
// the bench ever re-introduces multiple routing primitives, this becomes
// a genome field again.
const DEFAULT_RENDER = {
  routing: 'bezier',
  scale: 1.5,
  layerSpacing: 50,
};

function buildRenderOpts(genome, fixture) {
  const render = { ...DEFAULT_RENDER, ...(fixture.opts ?? {}), ...(genome.render ?? {}) };
  if (fixture.theme !== undefined) render.theme = fixture.theme;
  if (Array.isArray(fixture.routes) && fixture.routes.length > 0) {
    render.routes = fixture.routes;
  }
  // Pass strategy selections to layoutMetro
  if (genome.strategies) {
    render.strategies = genome.strategies;
  }
  if (genome.strategyConfig) {
    render.strategyConfig = genome.strategyConfig;
  }
  return render;
}

function buildEnergyCfg(genome, render) {
  const effectiveLayerSpacing = (render.layerSpacing ?? 50) * (render.scale ?? 1.5);
  return {
    ...DEFAULT_ENERGY_CFG,
    layer_spacing: effectiveLayerSpacing,
    ...(genome.energy ?? {}),
  };
}

export async function evaluate(genome, fixture, { weights } = {}) {
  const w = weights ?? (await loadDefaultWeights());
  const render = buildRenderOpts(genome, fixture);

  let raw;
  try {
    raw = layoutMetro(fixture.dag, render);
  } catch (err) {
    return { rejected: true, rule: 'render-failed', detail: err.message };
  }

  let layout;
  try {
    layout = projectLayout(fixture.dag, raw);
  } catch (err) {
    return { rejected: true, rule: 'adapter-failed', detail: err.message };
  }

  const rej = checkInvariants(layout);
  if (rej) return rej;

  const cfg = buildEnergyCfg(genome, render);

  const terms = {
    stretch: E_stretch(layout, cfg),
    bend: E_bend(layout, cfg),
    crossings: E_crossings(layout, cfg),
    monotone: E_monotone(layout, cfg),
    envelope: E_envelope(layout, cfg),
    channel: E_channel(layout, cfg),
    repel_nn: E_repel_nn(layout, cfg),
    repel_ne: E_repel_ne(layout, cfg),
    overlap: E_overlap(layout, cfg),
    direction_changes: E_direction_changes(layout, cfg),
    polyline_crossings: E_polyline_crossings(layout, cfg),
  };

  let score = 0;
  for (const name of TERM_NAMES) {
    const weight = w[name] ?? 0;
    score += weight * terms[name];
  }

  return { score, terms };
}
