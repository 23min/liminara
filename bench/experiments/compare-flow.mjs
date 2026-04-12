#!/usr/bin/env node
// compare-flow.mjs — Mode 2 (swimlane) comparison page.
// Shows swimlane variants built on layoutMetro + legacy layoutFlow reference.

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { dagMap } from '../../dag-map/src/index.js';
import { layoutMetro } from '../../dag-map/src/layout-metro.js';
import { layoutFlow } from '../../dag-map/src/layout-flow.js';
import { layoutFlowV2 } from '../../dag-map/src/layout-flow-v2.js';
import { renderFlowV2 } from '../../dag-map/src/render-flow-v2.js';
import { renderSVG } from '../../dag-map/src/render.js';
import { loadExperimentFixtures } from './fixtures.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const VERSIONS = {
  'metro-ref': {
    label: 'Metro (Mode 1)',
    engine: 'metro',
    opts: {
      strategies: { orderNodes: 'hybrid', reduceCrossings: 'none', assignLanes: 'ordered', positionX: 'compact' },
      mainSpacing: 26, subSpacing: 40,
    },
  },
  'flowv2-default': {
    label: 'FlowV2',
    engine: 'flowv2',
    opts: { laneHeight: 70, layerSpacing: 55 },
  },
  'flowv2-compact': {
    label: 'FlowV2 Compact',
    engine: 'flowv2',
    opts: { laneHeight: 50, layerSpacing: 40, scale: 1.2 },
  },
  'flowv2-wide': {
    label: 'FlowV2 Wide',
    engine: 'flowv2',
    opts: { laneHeight: 90, layerSpacing: 65 },
  },
  // Flow Legacy removed — render.js changes for Mode 1 (pills, track
  // offsets) broke layoutFlow's rendering. FlowV2 replaces it.
};

async function main() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outDir = join(__dirname, 'results', 'flow-' + timestamp);
  await mkdir(outDir, { recursive: true });

  const allFixtures = await loadExperimentFixtures();
  const fixtures = allFixtures.filter(f => f.routes && f.routes.length > 0);

  const versionNames = Object.keys(VERSIONS);

  console.log(`Comparing ${versionNames.length} versions × ${fixtures.length} fixtures`);

  const results = [];

  for (const f of fixtures) {
    const entry = { id: f.id, source: f.source, nodes: f.dag.nodes.length, edges: f.dag.edges.length, routes: f.routes.length, versions: {} };

    for (const [vName, version] of Object.entries(VERSIONS)) {
      try {
        const baseOpts = { theme: f.theme || 'cream', ...(f.opts || {}), routes: f.routes, labelSize: 1.2 };
        const mergedOpts = { ...baseOpts, ...version.opts };
        if (version.opts?.strategies) mergedOpts.strategies = { ...version.opts.strategies };
        if (version.opts?.strategyConfig) mergedOpts.strategyConfig = { ...version.opts.strategyConfig };

        let svg;
        if (version.engine === 'flow') {
          const layout = layoutFlow(f.dag, mergedOpts);
          svg = renderSVG(f.dag, layout, mergedOpts);
        } else if (version.engine === 'flowv2') {
          const layout = layoutFlowV2(f.dag, mergedOpts);
          svg = renderFlowV2(f.dag, layout, mergedOpts);
        } else {
          svg = dagMap(f.dag, mergedOpts).svg;
        }
        entry.versions[vName] = { svg, label: version.label };
      } catch (err) {
        entry.versions[vName] = { svg: `<svg width="200" height="60"><text x="10" y="30" fill="red">${err.message.slice(0, 60)}</text></svg>`, label: version.label };
      }
    }

    console.log('✓', f.id, `(${f.routes.length} routes)`);
    results.push(entry);
  }

  // Build HTML
  let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Swimlane Comparison ${timestamp}</title>
<style>
body { font-family: -apple-system, sans-serif; margin: 0; padding: 16px; background: #f0f0f0; }
h1 { font-size: 20px; margin-bottom: 4px; }
.meta { font-size: 12px; color: #666; margin-bottom: 16px; }
.fixture { background: white; margin-bottom: 24px; padding: 12px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.fixture h2 { font-size: 14px; color: #333; margin: 0 0 2px; }
.fixture .info { font-size: 11px; color: #999; margin-bottom: 8px; }
.grid { display: grid; grid-template-columns: repeat(${versionNames.length}, 1fr); gap: 8px; }
.cell { border: 1px solid #e0e0e0; border-radius: 4px; padding: 6px; overflow: auto; cursor: pointer; max-height: 500px; }
.cell:hover { border-color: #4a90d9; }
.cell h3 { font-size: 11px; color: #666; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.cell svg { max-width: 100%; height: auto; display: block; }
.modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; cursor: pointer; overflow: auto; }
.modal.open { display: flex; align-items: flex-start; justify-content: center; padding: 20px; }
.modal-content { background: white; border-radius: 8px; padding: 16px; overflow: auto; max-width: 95vw; max-height: 95vh; }
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

<h1>Mode 2: Swimlane Layout Comparison</h1>
<div class="meta">${versionNames.length} versions × ${fixtures.length} fixtures | Swimlane = each route gets its own Y lane</div>`;

  for (const r of results) {
    html += `<div class="fixture"><h2>${r.id}</h2><div class="info">${r.source} — ${r.nodes} nodes, ${r.edges} edges, ${r.routes} routes</div><div class="grid">`;
    for (const vName of versionNames) {
      const v = r.versions[vName];
      if (!v) continue;
      html += `<div class="cell" onclick="showModal(this)"><h3>${v.label || vName}</h3>${v.svg}</div>`;
    }
    html += `</div></div>`;
  }

  html += `</body></html>`;
  await writeFile(join(outDir, 'comparison.html'), html);
  console.log(`\nResults: ${outDir}/comparison.html`);
}

main().catch(e => { console.error(e); process.exit(1); });
