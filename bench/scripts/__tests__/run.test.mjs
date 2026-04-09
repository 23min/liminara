import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseArgs } from '../run.js';

test('parseArgs fills in defaults when no flags are given', () => {
  const args = parseArgs([]);
  assert.equal(args.seed, 1);
  assert.equal(args.generations, 20);
  assert.equal(args.populationSize, 8);
  assert.equal(args.eliteCount, 2);
  assert.equal(args.tournamentSize, 3);
  assert.equal(args.tier1MutationStrength, 0.1);
  assert.equal(args.regressionThreshold, 0.9);
  assert.equal(args.migrationInterval, 10);
  assert.equal(args.migrationRate, 0.05);
  assert.equal(args.resume, false);
  assert.equal(args.runId, 'run-seed1-g20');
  assert.equal(args.tier2MutationRate, undefined, 'tier2MutationRate should no longer exist');
});

test('parseArgs reads every flag', () => {
  const args = parseArgs([
    '--seed', '42',
    '--generations', '100',
    '--run-id', 'custom',
    '--resume',
    '--population', '16',
    '--elite', '4',
    '--tournament', '5',
    '--mut-t1', '0.2',
    '--guard', '0.85',
    '--migration-interval', '20',
    '--migration-rate', '0.1',
  ]);
  assert.equal(args.seed, 42);
  assert.equal(args.generations, 100);
  assert.equal(args.runId, 'custom');
  assert.equal(args.resume, true);
  assert.equal(args.populationSize, 16);
  assert.equal(args.eliteCount, 4);
  assert.equal(args.tournamentSize, 5);
  assert.equal(args.tier1MutationStrength, 0.2);
  assert.equal(args.regressionThreshold, 0.85);
  assert.equal(args.migrationInterval, 20);
  assert.equal(args.migrationRate, 0.1);
});

test('parseArgs rejects the removed --mut-t2 flag', () => {
  assert.throws(
    () => parseArgs(['--mut-t2', '0.1']),
    /unknown argument/,
  );
});

test('parseArgs throws on an unknown flag', () => {
  assert.throws(() => parseArgs(['--nonsense']), /unknown argument/);
});

test('parseArgs throws when a flag is missing its value', () => {
  assert.throws(() => parseArgs(['--seed']), /missing value/);
});

test('parseArgs derives a default run-id from seed and generations', () => {
  const args = parseArgs(['--seed', '7', '--generations', '50']);
  assert.equal(args.runId, 'run-seed7-g50');
});
