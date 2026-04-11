// fixtures.mjs — standard fixture set for experiment comparison.
//
// Focus on graphs complex enough to differentiate layout strategies.
// Simple graphs (4-6 nodes) produce identical output across all versions.

import { models } from '../../dag-map/test/models.js';
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export async function loadExperimentFixtures() {
  // Internal: only 8+ node models (simple ones don't differentiate)
  const internal = models
    .filter(m => m.dag.nodes.length >= 8)
    .map(m => ({ ...m, source: 'internal' }));

  // External: North DAGs 15-50 nodes, range of densities
  let external = [];
  const northDir = join(__dirname, '..', 'corpora', 'tier-c', 'north');
  if (existsSync(northDir)) {
    const { loadGraphMLDir } = await import('../loaders/graphml.mjs');
    const north = await loadGraphMLDir(northDir);

    const picks = [
      north.find(f => f.id === 'g.15.4'),
      north.find(f => f.id === 'g.15.7'),
      north.find(f => f.id === 'g.20.1'),
      north.find(f => f.id === 'g.20.3'),
      north.find(f => f.id === 'g.20.7'),
      north.find(f => f.id === 'g.25.1'),
      north.find(f => f.id === 'g.25.4'),
      north.find(f => f.id === 'g.30.1'),
      north.find(f => f.id === 'g.30.5'),
      north.find(f => f.id === 'g.40.5'),
      north.find(f => f.id === 'g.40.7'),
    ].filter(Boolean);

    external = picks.map(f => ({ ...f, source: 'north' }));
  }

  return [...internal, ...external];
}
