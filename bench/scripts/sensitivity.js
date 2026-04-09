// scripts/sensitivity.js — one-point sensitivity analysis of the GA's
// Tier 1 genome fields against the scalar fitness and per-term values.
//
// For each field F:
//   1. Start from defaultTier1()
//   2. Compute sigma_F = strength * (max_F - min_F)   (strength default 0.1,
//      matches the GA's default Tier 1 mutation strength)
//   3. Build two genomes: default + sigma_F, default - sigma_F (both clamped)
//   4. Score both across the full corpus
//   5. Record scalar delta and per-term delta vs default
//
// Report is sorted by total sensitivity = |delta_high| + |delta_low| and
// written to `bench/run/sensitivity/<timestamp>/report.md` plus `raw.json`.
//
// CLI usage:
//     node scripts/sensitivity.js
//
// Programmatic:
//     import { runSensitivity } from './scripts/sensitivity.js';
//     const { outDir, payload } = await runSensitivity();

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  TIER1_SCHEMA,
  TIER1_FIELDS,
  defaultTier1,
  clampTier1,
} from '../genome/tier1.mjs';
import { makeGenome, toEvaluatorGenome } from '../genome/genome.mjs';
import {
  evaluate,
  loadDefaultWeights,
  TERM_NAMES,
} from '../evaluator/evaluator.mjs';
import { loadTierA } from '../corpus/tier-a.mjs';
import { loadTierB } from '../corpus/tier-b.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = join(__dirname, '..');
const DEFAULT_OUT_ROOT = join(BENCH_ROOT, 'run', 'sensitivity');
const DEFAULT_STRENGTH = 0.1;
const DEAD_FIELD_EPSILON = 1e-9;

// ── buildMutatedGenome ──────────────────────────────────────────────────

export function buildMutatedGenome({ field, delta, tier1 }) {
  if (!(field in TIER1_SCHEMA)) {
    throw new Error(`unknown Tier 1 field: ${field}`);
  }
  const mutated = { ...tier1, [field]: tier1[field] + delta };
  const clamped = clampTier1(mutated);
  return makeGenome({ tier1: clamped });
}

// ── scoreGenomeAcross ───────────────────────────────────────────────────

export async function scoreGenomeAcross({ genome, fixtures, weights }) {
  const ev = toEvaluatorGenome(genome);
  const perFixture = {};
  const termTotals = Object.fromEntries(TERM_NAMES.map((n) => [n, 0]));
  let total = 0;
  let scoredCount = 0;
  let rejectedCount = 0;

  for (const f of fixtures) {
    const r = await evaluate(ev, f, { weights });
    if (r.rejected) {
      rejectedCount++;
      continue;
    }
    total += r.score;
    perFixture[f.id] = r.score;
    scoredCount++;
    for (const n of TERM_NAMES) {
      termTotals[n] += r.terms[n];
    }
  }

  return { total, perFixture, termTotals, scoredCount, rejectedCount };
}

// ── measureFieldSensitivity ─────────────────────────────────────────────

export async function measureFieldSensitivity({
  field,
  defaults,
  fixtures,
  weights,
  strength = DEFAULT_STRENGTH,
}) {
  const spec = TIER1_SCHEMA[field];
  if (!spec) throw new Error(`unknown Tier 1 field: ${field}`);

  const sigma = strength * (spec.max - spec.min);

  const baseGenome = makeGenome({ tier1: defaults.tier1 });
  const baseScore = await scoreGenomeAcross({ genome: baseGenome, fixtures, weights });

  const highGenome = buildMutatedGenome({
    field,
    delta: sigma,
    tier1: defaults.tier1,
  });
  const lowGenome = buildMutatedGenome({
    field,
    delta: -sigma,
    tier1: defaults.tier1,
  });

  const highScore = await scoreGenomeAcross({ genome: highGenome, fixtures, weights });
  const lowScore = await scoreGenomeAcross({ genome: lowGenome, fixtures, weights });

  const deltaHigh = highScore.total - baseScore.total;
  const deltaLow = lowScore.total - baseScore.total;
  const totalSensitivity = Math.abs(deltaHigh) + Math.abs(deltaLow);

  const perTermDelta = {};
  for (const n of TERM_NAMES) {
    perTermDelta[n] = {
      high: highScore.termTotals[n] - baseScore.termTotals[n],
      low: lowScore.termTotals[n] - baseScore.termTotals[n],
    };
  }

  const highClamped = highGenome.tier1[field] !== defaults.tier1[field] + sigma;
  const lowClamped = lowGenome.tier1[field] !== defaults.tier1[field] - sigma;

  return {
    field,
    sigma,
    baseValue: defaults.tier1[field],
    highValue: highGenome.tier1[field],
    lowValue: lowGenome.tier1[field],
    highClamped,
    lowClamped,
    deltaHigh,
    deltaLow,
    totalSensitivity,
    perTermDelta,
  };
}

// ── runSensitivity ──────────────────────────────────────────────────────

function stamp(now) {
  return now.toISOString().replace(/[:.]/g, '-');
}

export async function runSensitivity({
  outRoot = DEFAULT_OUT_ROOT,
  now = new Date(),
  strength = DEFAULT_STRENGTH,
  fixtureSlice = null,
} = {}) {
  const tierA = await loadTierA();
  const tierB = await loadTierB();
  const tierAUsed = fixtureSlice?.tierA != null ? tierA.slice(0, fixtureSlice.tierA) : tierA;
  const tierBUsed = fixtureSlice?.tierB != null ? tierB.slice(0, fixtureSlice.tierB) : tierB;
  const fixtures = [...tierAUsed, ...tierBUsed];
  const weights = await loadDefaultWeights();

  const defaults = {
    tier1: defaultTier1(),
  };

  const results = [];
  for (const field of TIER1_FIELDS) {
    const r = await measureFieldSensitivity({
      field,
      defaults,
      fixtures,
      weights,
      strength,
    });
    results.push(r);
  }

  results.sort((a, b) => b.totalSensitivity - a.totalSensitivity);

  const payload = {
    timestamp: now.toISOString(),
    strength,
    fieldCount: TIER1_FIELDS.length,
    fixtureCount: fixtures.length,
    tierACount: tierAUsed.length,
    tierBCount: tierBUsed.length,
    weights,
    results,
  };

  const outDir = join(outRoot, stamp(now));
  await mkdir(outDir, { recursive: true });
  await writeFile(join(outDir, 'raw.json'), JSON.stringify(payload, null, 2) + '\n', 'utf8');
  await writeFile(join(outDir, 'report.md'), formatSensitivityMarkdown(payload), 'utf8');

  return { outDir, payload };
}

// ── formatSensitivityMarkdown ───────────────────────────────────────────

function num(v, sig = 3) {
  if (v === 0) return '0';
  const abs = Math.abs(v);
  if (abs >= 1000 || abs < 0.001) return v.toExponential(sig - 1);
  return v.toPrecision(sig);
}

function dominantTerms(perTermDelta) {
  // Rank terms by contribution to total |high| + |low|, return the top 2.
  const mag = Object.entries(perTermDelta).map(([name, { high, low }]) => ({
    name,
    mag: Math.abs(high) + Math.abs(low),
  }));
  mag.sort((a, b) => b.mag - a.mag);
  const totalMag = mag.reduce((a, b) => a + b.mag, 0);
  if (totalMag === 0) return '—';
  return mag
    .filter((m) => m.mag > 0)
    .slice(0, 2)
    .map((m) => `${m.name} (${Math.round((100 * m.mag) / totalMag)}%)`)
    .join(', ');
}

export function formatSensitivityMarkdown(payload) {
  const lines = [];
  lines.push('# Sensitivity report');
  lines.push('');
  lines.push(`**Timestamp:** ${payload.timestamp}`);
  lines.push(`**Mutation strength:** ${payload.strength} (sigma = strength × (max − min) per field)`);
  lines.push(
    `**Fixtures scored:** ${payload.fixtureCount} (${payload.tierACount} Tier A + ${payload.tierBCount} Tier B)`,
  );
  lines.push(`**Tier 1 fields measured:** ${payload.fieldCount}`);
  lines.push('');
  lines.push('Each row reports the scalar fitness delta when the field is moved ±1σ from its default, with everything else held at the default genome. Total sensitivity = |Δhigh| + |Δlow|.');
  lines.push('');
  lines.push('| Rank | Field | σ | Δhigh | Δlow | Total | Dominant terms |');
  lines.push('|---|---|---|---|---|---|---|');

  payload.results.forEach((r, i) => {
    const dom = dominantTerms(r.perTermDelta);
    const row = `| ${i + 1} | \`${r.field}\` | ${num(r.sigma)} | ${num(r.deltaHigh)} | ${num(r.deltaLow)} | ${num(r.totalSensitivity)} | ${dom} |`;
    lines.push(row);
  });
  lines.push('');

  const dead = payload.results.filter((r) => r.totalSensitivity < DEAD_FIELD_EPSILON);
  if (dead.length > 0) {
    lines.push(`## Dead fields (total sensitivity < ${DEAD_FIELD_EPSILON})`);
    lines.push('');
    lines.push('These fields produced no change in the scalar fitness when mutated by ±1σ. They are wasted mutation budget for the GA and should be removed or wired through to something they can affect.');
    lines.push('');
    for (const r of dead) {
      lines.push(`- \`${r.field}\``);
    }
    lines.push('');
  } else {
    lines.push('## Dead fields');
    lines.push('');
    lines.push('None detected.');
    lines.push('');
  }

  lines.push('## Per-term sensitivity matrix');
  lines.push('');
  lines.push('Each cell is the magnitude of change each field can induce in each energy term (sum of |high| + |low|). Zero cells mean the field has no effect on that term at the default point.');
  lines.push('');
  const termHeader = ['| Field |', ...TERM_NAMES.map((n) => ` \`${n}\` |`)].join('');
  const termSep = ['|---|', ...TERM_NAMES.map(() => '---|')].join('');
  lines.push(termHeader);
  lines.push(termSep);
  for (const r of payload.results) {
    const cells = TERM_NAMES.map((n) => {
      const { high, low } = r.perTermDelta[n];
      const mag = Math.abs(high) + Math.abs(low);
      return mag < DEAD_FIELD_EPSILON ? ' 0 |' : ` ${num(mag, 2)} |`;
    });
    lines.push(`| \`${r.field}\` |${cells.join('')}`);
  }
  lines.push('');

  return lines.join('\n');
}

// ── CLI ─────────────────────────────────────────────────────────────────

const isDirectRun = import.meta.url === `file://${process.argv[1]}`;
if (isDirectRun) {
  runSensitivity()
    .then(({ outDir, payload }) => {
      process.stdout.write(
        `sensitivity: scored ${payload.fieldCount} fields × ${payload.fixtureCount} fixtures -> ${outDir}\n`,
      );
    })
    .catch((err) => {
      process.stderr.write(`sensitivity failed: ${err.stack || err.message}\n`);
      process.exit(1);
    });
}
