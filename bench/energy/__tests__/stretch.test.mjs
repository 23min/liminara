import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_stretch } from '../stretch.mjs';

// Layout shape expected by all energy terms:
//   { nodes: [{id, x, y, layer}], edges: [[from, to]], routes: [...], meta: {...} }

const cfg = { stretch_ideal_factor: 1.0, layer_spacing: 100 };

function layout(nodes, edges) {
  return { nodes, edges, routes: [], meta: {} };
}

test('stretch is zero when every edge length equals the ideal length', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
    ],
    [['a', 'b']],
  );
  assert.equal(E_stretch(l, cfg), 0);
});

test('stretch is zero when edges are shorter than ideal (only over-stretch is penalized)', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 50, y: 0, layer: 1 },
    ],
    [['a', 'b']],
  );
  assert.equal(E_stretch(l, cfg), 0);
});

test('stretch is positive when an edge exceeds its ideal length', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 150, y: 0, layer: 1 },
    ],
    [['a', 'b']],
  );
  // actual=150, ideal=100, over=50, penalty=2500
  assert.equal(E_stretch(l, cfg), 2500);
});

test('stretch orders a tight layout strictly better than a stretched one', () => {
  const tight = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 200, y: 0, layer: 2 },
    ],
    [['a', 'b'], ['b', 'c']],
  );
  const stretched = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 200, y: 0, layer: 1 },
      { id: 'c', x: 400, y: 0, layer: 2 },
    ],
    [['a', 'b'], ['b', 'c']],
  );
  assert.ok(E_stretch(tight, cfg) < E_stretch(stretched, cfg));
});

test('stretch throws for an edge referencing an unknown node', () => {
  const l = layout(
    [{ id: 'a', x: 0, y: 0, layer: 0 }],
    [['a', 'ghost']],
  );
  assert.throws(() => E_stretch(l, cfg), /unknown node/);
});
