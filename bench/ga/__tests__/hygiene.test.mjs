// AC8 — Steering does not bypass selection.
// The GA's core selection/breeding modules must not reference the Tinder
// vote log or the weight refit. Steering influences weights (which flow
// into scoreChild), not the selection operators themselves.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const GA_DIR = join(__dirname, '..');

const GUARDED_FILES = ['operators.mjs', 'generation.mjs', 'islands.mjs'];
const FORBIDDEN = ['tinder.jsonl', 'refit', 'votes.mjs', 'refitWeights'];

for (const file of GUARDED_FILES) {
  test(`${file} contains no reference to tinder voting or refit`, async () => {
    const src = await readFile(join(GA_DIR, file), 'utf8');
    for (const term of FORBIDDEN) {
      assert.ok(
        !src.includes(term),
        `${file} must not reference "${term}" — steering flows through weights, not selection operators`,
      );
    }
  });
}
