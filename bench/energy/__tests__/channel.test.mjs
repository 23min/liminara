import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_channel } from '../channel.mjs';

// E_channel — parallel-route separation. When two routes run side by side
// over an x-range, they should have a visual channel between them. If they
// get too close, penalty = (min_gap - actual_gap)^2, summed over overlapping
// near-parallel segment pairs from different routes.

const cfg = { channel_min_separation_px: 20 };

function layout(routes) {
  return { nodes: [], edges: [], routes, meta: {} };
}

function horizRoute(id, y, x0 = 0, x1 = 100) {
  return {
    id,
    nodes: ['a', 'b'],
    points: [
      { x: x0, y },
      { x: x1, y },
    ],
  };
}

test('channel is zero for an empty layout', () => {
  assert.equal(E_channel(layout([]), cfg), 0);
});

test('channel is zero when there is only a single route', () => {
  assert.equal(E_channel(layout([horizRoute('r1', 0)]), cfg), 0);
});

test('channel is zero when two parallel routes are farther apart than the min separation', () => {
  const l = layout([horizRoute('r1', 0), horizRoute('r2', 50)]);
  assert.equal(E_channel(l, cfg), 0);
});

test('channel is positive when two parallel routes are closer than the min separation', () => {
  // gap = 10, min = 20 -> deficit 10, penalty 100 per overlapping pair
  const l = layout([horizRoute('r1', 0), horizRoute('r2', 10)]);
  assert.ok(E_channel(l, cfg) > 0);
});

test('channel is zero when two routes do not overlap in their x-range', () => {
  // r1 covers [0, 40], r2 covers [60, 100], no x-overlap
  const l = layout([horizRoute('r1', 0, 0, 40), horizRoute('r2', 5, 60, 100)]);
  assert.equal(E_channel(l, cfg), 0);
});

test('channel orders well-separated parallel routes strictly better than crowded ones', () => {
  const spacious = layout([horizRoute('r1', 0), horizRoute('r2', 40)]);
  const crowded = layout([horizRoute('r1', 0), horizRoute('r2', 5)]);
  assert.ok(E_channel(spacious, cfg) < E_channel(crowded, cfg));
});
