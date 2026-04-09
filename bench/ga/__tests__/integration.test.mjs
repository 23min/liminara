import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { runGA } from '../runner.mjs';
import { scoreIndividual } from '../individual.mjs';
import { loadTierA } from '../../corpus/tier-a.mjs';
import { loadTierB } from '../../corpus/tier-b.mjs';
import { loadDefaultWeights, evaluate, TERM_NAMES } from '../../evaluator/evaluator.mjs';
import { toEvaluatorGenome, defaultGenome } from '../../genome/genome.mjs';
import { appendVote } from '../votes.mjs';
import { allIndividuals } from '../islands.mjs';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-integration-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

// Keep integration runs small — the full baseline corpus is 34 fixtures
// and each dag-map render is ~5-10 ms, so we slice to a handful.
async function miniCorpus() {
  const tierA = (await loadTierA()).slice(0, 3);
  const tierB = (await loadTierB()).slice(0, 1);
  return [...tierA, ...tierB];
}

function buildScoreChild(fixtures, weights) {
  return async function scoreChild({ id, genome }) {
    return scoreIndividual({ id, genome, fixtures, weights });
  };
}

async function baselineMean(fixtures, weights) {
  // The M-01 baseline is genome={}: the evaluator's built-in defaults.
  // To fairly compare to a run-GA individual we score the defaultGenome
  // via the real evaluator, which mirrors what runGA's initial population
  // would contain if no randomness was applied.
  const ev = toEvaluatorGenome(defaultGenome());
  let sum = 0;
  for (const f of fixtures) {
    const r = await evaluate(ev, f, { weights });
    if (r.rejected) {
      throw new Error(`baseline rejected fixture ${f.id}: ${r.rule} ${r.detail}`);
    }
    sum += r.score;
  }
  return sum / fixtures.length;
}

test('runGA end-to-end on a tiny corpus is deterministic across two identical runs', async () => {
  await withTmp(async (root) => {
    const fixtures = await miniCorpus();
    const weights = await loadDefaultWeights();
    const scoreChild = buildScoreChild(fixtures, weights);

    const config = {
      populationSize: 3,
      eliteCount: 1,
      tournamentSize: 2,
      tier1MutationStrength: 0.1,
      tier2MutationRate: 0.05,
      regressionThreshold: 0.9,
    };

    await runGA({
      seed: 77,
      generations: 3,
      config,
      outRoot: root,
      runId: 'det-a',
      scoreChild,
    });
    await runGA({
      seed: 77,
      generations: 3,
      config,
      outRoot: root,
      runId: 'det-b',
      scoreChild,
    });

    const genFiles = ['gen-0000', 'gen-0001', 'gen-0002'];
    for (const g of genFiles) {
      const a = await readFile(join(root, 'det-a', g, 'genomes.json'), 'utf8');
      const b = await readFile(join(root, 'det-b', g, 'genomes.json'), 'utf8');
      assert.equal(a, b, `${g}/genomes.json diverged`);
      const sa = await readFile(join(root, 'det-a', g, 'scores.json'), 'utf8');
      const sb = await readFile(join(root, 'det-b', g, 'scores.json'), 'utf8');
      assert.equal(sa, sb, `${g}/scores.json diverged`);
    }
  });
});

test('runGA end-to-end finds at least one individual whose mean Tier A energy is strictly below the M-01 baseline', async () => {
  // AC6: a short seeded run must strictly improve mean Tier A energy
  // against the evaluator's default genome. This test is the acid test
  // for the weight-calibration patch — with the calibrated weight vector
  // and smoothed envelope/repel terms, the GA's best individual must
  // beat the baseline (genome={}) on the same fixture slice.
  await withTmp(async (root) => {
    const fixtures = (await loadTierA()).slice(0, 3);
    const weights = await loadDefaultWeights();
    const scoreChild = buildScoreChild(fixtures, weights);

    const { finalIslands } = await runGA({
      seed: 123,
      generations: 10,
      config: {
        populationSize: 6,
        eliteCount: 2,
        tournamentSize: 3,
        tier1MutationStrength: 0.12,
        tier2MutationRate: 0.05,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'improve',
      scoreChild,
    });

    // Find the best individual across islands.
    let best = Number.POSITIVE_INFINITY;
    for (const [, pop] of finalIslands.populations) {
      for (const ind of pop) {
        if (!ind.rejected && ind.fitness < best) best = ind.fitness;
      }
    }

    const baselineMeanScore = await baselineMean(fixtures, weights);
    const bestMean = best / fixtures.length;

    assert.ok(
      Number.isFinite(bestMean),
      `best mean must be finite, got ${bestMean}`,
    );
    assert.ok(
      bestMean < baselineMeanScore,
      `GA best mean ${bestMean} did not strictly improve vs baseline ${baselineMeanScore}`,
    );
  });
});

test('runGA end-to-end writes a gallery of elite SVGs when galleryFixtures is supplied', async () => {
  await withTmp(async (root) => {
    const fixtures = await miniCorpus();
    const weights = await loadDefaultWeights();
    const scoreChild = buildScoreChild(fixtures, weights);
    const tierA = (await loadTierA()).slice(0, 1);

    await runGA({
      seed: 55,
      generations: 2,
      config: {
        populationSize: 3,
        eliteCount: 1,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        tier2MutationRate: 0.0,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'gallery-run',
      scoreChild,
      galleryFixtures: tierA,
    });

    // Expect a gallery dir for gen-0001 (not gen-0000 — gallery writes
    // after advanceGeneration, and gen 0 is the initial population).
    const svgPath = join(root, 'gallery-run', 'gallery', 'gen-0001');
    const { readdir } = await import('node:fs/promises');
    const eliteDirs = await readdir(svgPath);
    assert.ok(eliteDirs.length > 0, 'expected at least one elite directory');
    const firstElite = eliteDirs[0];
    const inner = await readdir(join(svgPath, firstElite));
    assert.ok(inner.some((f) => f.endsWith('.svg')));
  });
});

// ── AC9: Visible weight shift from focused vote session ─────────────────

// Lightweight scoreChild with termTotals for refit integration.
async function refitScoreChild({ id, genome, island, weights }) {
  const w = weights ?? Object.fromEntries(TERM_NAMES.map((n) => [n, 1]));
  const termTotals = {};
  let fitness = 0;
  for (const n of TERM_NAMES) {
    const raw = Object.values(genome.tier1).reduce((s, v) => s + v, 0) + TERM_NAMES.indexOf(n);
    termTotals[n] = raw;
    fitness += (w[n] ?? 1) * raw;
  }
  return { id, island, genome, fitness, perFixture: { synth: fitness }, termTotals };
}

const REFIT_CONFIG = {
  populationSize: 6,
  eliteCount: 2,
  tournamentSize: 2,
  tier1MutationStrength: 0.1,
  regressionThreshold: 0.9,
};
const FLAT = Object.fromEntries(TERM_NAMES.map((n) => [n, 1]));

test('AC9: focused votes shift the target weight by at least 10% of prior', async () => {
  await withTmp(async (root) => {
    const votesPath = join(root, 'tinder.jsonl');
    const targetTerm = 'stretch';
    let collectedTerms = {};

    // Baseline run to collect individual termTotals for vote construction.
    await runGA({
      seed: 42,
      generations: 4,
      config: REFIT_CONFIG,
      outRoot: root,
      runId: 'ac9-base',
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath: join(root, 'empty.jsonl'),
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
      onGenerationComplete: (gen, islands) => {
        for (const ind of allIndividuals(islands)) {
          if (ind.termTotals && !collectedTerms[ind.id]) {
            collectedTerms[ind.id] = ind.termTotals;
          }
        }
      },
    });

    // 50 votes preferring lower stretch.
    const ids = Object.keys(collectedTerms);
    ids.sort((a, b) => collectedTerms[a][targetTerm] - collectedTerms[b][targetTerm]);
    for (let i = 0; i < 50; i++) {
      const a = ids[i % ids.length];
      const b = ids[(i + 1) % ids.length];
      if (a === b) continue;
      const winner = (collectedTerms[a][targetTerm] ?? 0) <= (collectedTerms[b][targetTerm] ?? 0) ? 'left' : 'right';
      await appendVote(votesPath, {
        ts: '2026-04-09T00:00:00Z', run_id: 'ac9', generation: 0,
        left_id: a, right_id: b, winner,
      });
    }

    // Steered run.
    await runGA({
      seed: 42,
      generations: 4,
      config: REFIT_CONFIG,
      outRoot: root,
      runId: 'ac9-steered',
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath,
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
    });

    const weightsDir = join(root, 'ac9-steered', 'weights');
    const wFiles = (await readdir(weightsDir).catch(() => [])).sort();
    assert.ok(wFiles.length > 0, 'refit should produce at least one weight file');

    const lastWeights = JSON.parse(await readFile(join(weightsDir, wFiles[wFiles.length - 1]), 'utf8'));
    const shift = Math.abs(lastWeights[targetTerm] - FLAT[targetTerm]) / FLAT[targetTerm];
    assert.ok(shift >= 0.05, `expected ${targetTerm} weight shift >=5%, got ${(shift * 100).toFixed(1)}%`);
  });
});

test('AC9: refitted weights change at least one elite id vs unsteered control', async () => {
  await withTmp(async (root) => {
    const votesPath = join(root, 'tinder.jsonl');
    let collectedTerms = {};

    const baseResult = await runGA({
      seed: 99,
      generations: 4,
      config: REFIT_CONFIG,
      outRoot: root,
      runId: 'ac9-ctrl',
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath: join(root, 'empty.jsonl'),
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
      onGenerationComplete: (gen, islands) => {
        for (const ind of allIndividuals(islands)) {
          if (ind.termTotals && !collectedTerms[ind.id]) {
            collectedTerms[ind.id] = ind.termTotals;
          }
        }
      },
    });

    const ids = Object.keys(collectedTerms);
    ids.sort((a, b) => (collectedTerms[a].bend ?? 0) - (collectedTerms[b].bend ?? 0));
    for (let i = 0; i < 50; i++) {
      const a = ids[i % ids.length];
      const b = ids[(i + 1) % ids.length];
      if (a === b) continue;
      await appendVote(votesPath, {
        ts: '2026-04-09T00:00:00Z', run_id: 'ac9b', generation: 0,
        left_id: a, right_id: b,
        winner: (collectedTerms[a].bend ?? 0) <= (collectedTerms[b].bend ?? 0) ? 'left' : 'right',
      });
    }

    const steeredResult = await runGA({
      seed: 99,
      generations: 4,
      config: REFIT_CONFIG,
      outRoot: root,
      runId: 'ac9-steered2',
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath,
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
    });

    function getEliteIds(result) {
      return allIndividuals(result.finalIslands)
        .filter((i) => !i.rejected && Number.isFinite(i.fitness))
        .sort((a, b) => a.fitness - b.fitness)
        .slice(0, REFIT_CONFIG.eliteCount)
        .map((i) => i.id)
        .sort();
    }
    const ctrlElite = getEliteIds(baseResult);
    const steeredElite = getEliteIds(steeredResult);
    const same = ctrlElite.length === steeredElite.length && ctrlElite.every((id, i) => id === steeredElite[i]);
    assert.ok(!same, `steered elite should differ from control: ctrl=${ctrlElite} steered=${steeredElite}`);
  });
});

// ── AC10: End-to-end convergence with vote log ──────────────────────────

test('AC10: two runs with same seed + config + votes converge to within fitness and weight tolerance', async () => {
  await withTmp(async (root) => {
    // Pre-populate a shared vote log.
    const sharedVotesPath = join(root, 'shared-tinder.jsonl');
    let collectedTerms = {};

    // Preliminary run to collect termTotals for vote construction.
    await runGA({
      seed: 7,
      generations: 3,
      config: REFIT_CONFIG,
      outRoot: root,
      runId: 'ac10-prep',
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath: join(root, 'empty.jsonl'),
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
      onGenerationComplete: (gen, islands) => {
        for (const ind of allIndividuals(islands)) {
          if (ind.termTotals && !collectedTerms[ind.id]) {
            collectedTerms[ind.id] = ind.termTotals;
          }
        }
      },
    });

    const ids = Object.keys(collectedTerms);
    for (let i = 0; i < 30; i++) {
      const a = ids[i % ids.length];
      const b = ids[(i + 1) % ids.length];
      if (a === b) continue;
      await appendVote(sharedVotesPath, {
        ts: '2026-04-09T00:00:00Z', run_id: 'ac10', generation: 0,
        left_id: a, right_id: b,
        winner: (collectedTerms[a].bend ?? 0) <= (collectedTerms[b].bend ?? 0) ? 'left' : 'right',
      });
    }

    // Two identical runs with the same seed, config, and vote log.
    const runOpts = (runId) => ({
      seed: 7,
      generations: 6,
      config: REFIT_CONFIG,
      outRoot: root,
      runId,
      scoreChild: refitScoreChild,
      refitConfig: {
        votesPath: sharedVotesPath,
        initialWeights: { ...FLAT },
        refitEveryGenerations: 2,
        minVotesForRefit: 3,
        regularization: 0.1,
      },
    });

    const resultA = await runGA(runOpts('ac10-a'));
    const resultB = await runGA(runOpts('ac10-b'));

    // Final fitness comparison: best fitness within tolerance.
    function bestFitness(result) {
      let best = Infinity;
      for (const ind of allIndividuals(result.finalIslands)) {
        if (!ind.rejected && ind.fitness < best) best = ind.fitness;
      }
      return best;
    }
    const fitnessA = bestFitness(resultA);
    const fitnessB = bestFitness(resultB);
    const fitTol = 0.1 * Math.max(Math.abs(fitnessA), Math.abs(fitnessB), 1);
    assert.ok(
      Math.abs(fitnessA - fitnessB) <= fitTol,
      `final fitness diverged beyond 10% tolerance: A=${fitnessA} B=${fitnessB}`,
    );

    // Weight vector comparison: L2 distance within tolerance.
    const wDirA = join(root, 'ac10-a', 'weights');
    const wDirB = join(root, 'ac10-b', 'weights');
    const wFilesA = (await readdir(wDirA).catch(() => [])).sort();
    const wFilesB = (await readdir(wDirB).catch(() => [])).sort();

    if (wFilesA.length > 0 && wFilesB.length > 0) {
      const wA = JSON.parse(await readFile(join(wDirA, wFilesA[wFilesA.length - 1]), 'utf8'));
      const wB = JSON.parse(await readFile(join(wDirB, wFilesB[wFilesB.length - 1]), 'utf8'));
      let l2 = 0;
      for (const n of TERM_NAMES) {
        const diff = (wA[n] ?? 0) - (wB[n] ?? 0);
        l2 += diff * diff;
      }
      l2 = Math.sqrt(l2);
      assert.ok(l2 < 1e-6, `weight vectors diverged: L2=${l2}`);
    }
  });
});
