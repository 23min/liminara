import { test } from 'node:test';
import assert from 'node:assert/strict';

import { layoutWithDagre } from '../dagre.mjs';

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

test('layoutWithDagre returns canonical layout shape', () => {
  const layout = layoutWithDagre(SIMPLE_FIXTURE);

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

test('layoutWithDagre assigns layers consistent with topological order', () => {
  const layout = layoutWithDagre(SIMPLE_FIXTURE);

  const byId = Object.fromEntries(layout.nodes.map((n) => [n.id, n]));
  // a -> b -> c, a -> c: a is root (layer 0), b is middle, c is leaf
  assert.ok(byId.a.layer < byId.b.layer);
  assert.ok(byId.b.layer < byId.c.layer);
});

test('layoutWithDagre is deterministic', () => {
  const a = layoutWithDagre(SIMPLE_FIXTURE);
  const b = layoutWithDagre(SIMPLE_FIXTURE);

  assert.deepStrictEqual(a, b);
});

test('layoutWithDagre handles single-node fixture', () => {
  const layout = layoutWithDagre(SINGLE_NODE);

  assert.equal(layout.nodes.length, 1);
  assert.equal(layout.edges.length, 0);
  assert.equal(layout.nodes[0].id, 'x');
  assert.equal(layout.nodes[0].layer, 0);
});

test('layoutWithDagre returns an error result on failure instead of throwing', () => {
  const badFixture = {
    id: 'bad',
    dag: { nodes: [], edges: [['x', 'y']] },
    theme: 'cream',
    opts: {},
  };

  const result = layoutWithDagre(badFixture);
  // Should return layout or error — not throw
  assert.ok(result !== undefined);
});
