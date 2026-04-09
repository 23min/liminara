import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  createControlState,
  pause,
  resume,
  requestAbort,
  protect,
  unprotect,
  kill,
  isKilled,
  listProtectedGenomes,
  injectProtectedInto,
  appendControlEvent,
  readControlEvents,
} from '../control.mjs';
import { defaultGenome } from '../../genome/genome.mjs';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-control-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function mkInd(id, island = 'bezier', fitness = 10) {
  return { id, island, genome: defaultGenome(), fitness, perFixture: {}, termTotals: {} };
}

// ── createControlState ──────────────────────────────────────────────────

test('createControlState returns the expected shape with all fields at defaults', () => {
  const s = createControlState();
  assert.equal(s.paused, false);
  assert.equal(s.abortRequested, false);
  assert.ok(s.protectedGenomes instanceof Map);
  assert.equal(s.protectedGenomes.size, 0);
  assert.ok(s.killedIds instanceof Set);
  assert.equal(s.killedIds.size, 0);
});

// ── pause / resume ──────────────────────────────────────────────────────

test('pause sets paused to true, resume sets it back to false', () => {
  const s = createControlState();
  pause(s);
  assert.equal(s.paused, true);
  resume(s);
  assert.equal(s.paused, false);
});

test('pause is idempotent — calling pause twice stays paused', () => {
  const s = createControlState();
  pause(s);
  pause(s);
  assert.equal(s.paused, true);
});

test('resume on an already-unpaused state is a no-op', () => {
  const s = createControlState();
  resume(s);
  assert.equal(s.paused, false);
});

// ── requestAbort ────────────────────────────────────────────────────────

test('requestAbort sets abortRequested to true', () => {
  const s = createControlState();
  requestAbort(s);
  assert.equal(s.abortRequested, true);
});

// ── protect / unprotect / listProtectedGenomes ──────────────────────────

test('protect stores a deep clone of the genome keyed by individual id', () => {
  const s = createControlState();
  const genome = defaultGenome();
  protect(s, 'hero', genome);
  const stored = s.protectedGenomes.get('hero');
  assert.ok(stored);
  assert.deepEqual(stored, genome);
  genome.tier1.render_stretch_ideal_factor = 999;
  assert.notEqual(stored.tier1.render_stretch_ideal_factor, 999);
});

test('unprotect removes a previously protected genome', () => {
  const s = createControlState();
  protect(s, 'hero', defaultGenome());
  assert.equal(s.protectedGenomes.size, 1);
  unprotect(s, 'hero');
  assert.equal(s.protectedGenomes.size, 0);
});

test('unprotect on an unknown id is a no-op', () => {
  const s = createControlState();
  unprotect(s, 'ghost');
  assert.equal(s.protectedGenomes.size, 0);
});

test('listProtectedGenomes returns all protected entries as {id, genome} objects', () => {
  const s = createControlState();
  const g1 = defaultGenome();
  const g2 = defaultGenome();
  protect(s, 'a', g1);
  protect(s, 'b', g2);
  const list = listProtectedGenomes(s);
  assert.equal(list.length, 2);
  const ids = list.map((e) => e.id).sort();
  assert.deepEqual(ids, ['a', 'b']);
  for (const entry of list) {
    assert.ok(entry.genome);
    assert.ok(entry.genome.tier1);
  }
});

// ── kill / isKilled ─────────────────────────────────────────────────────

test('kill adds an id to killedIds; isKilled returns true for killed, false otherwise', () => {
  const s = createControlState();
  assert.equal(isKilled(s, 'villain'), false);
  kill(s, 'villain');
  assert.equal(isKilled(s, 'villain'), true);
  assert.equal(isKilled(s, 'hero'), false);
});

test('kill is idempotent — killing the same id twice does not error', () => {
  const s = createControlState();
  kill(s, 'x');
  kill(s, 'x');
  assert.equal(s.killedIds.size, 1);
});

// ── injectProtectedInto ─────────────────────────────────────────────────

test('injectProtectedInto adds deep-cloned individuals with unique ids to the population', () => {
  const s = createControlState();
  protect(s, 'hero', defaultGenome());
  protect(s, 'champ', defaultGenome());
  const population = [mkInd('existing-0'), mkInd('existing-1')];
  injectProtectedInto(s, population, 5);
  assert.equal(population.length, 4);
  const injectedIds = population.slice(2).map((i) => i.id);
  for (const injId of injectedIds) {
    assert.match(injId, /protected-.+-gen5/);
  }
});

test('injectProtectedInto deep-clones — mutating an injected genome does not affect the stored copy', () => {
  const s = createControlState();
  protect(s, 'hero', defaultGenome());
  const population = [];
  injectProtectedInto(s, population, 0);
  assert.equal(population.length, 1);
  population[0].genome.tier1.render_stretch_ideal_factor = 999;
  const stored = s.protectedGenomes.get('hero');
  assert.notEqual(stored.tier1.render_stretch_ideal_factor, 999);
});

test('injectProtectedInto with no protected genomes is a no-op', () => {
  const s = createControlState();
  const population = [mkInd('a')];
  injectProtectedInto(s, population, 1);
  assert.equal(population.length, 1);
});

// ── appendControlEvent / readControlEvents ──────────────────────────────

test('appendControlEvent writes a JSON line; readControlEvents reads it back', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'control.jsonl');
    await appendControlEvent(path, { action: 'pause', ts: '2026-04-09T10:00:00Z' });
    await appendControlEvent(path, { action: 'kill', ts: '2026-04-09T10:01:00Z', id: 'villain' });
    const events = await readControlEvents(path);
    assert.equal(events.length, 2);
    assert.equal(events[0].action, 'pause');
    assert.equal(events[1].action, 'kill');
    assert.equal(events[1].id, 'villain');
  });
});

test('readControlEvents returns an empty array when the file does not exist', async () => {
  await withTmp(async (dir) => {
    const events = await readControlEvents(join(dir, 'missing.jsonl'));
    assert.deepEqual(events, []);
  });
});

test('readControlEvents skips corrupt lines and returns only valid JSON objects', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'control.jsonl');
    const good = JSON.stringify({ action: 'pause', ts: '2026-04-09T10:00:00Z' });
    await writeFile(path, `${good}\n{ broken\n"just a string"\n${good}\n`, 'utf8');
    const events = await readControlEvents(path);
    assert.equal(events.length, 2);
    assert.equal(events[0].action, 'pause');
    assert.equal(events[1].action, 'pause');
  });
});

test('appendControlEvent creates parent directories when they do not exist', async () => {
  await withTmp(async (dir) => {
    const path = join(dir, 'nested', 'deep', 'control.jsonl');
    await appendControlEvent(path, { action: 'resume' });
    const raw = await readFile(path, 'utf8');
    assert.match(raw, /"action":"resume"/);
  });
});
