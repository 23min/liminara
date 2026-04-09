// gallery.mjs — renders thumbnail SVGs of elite individuals across a set
// of fixtures. Used by the GA runner to leave an "eyeball gallery" on disk
// after each generation.
//
// The render function is injected for testability. The default uses
// dag-map's `dagMap` convenience (layout + renderSVG in one call) and
// passes the individual's evaluator-projected render options as opts.

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { dagMap } from '../../dag-map/src/index.js';
import { toEvaluatorGenome } from '../genome/genome.mjs';

async function defaultRender(fixture, genome) {
  const ev = toEvaluatorGenome(genome);
  const opts = { ...(fixture.opts ?? {}), ...ev.render };
  if (fixture.theme !== undefined) opts.theme = fixture.theme;
  if (Array.isArray(fixture.routes) && fixture.routes.length > 0) {
    opts.routes = fixture.routes;
  }
  const { svg } = dagMap(fixture.dag, opts);
  return svg;
}

export async function writeGallery({
  galleryDir,
  elite,
  fixtures,
  render = defaultRender,
}) {
  await mkdir(galleryDir, { recursive: true });
  for (const individual of elite) {
    if (individual.rejected) continue;
    const indDir = join(galleryDir, individual.id);
    await mkdir(indDir, { recursive: true });
    for (const f of fixtures) {
      let svg;
      try {
        svg = await render(f, individual.genome);
      } catch (err) {
        svg = `<svg><!-- render failed: ${err.message} --></svg>`;
      }
      await writeFile(join(indDir, `${f.id}.svg`), svg, 'utf8');
    }
  }
}
