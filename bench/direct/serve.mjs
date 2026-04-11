#!/usr/bin/env node
// serve.mjs — Tinder server for direct-position GA.
//
// Runs the GA in the background, serves a dashboard where the user
// sees two layouts from the current population and votes.
//
// Usage: node bench/direct/serve.mjs --port 8888

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { DEFAULT_WEIGHTS, randomLayout, mutate } from './ga.mjs';
import { evaluateLayout } from './fitness.mjs';
import { loadGraphMLDir } from '../loaders/graphml.mjs';
import { buildGraph } from '../../dag-map/src/graph-utils.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');

// ── Parse args ──
const args = { port: 8888, seed: 42, pop: 200, gens: 500 };
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--port') args.port = parseInt(process.argv[++i]);
  if (process.argv[i] === '--seed') args.seed = parseInt(process.argv[++i]);
  if (process.argv[i] === '--pop') args.pop = parseInt(process.argv[++i]);
  if (process.argv[i] === '--gens') args.gens = parseInt(process.argv[++i]);
}

// ── Load fixtures ──
const north = await loadGraphMLDir(join(BENCH_ROOT, 'corpora', 'tier-c', 'north'));
const fixtures = north
  .filter(f => f.dag.nodes.length >= 15 && f.dag.nodes.length <= 40 && f.dag.edges.length >= 18)
  .slice(0, 20);

console.log(`Loaded ${fixtures.length} fixtures`);

// ── Shared state ──
const state = {
  fixtureIdx: 0,
  generation: 0,
  population: [],
  best: null,
  history: [],
  pairLeft: null,
  pairRight: null,
  votes: 0,
  running: false,
};

function currentFixture() { return fixtures[state.fixtureIdx]; }

function pickPair() {
  const pop = state.population;
  if (pop.length < 2) return;
  // Pick two random individuals from different quality tiers
  // so they look genuinely different
  const topHalf = pop.slice(0, Math.floor(pop.length / 2));
  const bottomHalf = pop.slice(Math.floor(pop.length / 2));
  const a = topHalf[Math.floor(Math.random() * topHalf.length)];
  const b = bottomHalf[Math.floor(Math.random() * bottomHalf.length)];
  // Randomize left/right so user doesn't always pick left
  if (Math.random() < 0.5) {
    state.pairLeft = a;
    state.pairRight = b;
  } else {
    state.pairLeft = b;
    state.pairRight = a;
  }
}

function renderSVG(individual, fixture) {
  if (!individual || !individual.positions) return '<svg width="200" height="60"><text x="10" y="30" fill="red">No data</text></svg>';

  const pos = individual.positions;
  const { nodes, edges } = fixture.dag;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const p of pos.values()) {
    if (p.x < minX) minX = p.x; if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x; if (p.y > maxY) maxY = p.y;
  }

  const pad = 40;
  const w = Math.max(200, maxX - minX + pad * 2);
  const h = Math.max(100, maxY - minY + pad * 2);
  const ox = pad - minX, oy = pad - minY;

  let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">`;
  svg += `<rect width="${w}" height="${h}" fill="#fdf6e3" rx="4"/>`;

  // Edges
  for (const [f, t] of edges) {
    const pf = pos.get(f), pt = pos.get(t);
    if (!pf || !pt) continue;
    svg += `<line x1="${pf.x + ox}" y1="${pf.y + oy}" x2="${pt.x + ox}" y2="${pt.y + oy}" stroke="#268bd2" stroke-width="1.5" stroke-opacity="0.4"/>`;
    // Arrowhead
    const dx = pt.x - pf.x, dy = pt.y - pf.y, len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      const ux = dx / len, uy = dy / len;
      svg += `<polygon points="${pt.x + ox},${pt.y + oy} ${pt.x + ox - ux * 6 - uy * 3},${pt.y + oy - uy * 6 + ux * 3} ${pt.x + ox - ux * 6 + uy * 3},${pt.y + oy - uy * 6 - ux * 3}" fill="#268bd2" fill-opacity="0.4"/>`;
    }
  }

  // Nodes
  for (const nd of nodes) {
    const p = pos.get(nd.id);
    if (!p) continue;
    svg += `<circle cx="${p.x + ox}" cy="${p.y + oy}" r="6" fill="#268bd2" stroke="#fff" stroke-width="1.5"/>`;
    svg += `<text x="${p.x + ox}" y="${p.y + oy - 9}" text-anchor="middle" font-size="10" fill="#333" font-family="sans-serif">${nd.id}</text>`;
  }

  // Score
  svg += `<text x="8" y="16" font-size="11" fill="#666" font-family="sans-serif">score: ${individual.score?.toFixed(0)} | crossings: ${individual.terms?.crossings ?? '?'} | overlap: ${individual.terms?.overlap ?? '?'}</text>`;
  svg += '</svg>';
  return svg;
}

// Store completed results per fixture
const results = new Map(); // fixtureId → { best, history }
let evolveAbort = false;

async function evolve() {
  evolveAbort = false;
  state.running = true;
  state.history = [];
  state.population = [];
  state.best = null;
  const fixture = currentFixture();
  console.log(`Evolving: ${fixture.id} (${fixture.dag.nodes.length} nodes, ${fixture.dag.edges.length} edges)`);

  // Check if we already have results for this fixture
  const cached = results.get(fixture.id);
  if (cached) {
    state.best = cached.best;
    state.history = cached.history;
    state.population = cached.population;
    state.generation = cached.generation;
    pickPair();
    state.running = false;
    console.log(`Loaded cached: ${fixture.id} — score: ${cached.best?.score?.toFixed(0)}`);
    return;
  }

  const { edges } = fixture.dag;
  const { childrenOf, parentsOf } = buildGraph(fixture.dag.nodes, fixture.dag.edges);

  // Run GA in chunks, yielding to event loop every 50 generations
  const popSize = args.pop;
  const eliteCount = Math.max(5, Math.floor(popSize * 0.05));
  const totalGens = args.gens;
  const chunkSize = 50;

  // Initialize population
  let population = [];
  for (let i = 0; i < popSize; i++) {
    const positions = randomLayout(fixture.dag, createPrng(args.seed + state.fixtureIdx * 10000 + i * 7919));
    repairFlow(positions, edges);
    const { score, terms, violations } = evaluateLayout(positions, edges, DEFAULT_WEIGHTS);
    population.push({ id: `g0-${i}`, positions, score, terms, violations });
  }
  population.sort((a, b) => a.score - b.score);

  state.best = population[0];
  state.population = population.slice(0, 100);
  state.generation = 0;
  state.history.push({ gen: 0, score: population[0].score, crossings: population[0].terms.crossings });
  pickPair();

  const prng = createPrng(args.seed + state.fixtureIdx * 10000);

  for (let gen = 1; gen <= totalGens; gen++) {
    if (evolveAbort) break;

    const next = [];
    for (let i = 0; i < eliteCount; i++) {
      next.push({ ...population[i], id: `g${gen}-e${i}` });
    }
    while (next.length < popSize) {
      const p1 = tournament(population, prng, 5);
      const p2 = tournament(population, prng, 5);
      let child = crossover(p1.positions, p2.positions, prng);
      child = mutate(child, edges, childrenOf, parentsOf, prng, {
        moveSigmaX: 25 + 15 * (1 - gen / totalGens),
        moveSigmaY: 40 + 20 * (1 - gen / totalGens),
      });
      repairFlow(child, edges);
      const { score, terms, violations } = evaluateLayout(child, edges, DEFAULT_WEIGHTS);
      next.push({ id: `g${gen}-${next.length}`, positions: child, score, terms, violations });
    }
    population = next.sort((a, b) => a.score - b.score);

    state.best = population[0];
    state.population = population.slice(0, 100);
    state.generation = gen;
    state.history.push({ gen, score: population[0].score, crossings: population[0].terms.crossings });
    pickPair();

    // Yield to event loop every chunkSize generations
    if (gen % chunkSize === 0) {
      await new Promise(r => setTimeout(r, 1));
    }
  }

  // Cache results
  results.set(fixture.id, {
    best: state.best,
    history: [...state.history],
    population: [...state.population],
    generation: state.generation,
  });

  state.running = false;
  console.log(`Done: ${fixture.id} — best score: ${state.best?.score?.toFixed(0)}`);
}

function tournament(pop, prng, size) {
  let best = pop[Math.floor(prng.next() * pop.length)];
  for (let i = 1; i < size; i++) {
    const c = pop[Math.floor(prng.next() * pop.length)];
    if (c.score < best.score) best = c;
  }
  return best;
}

function crossover(posA, posB, prng) {
  const result = new Map();
  for (const [id, pA] of posA) {
    const pB = posB.get(id);
    result.set(id, (pB && prng.next() < 0.5) ? { ...pB } : { ...pA });
  }
  return result;
}

function repairFlow(positions, edges) {
  const minGap = 25;
  for (let pass = 0; pass < 5; pass++) {
    for (const [from, to] of edges) {
      const pf = positions.get(from), pt = positions.get(to);
      if (pf && pt && pt.x <= pf.x + minGap) pt.x = pf.x + minGap;
    }
  }
}

function createPrng(seed) {
  let s = seed;
  function next() { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; }
  function nextGaussian() { const u1 = next() || 0.0001, u2 = next(); return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2); }
  return { next, nextGaussian };
}

// ── HTTP server ──
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/') {
    const html = await readFile(join(__dirname, 'index.html'), 'utf8');
    res.writeHead(200, { 'content-type': 'text/html' });
    return res.end(html);
  }

  if (path === '/state') {
    const fixture = currentFixture();
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({
      fixture: fixture?.id,
      fixtureCount: fixtures.length,
      generation: state.generation,
      running: state.running,
      votes: state.votes,
      bestScore: state.best?.score,
      bestTerms: state.best?.terms,
      history: state.history.slice(-200),
      leftSvg: state.pairLeft ? renderSVG(state.pairLeft, fixture) : null,
      rightSvg: state.pairRight ? renderSVG(state.pairRight, fixture) : null,
      leftScore: state.pairLeft?.score,
      rightScore: state.pairRight?.score,
      leftTerms: state.pairLeft?.terms,
      rightTerms: state.pairRight?.terms,
    }));
  }

  if (path === '/vote' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      state.votes++;
      pickPair(); // show next pair
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, votes: state.votes }));
    });
    return;
  }

  if (path === '/next-fixture') {
    evolveAbort = true; // stop current run
    state.fixtureIdx = (state.fixtureIdx + 1) % fixtures.length;
    setTimeout(() => evolve(), 10); // start after abort settles
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ fixture: currentFixture()?.id }));
  }

  if (path === '/prev-fixture') {
    evolveAbort = true;
    state.fixtureIdx = (state.fixtureIdx - 1 + fixtures.length) % fixtures.length;
    setTimeout(() => evolve(), 10);
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ fixture: currentFixture()?.id }));
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(args.port, () => {
  console.log(`Direct GA Tinder: http://localhost:${args.port}`);
  evolve(); // start first fixture
});
