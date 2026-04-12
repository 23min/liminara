#!/usr/bin/env node
// flow-explorer.mjs — interactive parameter explorer for FlowV2.
// Serves an HTML page with sliders that re-render the layout in real-time.

import http from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { layoutFlowV2 } from '../../dag-map/src/layout-flow-v2.js';
import { renderFlowV2 } from '../../dag-map/src/render-flow-v2.js';
import { models } from '../../dag-map/test/models.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Load all fixtures with routes
const fixtures = [];
for (const f of readdirSync(join(__dirname, '..', 'fixtures', 'mlcm')).filter(f => f.endsWith('.json'))) {
  fixtures.push(JSON.parse(readFileSync(join(__dirname, '..', 'fixtures', 'mlcm', f), 'utf8')));
}
for (const m of models.filter(m => m.routes && m.routes.length > 0)) {
  fixtures.push(m);
}
for (const f of readdirSync(join(__dirname, '..', 'fixtures', 'metro')).filter(f => f.endsWith('.json'))) {
  fixtures.push(JSON.parse(readFileSync(join(__dirname, '..', 'fixtures', 'metro', f), 'utf8')));
}

const port = parseInt(process.argv[2] || '9950');

const HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>FlowV2 Parameter Explorer</title>
<style>
body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f5f5; display: flex; flex-direction: column; height: 100vh; }
.controls { padding: 12px 16px; background: #fff; border-bottom: 1px solid #ddd; display: flex; flex-wrap: wrap; gap: 16px; align-items: center; }
.control { display: flex; align-items: center; gap: 6px; font-size: 12px; }
.control label { color: #666; min-width: 80px; }
.control input[type=range] { width: 120px; }
.control select { padding: 2px 6px; font-size: 12px; }
.control .val { color: #333; font-weight: 600; min-width: 30px; }
.viewport { flex: 1; overflow: auto; padding: 16px; }
.viewport svg { background: white; box-shadow: 0 1px 4px rgba(0,0,0,0.1); border-radius: 4px; }
.tooltip { position: fixed; background: #333; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; pointer-events: none; z-index: 100; display: none; }
</style>
</head>
<body>
<div class="controls">
  <div class="control">
    <label>Fixture:</label>
    <select id="fixture">${fixtures.map((f, i) => `<option value="${i}">${f.id} (${f.dag.nodes.length}n, ${f.routes?.length || 0}r)</option>`).join('')}</select>
  </div>
  <div class="control"><label>Scale:</label><input type="range" id="scale" min="0.5" max="2.5" step="0.1" value="1.5"><span class="val" id="scale-val">1.5</span></div>
  <div class="control"><label>Layer Sp:</label><input type="range" id="layerSpacing" min="20" max="100" step="5" value="55"><span class="val" id="layerSpacing-val">55</span></div>
  <div class="control"><label>Dot Sp:</label><input type="range" id="dotSpacing" min="4" max="30" step="1" value="12"><span class="val" id="dotSpacing-val">12</span></div>
  <div class="control"><label>Track Spread:</label><input type="range" id="trackSpread" min="0" max="8" step="0.5" value="0"><span class="val" id="trackSpread-val">0</span></div>
  <div class="control"><label>Corner R:</label><input type="range" id="cornerRadius" min="2" max="20" step="1" value="6"><span class="val" id="cornerRadius-val">6</span></div>
</div>
<div class="viewport" id="viewport"></div>
<div class="tooltip" id="tooltip"></div>

<script>
const params = ['scale','layerSpacing','dotSpacing','trackSpread','cornerRadius'];
const fixture = document.getElementById('fixture');

async function render() {
  const opts = {};
  for (const p of params) {
    const el = document.getElementById(p);
    opts[p] = parseFloat(el.value);
    document.getElementById(p + '-val').textContent = el.value;
  }
  opts.fixtureIdx = parseInt(fixture.value);

  const res = await fetch('/render?' + new URLSearchParams(opts));
  document.getElementById('viewport').innerHTML = await res.text();
}

for (const p of params) document.getElementById(p).addEventListener('input', render);
fixture.addEventListener('change', render);

// Tooltip
const tip = document.getElementById('tooltip');
document.addEventListener('mouseover', e => {
  const node = e.target.closest('[data-node-id]');
  const route = e.target.closest('[data-route-id]');
  if (node) { tip.textContent = node.querySelector('.dm-label')?.textContent || node.getAttribute('data-node-id'); tip.style.display = 'block'; }
  else if (route) { tip.textContent = route.getAttribute('data-route-id') + ': ' + (route.getAttribute('data-route-nodes') || ''); tip.style.display = 'block'; }
});
document.addEventListener('mousemove', e => { if (tip.style.display === 'block') { tip.style.left = (e.clientX+12)+'px'; tip.style.top = (e.clientY-8)+'px'; } });
document.addEventListener('mouseout', e => { if (e.target.closest('[data-node-id]') || e.target.closest('[data-route-id]')) tip.style.display = 'none'; });

render();
</script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html' });
    return res.end(HTML);
  }

  if (url.pathname === '/render') {
    const idx = parseInt(url.searchParams.get('fixtureIdx') || '0');
    const f = fixtures[idx] || fixtures[0];

    const opts = {
      routes: f.routes,
      theme: f.theme || 'cream',
      scale: parseFloat(url.searchParams.get('scale') || '1.5'),
      layerSpacing: parseFloat(url.searchParams.get('layerSpacing') || '55'),
      dotSpacing: parseFloat(url.searchParams.get('dotSpacing') || '12'),
      trackSpread: parseFloat(url.searchParams.get('trackSpread') || '0'),
      cornerRadius: parseFloat(url.searchParams.get('cornerRadius') || '6'),
    };

    try {
      const layout = layoutFlowV2(f.dag, opts);
      const svg = renderFlowV2(f.dag, layout, opts);
      res.writeHead(200, { 'content-type': 'image/svg+xml' });
      res.end(svg);
    } catch (err) {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(`<div style="color:red;padding:20px">${err.message}</div>`);
    }
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(port, () => {
  console.log(`FlowV2 Explorer: http://localhost:${port}/`);
  console.log(`${fixtures.length} fixtures loaded`);
});
