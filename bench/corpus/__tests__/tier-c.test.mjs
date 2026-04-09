import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { loadTierC } from '../tier-c.mjs';

const SAMPLE_GRAPHML = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="g" edgedefault="directed">
    <node id="a"/>
    <node id="b"/>
    <edge source="a" target="b"/>
  </graph>
</graphml>`;

const CYCLIC_GRAPHML = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="g" edgedefault="directed">
    <node id="x"/><node id="y"/>
    <edge source="x" target="y"/>
    <edge source="y" target="x"/>
  </graph>
</graphml>`;

async function makeTierCDir() {
  const dir = await mkdtemp(join(tmpdir(), 'tierc-'));
  await mkdir(join(dir, 'north'), { recursive: true });
  await mkdir(join(dir, 'random-dag'), { recursive: true });
  return dir;
}

test('loadTierC loads fixtures from north and random-dag subdirectories', async () => {
  const dir = await makeTierCDir();
  await writeFile(join(dir, 'north', 'g1.graphml'), SAMPLE_GRAPHML);
  await writeFile(join(dir, 'random-dag', 'r1.graphml'), SAMPLE_GRAPHML);

  const fixtures = await loadTierC({ dir });

  assert.equal(fixtures.length, 2);
  assert.equal(fixtures[0].id, 'north/g1');
  assert.equal(fixtures[1].id, 'random-dag/r1');
});

test('loadTierC produces valid fixture shapes', async () => {
  const dir = await makeTierCDir();
  await writeFile(join(dir, 'north', 'g1.graphml'), SAMPLE_GRAPHML);

  const fixtures = await loadTierC({ dir });

  const f = fixtures[0];
  assert.equal(typeof f.id, 'string');
  assert.ok(Array.isArray(f.dag.nodes));
  assert.ok(Array.isArray(f.dag.edges));
  assert.equal(f.theme, 'cream');
  assert.deepStrictEqual(f.opts, {});
  assert.equal(f.routes, undefined);
});

test('loadTierC skips cyclic graphs with onSkip callback', async () => {
  const dir = await makeTierCDir();
  await writeFile(join(dir, 'north', 'cyc.graphml'), CYCLIC_GRAPHML);
  await writeFile(join(dir, 'north', 'dag.graphml'), SAMPLE_GRAPHML);

  const skipped = [];
  const fixtures = await loadTierC({ dir, onSkip: (id, reason) => skipped.push({ id, reason }) });

  assert.equal(fixtures.length, 1);
  assert.equal(fixtures[0].id, 'north/dag');
  assert.equal(skipped.length, 1);
  assert.equal(skipped[0].id, 'cyc');
});

test('loadTierC throws if subdirectory is missing', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'tierc-'));
  // Don't create subdirs

  await assert.rejects(() => loadTierC({ dir }), /not found.*fetch-corpora/);
});

test('loadTierC is deterministic — stable order across runs', async () => {
  const dir = await makeTierCDir();
  await writeFile(join(dir, 'north', 'b.graphml'), SAMPLE_GRAPHML);
  await writeFile(join(dir, 'north', 'a.graphml'), SAMPLE_GRAPHML);
  await writeFile(join(dir, 'random-dag', 'z.graphml'), SAMPLE_GRAPHML);

  const a = await loadTierC({ dir });
  const b = await loadTierC({ dir });

  assert.deepStrictEqual(
    a.map((f) => f.id),
    b.map((f) => f.id),
  );
  // North before random-dag, each sorted alphabetically
  assert.deepStrictEqual(
    a.map((f) => f.id),
    ['north/a', 'north/b', 'random-dag/z'],
  );
});
