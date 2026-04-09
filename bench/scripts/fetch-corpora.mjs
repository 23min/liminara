#!/usr/bin/env node
// fetch-corpora.mjs — downloads North DAGs and Random DAGs GraphML archives
// from graphdrawing.org into bench/corpora/tier-c/. Idempotent: skips
// download if archive is already present. Fails gracefully on network error.

import { existsSync } from 'node:fs';
import { mkdir, rename, unlink, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TIER_C_DIR = join(__dirname, '..', 'corpora', 'tier-c');

const CORPORA = [
  {
    name: 'north',
    url: 'http://www.graphdrawing.org/data/north-graphml.tgz',
    archive: 'north-graphml.tgz',
  },
  {
    name: 'random-dag',
    url: 'http://www.graphdrawing.org/data/random-dag-graphml.tgz',
    archive: 'random-dag-graphml.tgz',
  },
];

export { CORPORA, TIER_C_DIR };

async function defaultDownload(url, destPath) {
  const { pipeline } = await import('node:stream/promises');
  const { createWriteStream } = await import('node:fs');
  const { Readable } = await import('node:stream');

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }
  const body = Readable.fromWeb(response.body);
  await pipeline(body, createWriteStream(destPath));
}

export async function fetchCorpora({ dir = TIER_C_DIR, download = defaultDownload } = {}) {
  await mkdir(dir, { recursive: true });

  const results = [];

  for (const corpus of CORPORA) {
    const archivePath = join(dir, corpus.archive);

    if (existsSync(archivePath)) {
      results.push({ name: corpus.name, status: 'cached', path: archivePath });
      continue;
    }

    const tmpPath = archivePath + '.tmp';
    try {
      await download(corpus.url, tmpPath);
      await rename(tmpPath, archivePath);
      results.push({ name: corpus.name, status: 'downloaded', path: archivePath });
    } catch (err) {
      try { await unlink(tmpPath); } catch (_) { /* ignore */ }
      results.push({ name: corpus.name, status: 'error', error: err.message });
    }
  }

  return results;
}

// CLI entry point
const isMain = process.argv[1] && (
  process.argv[1].endsWith('fetch-corpora.mjs') ||
  process.argv[1].endsWith('fetch-corpora.js')
);
if (isMain) {
  fetchCorpora().then((results) => {
    for (const r of results) {
      if (r.status === 'cached') console.log(`✓ ${r.name}: cached`);
      else if (r.status === 'downloaded') console.log(`✓ ${r.name}: downloaded`);
      else console.error(`✗ ${r.name}: ${r.error}`);
    }
    const errors = results.filter((r) => r.status === 'error');
    if (errors.length > 0) {
      console.error(`\n${errors.length} corpus download(s) failed.`);
      process.exit(1);
    }
    console.log('\nAll corpora ready.');
  });
}
