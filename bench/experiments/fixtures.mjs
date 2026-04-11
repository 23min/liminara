// fixtures.mjs — standard fixture set for experiment comparison.
//
// Four tiers:
// 1. MLCM fixtures — hand-crafted to test specific metro-line crossing challenges
// 2. Real metro networks — from juliuste/transit-map (with provided routes)
// 3. Internal models — dag-map's own test corpus (with provided routes)
// 4. External North DAGs — pure topology (routes auto-discovered)

import { models } from '../../dag-map/test/models.js';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export async function loadExperimentFixtures() {
  const fixtures = [];

  // Tier 1: MLCM fixtures (hand-crafted, with provided routes)
  const mlcmDir = join(__dirname, '..', 'fixtures', 'mlcm');
  if (existsSync(mlcmDir)) {
    const files = readdirSync(mlcmDir).filter(f => f.endsWith('.json')).sort();
    for (const file of files) {
      const data = JSON.parse(readFileSync(join(mlcmDir, file), 'utf8'));
      fixtures.push({ ...data, source: 'mlcm' });
    }
  }

  // Tier 2: Real metro networks (with provided routes/lines)
  const metroDir = join(__dirname, '..', 'fixtures', 'metro');
  if (existsSync(metroDir)) {
    const files = readdirSync(metroDir).filter(f => f.endsWith('.json')).sort();
    for (const file of files) {
      const data = JSON.parse(readFileSync(join(metroDir, file), 'utf8'));
      fixtures.push({ ...data, source: 'metro' });
    }
  }

  // Tier 3: Internal models (8+ nodes, with routes)
  const internal = models
    .filter(m => m.dag.nodes.length >= 8)
    .map(m => ({ ...m, source: 'internal' }));
  fixtures.push(...internal);

  // Tier 4: External North DAGs (15-50 nodes, routes auto-discovered)
  const northDir = join(__dirname, '..', 'corpora', 'tier-c', 'north');
  if (existsSync(northDir)) {
    const { loadGraphMLDir } = await import('../loaders/graphml.mjs');
    const north = await loadGraphMLDir(northDir);

    const picks = [
      north.find(f => f.id === 'g.20.3'),
      north.find(f => f.id === 'g.30.1'),
      north.find(f => f.id === 'g.40.5'),
    ].filter(Boolean);

    fixtures.push(...picks.map(f => ({ ...f, source: 'north' })));
  }

  return fixtures;
}
