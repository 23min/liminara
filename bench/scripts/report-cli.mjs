#!/usr/bin/env node
// report-cli.mjs — CLI entry point for generating the benchmark comparison
// report. Loads Tier A, Tier B, and (optionally) Tier C fixtures, then
// scores all three engines and writes the report.

import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';

import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';
import { loadDefaultWeights } from '../evaluator/evaluator.mjs';
import { generateReport } from './report.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RUN_DIR = join(__dirname, '..', 'run', 'report');
const TIER_C_DIR = join(__dirname, '..', 'corpora', 'tier-c');

async function main() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outDir = join(RUN_DIR, timestamp);

  const runId = process.argv.find((a) => a.startsWith('--run-id='))?.split('=')[1] ?? `report-${timestamp}`;
  const skipTierC = process.argv.includes('--skip-tier-c');

  console.log('Loading fixtures...');
  const tierA = await loadTierA();
  const tierB = await loadTierB();
  let tierC = [];

  if (!skipTierC) {
    const northDir = join(TIER_C_DIR, 'north');
    const randomDir = join(TIER_C_DIR, 'random-dag');
    if (existsSync(northDir) && existsSync(randomDir)) {
      const { loadTierC } = await import('../corpus/tier-c.mjs');
      const skipped = [];
      tierC = await loadTierC({
        onSkip: (id, reason) => skipped.push({ id, reason }),
      });
      if (skipped.length > 0) {
        console.log(`Skipped ${skipped.length} non-DAG graphs from Tier C`);
      }
    } else {
      console.log('Tier C corpora not found — run "make fetch-corpora" first. Continuing with Tier A + B only.');
    }
  }

  const fixtures = [...tierA, ...tierB, ...tierC];
  console.log(`Loaded ${fixtures.length} fixtures (A: ${tierA.length}, B: ${tierB.length}, C: ${tierC.length})`);

  const weights = await loadDefaultWeights();

  console.log('Scoring fixtures across dag-map, dagre, and ELK...');
  const data = await generateReport({
    fixtures,
    weights,
    outDir,
    runId,
    skipGallery: false,
  });

  console.log(`\nReport written to ${outDir}/`);
  console.log(`  report.md — human-readable comparison`);
  console.log(`  report.json — raw numbers`);

  // Print summary
  for (const [key, val] of Object.entries(data.summary)) {
    console.log(`  ${key}: ${val.wins}W / ${val.losses}L / ${val.ties}T`);
  }

  if (data.losses.length > 0) {
    console.log(`\n⚠ dag-map loses on ${data.losses.length} fixture/engine pairs. See report for details.`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
