// scripts/baseline.js — reference-floor scorer.
//
// Runs the evaluator across every Tier A and Tier B fixture with the current
// dag-map defaults (genome = {}, which falls back to the defaults baked into
// the evaluator) and writes the per-fixture totals and per-term breakdowns
// to `run/baseline/<timestamp>/scores.json`.
//
// CLI usage:
//     node scripts/baseline.js
//
// Programmatic usage (used by the test suite):
//     import { runBaseline } from './scripts/baseline.js';
//     await runBaseline({ outRoot, now });

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';
import { evaluate, loadDefaultWeights } from '../evaluator/evaluator.mjs';
import { route_fidelity } from '../diagnostics/route_fidelity.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');
const DEFAULT_OUT_ROOT = join(BENCH_ROOT, 'run', 'baseline');

function stamp(now) {
  // ISO-8601 with ":" replaced by "-" to keep it shell/filesystem friendly.
  const iso = now.toISOString();
  return iso.replace(/[:.]/g, '-');
}

export async function runBaseline({ outRoot = DEFAULT_OUT_ROOT, now = new Date() } = {}) {
  const weights = await loadDefaultWeights();

  const tierA = await loadTierA();
  const tierB = await loadTierB();

  const fixtures = [];
  const fidelity = [];
  for (const f of tierA) {
    const result = await evaluate({}, f, { weights });
    fixtures.push({ tier: 'A', id: f.id, result });
    const diag = await route_fidelity({}, f);
    fidelity.push({ tier: 'A', id: f.id, ...diag });
  }
  for (const f of tierB) {
    const result = await evaluate({}, f, { weights });
    fixtures.push({ tier: 'B', id: f.id, result });
    const diag = await route_fidelity({}, f);
    fidelity.push({ tier: 'B', id: f.id, ...diag });
  }

  const timestamp = now.toISOString();
  const outDir = join(outRoot, stamp(now));
  await mkdir(outDir, { recursive: true });
  const outPath = join(outDir, 'scores.json');
  const fidelityPath = join(outDir, 'route-fidelity.json');

  const payload = {
    timestamp,
    weights,
    fixtures,
  };
  const fidelityPayload = {
    timestamp,
    fixtures: fidelity,
  };
  // Sort-stable JSON so byte-level rerun comparisons only differ in the
  // timestamp field.
  await writeFile(outPath, JSON.stringify(payload, null, 2) + '\n', 'utf8');
  await writeFile(fidelityPath, JSON.stringify(fidelityPayload, null, 2) + '\n', 'utf8');

  return { outPath, fidelityPath, payload, fidelityPayload };
}

// When invoked directly as a CLI, run with defaults and print the output path.
const isDirectRun = import.meta.url === `file://${process.argv[1]}`;
if (isDirectRun) {
  runBaseline()
    .then(({ outPath, payload }) => {
      const count = payload.fixtures.length;
      process.stdout.write(`baseline: scored ${count} fixtures -> ${outPath}\n`);
    })
    .catch((err) => {
      process.stderr.write(`baseline failed: ${err.stack || err.message}\n`);
      process.exit(1);
    });
}
