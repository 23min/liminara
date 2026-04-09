import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TINDER_DIR = join(__dirname, '..', 'tinder');

test('tinder UI has index.html, app.mjs, and style.css (no build step)', async () => {
  const html = await readFile(join(TINDER_DIR, 'index.html'), 'utf8');
  const js = await readFile(join(TINDER_DIR, 'app.mjs'), 'utf8');
  const css = await readFile(join(TINDER_DIR, 'style.css'), 'utf8');
  assert.ok(html.length > 0);
  assert.ok(js.length > 0);
  assert.ok(css.length > 0);
});

test('index.html contains required structural elements', async () => {
  const html = await readFile(join(TINDER_DIR, 'index.html'), 'utf8');
  // Arena with pair display
  assert.ok(html.includes('id="pair"'), 'missing #pair container');
  assert.ok(html.includes('id="left-svg"'), 'missing #left-svg');
  assert.ok(html.includes('id="right-svg"'), 'missing #right-svg');
  // No-pair fallback
  assert.ok(html.includes('id="no-pair"'), 'missing #no-pair');
  // Vote buttons
  assert.ok(html.includes('id="btn-left"'), 'missing left vote button');
  assert.ok(html.includes('id="btn-right"'), 'missing right vote button');
  assert.ok(html.includes('id="btn-tie"'), 'missing tie button');
  assert.ok(html.includes('id="btn-skip"'), 'missing skip button');
  // Control buttons
  assert.ok(html.includes('id="btn-pause"'), 'missing pause button');
  assert.ok(html.includes('id="btn-protect-left"'), 'missing protect-left button');
  assert.ok(html.includes('id="btn-kill-left"'), 'missing kill-left button');
  // Footer
  assert.ok(html.includes('id="footer"'), 'missing footer');
  assert.ok(html.includes('id="weights-info"'), 'missing weights display');
  // Script module
  assert.ok(html.includes('type="module"'), 'app.mjs should be loaded as ES module');
});

test('app.mjs is syntactically valid JavaScript', () => {
  // node --check only works for CJS; for ESM we parse via dynamic import attempt.
  // Instead, verify the file parses without syntax errors by checking with node.
  const result = execSync(
    `node --check "${join(TINDER_DIR, 'app.mjs')}" 2>&1 || true`,
    { encoding: 'utf8' },
  );
  // --check on ESM may warn but won't error on syntax. A SyntaxError means broken.
  assert.ok(!result.includes('SyntaxError'), `app.mjs has syntax errors: ${result}`);
});

test('app.mjs registers keyboard shortcuts for ArrowLeft, ArrowRight, ArrowDown, Space', async () => {
  const js = await readFile(join(TINDER_DIR, 'app.mjs'), 'utf8');
  assert.ok(js.includes("'ArrowLeft'"), 'missing ArrowLeft handler');
  assert.ok(js.includes("'ArrowRight'"), 'missing ArrowRight handler');
  assert.ok(js.includes("'ArrowDown'"), 'missing ArrowDown handler');
  assert.ok(js.includes("' '"), 'missing Space handler');
});

test('app.mjs calls GET /state endpoint', async () => {
  const js = await readFile(join(TINDER_DIR, 'app.mjs'), 'utf8');
  assert.ok(js.includes('/state'), 'app.mjs should fetch /state');
});

test('app.mjs calls POST /vote and POST /control endpoints', async () => {
  const js = await readFile(join(TINDER_DIR, 'app.mjs'), 'utf8');
  assert.ok(js.includes('/vote'), 'app.mjs should post to /vote');
  assert.ok(js.includes('/control'), 'app.mjs should post to /control');
});
