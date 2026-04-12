#!/usr/bin/env node
// flow-explorer.mjs — FlowV2 explorer with permutation GA.
// Shows Default vs Evolved layouts side by side.

import http from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { layoutFlowV2 } from '../../dag-map/src/layout-flow-v2.js';
import { renderFlowV2 } from '../../dag-map/src/render-flow-v2.js';
import { models } from '../../dag-map/test/models.js';
import { evolveRouteOrder, evaluateFitness } from '../direct/permutation-ga.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const port = parseInt(process.argv[2] || '9950');

// Load fixtures
const fixtures = [];
for (const f of readdirSync(join(__dirname, '..', 'fixtures', 'mlcm')).filter(f => f.endsWith('.json'))) {
  fixtures.push(JSON.parse(readFileSync(join(__dirname, '..', 'fixtures', 'mlcm', f), 'utf8')));
}
for (const m of models.filter(m => m.routes && m.routes.length > 1)) {
  fixtures.push(m);
}
for (const f of readdirSync(join(__dirname, '..', 'fixtures', 'metro')).filter(f => f.endsWith('.json'))) {
  const data = JSON.parse(readFileSync(join(__dirname, '..', 'fixtures', 'metro', f), 'utf8'));
  if (data.routes && data.routes.length <= 20) fixtures.push(data); // skip huge ones
}

// Cache evolved permutations
const evolved = new Map();

const HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>FlowV2 Evolution Explorer</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, sans-serif; background: #f5f5f5; height: 100vh; display: flex; flex-direction: column; }
.header { padding: 10px 16px; background: #fff; border-bottom: 1px solid #ddd; display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
.header h1 { font-size: 15px; font-weight: 600; }
.header select { padding: 4px 8px; font-size: 12px; }
.header button { padding: 5px 14px; font-size: 12px; border: 1px solid #4a90d9; background: #4a90d9; color: white; border-radius: 4px; cursor: pointer; }
.header button:hover { background: #357abd; }
.header button:disabled { opacity: 0.5; cursor: default; }
.header .status { font-size: 11px; color: #666; }
.compare { flex: 1; display: grid; grid-template-columns: 1fr 1fr; gap: 0; overflow: auto; }
.panel { padding: 12px; overflow: auto; border-right: 1px solid #ddd; }
.panel:last-child { border-right: none; }
.panel h2 { font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
.panel .metrics { font-size: 11px; font-family: monospace; color: #333; margin-bottom: 8px; }
.panel .metrics .bad { color: #c00; font-weight: bold; }
.panel .metrics .good { color: #060; font-weight: bold; }
.panel svg { background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); border-radius: 4px; max-width: 100%; height: auto; }
.tooltip { position: fixed; background: #333; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; pointer-events: none; z-index: 100; display: none; }
</style>
</head>
<body>
<div class="header">
  <h1>FlowV2 Evolution</h1>
  <select id="fixture">${fixtures.map((f, i) => `<option value="${i}">${f.id} (${f.dag.nodes.length}n, ${f.routes?.length || 0}r)</option>`).join('')}</select>
  <button id="evolve-btn" onclick="runEvolve()">Evolve Route Order</button>
  <span class="status" id="status"></span>
</div>
<div class="compare">
  <div class="panel" id="default-panel">
    <h2>Default Order</h2>
    <div class="metrics" id="default-metrics"></div>
    <div id="default-svg"></div>
  </div>
  <div class="panel" id="evolved-panel">
    <h2>Evolved Order</h2>
    <div class="metrics" id="evolved-metrics"></div>
    <div id="evolved-svg"></div>
  </div>
</div>
<div class="tooltip" id="tooltip"></div>

<script>
const fixture = document.getElementById('fixture');

async function loadDefault() {
  const idx = fixture.value;
  const res = await fetch('/render?idx=' + idx + '&mode=default');
  const data = await res.json();
  document.getElementById('default-svg').innerHTML = data.svg;
  document.getElementById('default-metrics').innerHTML = formatMetrics(data.metrics, 'default');
  // Also load evolved if cached
  const eres = await fetch('/render?idx=' + idx + '&mode=evolved');
  const edata = await eres.json();
  if (edata.svg) {
    document.getElementById('evolved-svg').innerHTML = edata.svg;
    document.getElementById('evolved-metrics').innerHTML = formatMetrics(edata.metrics, 'evolved', data.metrics);
  } else {
    document.getElementById('evolved-svg').innerHTML = '<div style="padding:40px;color:#999;text-align:center">Click "Evolve Route Order" to find the optimal permutation</div>';
    document.getElementById('evolved-metrics').innerHTML = '';
  }
}

function formatMetrics(m, label, baseline) {
  if (!m) return '';
  let html = '';
  const crossCls = m.crossings > 0 ? 'bad' : 'good';
  html += 'crossings: <span class="' + crossCls + '">' + m.crossings + '</span>';
  if (baseline) html += ' (was ' + baseline.crossings + ')';
  html += ' | overlaps: ' + m.overlaps;
  html += ' | bends: ' + m.bends;
  html += ' | fitness: ' + m.fitness;
  if (baseline && baseline.fitness > 0) {
    const pct = ((1 - m.fitness / baseline.fitness) * 100).toFixed(0);
    html += ' <span class="good">(' + pct + '% better)</span>';
  }
  return html;
}

async function runEvolve() {
  const btn = document.getElementById('evolve-btn');
  const status = document.getElementById('status');
  btn.disabled = true;
  status.textContent = 'Evolving...';
  const idx = fixture.value;
  const res = await fetch('/evolve?idx=' + idx);
  const data = await res.json();
  btn.disabled = false;
  status.textContent = 'Done — ' + data.generations + ' generations';
  loadDefault(); // reload both panels
}

fixture.addEventListener('change', loadDefault);

// Tooltip
const tip = document.getElementById('tooltip');
document.addEventListener('mouseover', e => {
  const node = e.target.closest('[data-node-id]');
  const route = e.target.closest('[data-route-id]');
  if (node) { tip.textContent = node.querySelector('.dm-label')?.textContent || node.getAttribute('data-node-id'); tip.style.display = 'block'; }
  else if (route) { tip.textContent = route.getAttribute('data-route-id') + ': ' + (route.getAttribute('data-route-nodes')||''); tip.style.display = 'block'; }
});
document.addEventListener('mousemove', e => { if (tip.style.display === 'block') { tip.style.left = (e.clientX+12)+'px'; tip.style.top = (e.clientY-8)+'px'; } });
document.addEventListener('mouseout', e => { if (e.target.closest('[data-node-id]') || e.target.closest('[data-route-id]')) tip.style.display = 'none'; });

loadDefault();
</script>
</body>
</html>`;

function renderFixture(idx, permutation) {
  const f = fixtures[idx];
  if (!f) return { svg: '', metrics: null };

  const routes = permutation
    ? permutation.map(i => f.routes[i])
    : f.routes;

  const defaultPerm = f.routes.map((_, i) => i);
  const perm = permutation || defaultPerm;
  const metrics = evaluateFitness(f.dag, f.routes, perm);

  try {
    const layout = layoutFlowV2(f.dag, { routes, theme: f.theme || 'cream', trackSpread: 2 });
    const svg = renderFlowV2(f.dag, layout, {});
    return { svg, metrics };
  } catch (e) {
    return { svg: `<div style="color:red">${e.message}</div>`, metrics };
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html' });
    return res.end(HTML);
  }

  if (url.pathname === '/render') {
    const idx = parseInt(url.searchParams.get('idx') || '0');
    const mode = url.searchParams.get('mode') || 'default';

    let result;
    if (mode === 'evolved' && evolved.has(idx)) {
      result = renderFixture(idx, evolved.get(idx));
    } else if (mode === 'evolved') {
      result = { svg: null, metrics: null };
    } else {
      result = renderFixture(idx, null);
    }

    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify(result));
  }

  if (url.pathname === '/evolve') {
    const idx = parseInt(url.searchParams.get('idx') || '0');
    const f = fixtures[idx];
    if (!f) {
      res.writeHead(400, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: 'fixture not found' }));
    }

    const gens = f.routes.length > 15 ? 150 : 80;
    const pop = Math.max(20, f.routes.length * 3);
    const result = evolveRouteOrder(f.dag, f.routes, { generations: gens, populationSize: pop });

    evolved.set(idx, result.bestPermutation);

    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({
      permutation: result.bestPermutation,
      fitness: result.bestFitness,
      generations: result.history.length,
      history: result.history,
    }));
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(port, () => {
  console.log(`FlowV2 Evolution Explorer: http://localhost:${port}/`);
  console.log(`${fixtures.length} fixtures loaded`);
});
