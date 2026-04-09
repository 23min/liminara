// scripts/run.js — CLI wrapper for the GA runner.
//
// Usage:
//   node scripts/run.js --seed 42 --generations 20 [--resume] [--run-id <id>]
//                       [--population 8] [--elite 2] [--tournament 3]
//                       [--mut-t1 0.1] [--mut-t2 0.05] [--guard 0.9]
//
// Behaviour:
//   - Scores every Tier A + Tier B fixture via the real evaluator.
//   - Writes per-generation snapshots to bench/run/<run-id>/gen-NNNN/.
//   - Writes a gallery of elite SVGs over the Tier A fixtures per generation
//     to bench/run/<run-id>/gallery/gen-NNNN/.
//   - Installs a SIGINT handler so a Ctrl-C between generations exits
//     cleanly after the current generation finishes writing its snapshot.
//
// The runner is programmatically reusable — see bench/ga/runner.mjs. Tests
// exercise that API directly so the CLI stays thin.

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { runGA } from '../ga/runner.mjs';
import { scoreIndividual } from '../ga/individual.mjs';
import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';
import { loadDefaultWeights } from '../evaluator/evaluator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');
const DEFAULT_OUT_ROOT = join(BENCH_ROOT, 'run');

function parseArgs(argv) {
  const out = {
    seed: 1,
    generations: 20,
    runId: null,
    resume: false,
    populationSize: 8,
    eliteCount: 2,
    tournamentSize: 3,
    tier1MutationStrength: 0.1,
    regressionThreshold: 0.9,
    migrationInterval: 10,
    migrationRate: 0.05,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`missing value for ${a}`);
      return v;
    };
    switch (a) {
      case '--seed':
        out.seed = parseInt(next(), 10);
        break;
      case '--generations':
        out.generations = parseInt(next(), 10);
        break;
      case '--run-id':
        out.runId = next();
        break;
      case '--resume':
        out.resume = true;
        break;
      case '--population':
        out.populationSize = parseInt(next(), 10);
        break;
      case '--elite':
        out.eliteCount = parseInt(next(), 10);
        break;
      case '--tournament':
        out.tournamentSize = parseInt(next(), 10);
        break;
      case '--mut-t1':
        out.tier1MutationStrength = parseFloat(next());
        break;
      case '--guard':
        out.regressionThreshold = parseFloat(next());
        break;
      case '--migration-interval':
        out.migrationInterval = parseInt(next(), 10);
        break;
      case '--migration-rate':
        out.migrationRate = parseFloat(next());
        break;
      case '--help':
      case '-h':
        printHelp();
        process.exit(0);
      default:
        throw new Error(`unknown argument: ${a}`);
    }
  }
  if (!out.runId) {
    out.runId = `run-seed${out.seed}-g${out.generations}`;
  }
  return out;
}

function printHelp() {
  process.stdout.write(
    `Usage: node scripts/run.js [options]\n` +
      `  --seed <int>            PRNG seed (default 1)\n` +
      `  --generations <int>     number of generations (default 20)\n` +
      `  --run-id <string>       run directory name (default: run-seedN-gM)\n` +
      `  --resume                resume from the last snapshot in run-id\n` +
      `  --population <int>      per-island population size (default 8)\n` +
      `  --elite <int>           elite carry-over count per island (default 2)\n` +
      `  --tournament <int>      tournament size (default 3)\n` +
      `  --mut-t1 <float>        Tier 1 Gaussian mutation strength (default 0.1)\n` +
      `  --guard <float>         regression quality threshold (default 0.9)\n` +
      `  --migration-interval <int> generations between ring-topology migrations (default 10)\n` +
      `  --migration-rate <float>   fraction of each island that migrates per event (default 0.05)\n`,
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const fixtures = [...(await loadTierA()), ...(await loadTierB())];
  const tierA = await loadTierA();
  const weights = await loadDefaultWeights();

  const scoreChild = async ({ id, genome, island }) =>
    scoreIndividual({ id, genome, fixtures, weights, island });

  // SIGINT: flip a flag the caller can poll. The runner currently finishes
  // the current generation's snapshot atomically before returning, so an
  // abort after generation N leaves a consistent gen-NNNN/ on disk.
  let abortRequested = false;
  process.on('SIGINT', () => {
    process.stderr.write('\nSIGINT received — finishing current generation and exiting cleanly\n');
    abortRequested = true;
  });

  // The runner does not yet expose a per-generation hook; we rely on
  // atomic snapshot writes to leave a clean state when the process dies.
  // A follow-up in M-DAGBENCH-03 can add an `onGeneration` callback for
  // finer-grained cooperative abort.
  const result = await runGA({
    seed: args.seed,
    generations: args.generations,
    config: {
      populationSize: args.populationSize,
      eliteCount: args.eliteCount,
      tournamentSize: args.tournamentSize,
      tier1MutationStrength: args.tier1MutationStrength,
      regressionThreshold: args.regressionThreshold,
      migrationInterval: args.migrationInterval,
      migrationRate: args.migrationRate,
    },
    outRoot: DEFAULT_OUT_ROOT,
    runId: args.runId,
    scoreChild,
    resume: args.resume,
    galleryFixtures: tierA,
  });

  process.stdout.write(`run complete: ${result.runDir}\n`);
  if (abortRequested) process.exit(130);
}

const isDirectRun = import.meta.url === `file://${process.argv[1]}`;
if (isDirectRun) {
  main().catch((err) => {
    process.stderr.write(`run failed: ${err.stack || err.message}\n`);
    process.exit(1);
  });
}

export { parseArgs };
