import { test } from 'node:test';
import assert from 'node:assert/strict';
import { E_envelope } from '../envelope.mjs';

// E_envelope penalizes deviation of the layout bounding-box aspect ratio
// from a target ratio. `ratio = width / height`. Penalty is (log(ratio) -
// log(target))^2 so a 2x-too-wide layout and a 2x-too-tall layout are
// penalized equally. Log-space keeps the term symmetric around the target.

const cfg = { envelope_target_ratio: 2.0 };

function layout(nodes) {
  return { nodes, edges: [], routes: [], meta: {} };
}

test('envelope is zero for a layout whose aspect ratio exactly matches the target', () => {
  // width 200, height 100, ratio 2.0
  const l = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 200, y: 100, layer: 1 },
  ]);
  assert.equal(E_envelope(l, cfg), 0);
});

test('envelope is zero when the layout has no nodes', () => {
  assert.equal(E_envelope(layout([]), cfg), 0);
});

test('envelope is positive when the layout is too wide vs the target', () => {
  // width 400, height 100, ratio 4.0 vs target 2.0
  const l = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 400, y: 100, layer: 1 },
  ]);
  assert.ok(E_envelope(l, cfg) > 0);
});

test('envelope penalizes too-wide and too-tall symmetrically around the target', () => {
  // too-wide: ratio 4.0 (log ratio = ln(2) above target)
  const tooWide = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 400, y: 100, layer: 1 },
  ]);
  // too-tall: ratio 1.0 (log ratio = ln(2) below target)
  const tooTall = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 100, y: 100, layer: 1 },
  ]);
  const a = E_envelope(tooWide, cfg);
  const b = E_envelope(tooTall, cfg);
  assert.ok(Math.abs(a - b) < 1e-12);
});

test('envelope orders a near-target layout strictly better than a far-target one', () => {
  // ratio 2.2 vs target 2.0
  const near = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 220, y: 100, layer: 1 },
  ]);
  // ratio 8.0 vs target 2.0
  const far = layout([
    { id: 'a', x: 0, y: 0, layer: 0 },
    { id: 'b', x: 800, y: 100, layer: 1 },
  ]);
  assert.ok(E_envelope(near, cfg) < E_envelope(far, cfg));
});

test('envelope handles a degenerate zero-height layout without dividing by zero', () => {
  const l = layout([
    { id: 'a', x: 0, y: 50, layer: 0 },
    { id: 'b', x: 100, y: 50, layer: 1 },
  ]);
  const v = E_envelope(l, cfg);
  assert.ok(Number.isFinite(v));
  assert.ok(v >= 0);
});
