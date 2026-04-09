import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { existsSync } from 'node:fs';

import { fetchCorpora, CORPORA } from '../fetch-corpora.mjs';

function mockDownload(data = 'archive-data') {
  const calls = [];
  async function download(url, destPath) {
    calls.push({ url, destPath });
    const { writeFile: wf } = await import('node:fs/promises');
    await wf(destPath, data);
  }
  download.calls = calls;
  return download;
}

function failingDownload(message = 'ENOTFOUND') {
  return async () => { throw new Error(message); };
}

test('fetchCorpora downloads archives to target directory', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fetch-'));
  const dl = mockDownload('fake-tgz');
  const results = await fetchCorpora({ dir, download: dl });

  assert.equal(results.length, 2);
  for (const r of results) {
    assert.equal(r.status, 'downloaded');
    assert.ok(existsSync(r.path));
    const content = await readFile(r.path, 'utf8');
    assert.equal(content, 'fake-tgz');
  }
  assert.equal(dl.calls.length, 2);
});

test('fetchCorpora is idempotent — skips existing archives', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fetch-'));
  for (const c of CORPORA) {
    await writeFile(join(dir, c.archive), 'existing');
  }

  const dl = mockDownload();
  const results = await fetchCorpora({ dir, download: dl });

  assert.equal(dl.calls.length, 0);
  assert.equal(results.length, 2);
  for (const r of results) {
    assert.equal(r.status, 'cached');
  }
});

test('fetchCorpora fails gracefully on network error with no partial state', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fetch-'));
  const results = await fetchCorpora({ dir, download: failingDownload('ENOTFOUND') });

  assert.equal(results.length, 2);
  for (const r of results) {
    assert.equal(r.status, 'error');
    assert.match(r.error, /ENOTFOUND/);
  }
  for (const c of CORPORA) {
    assert.ok(!existsSync(join(dir, c.archive)), 'no final archive');
    assert.ok(!existsSync(join(dir, c.archive + '.tmp')), 'no temp file');
  }
});

test('fetchCorpora fails gracefully on HTTP error', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fetch-'));
  const results = await fetchCorpora({ dir, download: failingDownload('HTTP 404 Not Found') });

  for (const r of results) {
    assert.equal(r.status, 'error');
    assert.match(r.error, /404/);
  }
});

test('fetchCorpora creates target directory if missing', async () => {
  const base = await mkdtemp(join(tmpdir(), 'fetch-'));
  const dir = join(base, 'nested', 'tier-c');
  const results = await fetchCorpora({ dir, download: mockDownload() });

  assert.ok(existsSync(dir));
  assert.equal(results.length, 2);
  for (const r of results) assert.equal(r.status, 'downloaded');
});

test('CORPORA has expected entries pointing to graphdrawing.org', () => {
  assert.equal(CORPORA.length, 2);
  assert.equal(CORPORA[0].name, 'north');
  assert.equal(CORPORA[1].name, 'random-dag');
  assert.ok(CORPORA[0].url.includes('graphdrawing.org'));
  assert.ok(CORPORA[1].url.includes('graphdrawing.org'));
});
