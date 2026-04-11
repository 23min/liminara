#!/usr/bin/env node
// serve-lanes.mjs — Tinder server for lane-based DAG layout GA.

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { evaluateLaneLayout, DEFAULT_WEIGHTS, randomLaneAssignment } from './lane-model.mjs';
import { loadGraphMLDir } from '../loaders/graphml.mjs';
import { buildGraph, topoSortAndRank } from '../../dag-map/src/graph-utils.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');

const args = { port: 8888, seed: 42, pop: 200, gens: 2000 };
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--port') args.port = parseInt(process.argv[++i]);
  if (process.argv[i] === '--seed') args.seed = parseInt(process.argv[++i]);
  if (process.argv[i] === '--pop') args.pop = parseInt(process.argv[++i]);
  if (process.argv[i] === '--gens') args.gens = parseInt(process.argv[++i]);
}

const north = await loadGraphMLDir(join(BENCH_ROOT, 'corpora', 'tier-c', 'north'));
const fixtures = north
  .filter(f => f.dag.nodes.length >= 12 && f.dag.nodes.length <= 35 && f.dag.edges.length >= 15)
  .slice(0, 20);
console.log(`Loaded ${fixtures.length} fixtures`);

const state = { fixtureIdx: 0, generation: 0, best: null, population: [], history: [], pairLeft: null, pairRight: null, votes: 0, running: false };
const cache = new Map();
let evolveAbort = false;

function currentFixture() { return fixtures[state.fixtureIdx]; }

function pickPair() {
  const pop = state.population;
  if (pop.length < 2) return;
  const top = pop.slice(0, Math.max(3, Math.floor(pop.length / 3)));
  const rest = pop.slice(Math.floor(pop.length / 3));
  const a = top[Math.floor(Math.random() * top.length)];
  const b = rest[Math.floor(Math.random() * rest.length)];
  if (Math.random() < 0.5) { state.pairLeft = a; state.pairRight = b; }
  else { state.pairLeft = b; state.pairRight = a; }
}

function renderSVG(ind, fixture) {
  if (!ind?.positions) return '<svg viewBox="0 0 200 60"><text x="10" y="30" fill="red">No data</text></svg>';
  const pos = ind.positions;
  const { nodes, edges } = fixture.dag;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const p of pos.values()) { if (p.x < minX) minX = p.x; if (p.y < minY) minY = p.y; if (p.x > maxX) maxX = p.x; if (p.y > maxY) maxY = p.y; }
  const pad = 40, w = Math.max(200, maxX - minX + pad * 2), h = Math.max(100, maxY - minY + pad * 2), ox = pad - minX, oy = pad - minY;

  let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">`;
  svg += `<rect width="${w}" height="${h}" fill="#fdf6e3" rx="4"/>`;

  // Lane grid
  const laneYs = new Set();
  if (ind.assignment) for (const [id] of ind.assignment) { const p = pos.get(id); if (p) laneYs.add(Math.round(p.y)); }
  for (const ly of laneYs) svg += `<line x1="${pad}" y1="${ly + oy}" x2="${w - pad}" y2="${ly + oy}" stroke="#e8e3d8" stroke-width="0.5" stroke-dasharray="4,4"/>`;

  // Edges
  for (const [f, t] of edges) {
    const pf = pos.get(f), pt = pos.get(t);
    if (!pf || !pt) continue;
    const horiz = ind.assignment && ind.assignment.get(f) === ind.assignment.get(t);
    const col = horiz ? '#268bd2' : '#b58900';
    const op = horiz ? 0.7 : 0.4;
    const sw = horiz ? 2.5 : 1.2;
    svg += `<line x1="${pf.x + ox}" y1="${pf.y + oy}" x2="${pt.x + ox}" y2="${pt.y + oy}" stroke="${col}" stroke-width="${sw}" stroke-opacity="${op}"/>`;
    const dx = pt.x - pf.x, dy = pt.y - pf.y, len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) { const ux = dx / len, uy = dy / len; svg += `<polygon points="${pt.x + ox},${pt.y + oy} ${pt.x + ox - ux * 6 - uy * 3},${pt.y + oy - uy * 6 + ux * 3} ${pt.x + ox - ux * 6 + uy * 3},${pt.y + oy - uy * 6 - ux * 3}" fill="${col}" fill-opacity="${op}"/>`; }
  }

  // Nodes
  for (const nd of nodes) {
    const p = pos.get(nd.id);
    if (!p) continue;
    svg += `<circle cx="${p.x + ox}" cy="${p.y + oy}" r="6" fill="#268bd2" stroke="#fff" stroke-width="1.5"/>`;
    svg += `<text x="${p.x + ox}" y="${p.y + oy - 9}" text-anchor="middle" font-size="9" fill="#333" font-family="sans-serif">${nd.id}</text>`;
  }

  const horizCount = edges.filter(([f, t]) => ind.assignment?.get(f) === ind.assignment?.get(t)).length;
  svg += `<text x="8" y="14" font-size="10" fill="#888" font-family="sans-serif">score ${ind.score?.toFixed(0)} | ✗${ind.terms?.crossings ?? '?'} | ─${horizCount}/${edges.length} | ↕${ind.terms?.direction_changes ?? '?'}</text>`;
  svg += '</svg>';
  return svg;
}

function createPrng(seed) {
  let s = seed;
  return { next() { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; }, nextInt(max) { return Math.floor(this.next() * (max + 1)); } };
}

async function evolve() {
  evolveAbort = false;
  state.running = true;
  state.history = [];
  state.population = [];
  state.best = null;
  const fixture = currentFixture();

  if (cache.has(fixture.id)) {
    const c = cache.get(fixture.id);
    Object.assign(state, { best: c.best, history: c.history, population: c.population, generation: c.generation, running: false });
    pickPair();
    return;
  }

  console.log(`Evolving: ${fixture.id} (${fixture.dag.nodes.length}n, ${fixture.dag.edges.length}e)`);
  const { childrenOf, parentsOf } = buildGraph(fixture.dag.nodes, fixture.dag.edges);
  const { rank, maxRank } = topoSortAndRank(fixture.dag.nodes, childrenOf, parentsOf);

  const layerWidths = new Array(maxRank + 1).fill(0);
  for (const nd of fixture.dag.nodes) layerWidths[rank.get(nd.id)]++;
  const numLanes = Math.max(Math.max(...layerWidths) + 2, Math.ceil(fixture.dag.nodes.length * 0.5));
  const layoutOpts = { laneHeight: 50, layerSpacing: 80, margin: 50 };
  const prng = createPrng(args.seed + state.fixtureIdx * 10000);

  let pop = [];
  for (let i = 0; i < args.pop; i++) {
    const a = randomLaneAssignment(fixture.dag, numLanes, createPrng(args.seed + state.fixtureIdx * 10000 + i * 7919));
    const { score, terms, positions } = evaluateLaneLayout(fixture.dag, a, DEFAULT_WEIGHTS, layoutOpts);
    pop.push({ id: `g0-${i}`, assignment: a, score, terms, positions });
  }
  pop.sort((a, b) => a.score - b.score);
  state.best = pop[0]; state.population = pop.slice(0, 80); state.generation = 0;
  state.history.push({ gen: 0, score: pop[0].score });
  pickPair();

  const elite = Math.max(5, Math.floor(args.pop * 0.05));

  for (let gen = 1; gen <= args.gens; gen++) {
    if (evolveAbort) break;
    const next = [];
    for (let i = 0; i < elite; i++) next.push({ ...pop[i], id: `g${gen}-e${i}` });

    while (next.length < args.pop) {
      let p1 = pop[prng.nextInt(pop.length - 1)];
      for (let k = 0; k < 4; k++) { const c = pop[prng.nextInt(pop.length - 1)]; if (c.score < p1.score) p1 = c; }
      let p2 = pop[prng.nextInt(pop.length - 1)];
      for (let k = 0; k < 4; k++) { const c = pop[prng.nextInt(pop.length - 1)]; if (c.score < p2.score) p2 = c; }

      const child = new Map();
      for (const [id, lA] of p1.assignment) child.set(id, prng.next() < 0.5 ? lA : (p2.assignment.get(id) ?? lA));

      for (let m = 0; m < 1 + prng.nextInt(3); m++) {
        const nid = fixture.dag.nodes[prng.nextInt(fixture.dag.nodes.length - 1)].id;
        const r = prng.next();
        if (r < 0.3) {
          const nb = [...(childrenOf.get(nid) || []), ...(parentsOf.get(nid) || [])];
          if (nb.length > 0) child.set(nid, child.get(nb[prng.nextInt(nb.length - 1)]));
        } else if (r < 0.55) {
          child.set(nid, prng.nextInt(numLanes - 1));
        } else if (r < 0.8) {
          const sl = fixture.dag.nodes.filter(n => rank.get(n.id) === rank.get(nid) && n.id !== nid);
          if (sl.length > 0) { const o = sl[prng.nextInt(sl.length - 1)].id; const t = child.get(nid); child.set(nid, child.get(o)); child.set(o, t); }
        } else {
          child.set(nid, Math.max(0, Math.min(numLanes - 1, child.get(nid) + (prng.next() < 0.5 ? -1 : 1))));
        }
      }

      const { score, terms, positions } = evaluateLaneLayout(fixture.dag, child, DEFAULT_WEIGHTS, layoutOpts);
      next.push({ id: `g${gen}-${next.length}`, assignment: child, score, terms, positions });
    }

    pop = next.sort((a, b) => a.score - b.score);
    state.best = pop[0]; state.population = pop.slice(0, 80); state.generation = gen;
    state.history.push({ gen, score: pop[0].score });
    pickPair();
    if (gen % 50 === 0) await new Promise(r => setTimeout(r, 1));
  }

  cache.set(fixture.id, { best: state.best, history: [...state.history], population: [...state.population], generation: state.generation });
  state.running = false;
  console.log(`Done: ${fixture.id} — score ${state.best?.score?.toFixed(0)} | ✗${state.best?.terms?.crossings}`);
}

const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, `http://${req.headers.host}`).pathname;
  if (path === '/') { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(await readFile(join(__dirname, 'index.html'), 'utf8')); }
  if (path === '/state') {
    const f = currentFixture();
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ fixture: f?.id, nodes: f?.dag.nodes.length, edges: f?.dag.edges.length, fixtureCount: fixtures.length, fixtureIdx: state.fixtureIdx, generation: state.generation, totalGens: args.gens, running: state.running, votes: state.votes, bestScore: state.best?.score, bestTerms: state.best?.terms, history: state.history.slice(-300), leftSvg: state.pairLeft ? renderSVG(state.pairLeft, f) : null, rightSvg: state.pairRight ? renderSVG(state.pairRight, f) : null, leftScore: state.pairLeft?.score, rightScore: state.pairRight?.score }));
  }
  if (path === '/vote' && req.method === 'POST') { let b = ''; req.on('data', c => b += c); req.on('end', () => { state.votes++; pickPair(); res.writeHead(200); res.end('{"ok":true}'); }); return; }
  if (path === '/next-fixture') { evolveAbort = true; state.fixtureIdx = (state.fixtureIdx + 1) % fixtures.length; setTimeout(() => evolve(), 10); res.writeHead(200); return res.end(`{"fixture":"${currentFixture()?.id}"}`); }
  if (path === '/prev-fixture') { evolveAbort = true; state.fixtureIdx = (state.fixtureIdx - 1 + fixtures.length) % fixtures.length; setTimeout(() => evolve(), 10); res.writeHead(200); return res.end(`{"fixture":"${currentFixture()?.id}"}`); }
  res.writeHead(404); res.end('not found');
});

server.listen(args.port, () => { console.log(`Lane GA: http://localhost:${args.port}`); evolve(); });
