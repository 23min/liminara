// refit.mjs — Bradley-Terry-style weight refit over pairwise votes.
//
// The GA's scalar fitness is a weighted sum of 8 energy terms:
//   fitness(i) = sum_k w_k * term_k(i)
// where lower is better. A pairwise vote "A beats B" says the voter
// prefers A's layout to B's layout. In the model, "A beats B" means
// A has lower fitness, i.e. w . (terms(B) - terms(A)) > 0.
//
// Let x_i = terms(loser_i) - terms(winner_i). Under a Bradley-Terry /
// logistic model, the probability of the observed preference is
// sigmoid(w . x_i). The negative log-likelihood is:
//
//   NLL(w) = sum_i c_i * log(1 + exp(-w . x_i))
//
// where c_i is the per-vote temporal-decay weight (recent votes matter
// more). We add L2 regularization toward the prior weights:
//
//   L(w) = NLL(w) + lambda * ||w - w_prior||^2
//
// Both terms are convex, and the L2 term makes the Hessian strictly
// positive definite, so Newton's method converges cleanly. After
// optimization, weights are clamped to >= 0 because weights are penalty
// magnitudes (a negative weight would flip a term from penalty to reward,
// which breaks the energy contract).
//
// Temporal decay is in vote-count space: vote i (1-indexed) contributes
//   c_i = 2^(-(N - i) / halfLifeVotes)
// where N is the total number of valid votes at refit time. Vote-count
// decay is chosen for interpretability ("recent votes matter more than
// old votes" is a cleaner mental model than wall-clock decay).
//
// The refit does NOT consume wall-clock time anywhere. It is stable and
// reproducible across calls with identical inputs in the same session.

import { TERM_NAMES } from '../evaluator/evaluator.mjs';

const DEFAULT_HALF_LIFE_VOTES = 30;
const DEFAULT_REGULARIZATION = 1;
const DEFAULT_MIN_VOTES = 5;
const DEFAULT_MAX_ITERATIONS = 20;
const NEWTON_TOLERANCE = 1e-8;

function sigmoid(z) {
  if (z >= 0) {
    const ez = Math.exp(-z);
    return 1 / (1 + ez);
  }
  const ez = Math.exp(z);
  return ez / (1 + ez);
}

function weightsToVector(weights) {
  return TERM_NAMES.map((n) => weights[n] ?? 0);
}

function vectorToWeights(v) {
  const out = {};
  for (let i = 0; i < TERM_NAMES.length; i++) {
    out[TERM_NAMES[i]] = v[i];
  }
  return out;
}

function termDiff(loserTerms, winnerTerms) {
  // x = terms(loser) - terms(winner)
  return TERM_NAMES.map((n) => (loserTerms[n] ?? 0) - (winnerTerms[n] ?? 0));
}

function isZeroVector(v) {
  for (const x of v) if (x !== 0) return false;
  return true;
}

function dot(a, b) {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * b[i];
  return s;
}

// Solve H * x = b for x via in-place Gaussian elimination with partial pivoting.
// H is an n×n symmetric positive definite matrix here (L2-regularized logistic),
// so full pivoting is overkill — partial pivoting is plenty.
function solveLinearSystem(H, b) {
  const n = b.length;
  // Augmented matrix copy
  const A = H.map((row) => row.slice());
  const rhs = b.slice();
  for (let k = 0; k < n; k++) {
    // Partial pivot: find the row with largest |A[i][k]| for i >= k
    let maxRow = k;
    let maxVal = Math.abs(A[k][k]);
    for (let i = k + 1; i < n; i++) {
      if (Math.abs(A[i][k]) > maxVal) {
        maxVal = Math.abs(A[i][k]);
        maxRow = i;
      }
    }
    if (maxVal < 1e-12) {
      throw new Error('refit: singular Hessian in Newton step');
    }
    if (maxRow !== k) {
      const tmp = A[k];
      A[k] = A[maxRow];
      A[maxRow] = tmp;
      const tmpRhs = rhs[k];
      rhs[k] = rhs[maxRow];
      rhs[maxRow] = tmpRhs;
    }
    // Eliminate column k in rows below
    for (let i = k + 1; i < n; i++) {
      const factor = A[i][k] / A[k][k];
      for (let j = k; j < n; j++) {
        A[i][j] -= factor * A[k][j];
      }
      rhs[i] -= factor * rhs[k];
    }
  }
  // Back-substitute
  const x = new Array(n);
  for (let i = n - 1; i >= 0; i--) {
    let sum = rhs[i];
    for (let j = i + 1; j < n; j++) sum -= A[i][j] * x[j];
    x[i] = sum / A[i][i];
  }
  return x;
}

function computeLoss(w, priorVec, xs, cs, lambda) {
  let nll = 0;
  for (let i = 0; i < xs.length; i++) {
    const z = dot(w, xs[i]);
    // log(1 + exp(-z)) computed stably
    const stable = z >= 0 ? Math.log(1 + Math.exp(-z)) : -z + Math.log(1 + Math.exp(z));
    nll += cs[i] * stable;
  }
  let reg = 0;
  for (let k = 0; k < w.length; k++) {
    reg += (w[k] - priorVec[k]) * (w[k] - priorVec[k]);
  }
  return nll + lambda * reg;
}

function newtonStep(w, priorVec, xs, cs, lambda) {
  const n = w.length;
  // Gradient: dL/dw_k = sum_i c_i * (-(1 - sigmoid(w . x_i)) * x_i[k])
  //                   + 2*lambda*(w_k - w_prior_k)
  const grad = new Array(n).fill(0);
  for (let i = 0; i < xs.length; i++) {
    const z = dot(w, xs[i]);
    const s = sigmoid(z);
    const coef = cs[i] * -(1 - s);
    for (let k = 0; k < n; k++) grad[k] += coef * xs[i][k];
  }
  for (let k = 0; k < n; k++) grad[k] += 2 * lambda * (w[k] - priorVec[k]);

  // Hessian: d2L/(dw_j dw_k) = sum_i c_i * s * (1 - s) * x_i[j] * x_i[k]
  //                          + 2*lambda*I
  const H = Array.from({ length: n }, () => new Array(n).fill(0));
  for (let i = 0; i < xs.length; i++) {
    const z = dot(w, xs[i]);
    const s = sigmoid(z);
    const weight = cs[i] * s * (1 - s);
    for (let j = 0; j < n; j++) {
      for (let k = 0; k < n; k++) {
        H[j][k] += weight * xs[i][j] * xs[i][k];
      }
    }
  }
  for (let k = 0; k < n; k++) H[k][k] += 2 * lambda;

  const delta = solveLinearSystem(H, grad);

  // Backtracking line search: the full Newton step can overshoot badly
  // when the Hessian is near-singular (e.g., when s*(1-s) ≈ 0 because
  // sigmoid(w·x) is saturated). Start at alpha=1 and halve until the
  // loss actually decreases. Cap the backtracks so a pathological case
  // doesn't loop forever.
  const currentLoss = computeLoss(w, priorVec, xs, cs, lambda);
  let alpha = 1;
  let w_new = new Array(n);
  for (let attempt = 0; attempt < 30; attempt++) {
    for (let k = 0; k < n; k++) w_new[k] = w[k] - alpha * delta[k];
    const candidateLoss = computeLoss(w_new, priorVec, xs, cs, lambda);
    if (candidateLoss <= currentLoss) break;
    alpha *= 0.5;
  }

  return { w_new, grad, delta, alpha };
}

export function refitWeights({
  votes,
  termsById,
  priorWeights,
  halfLifeVotes = DEFAULT_HALF_LIFE_VOTES,
  regularization = DEFAULT_REGULARIZATION,
  minVotesForRefit = DEFAULT_MIN_VOTES,
  maxIterations = DEFAULT_MAX_ITERATIONS,
} = {}) {
  if (!votes || votes.length === 0) {
    return { weights: { ...priorWeights }, skipped: true, reason: 'no-votes' };
  }

  // Phase 1: normalize votes to (loser - winner) term-diff vectors.
  const xs = [];
  let unknownVoteCount = 0;
  let skipOrTieCount = 0;
  let degenerateVoteCount = 0;

  for (const v of votes) {
    if (v.winner === 'skip' || v.winner === 'tie') {
      skipOrTieCount++;
      continue;
    }
    if (v.winner !== 'left' && v.winner !== 'right') {
      skipOrTieCount++;
      continue;
    }
    const winnerId = v.winner === 'left' ? v.left_id : v.right_id;
    const loserId = v.winner === 'left' ? v.right_id : v.left_id;
    const winnerTerms = termsById[winnerId];
    const loserTerms = termsById[loserId];
    if (!winnerTerms || !loserTerms) {
      unknownVoteCount++;
      continue;
    }
    const x = termDiff(loserTerms, winnerTerms);
    if (isZeroVector(x)) {
      degenerateVoteCount++;
      continue;
    }
    xs.push(x);
  }

  const validVoteCount = xs.length;

  if (validVoteCount === 0) {
    if (skipOrTieCount === votes.length) {
      return { weights: { ...priorWeights }, skipped: true, reason: 'all-skip-or-tie' };
    }
    return { weights: { ...priorWeights }, skipped: true, reason: 'no-valid-votes' };
  }

  if (validVoteCount < minVotesForRefit) {
    return {
      weights: { ...priorWeights },
      skipped: true,
      reason: 'below-minimum',
      validVoteCount,
      minVotesForRefit,
    };
  }

  // Phase 2: temporal decay weights.
  // c_i = 2^(-(N - i) / halfLifeVotes), 1-indexed so the most recent vote
  // (i = N) gets weight 1 and older votes decay.
  const N = validVoteCount;
  const cs = new Array(N);
  for (let i = 1; i <= N; i++) {
    cs[i - 1] = Math.pow(2, -(N - i) / halfLifeVotes);
  }

  // Phase 3: Newton iteration.
  const priorVec = weightsToVector(priorWeights);
  let w = priorVec.slice();
  let iterations = 0;
  for (let iter = 0; iter < maxIterations; iter++) {
    const step = newtonStep(w, priorVec, xs, cs, regularization);
    let maxDelta = 0;
    for (let k = 0; k < w.length; k++) {
      const d = Math.abs(step.w_new[k] - w[k]);
      if (d > maxDelta) maxDelta = d;
    }
    w = step.w_new;
    iterations++;
    if (maxDelta < NEWTON_TOLERANCE) break;
  }

  // Phase 4: clamp to >= 0 and record which entries were clamped.
  const clamped = [];
  for (let k = 0; k < w.length; k++) {
    if (w[k] < 0) {
      clamped.push(TERM_NAMES[k]);
      w[k] = 0;
    }
  }

  // Phase 5: final loss (for reporting).
  let loss = 0;
  for (let i = 0; i < xs.length; i++) {
    const z = dot(w, xs[i]);
    // log(1 + exp(-z)) computed stably
    const stable = z >= 0 ? Math.log(1 + Math.exp(-z)) : -z + Math.log(1 + Math.exp(z));
    loss += cs[i] * stable;
  }
  let reg = 0;
  for (let k = 0; k < w.length; k++) {
    reg += (w[k] - priorVec[k]) * (w[k] - priorVec[k]);
  }
  loss += regularization * reg;

  const effectiveVoteCount = cs.reduce((a, b) => a + b, 0);

  return {
    weights: vectorToWeights(w),
    iterations,
    loss,
    clamped,
    validVoteCount,
    unknownVoteCount,
    skipOrTieCount,
    degenerateVoteCount,
    effectiveVoteCount,
  };
}
