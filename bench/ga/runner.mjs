// runner.mjs — headless GA runner.
//
// Design contracts:
//   - Determinism: each generation uses a PRNG forked from (seed, genIndex)
//     so two runs with the same seed produce byte-identical snapshots
//     regardless of earlier state. Resume inherits the same property.
//   - Atomic writes: every snapshot file is written to `.tmp` and renamed.
//     A crash mid-write leaves the previous snapshot intact.
//   - scoreChild is injected: tests stub it; production wires in the
//     real dag-map evaluator.

import { mkdir, writeFile, readFile, readdir, rename } from 'node:fs/promises';
import { join } from 'node:path';

import { createPrng } from './prng.mjs';
import {
  createIslands,
  placeIndividual,
  allIndividuals,
  DEFAULT_POPULATION_KEYS,
} from './islands.mjs';
import { advanceGeneration, selectEliteWithGuard } from './generation.mjs';
import { randomGenome, makeGenome } from '../genome/genome.mjs';
import {
  createBestEver,
  updateBestEver,
  loadBestEver,
  saveBestEver,
} from '../regression/guard.mjs';
import { writeGallery } from './gallery.mjs';
import { shouldMigrate, migrateRing } from './migration.mjs';
import { isKilled, injectProtectedInto } from './control.mjs';
import { refitWeights } from './refit.mjs';
import { readVotes } from './votes.mjs';

const GEN_PREFIX = 'gen-';

function genDirName(index) {
  return `${GEN_PREFIX}${String(index).padStart(4, '0')}`;
}

async function atomicWriteJSON(path, data) {
  const tmp = `${path}.tmp`;
  await writeFile(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
  await rename(tmp, path);
}

async function listGenerations(runDir) {
  let entries;
  try {
    entries = await readdir(runDir);
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  return entries
    .filter((e) => e.startsWith(GEN_PREFIX))
    .map((e) => parseInt(e.slice(GEN_PREFIX.length), 10))
    .filter((n) => Number.isInteger(n))
    .sort((a, b) => a - b);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function awaitUnpause(controlState) {
  while (controlState && controlState.paused) {
    await sleep(20);
  }
}

async function writeSnapshot(runDir, genIndex, islands, rejectedLog, weightsFile = null) {
  const dir = join(runDir, genDirName(genIndex));
  await mkdir(dir, { recursive: true });

  const all = allIndividuals(islands);
  // Sort by id for byte-stable output.
  all.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const genomes = all.map((i) => ({
    id: i.id,
    island: i.island,
    genome: i.genome,
  }));
  const scores = {
    fitnesses: all.map((i) => i.fitness),
    individuals: all.map((i) => ({
      id: i.id,
      island: i.island,
      fitness: i.fitness,
      perFixture: i.perFixture ?? {},
      rejected: i.rejected === true || undefined,
    })),
  };
  if (weightsFile !== null) {
    scores.weightsFile = weightsFile;
  }
  const elitePerIsland = {};
  for (const [islandKey, pop] of islands.populations) {
    const sorted = pop.slice().sort((a, b) => a.fitness - b.fitness);
    elitePerIsland[islandKey] = sorted.slice(0, Math.min(2, sorted.length)).map((i) => i.id);
  }
  const elite = { perIsland: elitePerIsland, rejectedByGuard: rejectedLog };

  await atomicWriteJSON(join(dir, 'genomes.json'), genomes);
  await atomicWriteJSON(join(dir, 'scores.json'), scores);
  await atomicWriteJSON(join(dir, 'elite.json'), elite);
}

async function readSnapshot(runDir, genIndex) {
  const dir = join(runDir, genDirName(genIndex));
  const genomes = JSON.parse(await readFile(join(dir, 'genomes.json'), 'utf8'));
  const scores = JSON.parse(await readFile(join(dir, 'scores.json'), 'utf8'));
  const byId = new Map(scores.individuals.map((i) => [i.id, i]));

  // Reconstruct the island set from the actual keys in the snapshot so
  // resume works with custom population layouts, not just DEFAULT_POPULATION_KEYS.
  const keys = [...new Set(genomes.map((g) => g.island))];
  const islands = createIslands(keys);
  for (const g of genomes) {
    const s = byId.get(g.id) ?? {};
    const individual = {
      id: g.id,
      island: g.island,
      genome: makeGenome(g.genome),
      fitness: s.fitness ?? Number.POSITIVE_INFINITY,
      perFixture: s.perFixture ?? {},
    };
    if (s.rejected) individual.rejected = true;
    placeIndividual(islands, individual);
  }
  return islands;
}

function genPrng(seed, genIndex) {
  return createPrng(seed).fork(`gen-${genIndex}`);
}

async function initializePopulation({ seed, config, scoreChild }) {
  const populationKeys = config.populationKeys ?? DEFAULT_POPULATION_KEYS;
  const islands = createIslands(populationKeys);
  const initPrng = createPrng(seed).fork('init');
  let counter = 0;
  for (const islandKey of populationKeys) {
    for (let i = 0; i < config.populationSize; i++) {
      const g = randomGenome(initPrng);
      // Apply pinned strategies for this island
      if (config.pinnedStrategies && config.pinnedStrategies[islandKey]) {
        const pins = config.pinnedStrategies[islandKey];
        for (const [gene, value] of Object.entries(pins)) {
          g.strategy[gene] = value;
        }
      }
      const id = `g0-${islandKey}-${counter++}`;
      const scored = await scoreChild({ id, genome: g, island: islandKey });
      if (scored.island === undefined) scored.island = islandKey;
      placeIndividual(islands, scored);
    }
  }
  return islands;
}

function feedBestEverFromIslands(tracker, islands) {
  for (const ind of allIndividuals(islands)) {
    if (ind.rejected) continue;
    for (const [fid, score] of Object.entries(ind.perFixture ?? {})) {
      updateBestEver(tracker, fid, score);
    }
  }
}

export async function runGA({
  seed,
  generations,
  config,
  outRoot,
  runId,
  scoreChild,
  resume = false,
  galleryFixtures = null,
  galleryRender = undefined,
  controlState = null,
  onGenerationComplete = null,
  refitConfig = null,
}) {
  if (typeof seed !== 'number') throw new Error('runGA: seed is required');
  if (typeof generations !== 'number') throw new Error('runGA: generations is required');
  if (!config) throw new Error('runGA: config is required');
  if (!outRoot) throw new Error('runGA: outRoot is required');
  if (!runId) throw new Error('runGA: runId is required');
  if (typeof scoreChild !== 'function') throw new Error('runGA: scoreChild is required');

  const runDir = join(outRoot, runId);
  await mkdir(runDir, { recursive: true });

  const bestEverPath = join(runDir, 'best-ever.json');

  // Refit state: track current weights, active file name, and per-individual
  // termTotals across all generations (needed by the BT refit to compute
  // term differences for historical individuals referenced in votes).
  let currentWeights = refitConfig ? { ...refitConfig.initialWeights } : null;
  let activeWeightsFile = refitConfig ? 'default' : null;
  const termsById = {};

  // Wrap scoreChild to pass current weights when refit is active.
  const callScoreChild = refitConfig
    ? (args) => scoreChild({ ...args, weights: currentWeights })
    : scoreChild;

  let islands;
  let bestEver;
  let startGen = 0;

  const existing = await listGenerations(runDir);
  if (resume && existing.length > 0) {
    const lastGen = existing[existing.length - 1];
    islands = await readSnapshot(runDir, lastGen);
    bestEver = await loadBestEver(bestEverPath);
    startGen = lastGen + 1;
  } else {
    islands = await initializePopulation({ seed, config, scoreChild: callScoreChild });
    bestEver = createBestEver();
    feedBestEverFromIslands(bestEver, islands);
    await saveBestEver(bestEverPath, bestEver);
    await writeSnapshot(runDir, 0, islands, [], activeWeightsFile);
    startGen = 1;
  }

  // Seed termsById from the initial population.
  if (refitConfig) {
    for (const ind of allIndividuals(islands)) {
      if (ind.termTotals) termsById[ind.id] = ind.termTotals;
    }
  }

  for (let gen = startGen; gen < generations; gen++) {
    // Control: pause gate — block until unpaused.
    await awaitUnpause(controlState);

    // Control: abort — exit cleanly after the last completed snapshot.
    if (controlState && controlState.abortRequested) break;

    const prng = genPrng(seed, gen);
    islands = await advanceGeneration(islands, {
      prng,
      scoreChild: callScoreChild,
      bestEver,
      config,
      generationIndex: gen,
    });

    // Control: remove killed individuals from all island populations.
    if (controlState && controlState.killedIds.size > 0) {
      for (const [key, pop] of islands.populations) {
        islands.populations.set(key, pop.filter((ind) => !isKilled(controlState, ind.id)));
      }
    }

    // Control: inject protected genomes — score them so they participate
    // in selection with real fitness values.
    if (controlState && controlState.protectedGenomes.size > 0) {
      const injected = [];
      injectProtectedInto(controlState, injected, gen);
      for (const ind of injected) {
        const scored = await callScoreChild({ id: ind.id, genome: ind.genome });
        scored.id = ind.id;
        // Place into the first island (protected genomes are island-agnostic).
        const firstKey = islands.populations.keys().next().value;
        scored.island = firstKey;
        placeIndividual(islands, scored);
      }
    }

    // Introgression: every `migrationInterval` generations, migrate a
    // small number of individuals between neighbouring islands on a ring.
    if (shouldMigrate(gen, config)) {
      const migrationPrng = createPrng(seed).fork(`migration-${gen}`);
      migrateRing(islands, migrationPrng, {
        migrationRate: config.migrationRate ?? 0.05,
        tournamentSize: config.tournamentSize,
      });
    }

    feedBestEverFromIslands(bestEver, islands);
    await saveBestEver(bestEverPath, bestEver);

    // Accumulate termTotals for the refit's termsById.
    if (refitConfig) {
      for (const ind of allIndividuals(islands)) {
        if (ind.termTotals) termsById[ind.id] = ind.termTotals;
      }
    }

    // Refit schedule: every N generations, attempt a weight refit.
    if (refitConfig && gen > 0 && gen % (refitConfig.refitEveryGenerations ?? 5) === 0) {
      const { votes: voteList } = await readVotes(refitConfig.votesPath);
      const result = refitWeights({
        votes: voteList,
        termsById,
        priorWeights: currentWeights,
        halfLifeVotes: refitConfig.halfLifeVotes,
        regularization: refitConfig.regularization,
        minVotesForRefit: refitConfig.minVotesForRefit,
      });
      if (!result.skipped) {
        currentWeights = result.weights;
        const weightsFileName = `gen-${String(gen).padStart(4, '0')}.json`;
        const weightsDir = join(runDir, 'weights');
        await mkdir(weightsDir, { recursive: true });
        await atomicWriteJSON(join(weightsDir, weightsFileName), currentWeights);
        activeWeightsFile = `weights/${weightsFileName}`;
      }
    }

    // Recompute elite log for reporting.
    const rejectedLog = [];
    const topByFitness = [];
    for (const [, pop] of islands.populations) {
      const { rejected } = selectEliteWithGuard(
        pop,
        config.eliteCount,
        bestEver,
        { threshold: config.regressionThreshold },
      );
      for (const r of rejected) rejectedLog.push(r);
      const sorted = pop
        .slice()
        .filter((i) => !i.rejected)
        .sort((a, b) => a.fitness - b.fitness);
      for (const e of sorted.slice(0, config.eliteCount)) topByFitness.push(e);
    }
    await writeSnapshot(runDir, gen, islands, rejectedLog, activeWeightsFile);

    if (Array.isArray(galleryFixtures) && galleryFixtures.length > 0) {
      const galleryDir = join(runDir, 'gallery', genDirName(gen));
      await writeGallery({
        galleryDir,
        elite: topByFitness,
        fixtures: galleryFixtures,
        ...(galleryRender ? { render: galleryRender } : {}),
      });
    }

    // Hook: notify caller after each generation.
    if (typeof onGenerationComplete === 'function') {
      onGenerationComplete(gen, islands);
    }
  }

  return { runDir, finalIslands: islands, bestEver };
}

export async function loadWeightsFile(path) {
  return JSON.parse(await readFile(path, 'utf8'));
}
