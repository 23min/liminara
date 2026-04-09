// scripts/tinder.js — Live steering HTTP server for the Tinder UI.
//
// Single Node process: runs the GA in the background and serves the
// voting UI over HTTP. Node core only — no new bench deps.
//
// Usage:
//   node scripts/tinder.js --run-id <id> --seed <int> --generations <n> [--port 8765]

import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { runGA } from '../ga/runner.mjs';
import { createControlState, pause, resume, requestAbort, protect, unprotect, kill, appendControlEvent } from '../ga/control.mjs';
import { appendVote, readVotes } from '../ga/votes.mjs';
import { allIndividuals } from '../ga/islands.mjs';
import { loadDefaultWeights, TERM_NAMES } from '../evaluator/evaluator.mjs';
import { scoreIndividual } from '../ga/individual.mjs';
import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';
import { createPrng } from '../ga/prng.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');
const DEFAULT_OUT_ROOT = join(BENCH_ROOT, 'run');

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
};

// ── CLI args ────────────────────────────────────────────────────────────

export function parseTinderArgs(argv) {
  const out = {
    seed: 1,
    generations: 20,
    runId: null,
    port: 8765,
    populationSize: 8,
    eliteCount: 2,
    tournamentSize: 3,
    tier1MutationStrength: 0.1,
    regressionThreshold: 0.9,
    migrationInterval: 10,
    migrationRate: 0.05,
    refitEveryGenerations: 5,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`missing value for ${a}`);
      return v;
    };
    switch (a) {
      case '--seed': out.seed = parseInt(next(), 10); break;
      case '--generations': out.generations = parseInt(next(), 10); break;
      case '--run-id': out.runId = next(); break;
      case '--port': out.port = parseInt(next(), 10); break;
      case '--population': out.populationSize = parseInt(next(), 10); break;
      case '--elite': out.eliteCount = parseInt(next(), 10); break;
      case '--tournament': out.tournamentSize = parseInt(next(), 10); break;
      case '--mut-t1': out.tier1MutationStrength = parseFloat(next()); break;
      case '--guard': out.regressionThreshold = parseFloat(next()); break;
      case '--refit-every': out.refitEveryGenerations = parseInt(next(), 10); break;
      default: throw new Error(`unknown argument: ${a}`);
    }
  }
  if (!out.runId) out.runId = `tinder-seed${out.seed}-g${out.generations}`;
  return out;
}

// ── Pair selection ──────────────────────────────────────────────────────

export function selectPair(elite, seed, votedPairs) {
  if (!elite || elite.length < 2) return null;

  // Build all possible pairs.
  const pairs = [];
  for (let i = 0; i < elite.length; i++) {
    for (let j = i + 1; j < elite.length; j++) {
      pairs.push([elite[i], elite[j]]);
    }
  }

  // Build a set of already-voted pair keys (order-independent).
  const votedSet = new Set();
  for (const v of votedPairs) {
    const a = v.left_id;
    const b = v.right_id;
    if (a && b) {
      votedSet.add(a < b ? `${a}:${b}` : `${b}:${a}`);
    }
  }

  // Filter to unvoted pairs.
  const available = pairs.filter(([a, b]) => {
    const key = a.id < b.id ? `${a.id}:${b.id}` : `${b.id}:${a.id}`;
    return !votedSet.has(key);
  });

  if (available.length === 0) return null;

  // Deterministic pick.
  const prng = createPrng(seed + votedPairs.length);
  const idx = prng.nextInt(0, available.length - 1);
  const [left, right] = available[idx];
  return { left, right };
}

// ── Server ──────────────────────────────────────────────────────────────

export async function createTinderServer({
  seed,
  generations,
  port,
  config,
  outRoot,
  runId,
  scoreChild,
  webRoot,
  resume: resumeRun = false,
  initialWeights = null,
}) {
  const controlState = createControlState();
  const runDir = join(outRoot, runId);
  const votesPath = join(runDir, 'tinder.jsonl');
  const controlLogPath = join(runDir, 'control.jsonl');
  const weights = initialWeights ?? Object.fromEntries(TERM_NAMES.map((n) => [n, 1]));

  // Shared mutable state updated by onGenerationComplete.
  const shared = {
    generation: 0,
    elite: [],
    voteCount: 0,
    votesSinceLastRefit: 0,
    currentWeights: { ...weights },
  };

  function updateElite(islands) {
    const all = allIndividuals(islands);
    shared.elite = all
      .filter((i) => !i.rejected && Number.isFinite(i.fitness))
      .sort((a, b) => a.fitness - b.fitness)
      .slice(0, Math.max(config.eliteCount * 3, 6));
  }

  // ── HTTP handler ────────────────────────────────────────────────

  async function readBody(req) {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    return Buffer.concat(chunks).toString('utf8');
  }

  function jsonResponse(res, status, data) {
    const body = JSON.stringify(data);
    res.writeHead(status, { 'content-type': 'application/json' });
    res.end(body);
  }

  async function serveStatic(res, filePath) {
    try {
      const data = await readFile(filePath);
      const ext = extname(filePath);
      res.writeHead(200, { 'content-type': MIME[ext] ?? 'application/octet-stream' });
      res.end(data);
    } catch {
      res.writeHead(404);
      res.end('not found');
    }
  }

  async function getCurrentPair() {
    const { votes } = await readVotes(votesPath);
    // Filter to votes from current generation.
    const genVotes = votes.filter((v) => v.generation === shared.generation);
    shared.voteCount = votes.length;
    return selectPair(shared.elite, seed, genVotes);
  }

  async function handleRequest(req, res) {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const path = url.pathname;

    // GET /
    if (req.method === 'GET' && path === '/') {
      return serveStatic(res, join(webRoot, 'index.html'));
    }

    // GET /static/*
    if (req.method === 'GET' && path.startsWith('/static/')) {
      const rel = path.slice('/static/'.length);
      if (rel.includes('..')) { res.writeHead(403); return res.end(); }
      return serveStatic(res, join(webRoot, rel));
    }

    // GET /state
    if (req.method === 'GET' && path === '/state') {
      const pair = await getCurrentPair();
      return jsonResponse(res, 200, {
        runId,
        generation: shared.generation,
        paused: controlState.paused,
        voteCount: shared.voteCount,
        votesSinceLastRefit: shared.votesSinceLastRefit,
        currentWeights: shared.currentWeights,
        pair,
      });
    }

    // GET /svg/:individualId/:fixtureId
    if (req.method === 'GET' && path.startsWith('/svg/')) {
      const parts = path.slice('/svg/'.length).split('/');
      if (parts.length >= 2) {
        const [indId, fixId] = parts;
        const genDir = `gen-${String(shared.generation).padStart(4, '0')}`;
        const svgPath = join(runDir, 'gallery', genDir, indId, `${fixId}.svg`);
        return serveStatic(res, svgPath);
      }
      res.writeHead(400);
      return res.end('bad svg path');
    }

    // POST /vote
    if (req.method === 'POST' && path === '/vote') {
      try {
        const body = JSON.parse(await readBody(req));
        await appendVote(votesPath, {
          ts: new Date().toISOString(),
          run_id: runId,
          generation: shared.generation,
          left_id: body.left_id ?? body.leftId,
          right_id: body.right_id ?? body.rightId,
          winner: body.winner,
          ...(body.voter_note ? { voter_note: body.voter_note } : {}),
        });
        shared.votesSinceLastRefit++;
        const pair = await getCurrentPair();
        return jsonResponse(res, 200, { ok: true, pair });
      } catch (err) {
        return jsonResponse(res, 400, { error: err.message });
      }
    }

    // POST /control
    if (req.method === 'POST' && path === '/control') {
      try {
        const body = JSON.parse(await readBody(req));
        const ts = new Date().toISOString();
        switch (body.action) {
          case 'pause':
            pause(controlState);
            await appendControlEvent(controlLogPath, { action: 'pause', ts });
            break;
          case 'resume':
            resume(controlState);
            await appendControlEvent(controlLogPath, { action: 'resume', ts });
            break;
          case 'protect':
            if (body.id) {
              const ind = shared.elite.find((e) => e.id === body.id);
              if (ind) {
                protect(controlState, body.id, ind.genome);
                await appendControlEvent(controlLogPath, { action: 'protect', ts, id: body.id });
              }
            }
            break;
          case 'unprotect':
            unprotect(controlState, body.id);
            await appendControlEvent(controlLogPath, { action: 'unprotect', ts, id: body.id });
            break;
          case 'kill':
            kill(controlState, body.id);
            await appendControlEvent(controlLogPath, { action: 'kill', ts, id: body.id });
            break;
          default:
            return jsonResponse(res, 400, { error: `unknown action: ${body.action}` });
        }
        return jsonResponse(res, 200, { ok: true, paused: controlState.paused });
      } catch (err) {
        return jsonResponse(res, 400, { error: err.message });
      }
    }

    res.writeHead(404);
    res.end('not found');
  }

  // ── Start server + GA ───────────────────────────────────────────

  const server = http.createServer(handleRequest);
  await new Promise((resolve) => server.listen(port, resolve));

  const gaPromise = runGA({
    seed,
    generations,
    config,
    outRoot,
    runId,
    scoreChild,
    resume: resumeRun,
    controlState,
    refitConfig: {
      votesPath,
      initialWeights: weights,
      refitEveryGenerations: config.refitEveryGenerations ?? 5,
      regularization: 0.1,
      minVotesForRefit: 5,
    },
    onGenerationComplete: (gen, islands) => {
      shared.generation = gen;
      updateElite(islands);
    },
  });

  return { server, gaPromise, controlState, shared };
}

// ── CLI entry point ─────────────────────────────────────────────────────

const isDirectRun = import.meta.url === `file://${process.argv[1]}`;
if (isDirectRun) {
  (async () => {
    const args = parseTinderArgs(process.argv.slice(2));
    const fixtures = [...(await loadTierA()), ...(await loadTierB())];
    const tierA = await loadTierA();
    const weights = await loadDefaultWeights();

    const scoreChild = async ({ id, genome, island, weights: w }) =>
      scoreIndividual({ id, genome, fixtures, weights: w ?? weights, island });

    const { server, gaPromise, controlState } = await createTinderServer({
      seed: args.seed,
      generations: args.generations,
      port: args.port,
      config: {
        populationSize: args.populationSize,
        eliteCount: args.eliteCount,
        tournamentSize: args.tournamentSize,
        tier1MutationStrength: args.tier1MutationStrength,
        regressionThreshold: args.regressionThreshold,
        migrationInterval: args.migrationInterval,
        migrationRate: args.migrationRate,
        refitEveryGenerations: args.refitEveryGenerations,
      },
      outRoot: DEFAULT_OUT_ROOT,
      runId: args.runId,
      scoreChild,
      webRoot: join(BENCH_ROOT, 'web', 'tinder'),
      initialWeights: weights,
      galleryFixtures: tierA,
    });

    const addr = server.address();
    process.stdout.write(`Tinder UI: http://localhost:${addr.port}/\n`);
    process.stdout.write(`Run: ${args.runId}, seed: ${args.seed}, generations: ${args.generations}\n`);

    process.on('SIGINT', () => {
      process.stderr.write('\nSIGINT — finishing current generation...\n');
      requestAbort(controlState);
      gaPromise.then(() => {
        server.close();
        process.stdout.write('Clean shutdown.\n');
        process.exit(0);
      });
    });

    await gaPromise;
    process.stdout.write('GA complete. Server still running for review. Ctrl-C to exit.\n');
  })().catch((err) => {
    process.stderr.write(`Fatal: ${err.stack || err.message}\n`);
    process.exit(1);
  });
}
