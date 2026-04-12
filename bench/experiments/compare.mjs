#!/usr/bin/env node
// compare.mjs — run all versions on all fixtures, produce comparison HTML + metrics.

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { dagMap } from '../../dag-map/src/index.js';
import { layoutMetro } from '../../dag-map/src/layout-metro.js';
import { layoutFlow } from '../../dag-map/src/layout-flow.js';
import { renderSVG } from '../../dag-map/src/render.js';
import { VERSIONS } from './versions.mjs';
import { loadExperimentFixtures } from './fixtures.mjs';
import { computeMetrics } from './metrics.mjs';
import { computeMLCMMetrics } from './mlcm-metrics.mjs';
import { layoutWithDagre } from '../adapters/dagre.mjs';
import { layoutWithELK } from '../adapters/elk.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function renderDagreSVG(layout) {
  if (layout.error || !layout.nodes?.length) return '<svg width="200" height="60"><text x="10" y="30" fill="red">Error</text></svg>';
  const nodes = layout.nodes;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const n of nodes) { if (n.x < minX) minX = n.x; if (n.y < minY) minY = n.y; if (n.x > maxX) maxX = n.x; if (n.y > maxY) maxY = n.y; }
  const pad = 40, w = Math.max(200, maxX - minX + pad * 2), h = Math.max(100, maxY - minY + pad * 2), ox = pad - minX, oy = pad - minY;
  let s = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="${w}" height="${h}" fill="#fdf6e3" rx="4"/>`;
  for (const r of (layout.routes || [])) { if (r.points?.length >= 2) { const d = r.points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x + ox} ${p.y + oy}`).join(' '); s += `<path d="${d}" fill="none" stroke="#268bd2" stroke-width="1.8" stroke-opacity="0.45"/>`; } }
  const posMap = new Map(nodes.map(n => [n.id, n]));
  for (const [a, b] of layout.edges) { const p = posMap.get(a), q = posMap.get(b); if (!p || !q) continue; s += `<line x1="${p.x + ox}" y1="${p.y + oy}" x2="${q.x + ox}" y2="${q.y + oy}" stroke="#93a1a1" stroke-width="1.2" stroke-opacity="0.3"/>`; }
  for (const n of nodes) { s += `<circle cx="${n.x + ox}" cy="${n.y + oy}" r="5" fill="#268bd2" stroke="#fff" stroke-width="1"/><text x="${n.x + ox}" y="${n.y + oy - 8}" text-anchor="middle" font-size="10" fill="#333" font-family="sans-serif">${n.id}</text>`; }
  return s + '</svg>';
}

async function main() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outDir = join(__dirname, 'results', timestamp);
  await mkdir(outDir, { recursive: true });

  const fixtures = await loadExperimentFixtures();
  const versionNames = Object.keys(VERSIONS);

  console.log(`Comparing ${versionNames.length} versions × ${fixtures.length} fixtures`);

  // Run all versions on all fixtures
  const results = []; // { fixture, versions: { vName: { svg, metrics, error } } }

  for (const f of fixtures) {
    const entry = { id: f.id, source: f.source, nodes: f.dag.nodes.length, edges: f.dag.edges.length, versions: {} };

    for (const [vName, version] of Object.entries(VERSIONS)) {
      const baseOpts = { theme: f.theme || 'cream', ...(f.opts || {}), labelSize: 1.2 };
      if (f.routes) baseOpts.routes = f.routes;
      const mergedOpts = { ...baseOpts, ...version.opts };
      if (version.opts?.strategies) mergedOpts.strategies = { ...version.opts.strategies };
      if (version.opts?.strategyConfig) mergedOpts.strategyConfig = { ...version.opts.strategyConfig };

      try {
        const layout = layoutMetro(f.dag, mergedOpts);
        const svg = dagMap(f.dag, mergedOpts).svg;
        const metrics = computeMetrics(f.dag, layout);
        const mlcm = computeMLCMMetrics(f.dag, layout);
        entry.versions[vName] = { svg, metrics: { ...metrics, ...mlcm } };
      } catch (err) {
        entry.versions[vName] = { svg: `<svg width="200" height="60"><text x="10" y="30" fill="red">${err.message.slice(0, 60)}</text></svg>`, metrics: null, error: err.message };
      }
    }

    // Also render dagre for reference
    try {
      const dagreLayout = layoutWithDagre(f);
      entry.versions['dagre'] = { svg: renderDagreSVG(dagreLayout), metrics: null, reference: true };
    } catch (err) {
      entry.versions['dagre'] = { svg: '<svg width="200" height="60"><text x="10" y="30" fill="red">dagre error</text></svg>', metrics: null };
    }

    // Render layoutFlow (Mode 2) for fixtures with provided routes
    if (f.routes && f.routes.length > 0) {
      try {
        const flowOpts = { routes: f.routes, theme: f.theme || 'cream', direction: 'ltr', scale: 1.2 };
        const flowLayout = layoutFlow(f.dag, flowOpts);
        const flowSvg = renderSVG(f.dag, flowLayout, flowOpts);
        entry.versions['flow'] = { svg: flowSvg, metrics: null, reference: true };
      } catch (err) {
        entry.versions['flow'] = { svg: `<svg width="200" height="60"><text x="10" y="30" fill="red">Flow: ${err.message.slice(0, 50)}</text></svg>`, metrics: null };
      }
    }

    console.log('✓', f.id);
    results.push(entry);
  }

  // Build metrics table
  const metricsCSV = ['fixture,source,nodes,edges,version,crossings,overlaps,dirChanges,trunkVar,edgeLen,area'];
  for (const r of results) {
    for (const [vName, v] of Object.entries(r.versions)) {
      if (!v.metrics) continue;
      const m = v.metrics;
      metricsCSV.push(`${r.id},${r.source},${r.nodes},${r.edges},${vName},${m.crossings},${m.overlaps},${m.directionChanges},${m.trunkVariance},${m.totalEdgeLength},${m.area}`);
    }
  }
  await writeFile(join(outDir, 'metrics.csv'), metricsCSV.join('\n'));

  // Build HTML comparison
  const allVersionNames = [...versionNames, 'dagre', 'flow'];
  const colWidth = Math.floor(100 / allVersionNames.length);

  let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Experiment ${timestamp}</title>
<style>
body { font-family: -apple-system, sans-serif; margin: 0; padding: 16px; background: #f0f0f0; }
h1 { font-size: 18px; margin-bottom: 4px; }
.meta { font-size: 12px; color: #666; margin-bottom: 16px; }
.fixture { background: white; margin-bottom: 24px; padding: 12px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.fixture h2 { font-size: 14px; color: #333; margin: 0 0 2px; }
.fixture .info { font-size: 11px; color: #999; margin-bottom: 8px; }
.grid { display: grid; grid-template-columns: repeat(${allVersionNames.length}, 1fr); gap: 8px; }
.cell { border: 1px solid #e0e0e0; border-radius: 4px; padding: 6px; overflow: auto; cursor: pointer; }
.cell:hover { border-color: #4a90d9; }
.cell h3 { font-size: 11px; color: #666; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.cell svg { max-width: 100%; height: auto; display: block; }
.cell .m { font-size: 9px; color: #999; margin-top: 4px; font-family: monospace; }
.cell .m .bad { color: #c00; font-weight: bold; }
.cell .m .good { color: #060; }
table.summary { border-collapse: collapse; width: 100%; margin-top: 16px; font-size: 11px; }
table.summary th, table.summary td { border: 1px solid #ddd; padding: 4px 8px; text-align: right; }
table.summary th { background: #f5f5f5; text-align: left; }
table.summary .best { background: #e6ffe6; font-weight: bold; }
.modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; cursor: pointer; overflow: auto; }
.modal.open { display: flex; align-items: center; justify-content: center; }
.modal-content { background: white; border-radius: 8px; padding: 16px; max-width: 95vw; max-height: 95vh; overflow: auto; }
.modal-content h3 { margin: 0 0 8px; font-size: 14px; color: #333; }
.modal-content svg { display: block; max-width: 100%; height: auto; }
.modal-content .m { font-size: 11px; color: #666; margin-top: 8px; font-family: monospace; }
.tooltip { position: fixed; background: #333; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; pointer-events: none; z-index: 2000; display: none; font-family: sans-serif; }
</style></head><body>

<div class="tooltip" id="tooltip"></div>

<div class="modal" id="modal" onclick="this.classList.remove('open')">
  <div class="modal-content" onclick="event.stopPropagation()">
    <h3 id="modal-title"></h3>
    <div id="modal-svg"></div>
    <div class="m" id="modal-metrics"></div>
  </div>
</div>

<script>
function showModal(cell) {
  const title = cell.querySelector('h3')?.textContent || '';
  const fixture = cell.closest('.fixture')?.querySelector('h2')?.textContent || '';
  const svg = cell.querySelector('svg')?.outerHTML || '';
  const metrics = cell.querySelector('.m')?.innerHTML || '';
  document.getElementById('modal-title').textContent = fixture + ' — ' + title;
  document.getElementById('modal-svg').innerHTML = svg;
  document.getElementById('modal-metrics').innerHTML = metrics;
  document.getElementById('modal').classList.add('open');
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') document.getElementById('modal').classList.remove('open'); });

// Hover tooltips on station nodes
const tip = document.getElementById('tooltip');
document.addEventListener('mouseover', e => {
  const g = e.target.closest('[data-node-id]');
  if (g) {
    const id = g.getAttribute('data-node-id');
    const label = g.querySelector('.dm-label')?.textContent || id;
    tip.textContent = label;
    tip.style.display = 'block';
  }
});
document.addEventListener('mousemove', e => {
  if (tip.style.display === 'block') {
    tip.style.left = (e.clientX + 12) + 'px';
    tip.style.top = (e.clientY - 8) + 'px';
  }
});
document.addEventListener('mouseout', e => {
  const g = e.target.closest('[data-node-id]');
  if (g) tip.style.display = 'none';
});
</script>
<h1>Layout Experiment: ${timestamp}</h1>
<div class="meta">${versionNames.length} versions × ${fixtures.length} fixtures | dagre as reference</div>`;

  // Summary table — MLCM metrics first (what the literature cares about)
  html += `<table class="summary"><tr><th>Version</th><th>Stn Cross</th><th>Btw Cross</th><th>Overlaps</th><th>Bends/Line</th><th>Bundle Coh</th><th>Monotonic</th><th>Trunk Var</th></tr>`;
  for (const vName of versionNames) {
    const ms = results.map(r => r.versions[vName]?.metrics).filter(Boolean);
    if (ms.length === 0) continue;
    const avg = (key) => (ms.reduce((a, m) => a + (m[key] ?? 0), 0) / ms.length).toFixed(1);
    const avgPct = (key) => (ms.reduce((a, m) => a + (m[key] ?? 0), 0) / ms.length * 100).toFixed(0) + '%';
    html += `<tr><td>${VERSIONS[vName].label}</td>`;
    html += `<td>${avg('stationCrossings')}</td>`;
    html += `<td>${avg('betweenCrossings')}</td>`;
    html += `<td>${avg('overlaps')}</td>`;
    html += `<td>${avg('bendsPerLine')}</td>`;
    html += `<td>${avgPct('bundleCoherence')}</td>`;
    html += `<td>${avg('monotonicityViolations')}</td>`;
    html += `<td>${avg('trunkVariance')}</td>`;
    html += `</tr>`;
  }
  html += `</table>`;

  // Per-fixture comparison
  for (const r of results) {
    html += `<div class="fixture"><h2>${r.id}</h2><div class="info">${r.source} — ${r.nodes} nodes, ${r.edges} edges</div><div class="grid">`;
    for (const vName of allVersionNames) {
      const v = r.versions[vName];
      if (!v) continue;
      const label = VERSIONS[vName]?.label || vName;
      html += `<div class="cell" onclick="showModal(this)"><h3>${label}</h3>${v.svg}`;
      if (v.metrics) {
        const m = v.metrics;
        html += `<div class="m">`;
        html += `stn✕: <span class="${(m.stationCrossings??0) > 0 ? 'bad' : 'good'}">${m.stationCrossings??0}</span> `;
        html += `btw✕: <span class="${(m.betweenCrossings??0) > 0 ? 'bad' : ''}">${m.betweenCrossings??0}</span> `;
        html += `overlap: <span class="${m.overlaps > 0 ? 'bad' : ''}">${m.overlaps}</span> `;
        html += `bends: ${(m.bendsPerLine??0).toFixed(1)}/line `;
        html += `trunk: ${m.trunkVariance.toFixed(0)}`;
        html += `</div>`;
      }
      html += `</div>`;
    }
    html += `</div></div>`;
  }

  html += `</body></html>`;
  await writeFile(join(outDir, 'comparison.html'), html);
  await writeFile(join(outDir, 'metrics.json'), JSON.stringify(results.map(r => ({
    id: r.id, source: r.source, nodes: r.nodes, edges: r.edges,
    versions: Object.fromEntries(Object.entries(r.versions).map(([k, v]) => [k, { metrics: v.metrics }])),
  })), null, 2));

  console.log(`\nResults: ${outDir}/`);
  console.log('  comparison.html — visual side-by-side');
  console.log('  metrics.csv — machine-readable');
  console.log('  metrics.json — structured data');
}

main().catch(e => { console.error(e); process.exit(1); });
