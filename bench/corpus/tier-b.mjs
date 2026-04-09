// Tier B fixture loader.
//
// Tier B is a snapshot of Liminara pack plans (Radar first). Each fixture
// lives as a JSON file in `dag-map/bench/fixtures/tier-b/` with the canonical
// shape `{id, dag: {nodes, edges}, theme, opts}`. Routes are absent — pack
// plans do not pre-assign routes; route extraction is part of the genome.
//
// Fixtures are returned in lexicographic filename order so two calls on the
// same directory produce the same list in the same order.
//
// Missing directory, missing fields, or unparsable JSON all throw an error
// whose message includes the offending path and the reason.

import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_DIR = join(__dirname, '..', 'fixtures', 'tier-b');

export async function loadTierB({ dir = DEFAULT_DIR } = {}) {
  let entries;
  try {
    entries = await readdir(dir);
  } catch (err) {
    throw new Error(`loadTierB: cannot read directory ${dir}: ${err.message}`);
  }

  const files = entries.filter((name) => name.endsWith('.json')).sort();

  const fixtures = [];
  for (const name of files) {
    const path = join(dir, name);
    let raw;
    try {
      raw = await readFile(path, 'utf8');
    } catch (err) {
      throw new Error(`loadTierB: cannot read ${path}: ${err.message}`);
    }
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      throw new Error(`loadTierB: malformed JSON at ${path}: ${err.message}`);
    }
    validateTierBFixture(parsed, path);
    fixtures.push(parsed);
  }

  return fixtures;
}

function validateTierBFixture(f, path) {
  if (!f || typeof f !== 'object') {
    throw new Error(`loadTierB: fixture at ${path} is not an object`);
  }
  if (typeof f.id !== 'string' || f.id.length === 0) {
    throw new Error(`loadTierB: fixture at ${path} is missing a string id`);
  }
  if (!f.dag || typeof f.dag !== 'object') {
    throw new Error(`loadTierB: fixture at ${path} is missing dag`);
  }
  if (!Array.isArray(f.dag.nodes)) {
    throw new Error(`loadTierB: fixture at ${path} dag.nodes is not an array`);
  }
  if (!Array.isArray(f.dag.edges)) {
    throw new Error(`loadTierB: fixture at ${path} dag.edges is not an array`);
  }
  if (f.routes !== undefined) {
    throw new Error(`loadTierB: fixture at ${path} must not carry routes (Tier B has no hand-authored routes)`);
  }
  if (!f.theme) {
    throw new Error(`loadTierB: fixture at ${path} is missing theme`);
  }
  if (!f.opts) {
    throw new Error(`loadTierB: fixture at ${path} is missing opts`);
  }
}
