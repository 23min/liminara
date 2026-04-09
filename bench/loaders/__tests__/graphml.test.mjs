import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseGraphML, loadGraphMLDir } from '../graphml.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SAMPLE_DIR = join(__dirname, '..', '..', 'test', 'fixtures-tier-c-sample');

// --- parseGraphML unit tests ---

test('parseGraphML converts a DAG GraphML to fixture shape', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="g0" edgedefault="directed">
    <node id="n0"/>
    <node id="n1"/>
    <node id="n2"/>
    <edge source="n0" target="n1"/>
    <edge source="n1" target="n2"/>
  </graph>
</graphml>`;

  const result = parseGraphML(xml, 'test-graph');

  assert.equal(result.id, 'test-graph');
  assert.deepStrictEqual(result.dag.nodes, [
    { id: 'n0', label: 'n0' },
    { id: 'n1', label: 'n1' },
    { id: 'n2', label: 'n2' },
  ]);
  assert.deepStrictEqual(result.dag.edges, [['n0', 'n1'], ['n1', 'n2']]);
  assert.equal(result.theme, 'cream');
  assert.deepStrictEqual(result.opts, {});
  assert.equal(result.routes, undefined);
});

test('parseGraphML returns null for cyclic graphs with a reason', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="cyc" edgedefault="directed">
    <node id="x"/>
    <node id="y"/>
    <node id="z"/>
    <edge source="x" target="y"/>
    <edge source="y" target="z"/>
    <edge source="z" target="x"/>
  </graph>
</graphml>`;

  const result = parseGraphML(xml, 'cyclic');

  assert.equal(result, null);
});

test('parseGraphML handles undirected graphs as non-DAGs', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="u1" edgedefault="undirected">
    <node id="a"/>
    <node id="b"/>
    <edge source="a" target="b"/>
  </graph>
</graphml>`;

  const result = parseGraphML(xml, 'undirected');
  assert.equal(result, null);
});

test('parseGraphML handles single-node graph', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="single" edgedefault="directed">
    <node id="solo"/>
  </graph>
</graphml>`;

  const result = parseGraphML(xml, 'single');
  assert.equal(result.id, 'single');
  assert.equal(result.dag.nodes.length, 1);
  assert.equal(result.dag.edges.length, 0);
});

test('parseGraphML handles empty graph', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns">
  <graph id="empty" edgedefault="directed">
  </graph>
</graphml>`;

  const result = parseGraphML(xml, 'empty');
  assert.equal(result, null);
});

// --- loadGraphMLDir tests ---

test('loadGraphMLDir loads sample fixtures in deterministic order', async () => {
  const fixtures = await loadGraphMLDir(SAMPLE_DIR);

  // cyclic-sample should be skipped, leaving north-sample and random-dag-sample
  assert.equal(fixtures.length, 2);
  // Lexicographic order: north-sample before random-dag-sample
  assert.equal(fixtures[0].id, 'north-sample');
  assert.equal(fixtures[1].id, 'random-dag-sample');
});

test('loadGraphMLDir produces valid fixture shapes', async () => {
  const fixtures = await loadGraphMLDir(SAMPLE_DIR);

  for (const f of fixtures) {
    assert.equal(typeof f.id, 'string');
    assert.ok(Array.isArray(f.dag.nodes));
    assert.ok(Array.isArray(f.dag.edges));
    assert.equal(f.theme, 'cream');
    assert.deepStrictEqual(f.opts, {});
    assert.equal(f.routes, undefined);
    for (const n of f.dag.nodes) {
      assert.equal(typeof n.id, 'string');
      assert.equal(typeof n.label, 'string');
    }
    for (const e of f.dag.edges) {
      assert.equal(e.length, 2);
    }
  }
});

test('loadGraphMLDir is deterministic — two calls produce same result', async () => {
  const a = await loadGraphMLDir(SAMPLE_DIR);
  const b = await loadGraphMLDir(SAMPLE_DIR);

  assert.deepStrictEqual(a, b);
});

test('loadGraphMLDir returns skipped info', async () => {
  const skipped = [];
  await loadGraphMLDir(SAMPLE_DIR, { onSkip: (id, reason) => skipped.push({ id, reason }) });

  assert.ok(skipped.length >= 1);
  const cyclic = skipped.find((s) => s.id === 'cyclic-sample');
  assert.ok(cyclic, 'cyclic-sample should be skipped');
  assert.ok(cyclic.reason.length > 0);
});
