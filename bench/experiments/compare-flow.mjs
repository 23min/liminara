#!/usr/bin/env node
// compare-flow.mjs — Mode 2 (layoutFlow) comparison page.
// Shows Flow variants side by side with one Mode 1 reference.

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { dagMap } from '../../dag-map/src/index.js';
import { layoutMetro } from '../../dag-map/src/layout-metro.js';
import { layoutFlow } from '../../dag-map/src/layout-flow.js';
import { renderSVG } from '../../dag-map/src/render.js';
import { loadExperimentFixtures } from './fixtures.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Flow variants to compare
const FLOW_VERSIONS = {
  'flow-default': {
    label: 'Flow Default',
    opts: { direction: 'ltr' },
  },
  'flow-ttb': {
    label: 'Flow TTB',
    opts: { direction: 'ttb' },
  },
  'flow-compact': {
    label: 'Flow Compact',
    opts: { direction: 'ltr', scale: 0.9, columnSpacing: 50, layerSpacing: 35, dotSpacing: 10 },
  },
  'flow-wide': {
    label: 'Flow Wide',
    opts: { direction: 'ltr', scale: 1.2, columnSpacing: 100, layerSpacing: 50 },
  },
};

async function main() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outDir = join(__dirname, 'results', 'flow-' + timestamp);
  await mkdir(outDir, { recursive: true });

  const allFixtures = await loadExperimentFixtures();
  // Only fixtures with provided routes (Flow requires them)
  const fixtures = allFixtures.filter(f => f.routes && f.routes.length > 0);

  const versionNames = Object.keys(FLOW_VERSIONS);
  const allVersionNames = ['metro-ref', ...versionNames];

  console.log(`Comparing ${versionNames.length} Flow variants + Metro reference × ${fixtures.length} fixtures`);

  const results = [];

  for (const f of fixtures) {
    const entry = { id: f.id, source: f.source, nodes: f.dag.nodes.length, edges: f.dag.edges.length, routes: f.routes.length, versions: {} };

    // Mode 1 reference (GA Evolved)
    try {
      const metroOpts = {
        theme: f.theme || 'cream', ...(f.opts || {}), routes: f.routes, labelSize: 1.2,
        strategies: { orderNodes: 'hybrid', reduceCrossings: 'none', assignLanes: 'ordered', positionX: 'compact' },
        mainSpacing: 26, subSpacing: 40,
      };
      entry.versions['metro-ref'] = { svg: dagMap(f.dag, metroOpts).svg, label: 'Metro (Mode 1)' };
    } catch (err) {
      entry.versions['metro-ref'] = { svg: `<svg width="200" height="60"><text x="10" y="30" fill="red">${err.message.slice(0, 50)}</text></svg>`, label: 'Metro (Mode 1)' };
    }

    // Flow variants
    for (const [vName, version] of Object.entries(FLOW_VERSIONS)) {
      try {
        const opts = { routes: f.routes, theme: f.theme || 'cream', ...version.opts };
        const layout = layoutFlow(f.dag, opts);
        const svg = renderSVG(f.dag, layout, opts);
        entry.versions[vName] = { svg, label: version.label,
          info: `${layout.width?.toFixed(0)}×${layout.height?.toFixed(0)}px` };
      } catch (err) {
        entry.versions[vName] = { svg: `<svg width="200" height="60"><text x="10" y="30" fill="red">${err.message.slice(0, 50)}</text></svg>`, label: version.label };
      }
    }

    console.log('✓', f.id, `(${f.routes.length} routes)`);
    results.push(entry);
  }

  // Build HTML
  let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Flow Comparison ${timestamp}</title>
<style>
body { font-family: -apple-system, sans-serif; margin: 0; padding: 16px; background: #f0f0f0; }
h1 { font-size: 20px; margin-bottom: 4px; }
.meta { font-size: 12px; color: #666; margin-bottom: 16px; }
.fixture { background: white; margin-bottom: 24px; padding: 12px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.fixture h2 { font-size: 14px; color: #333; margin: 0 0 2px; }
.fixture .info { font-size: 11px; color: #999; margin-bottom: 8px; }
.grid { display: grid; grid-template-columns: repeat(${allVersionNames.length}, 1fr); gap: 8px; }
.cell { border: 1px solid #e0e0e0; border-radius: 4px; padding: 6px; overflow: auto; cursor: pointer; max-height: 400px; }
.cell:hover { border-color: #4a90d9; }
.cell h3 { font-size: 11px; color: #666; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.cell .size { font-size: 9px; color: #aaa; }
.cell svg { max-width: 100%; height: auto; display: block; }
.modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; cursor: pointer; overflow: auto; }
.modal.open { display: flex; align-items: flex-start; justify-content: center; padding: 20px; }
.modal-content { background: white; border-radius: 8px; padding: 16px; overflow: auto; max-width: 95vw; }
.modal-content h3 { margin: 0 0 8px; font-size: 14px; color: #333; }
.modal-content svg { display: block; max-width: none; width: auto; height: auto; }
.tooltip { position: fixed; background: #333; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; pointer-events: none; z-index: 2000; display: none; }
</style></head><body>

<div class="modal" id="modal" onclick="this.classList.remove('open')">
  <div class="modal-content" onclick="event.stopPropagation()">
    <h3 id="modal-title"></h3>
    <div id="modal-svg"></div>
  </div>
</div>
<div class="tooltip" id="tooltip"></div>

<script>
function showModal(cell) {
  const title = cell.querySelector('h3')?.textContent || '';
  const fixture = cell.closest('.fixture')?.querySelector('h2')?.textContent || '';
  document.getElementById('modal-title').textContent = fixture + ' — ' + title;
  document.getElementById('modal-svg').innerHTML = cell.querySelector('svg')?.outerHTML || '';
  document.getElementById('modal').classList.add('open');
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') document.getElementById('modal').classList.remove('open'); });
const tip = document.getElementById('tooltip');
document.addEventListener('mouseover', e => {
  const g = e.target.closest('[data-node-id]');
  if (g) { tip.textContent = g.querySelector('.dm-label')?.textContent || g.getAttribute('data-node-id'); tip.style.display = 'block'; }
});
document.addEventListener('mousemove', e => { if (tip.style.display === 'block') { tip.style.left = (e.clientX+12)+'px'; tip.style.top = (e.clientY-8)+'px'; } });
document.addEventListener('mouseout', e => { if (e.target.closest('[data-node-id]')) tip.style.display = 'none'; });
</script>

<h1>Mode 2: Flow Layout Comparison</h1>
<div class="meta">${versionNames.length} Flow variants + Metro reference × ${fixtures.length} fixtures</div>`;

  for (const r of results) {
    html += `<div class="fixture"><h2>${r.id}</h2><div class="info">${r.source} — ${r.nodes} nodes, ${r.edges} edges, ${r.routes} routes</div><div class="grid">`;
    for (const vName of allVersionNames) {
      const v = r.versions[vName];
      if (!v) continue;
      html += `<div class="cell" onclick="showModal(this)"><h3>${v.label || vName}</h3>${v.svg}`;
      if (v.info) html += `<div class="size">${v.info}</div>`;
      html += `</div>`;
    }
    html += `</div></div>`;
  }

  html += `</body></html>`;
  await writeFile(join(outDir, 'comparison.html'), html);
  console.log(`\nResults: ${outDir}/comparison.html`);
}

main().catch(e => { console.error(e); process.exit(1); });
