import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { refitWeights } from '../refit.mjs';
import { TERM_NAMES } from '../../evaluator/evaluator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function emptyTerms() {
  return Object.fromEntries(TERM_NAMES.map((n) => [n, 0]));
}

function makeIndividual(id, overrides = {}) {
  return { id, termTotals: { ...emptyTerms(), ...overrides } };
}

function buildTermsMap(individuals) {
  const out = {};
  for (const ind of individuals) out[ind.id] = ind.termTotals;
  return out;
}

function flatWeights(value = 1) {
  return Object.fromEntries(TERM_NAMES.map((n) => [n, value]));
}

function vote(left_id, right_id, winner, generation = 1) {
  return { ts: '2026-04-08T00:00:00Z', run_id: 'test', generation, left_id, right_id, winner };
}

// ── degenerate / guard cases ────────────────────────────────────────────

test('refitWeights returns the prior unchanged with reason "no-votes" when given an empty vote log', () => {
  const prior = flatWeights(1);
  const result = refitWeights({
    votes: [],
    termsById: {},
    priorWeights: prior,
  });
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'no-votes');
  assert.deepEqual(result.weights, prior);
});

test('refitWeights returns the prior unchanged when every vote is skip or tie', () => {
  const prior = flatWeights(1);
  const result = refitWeights({
    votes: [vote('a', 'b', 'skip'), vote('c', 'd', 'tie')],
    termsById: {},
    priorWeights: prior,
    minVotesForRefit: 1,
  });
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'all-skip-or-tie');
  assert.deepEqual(result.weights, prior);
});

test('refitWeights returns the prior unchanged when the vote count is below minVotesForRefit', () => {
  const prior = flatWeights(1);
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 20 }),
  ];
  const result = refitWeights({
    votes: [vote('a', 'b', 'left')],
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    minVotesForRefit: 5,
  });
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'below-minimum');
});

test('refitWeights skips votes that reference an unknown individual id', () => {
  const prior = flatWeights(1);
  const inds = [makeIndividual('a', { stretch: 10 }), makeIndividual('b', { stretch: 20 })];
  // 5 valid votes + 2 with unknown ids
  const votes = [
    vote('a', 'b', 'left'),
    vote('a', 'b', 'left'),
    vote('a', 'b', 'left'),
    vote('a', 'b', 'left'),
    vote('a', 'b', 'left'),
    vote('a', 'ghost', 'left'),
    vote('ghost', 'b', 'right'),
  ];
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    minVotesForRefit: 5,
  });
  assert.equal(result.skipped, undefined, 'expected a real refit, not a skip');
  assert.equal(result.unknownVoteCount, 2);
  assert.equal(result.validVoteCount, 5);
});

// ── prior-preserving case ───────────────────────────────────────────────

test('refitWeights on a vote log whose preferences match the prior returns weights close to the prior', () => {
  // Two individuals. B has higher stretch than A. With a prior that
  // already weights stretch positively, votes for "A beats B" (low stretch
  // is preferred) are consistent with the prior. Refit should not move
  // weights much.
  const prior = { ...flatWeights(0), stretch: 1 };
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 50 }),
  ];
  const votes = Array.from({ length: 20 }, () => vote('a', 'b', 'left'));
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 1,
    minVotesForRefit: 5,
  });
  // stretch should stay positive, and should not have exploded.
  assert.ok(result.weights.stretch > 0);
  assert.ok(Math.abs(result.weights.stretch - prior.stretch) < 0.5);
});

// ── single-term preference ──────────────────────────────────────────────

test('refitWeights increases the weight of a term when every vote prefers the low-term individual', () => {
  // A has low envelope, B has high envelope. Every vote picks A.
  // Starting prior: envelope = 0 (not yet important). After refit,
  // envelope should have positive weight.
  const prior = { ...flatWeights(0.1), envelope: 0 };
  const inds = [
    makeIndividual('a', { envelope: 5 }),
    makeIndividual('b', { envelope: 50 }),
  ];
  const votes = Array.from({ length: 30 }, () => vote('a', 'b', 'left'));
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 0.01,
    minVotesForRefit: 5,
  });
  assert.ok(result.weights.envelope > prior.envelope, `envelope did not rise: ${result.weights.envelope}`);
  // Other terms should not have moved much (the votes give no signal on them).
  for (const name of TERM_NAMES) {
    if (name === 'envelope') continue;
    assert.ok(
      Math.abs(result.weights[name] - prior[name]) < 0.1,
      `${name} moved unexpectedly: prior=${prior[name]} post=${result.weights[name]}`,
    );
  }
});

// ── zero-clamp case ─────────────────────────────────────────────────────

test('refitWeights clamps negative unconstrained solutions to zero', () => {
  // Construct a case where the votes would push a weight negative:
  // A has HIGH bend, B has LOW bend. Votes pick A (the high-bend one).
  // This is "bend is preferred to be high", which in our negative-is-better
  // framing would correspond to a negative weight — which is invalid
  // because weights are penalty magnitudes. The refit must clamp.
  const prior = { ...flatWeights(0), bend: 0.5 };
  const inds = [
    makeIndividual('a', { bend: 50 }),
    makeIndividual('b', { bend: 5 }),
  ];
  const votes = Array.from({ length: 40 }, () => vote('a', 'b', 'left'));
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 0.001, // weak regularization so the data dominates
    minVotesForRefit: 5,
  });
  assert.ok(result.weights.bend >= 0, `bend went negative: ${result.weights.bend}`);
  assert.equal(result.clamped.includes('bend'), true, 'expected bend in clamped list');
});

// ── temporal decay ──────────────────────────────────────────────────────

test('refitWeights honors temporal decay: stale dissenting votes lose influence to recent concurring votes', () => {
  // 5 stale votes preferring B (high stretch)
  // 30 recent votes preferring A (low stretch)
  // With a short half-life, recent votes should dominate — stretch weight
  // should move POSITIVE (low stretch is preferred) despite the stale
  // dissent. We compare the temporal-decay run to a control run where
  // the same vote log is interpreted in the reverse order (stale = recent)
  // — the two should end up on opposite sides of zero. Absolute magnitudes
  // depend on regularization and aren't asserted.
  const prior = { ...flatWeights(0), stretch: 0 };
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 50 }),
  ];
  const withDecay = refitWeights({
    votes: [
      ...Array.from({ length: 5 }, () => vote('a', 'b', 'right')), // stale, prefer B
      ...Array.from({ length: 30 }, () => vote('a', 'b', 'left')), // recent, prefer A
    ],
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 5, // very short half-life so stale votes really fade
    regularization: 0.01,
    minVotesForRefit: 5,
  });
  const reversedOrder = refitWeights({
    votes: [
      ...Array.from({ length: 30 }, () => vote('a', 'b', 'left')), // stale, prefer A
      ...Array.from({ length: 5 }, () => vote('a', 'b', 'right')), // recent, prefer B
    ],
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 5,
    regularization: 0.01,
    minVotesForRefit: 5,
  });
  assert.ok(
    withDecay.weights.stretch > 0,
    `stretch should be positive when recent votes prefer low stretch: ${withDecay.weights.stretch}`,
  );
  assert.ok(
    reversedOrder.weights.stretch < 0 || reversedOrder.weights.stretch === 0,
    `stretch should be <=0 when recent votes prefer high stretch: ${reversedOrder.weights.stretch}`,
  );
  // Direction flip between the two: if they weren't affected by recency,
  // they'd be identical (same vote counts, same term diffs).
  assert.ok(
    withDecay.weights.stretch > reversedOrder.weights.stretch,
    `temporal decay did not differentiate the two orderings: ${withDecay.weights.stretch} vs ${reversedOrder.weights.stretch}`,
  );
});

// ── stability / reproducibility ─────────────────────────────────────────

test('refitWeights is stable across identical inputs in one session', () => {
  const prior = { ...flatWeights(0), stretch: 0.5 };
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 50 }),
  ];
  const votes = Array.from({ length: 20 }, () => vote('a', 'b', 'left'));
  const opts = {
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 0.01,
    minVotesForRefit: 5,
  };
  const a = refitWeights(opts);
  const b = refitWeights(opts);
  assert.deepEqual(a.weights, b.weights);
});

// ── filter degenerate votes ─────────────────────────────────────────────

test('refitWeights filters votes where winner and loser have identical termTotals', () => {
  // Vote pairs with zero x vector carry no information and would confuse
  // the solver. They should be filtered and counted.
  const prior = flatWeights(0.5);
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 10 }), // identical to a
    makeIndividual('c', { stretch: 10 }),
    makeIndividual('d', { stretch: 50 }),
  ];
  const votes = [
    vote('a', 'b', 'left'), // degenerate — same terms
    vote('c', 'd', 'left'), // valid
    vote('c', 'd', 'left'),
    vote('c', 'd', 'left'),
    vote('c', 'd', 'left'),
    vote('c', 'd', 'left'),
  ];
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 0.01,
    minVotesForRefit: 5,
  });
  assert.equal(result.degenerateVoteCount, 1);
  assert.equal(result.validVoteCount, 5);
});

// ── sanity: all 8 term weights present in output ────────────────────────

test('refitWeights output contains exactly the 8 term weights', () => {
  const prior = flatWeights(0.5);
  const inds = [
    makeIndividual('a', { stretch: 10 }),
    makeIndividual('b', { stretch: 20 }),
  ];
  const votes = Array.from({ length: 10 }, () => vote('a', 'b', 'left'));
  const result = refitWeights({
    votes,
    termsById: buildTermsMap(inds),
    priorWeights: prior,
    halfLifeVotes: 30,
    regularization: 0.1,
    minVotesForRefit: 5,
  });
  assert.deepEqual(Object.keys(result.weights).sort(), [...TERM_NAMES].sort());
});

// ── Math.random hygiene ─────────────────────────────────────────────────

test('refit source does not call Math.random', async () => {
  const src = await readFile(join(__dirname, '..', 'refit.mjs'), 'utf8');
  const stripped = src
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
  assert.ok(!/Math\.random\s*\(/.test(stripped), 'refit.mjs must not call Math.random');
});
