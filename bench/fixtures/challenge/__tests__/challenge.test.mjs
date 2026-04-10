import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import { challengeGraphs } from '../index.mjs';
import { evaluate, loadDefaultWeights } from '../../../evaluator/evaluator.mjs';

describe('challenge benchmark suite', () => {
  test('all challenge graphs have valid DAG structure', () => {
    for (const g of challengeGraphs) {
      assert.ok(g.id, 'graph needs an id');
      assert.ok(g.challenge, 'graph needs a challenge type');
      assert.ok(Array.isArray(g.dag.nodes), `${g.id}: nodes must be an array`);
      assert.ok(Array.isArray(g.dag.edges), `${g.id}: edges must be an array`);
      assert.ok(g.dag.nodes.length >= 2, `${g.id}: need at least 2 nodes`);

      // Verify all edge endpoints exist
      const ids = new Set(g.dag.nodes.map(n => n.id));
      for (const [from, to] of g.dag.edges) {
        assert.ok(ids.has(from), `${g.id}: edge source ${from} not in nodes`);
        assert.ok(ids.has(to), `${g.id}: edge target ${to} not in nodes`);
      }
    }
  });

  test('all challenge graphs evaluate without rejection', async () => {
    const weights = await loadDefaultWeights();
    for (const g of challengeGraphs) {
      const result = await evaluate({}, g, { weights });
      assert.ok(!result.rejected, `${g.id} was rejected: ${result.rule} — ${result.detail}`);
      assert.ok(Number.isFinite(result.score), `${g.id}: score must be finite`);
    }
  });

  test('crossing challenge graphs have nonzero polyline_crossings with default layout', async () => {
    const weights = await loadDefaultWeights();
    const crossingGraphs = challengeGraphs.filter(g => g.challenge === 'crossings');
    assert.ok(crossingGraphs.length >= 1, 'need at least one crossing challenge');
    let anyNonzero = false;
    for (const g of crossingGraphs) {
      const result = await evaluate({}, g, { weights });
      if (result.terms.polyline_crossings > 0) anyNonzero = true;
    }
    assert.ok(anyNonzero, 'at least one crossing challenge should have nonzero polyline crossings');
  });

  test('fan graphs have nonzero overlap with default layout', async () => {
    const weights = await loadDefaultWeights();
    const fanGraphs = challengeGraphs.filter(g => g.challenge.startsWith('fan'));
    let anyOverlap = false;
    for (const g of fanGraphs) {
      const result = await evaluate({}, g, { weights });
      if (result.terms.overlap > 0) anyOverlap = true;
    }
    // Fan graphs often have overlapping edges with default layout
    // (multiple edges through the same Y at shared nodes)
    assert.ok(anyOverlap, 'at least one fan graph should have nonzero overlap');
  });

  test('suite covers all challenge types', () => {
    const types = new Set(challengeGraphs.map(g => g.challenge));
    assert.ok(types.has('crossings'), 'need crossing challenges');
    assert.ok(types.has('fan-out'), 'need fan-out challenges');
    assert.ok(types.has('fan-in'), 'need fan-in challenges');
    assert.ok(types.has('wide-layer'), 'need wide-layer challenges');
    assert.ok(types.has('parallel-paths'), 'need parallel-path challenges');
    assert.ok(types.has('symmetry'), 'need symmetry challenges');
    assert.ok(types.has('dense'), 'need dense challenges');
  });
});
