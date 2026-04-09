// guard.mjs — per-fixture best-ever tracker and regression guard.
//
// Fitness convention: LOWER is better (energy). "Best-ever" for a fixture
// is the smallest score ever recorded for it in the current run.
//
// Rejection rule:
//   quality_ratio = best_ever / score
//   reject if quality_ratio < threshold (default 0.9)
// Equivalently: reject if score > best_ever / threshold. This means
// "losing more than 10% of quality on any single fixture disqualifies
// the individual from the elite set" when threshold = 0.9.
//
// Epic note: the guard is primarily aimed at Tier B fixtures (the
// Liminara-realistic corpus). The caller decides which fixtures to pass
// into `regressionGuard`; this module is fixture-agnostic.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export function createBestEver() {
  return { bestEver: {} };
}

export function updateBestEver(tracker, fixtureId, score) {
  if (typeof score !== 'number' || !Number.isFinite(score)) {
    throw new Error(`updateBestEver: score must be a finite number, got ${score}`);
  }
  const prev = tracker.bestEver[fixtureId];
  if (prev === undefined || score < prev) {
    tracker.bestEver[fixtureId] = score;
  }
}

export function regressionGuard(tracker, perFixtureScores, { threshold = 0.9 } = {}) {
  const reasons = [];
  for (const [fixtureId, score] of Object.entries(perFixtureScores)) {
    const best = tracker.bestEver[fixtureId];
    if (best === undefined) continue; // no prior baseline, nothing to regress against
    // quality_ratio = best / score; reject when it drops below threshold.
    // Guard against divide-by-zero: if score is <= 0 it is trivially better.
    if (score <= 0) continue;
    const ratio = best / score;
    if (ratio < threshold) {
      reasons.push({
        fixtureId,
        score,
        bestEver: best,
        qualityRatio: ratio,
        threshold,
      });
    }
  }
  if (reasons.length > 0) {
    return { rejected: true, reasons };
  }
  return { rejected: false };
}

export async function saveBestEver(path, tracker) {
  await mkdir(dirname(path), { recursive: true });
  const payload = { bestEver: tracker.bestEver };
  await writeFile(path, JSON.stringify(payload, null, 2) + '\n', 'utf8');
}

export async function loadBestEver(path) {
  let raw;
  try {
    raw = await readFile(path, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return createBestEver();
    throw new Error(`loadBestEver: cannot read ${path}: ${err.message}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(`loadBestEver: corrupt best-ever file at ${path}: ${err.message}`);
  }
  if (!parsed || typeof parsed !== 'object' || !parsed.bestEver) {
    throw new Error(`loadBestEver: ${path} is missing the bestEver field`);
  }
  return { bestEver: { ...parsed.bestEver } };
}
