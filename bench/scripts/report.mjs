#!/usr/bin/env node
// report.mjs — generates a comparison report scoring dag-map, dagre, and ELK
// against the energy functional. Produces report.md, report.json, and an
// optional SVG gallery.

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { dagMap } from '../../dag-map/src/index.js';
import { layoutWithDagMap } from '../adapters/dagmap.mjs';
import { layoutWithDagre } from '../adapters/dagre.mjs';
import { layoutWithELK } from '../adapters/elk.mjs';

import { E_stretch } from '../energy/stretch.mjs';
import { E_bend } from '../energy/bend.mjs';
import { E_crossings } from '../energy/crossings.mjs';
import { E_monotone } from '../energy/monotone.mjs';
import { E_envelope } from '../energy/envelope.mjs';
import { E_channel } from '../energy/channel.mjs';
import { E_repel_nn } from '../energy/repel_nn.mjs';
import { E_repel_ne } from '../energy/repel_ne.mjs';

const TERM_NAMES = ['stretch', 'bend', 'crossings', 'monotone', 'envelope', 'channel', 'repel_nn', 'repel_ne'];

const TERM_FNS = {
  stretch: E_stretch,
  bend: E_bend,
  crossings: E_crossings,
  monotone: E_monotone,
  envelope: E_envelope,
  channel: E_channel,
  repel_nn: E_repel_nn,
  repel_ne: E_repel_ne,
};

const DEFAULT_ENERGY_CFG = {
  stretch_ideal_factor: 1.0,
  repel_threshold_px: 40,
  channel_min_separation_px: 20,
  envelope_target_ratio: 2.0,
  layer_spacing: 75, // 50 * 1.5 default scale
};

function scoreLayout(layout, weights, cfg = DEFAULT_ENERGY_CFG) {
  if (layout.error || layout.nodes.length === 0) {
    return { score: Infinity, terms: null, error: layout.error || 'empty layout' };
  }

  const terms = {};
  let score = 0;
  for (const name of TERM_NAMES) {
    const val = TERM_FNS[name](layout, cfg);
    terms[name] = val;
    score += (weights[name] ?? 0) * val;
  }

  return { score, terms };
}

async function scoreFixture(fixture, weights, genome) {
  const engines = {};

  // dag-map (synchronous)
  const dmLayout = layoutWithDagMap(fixture, genome);
  engines['dag-map'] = scoreLayout(dmLayout, weights);

  // dagre (synchronous)
  const dagreLayout = layoutWithDagre(fixture);
  engines['dagre'] = scoreLayout(dagreLayout, weights);

  // ELK (async)
  const elkLayout = await layoutWithELK(fixture);
  engines['elk'] = scoreLayout(elkLayout, weights);

  return engines;
}

function computeSummary(fixtureResults) {
  const comparisons = {};
  for (const rival of ['dagre', 'elk']) {
    let wins = 0, losses = 0, ties = 0;
    for (const entry of fixtureResults) {
      const dm = entry.engines['dag-map'];
      const other = entry.engines[rival];
      if (dm.error && other.error) { ties++; continue; }
      if (dm.error) { losses++; continue; }
      if (other.error) { wins++; continue; }
      if (dm.score < other.score) wins++;
      else if (dm.score > other.score) losses++;
      else ties++;
    }
    comparisons[`dag-map_vs_${rival}`] = { wins, losses, ties };
  }
  return comparisons;
}

function findLosses(fixtureResults) {
  const losses = [];
  for (const entry of fixtureResults) {
    const dm = entry.engines['dag-map'];
    for (const rival of ['dagre', 'elk']) {
      const other = entry.engines[rival];
      if (dm.error && !other.error) {
        losses.push({ fixture: entry.id, vs: rival, reason: `dag-map error: ${dm.error}` });
      } else if (!dm.error && !other.error && dm.score > other.score) {
        losses.push({ fixture: entry.id, vs: rival, dagMapScore: dm.score, rivalScore: other.score });
      }
    }
  }
  return losses;
}

function renderMarkdown(data) {
  const lines = [];
  lines.push('# Benchmark Report');
  lines.push('');
  lines.push(`**Run ID:** ${data.meta.runId}`);
  lines.push(`**Date:** ${data.meta.date}`);
  lines.push(`**Fixtures:** ${data.fixtures.length}`);
  lines.push('');

  // Elite info (honesty)
  if (data.meta.elite) {
    lines.push('## Evolved Elite');
    lines.push('');
    lines.push(`- **Individual:** ${data.meta.elite.individualId}`);
    lines.push(`- **Generation:** ${data.meta.elite.generation}`);
    lines.push(`- **Fitness:** ${data.meta.elite.fitness.toFixed(4)}`);
    lines.push('');
    lines.push('**Genome:**');
    lines.push('');
    lines.push('| Parameter | Value |');
    lines.push('|-----------|-------|');
    if (data.meta.elite.genome?.tier1) {
      for (const [k, v] of Object.entries(data.meta.elite.genome.tier1)) {
        lines.push(`| ${k} | ${typeof v === 'number' ? v.toFixed(4) : v} |`);
      }
    }
    lines.push('');
  } else {
    lines.push('## dag-map Parameters');
    lines.push('');
    lines.push('Using **default** parameters (no evolved elite specified).');
    lines.push('');
  }

  // Weight Vector (honesty)
  lines.push('## Weight Vector');
  lines.push('');
  lines.push('| Term | Weight |');
  lines.push('|------|--------|');
  for (const name of TERM_NAMES) {
    lines.push(`| ${name} | ${data.meta.weights[name] ?? 0} |`);
  }
  lines.push('');

  // Summary
  lines.push('## Summary');
  lines.push('');
  lines.push('| Matchup | Wins | Losses | Ties |');
  lines.push('|---------|------|--------|------|');
  for (const [key, val] of Object.entries(data.summary)) {
    lines.push(`| ${key} | ${val.wins} | ${val.losses} | ${val.ties} |`);
  }
  lines.push('');

  // Loss fixtures (honesty — listed explicitly)
  lines.push('## Fixtures Where dag-map Loses');
  lines.push('');
  if (data.losses.length === 0) {
    lines.push('dag-map does not lose on any fixture in this run.');
  } else {
    lines.push('| Fixture | vs | dag-map Score | Rival Score |');
    lines.push('|---------|-----|---------------|-------------|');
    for (const l of data.losses) {
      if (l.reason) {
        lines.push(`| ${l.fixture} | ${l.vs} | ${l.reason} | — |`);
      } else {
        lines.push(`| ${l.fixture} | ${l.vs} | ${l.dagMapScore.toFixed(4)} | ${l.rivalScore.toFixed(4)} |`);
      }
    }
  }
  lines.push('');

  // Per-fixture breakdown
  lines.push('## Per-Fixture Scores');
  lines.push('');
  lines.push('| Fixture | dag-map | dagre | ELK | Winner |');
  lines.push('|---------|---------|-------|-----|--------|');
  for (const entry of data.fixtures) {
    const scores = {};
    for (const [eng, res] of Object.entries(entry.engines)) {
      scores[eng] = res.error ? 'ERR' : res.score.toFixed(4);
    }
    const validScores = Object.entries(entry.engines)
      .filter(([, r]) => !r.error)
      .map(([eng, r]) => [eng, r.score]);
    const winner = validScores.length > 0
      ? validScores.reduce((a, b) => (a[1] <= b[1] ? a : b))[0]
      : '—';
    lines.push(`| ${entry.id} | ${scores['dag-map']} | ${scores['dagre']} | ${scores['elk']} | ${winner} |`);
  }
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate a comparison report.
 * @param {Object} opts
 * @param {Array} opts.fixtures - fixture list
 * @param {Object} opts.weights - energy term weights
 * @param {string} opts.outDir - output directory
 * @param {string} opts.runId - run identifier
 * @param {Object} [opts.genome] - dag-map genome overrides
 * @param {boolean} [opts.skipGallery] - skip SVG gallery generation
 */
export async function generateReport({ fixtures, weights, outDir, runId, genome, eliteInfo, skipGallery }) {
  await mkdir(outDir, { recursive: true });

  const fixtureResults = [];
  for (const f of fixtures) {
    const engines = await scoreFixture(f, weights, genome);
    fixtureResults.push({ id: f.id, engines });
  }

  const summary = computeSummary(fixtureResults);
  const losses = findLosses(fixtureResults);

  const data = {
    meta: {
      runId,
      date: new Date().toISOString().slice(0, 10),
      weights,
      fixtureCount: fixtures.length,
      elite: eliteInfo ? {
        individualId: eliteInfo.individualId,
        generation: eliteInfo.genIndex,
        fitness: eliteInfo.fitness,
        genome: eliteInfo.genome,
      } : null,
    },
    summary,
    losses,
    fixtures: fixtureResults,
  };

  // Write JSON
  await writeFile(join(outDir, 'report.json'), JSON.stringify(data, null, 2), 'utf8');

  // Write Markdown
  const md = renderMarkdown(data);
  await writeFile(join(outDir, 'report.md'), md, 'utf8');

  // Gallery — render dag-map SVGs for each fixture (dagre/ELK produce
  // coordinates only, not renderable SVGs, so gallery is dag-map only)
  if (!skipGallery) {
    const galleryDir = join(outDir, 'gallery');
    await mkdir(galleryDir, { recursive: true });
    for (const f of fixtures) {
      try {
        const opts = { ...(f.opts ?? {}), ...(genome?.render ?? {}) };
        if (f.theme) opts.theme = f.theme;
        if (Array.isArray(f.routes) && f.routes.length > 0) opts.routes = f.routes;
        const { svg } = dagMap(f.dag, opts);
        const safeName = f.id.replace(/\//g, '__');
        await writeFile(join(galleryDir, `${safeName}.svg`), svg, 'utf8');
      } catch (_) { /* skip render failures */ }
    }
  }

  return data;
}
