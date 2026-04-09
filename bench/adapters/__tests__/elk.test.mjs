import { test } from 'node:test';
import assert from 'node:assert/strict';

import { layoutWithELK } from '../elk.mjs';

const SIMPLE_FIXTURE = {
  id: 'simple',
  dag: {
    nodes: [
      { id: 'a', label: 'a' },
      { id: 'b', label: 'b' },
      { id: 'c', label: 'c' },
    ],
    edges: [['a', 'b'], ['a', 'c'], ['b', 'c']],
  },
  theme: 'cream',
  opts: {},
};

const SINGLE_NODE = {
  id: 'single',
  dag: {
    nodes: [{ id: 'x', label: 'x' }],
    edges: [],
  },
  theme: 'cream',
  opts: {},
};

test('layoutWithELK returns canonical layout shape', async () => {
  const layout = await layoutWithELK(SIMPLE_FIXTURE);

  assert.ok(Array.isArray(layout.nodes));
  assert.ok(Array.isArray(layout.edges));
  assert.ok(Array.isArray(layout.routes));
  assert.ok(layout.meta !== undefined);

  assert.equal(layout.nodes.length, 3);
  assert.equal(layout.edges.length, 3);

  for (const n of layout.nodes) {
    assert.equal(typeof n.id, 'string');
    assert.equal(typeof n.x, 'number');
    assert.equal(typeof n.y, 'number');
    assert.equal(typeof n.layer, 'number');
    assert.ok(Number.isFinite(n.x));
    assert.ok(Number.isFinite(n.y));
  }
});

test('layoutWithELK assigns layers consistent with topological order', async () => {
  const layout = await layoutWithELK(SIMPLE_FIXTURE);

  const byId = Object.fromEntries(layout.nodes.map((n) => [n.id, n]));
  assert.ok(byId.a.layer < byId.b.layer);
  assert.ok(byId.b.layer < byId.c.layer);
});

test('layoutWithELK is deterministic', async () => {
  const a = await layoutWithELK(SIMPLE_FIXTURE);
  const b = await layoutWithELK(SIMPLE_FIXTURE);

  assert.deepStrictEqual(a, b);
});

test('layoutWithELK handles single-node fixture', async () => {
  const layout = await layoutWithELK(SINGLE_NODE);

  assert.equal(layout.nodes.length, 1);
  assert.equal(layout.edges.length, 0);
  assert.equal(layout.nodes[0].id, 'x');
  assert.equal(layout.nodes[0].layer, 0);
});

test('layoutWithELK returns error result on failure instead of throwing', async () => {
  const badFixture = {
    id: 'bad',
    dag: { nodes: [], edges: [['x', 'y']] },
    theme: 'cream',
    opts: {},
  };

  const result = await layoutWithELK(badFixture);
  assert.ok(result !== undefined);
});
