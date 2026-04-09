import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_monotone } from '../monotone.mjs';

// Layout shape expected by all energy terms:
//   { nodes: [{id, x, y, layer}], edges: [[from, to]], routes: [{id, nodes, points:[{x,y}]}], meta: {...} }
//
// E_monotone penalizes any non-monotone X progression along a rendered route polyline.
// A route that goes 10 -> 20 -> 30 is monotone (penalty 0).
// A route that goes 10 -> 20 -> 15 -> 30 has a backtrack of 5 and pays for it.

const cfg = {};

function layout(routes) {
  return { nodes: [], edges: [], routes, meta: {} };
}

test('monotone is zero for an empty layout', () => {
  assert.equal(E_monotone(layout([]), cfg), 0);
});

test('monotone is zero for a single strictly increasing polyline', () => {
  const l = layout([
    {
      id: 'r1',
      nodes: ['a', 'b', 'c'],
      points: [
        { x: 0, y: 0 },
        { x: 50, y: 10 },
        { x: 100, y: 10 },
      ],
    },
  ]);
  assert.equal(E_monotone(l, cfg), 0);
});

test('monotone is zero when a segment is purely vertical (no x change)', () => {
  // Vertical steps are not backtracks; they neither advance nor retreat in x.
  const l = layout([
    {
      id: 'r1',
      nodes: ['a', 'b', 'c'],
      points: [
        { x: 0, y: 0 },
        { x: 50, y: 0 },
        { x: 50, y: 40 },
        { x: 100, y: 40 },
      ],
    },
  ]);
  assert.equal(E_monotone(l, cfg), 0);
});

test('monotone is positive when a route backtracks in x', () => {
  // 0 -> 50 -> 20 -> 100: backtrack of 30 in the middle segment.
  const l = layout([
    {
      id: 'r1',
      nodes: ['a', 'b', 'c', 'd'],
      points: [
        { x: 0, y: 0 },
        { x: 50, y: 0 },
        { x: 20, y: 0 },
        { x: 100, y: 0 },
      ],
    },
  ]);
  assert.ok(E_monotone(l, cfg) > 0);
});

test('monotone orders a forward-only route strictly better than a backtracking one', () => {
  const forward = layout([
    {
      id: 'r1',
      nodes: ['a', 'b', 'c'],
      points: [
        { x: 0, y: 0 },
        { x: 50, y: 0 },
        { x: 100, y: 0 },
      ],
    },
  ]);
  const backtracking = layout([
    {
      id: 'r1',
      nodes: ['a', 'b', 'c'],
      points: [
        { x: 0, y: 0 },
        { x: 80, y: 0 },
        { x: 40, y: 0 },
        { x: 100, y: 0 },
      ],
    },
  ]);
  assert.ok(E_monotone(forward, cfg) < E_monotone(backtracking, cfg));
});

test('monotone sums backtracks across multiple routes', () => {
  // Two routes, each with a clear backtrack. Penalty should be strictly larger
  // than either route alone.
  const r1 = {
    id: 'r1',
    nodes: ['a', 'b', 'c'],
    points: [
      { x: 0, y: 0 },
      { x: 50, y: 0 },
      { x: 30, y: 0 },
      { x: 100, y: 0 },
    ],
  };
  const r2 = {
    id: 'r2',
    nodes: ['a', 'b', 'c'],
    points: [
      { x: 0, y: 10 },
      { x: 80, y: 10 },
      { x: 60, y: 10 },
      { x: 120, y: 10 },
    ],
  };
  const one = E_monotone(layout([r1]), cfg);
  const two = E_monotone(layout([r1, r2]), cfg);
  assert.ok(two > one);
});
