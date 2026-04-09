import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_repel_ne } from '../repel_ne.mjs';

// E_repel_ne — node-edge repulsion. A proxy for label crowding: when a
// rendered edge passes close to a node that is NOT one of that segment's
// endpoints, the label attached to the node will collide with the edge.
// For each (node, segment) pair whose closest-point distance d is below
// threshold, penalty = ((threshold - d) / threshold)^2. Bounded at 1 per
// (node, segment) pair. Coincidence with a segment endpoint is not counted
// (endpoint means the segment legitimately meets the node).

const cfg = { repel_threshold_px: 40 };

function layout(nodes, routes) {
  return { nodes, edges: [], routes, meta: {} };
}

test('repel_ne is zero for an empty layout', () => {
  assert.equal(E_repel_ne(layout([], []), cfg), 0);
});

test('repel_ne is zero when the only node is an endpoint of the only segment', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  assert.equal(E_repel_ne(l, cfg), 0);
});

test('repel_ne is zero when a third node sits far from the segment', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 50, y: 200, layer: 0 },
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  assert.equal(E_repel_ne(l, cfg), 0);
});

test('repel_ne is positive when a node sits close to an unrelated segment interior', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 50, y: 10, layer: 0 }, // 10px above the midpoint of a-b
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  assert.ok(E_repel_ne(l, cfg) > 0);
});

test('repel_ne orders a node pushed away from a segment strictly better than one pressed against it', () => {
  const away = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 50, y: 30, layer: 0 },
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  const close = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 50, y: 3, layer: 0 },
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  assert.ok(E_repel_ne(away, cfg) < E_repel_ne(close, cfg));
});

test('repel_ne returns a finite value when a node sits exactly on a segment interior', () => {
  const l = layout(
    [
      { id: 'a', x: 0, y: 0, layer: 0 },
      { id: 'b', x: 100, y: 0, layer: 1 },
      { id: 'c', x: 50, y: 0, layer: 0 },
    ],
    [
      {
        id: 'r1',
        nodes: ['a', 'b'],
        points: [
          { x: 0, y: 0 },
          { x: 100, y: 0 },
        ],
      },
    ],
  );
  const v = E_repel_ne(l, cfg);
  assert.ok(Number.isFinite(v));
  assert.ok(v > 0);
});
