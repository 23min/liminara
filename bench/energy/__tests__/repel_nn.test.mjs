import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_repel_nn } from '../repel_nn.mjs';

// E_repel_nn — node-node repulsion. For every pair of nodes whose distance
// is below `repel_threshold_px`, we add ((threshold - d) / threshold)^2.
// That is 0 at d = threshold, 1 at d = 0, and strictly monotone in d over
// the active range. Bounded at 1 per pair so the term's total is bounded
// at n*(n-1)/2 for any layout.

const cfg = { repel_threshold_px: 50 };

function layout(nodes) {
  return { nodes, edges: [], routes: [], meta: {} };
}

test('repel_nn is zero for an empty layout', () => {
  assert.equal(E_repel_nn(layout([]), cfg), 0);
});

test('repel_nn is zero when every node pair is farther than the threshold', () => {
  const l = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 100, y: 0, layer: 1 },
    { id: 'c', x: 200, y: 0, layer: 2 },
  ]);
  assert.equal(E_repel_nn(l, cfg), 0);
});

test('repel_nn is zero at exactly the threshold distance', () => {
  const l = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 50, y: 0, layer: 1 },
  ]);
  assert.equal(E_repel_nn(l, cfg), 0);
});

test('repel_nn is positive when two nodes are closer than the threshold', () => {
  const l = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 25, y: 0, layer: 1 },
  ]);
  // ((50 - 25) / 50)^2 = 0.25
  assert.equal(E_repel_nn(l, cfg), 0.25);
});

test('repel_nn saturates at exactly 1 per pair for coincident nodes', () => {
  // Two nodes at the same point contribute the bounded maximum per pair.
  const l = layout([
    { id: 'a', x: 5, y: 5, layer: 0 },
    { id: 'b', x: 5, y: 5, layer: 1 },
  ]);
  assert.equal(E_repel_nn(l, cfg), 1);
});

test('repel_nn is monotone: closer pairs pay more than farther pairs below threshold', () => {
  const closer = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 10, y: 0, layer: 1 },
  ]);
  const farther = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 30, y: 0, layer: 1 },
  ]);
  assert.ok(E_repel_nn(closer, cfg) > E_repel_nn(farther, cfg));
});

test('repel_nn orders a spaced-out layout strictly better than a crowded one', () => {
  const spaced = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 200, y: 0, layer: 1 },
    { id: 'c', x: 400, y: 0, layer: 2 },
  ]);
  const crowded = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 10, y: 0, layer: 1 },
    { id: 'c', x: 20, y: 0, layer: 2 },
  ]);
  assert.ok(E_repel_nn(spaced, cfg) < E_repel_nn(crowded, cfg));
});

test('repel_nn is bounded at n*(n-1)/2 for any layout', () => {
  // Three coincident nodes => 3 pairs, each saturated at 1 => total 3.
  const l = layout([
    { id: 'a', x: 5, y: 5, layer: 0 },
    { id: 'b', x: 5, y: 5, layer: 1 },
    { id: 'c', x: 5, y: 5, layer: 2 },
  ]);
  assert.equal(E_repel_nn(l, cfg), 3);
});
