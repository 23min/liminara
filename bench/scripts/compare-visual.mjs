#!/usr/bin/env node
// compare-visual.mjs — generates an HTML page showing dag-map, dagre, and ELK
// layouts side by side for visual comparison.

import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { dagMap } from '../../dag-map/src/index.js';
import { layoutWithDagre } from '../adapters/dagre.mjs';
import { layoutWithELK } from '../adapters/elk.mjs';
import { loadGraphMLDir } from '../loaders/graphml.mjs';
import { models } from '../../dag-map/test/models.js';
import { toEvaluatorGenome } from '../genome/genome.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Simple SVG renderer for dagre/ELK layouts (node positions + edges)
function renderSimpleSVG(layout, title) {
  if (layout.error) return `<svg width="200" height="60"><text x="10" y="30" font-size="14" fill="red">Error: ${layout.error}</text></svg>`;

  const nodes = layout.nodes;
  const edges = layout.edges;
  const routes = layout.routes || [];

  if (nodes.length === 0) return `<svg width="200" height="60"><text x="10" y="30" font-size="14">No nodes</text></svg>`;

  // Compute bounds
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const n of nodes) {
    if (n.x < minX) minX = n.x;
    if (n.y < minY) minY = n.y;
    if (n.x > maxX) maxX = n.x;
    if (n.y > maxY) maxY = n.y;
  }

  const pad = 40;
  const w = Math.max(200, maxX - minX + pad * 2);
  const h = Math.max(100, maxY - minY + pad * 2);
  const ox = pad - minX;
  const oy = pad - minY;

  const lines = [];
  lines.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`);
  lines.push(`<rect width="${w}" height="${h}" fill="#fdf6e3" rx="4"/>`);
  lines.push(`<text x="8" y="16" font-size="11" fill="#666" font-family="sans-serif">${title}</text>`);

  // Draw route polylines (if available, for bend visibility)
  for (const route of routes) {
    if (route.points && route.points.length >= 2) {
      const d = route.points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x + ox} ${p.y + oy}`).join(' ');
      lines.push(`<path d="${d}" fill="none" stroke="#268bd2" stroke-width="1.5" stroke-opacity="0.5"/>`);
    }
  }

  // Draw edges as straight lines (fallback if no route points)
  const posMap = new Map(nodes.map(n => [n.id, n]));
  for (const [s, t] of edges) {
    const a = posMap.get(s);
    const b = posMap.get(t);
    if (!a || !b) continue;
    // Check if this edge has a route with points
    const hasRoute = routes.some(r => r.nodes && r.nodes[0] === s && r.nodes[1] === t && r.points?.length >= 2);
    if (!hasRoute) {
      lines.push(`<line x1="${a.x + ox}" y1="${a.y + oy}" x2="${b.x + ox}" y2="${b.y + oy}" stroke="#93a1a1" stroke-width="1" stroke-opacity="0.4"/>`);
    }
    // Arrowhead
    const dx = b.x - a.x, dy = b.y - a.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      const ux = dx / len, uy = dy / len;
      const ax = b.x + ox - ux * 8, ay = b.y + oy - uy * 8;
      lines.push(`<polygon points="${b.x + ox},${b.y + oy} ${ax - uy * 3},${ay + ux * 3} ${ax + uy * 3},${ay - ux * 3}" fill="#93a1a1" fill-opacity="0.5"/>`);
    }
  }

  // Draw nodes
  for (const n of nodes) {
    lines.push(`<circle cx="${n.x + ox}" cy="${n.y + oy}" r="5" fill="#268bd2" stroke="#fff" stroke-width="1"/>`);
    lines.push(`<text x="${n.x + ox}" y="${n.y + oy - 8}" text-anchor="middle" font-size="8" fill="#586e75" font-family="sans-serif">${n.id}</text>`);
  }

  lines.push('</svg>');
  return lines.join('\n');
}

async function main() {
  const outDir = join(__dirname, '..', 'run', 'visual-compare');
  await mkdir(outDir, { recursive: true });

  // Load evolved genome if available
  let evolvedEv = null;
  try {
    const genomes = JSON.parse(await readFile(join(__dirname, '..', 'run', 'run-seed300-g100', 'gen-0099', 'genomes.json'), 'utf8'));
    const scores = JSON.parse(await readFile(join(__dirname, '..', 'run', 'run-seed300-g100', 'gen-0099', 'scores.json'), 'utf8'));
    const valid = scores.individuals.filter(i => !i.rejected).sort((a, b) => a.fitness - b.fitness);
    const best = genomes.find(g => g.id === valid[0].id);
    evolvedEv = toEvaluatorGenome({ tier1: best.genome.tier1, strategy: best.genome.strategy });
    console.log('Loaded evolved elite:', valid[0].id);
  } catch (e) {
    console.log('No evolved elite found, using defaults only');
  }

  // Collect fixtures: some internal models + external DAGs
  const fixtures = [];

  // Internal models (pick a few interesting ones)
  const internalPicks = ['diamond', 'two_cls_diverge', 'procurement', 'loan_approval', 'insurance_claim', 'cicd'];
  for (const model of models) {
    if (internalPicks.includes(model.id)) {
      fixtures.push({ ...model, source: 'tier-a' });
    }
  }

  // External DAGs
  try {
    const north = await loadGraphMLDir(join(__dirname, '..', 'corpora', 'tier-c', 'north'));
    const picks = ['g.10.11', 'g.12.7', 'g.15.4', 'g.20.3', 'g.25.1', 'g.30.1', 'g.40.5'];
    for (const id of picks) {
      const f = north.find(n => n.id === id);
      if (f) fixtures.push({ ...f, source: 'north' });
    }
  } catch (e) {
    console.log('No external corpora:', e.message);
  }

  console.log(`Rendering ${fixtures.length} fixtures × 4 variants...`);

  const pages = [];
  for (const f of fixtures) {
    const baseOpts = { theme: f.theme || 'cream', ...(f.opts || {}) };
    if (f.routes) baseOpts.routes = f.routes;

    // 1. dag-map default
    let dmDefaultSvg;
    try {
      dmDefaultSvg = dagMap(f.dag, baseOpts).svg;
    } catch (e) {
      dmDefaultSvg = `<svg width="200" height="60"><text x="10" y="30" fill="red">Error: ${e.message}</text></svg>`;
    }

    // 2. dag-map evolved
    let dmEvolvedSvg;
    if (evolvedEv) {
      try {
        const evoOpts = { ...baseOpts, ...evolvedEv.render };
        if (evolvedEv.strategies) evoOpts.strategies = evolvedEv.strategies;
        if (evolvedEv.strategyConfig) evoOpts.strategyConfig = evolvedEv.strategyConfig;
        dmEvolvedSvg = dagMap(f.dag, evoOpts).svg;
      } catch (e) {
        dmEvolvedSvg = `<svg width="200" height="60"><text x="10" y="30" fill="red">Error: ${e.message}</text></svg>`;
      }
    }

    // 3. dagre
    const dagreLayout = layoutWithDagre(f);
    const dagreSvg = renderSimpleSVG(dagreLayout, 'dagre');

    // 4. ELK
    const elkLayout = await layoutWithELK(f);
    const elkSvg = renderSimpleSVG(elkLayout, 'ELK');

    pages.push({ id: f.id, source: f.source, nodes: f.dag.nodes.length, edges: f.dag.edges.length,
      dmDefaultSvg, dmEvolvedSvg, dagreSvg, elkSvg });
    console.log('✓', f.id);
  }

  // Build HTML
  const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>DAG Layout Comparison</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 20px; background: #f5f5f5; }
  h1 { font-size: 20px; color: #333; }
  .fixture { margin-bottom: 40px; background: white; padding: 16px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  .fixture h2 { font-size: 15px; color: #555; margin: 0 0 4px 0; }
  .fixture .meta { font-size: 12px; color: #999; margin-bottom: 12px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .cell { border: 1px solid #e0e0e0; border-radius: 4px; padding: 8px; overflow: auto; }
  .cell h3 { font-size: 12px; color: #888; margin: 0 0 8px 0; text-transform: uppercase; letter-spacing: 1px; }
  .cell svg { max-width: 100%; height: auto; }
</style>
</head>
<body>
<h1>DAG Layout Comparison: dag-map vs dagre vs ELK</h1>
${pages.map(p => `
<div class="fixture">
  <h2>${p.id}</h2>
  <div class="meta">${p.source} — ${p.nodes} nodes, ${p.edges} edges</div>
  <div class="grid">
    <div class="cell"><h3>dag-map (default)</h3>${p.dmDefaultSvg}</div>
    <div class="cell"><h3>dag-map (evolved)</h3>${p.dmEvolvedSvg || '<em>no elite</em>'}</div>
    <div class="cell"><h3>dagre</h3>${p.dagreSvg}</div>
    <div class="cell"><h3>ELK</h3>${p.elkSvg}</div>
  </div>
</div>`).join('\n')}
</body>
</html>`;

  const outPath = join(outDir, 'comparison.html');
  await writeFile(outPath, html);
  console.log(`\nComparison page: ${outPath}`);
}

main().catch(e => { console.error(e); process.exit(1); });
