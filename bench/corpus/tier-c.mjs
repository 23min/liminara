// Tier C fixture loader.
//
// Tier C loads external benchmark graphs (North DAGs, Random DAGs) from
// graphdrawing.org. Archives must be fetched first via fetch-corpora.mjs
// and extracted into bench/corpora/tier-c/{north,random-dag}/.
//
// The loader reads .graphml files from each subdirectory, converts them to
// the bench fixture shape via the GraphML loader, and returns them in a
// stable order (north first, then random-dag, each sorted by filename).

import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadGraphMLDir } from '../loaders/graphml.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_DIR = join(__dirname, '..', 'corpora', 'tier-c');

const SUBDIRS = ['north', 'random-dag'];

export async function loadTierC({ dir = DEFAULT_DIR, onSkip } = {}) {
  const fixtures = [];

  for (const sub of SUBDIRS) {
    const subDir = join(dir, sub);
    if (!existsSync(subDir)) {
      throw new Error(
        `loadTierC: directory ${subDir} not found. Run 'make fetch-corpora' first, then extract the archives.`
      );
    }

    const subFixtures = await loadGraphMLDir(subDir, { onSkip });
    // Prefix IDs to avoid collisions between corpora
    for (const f of subFixtures) {
      f.id = `${sub}/${f.id}`;
      fixtures.push(f);
    }
  }

  return fixtures;
}
