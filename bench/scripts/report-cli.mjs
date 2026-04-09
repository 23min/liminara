#!/usr/bin/env node
// report-cli.mjs — CLI entry point for generating the benchmark comparison
// report. Loads Tier A, Tier B, and (optionally) Tier C fixtures, then
// scores all three engines and writes the report.
//
// Usage:
//   node scripts/report-cli.mjs [--elite <run-dir>] [--run-id <id>] [--skip-tier-c]
//
// --elite <run-dir>  Use the best genome from a GA run's latest generation
//                    snapshot (e.g. bench/run/run-seed42-g50). Without this
//                    flag, dag-map is scored with default parameters.

import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';

import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';
import { loadDefaultWeights } from '../evaluator/evaluator.mjs';
import { toEvaluatorGenome } from '../genome/genome.mjs';
import { generateReport } from './report.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RUN_DIR = join(__dirname, '..', 'run', 'report');
const TIER_C_DIR = join(__dirname, '..', 'corpora', 'tier-c');

/**
 * Load the best genome from the latest generation snapshot in a GA run directory.
 * Returns { genome, genIndex, individualId } or null.
 */
export async function loadEliteFromRun(runDir) {
  const entries = await readdir(runDir);
  const genDirs = entries
    .filter((e) => e.startsWith('gen-'))
    .sort();

  if (genDirs.length === 0) return null;

  const latestGen = genDirs[genDirs.length - 1];
  const genDir = join(runDir, latestGen);

  const genomes = JSON.parse(await readFile(join(genDir, 'genomes.json'), 'utf8'));
  const scores = JSON.parse(await readFile(join(genDir, 'scores.json'), 'utf8'));

  // Find the individual with the lowest fitness (best score)
  const validIndividuals = scores.individuals.filter((i) => !i.rejected);
  if (validIndividuals.length === 0) return null;

  validIndividuals.sort((a, b) => a.fitness - b.fitness);
  const bestId = validIndividuals[0].id;
  const bestGenome = genomes.find((g) => g.id === bestId);

  if (!bestGenome) return null;

  return {
    genome: bestGenome.genome,
    genIndex: parseInt(latestGen.replace('gen-', ''), 10),
    individualId: bestId,
    fitness: validIndividuals[0].fitness,
  };
}

function parseArgs(argv) {
  const out = { eliteDir: null, runId: null, skipTierC: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--elite':
        out.eliteDir = argv[++i];
        break;
      case '--run-id':
        out.runId = argv[++i];
        break;
      case '--skip-tier-c':
        out.skipTierC = true;
        break;
    }
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outDir = join(RUN_DIR, timestamp);
  const runId = args.runId ?? `report-${timestamp}`;

  // Load elite genome if specified
  let genome = null;
  let eliteInfo = null;
  if (args.eliteDir) {
    console.log(`Loading elite from ${args.eliteDir}...`);
    eliteInfo = await loadEliteFromRun(args.eliteDir);
    if (!eliteInfo) {
      console.error('No valid elite found in the specified run directory.');
      process.exit(1);
    }
    genome = toEvaluatorGenome(eliteInfo.genome);
    console.log(`  Elite: ${eliteInfo.individualId} (gen ${eliteInfo.genIndex}, fitness ${eliteInfo.fitness.toFixed(4)})`);
  } else {
    console.log('No --elite specified — using dag-map default parameters.');
  }

  // Load fixtures
  console.log('Loading fixtures...');
  const tierA = await loadTierA();
  const tierB = await loadTierB();
  let tierC = [];

  if (!args.skipTierC) {
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
    genome,
    eliteInfo,
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

const isDirectRun = process.argv[1] && (
  process.argv[1].endsWith('report-cli.mjs') ||
  process.argv[1].endsWith('report-cli.js')
);
if (isDirectRun) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
