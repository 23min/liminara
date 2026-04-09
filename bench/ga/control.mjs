// control.mjs — in-memory GA control state for the Tinder UI.
//
// The control state is a mutable object checked by the runner between
// generations. The HTTP server mutates it via POST /control. Every
// mutation also appends to control.jsonl for audit.

import { appendFile, readFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export function createControlState() {
  return {
    paused: false,
    abortRequested: false,
    protectedGenomes: new Map(),
    killedIds: new Set(),
  };
}

export function pause(state) {
  state.paused = true;
}

export function resume(state) {
  state.paused = false;
}

export function requestAbort(state) {
  state.abortRequested = true;
}

function deepCloneGenome(genome) {
  return { tier1: { ...genome.tier1 } };
}

export function protect(state, id, genome) {
  state.protectedGenomes.set(id, deepCloneGenome(genome));
}

export function unprotect(state, id) {
  state.protectedGenomes.delete(id);
}

export function listProtectedGenomes(state) {
  return [...state.protectedGenomes.entries()].map(([id, genome]) => ({ id, genome }));
}

export function kill(state, id) {
  state.killedIds.add(id);
}

export function isKilled(state, id) {
  return state.killedIds.has(id);
}

export function injectProtectedInto(state, population, genIndex) {
  for (const [originalId, genome] of state.protectedGenomes) {
    population.push({
      id: `protected-${originalId}-gen${genIndex}`,
      genome: deepCloneGenome(genome),
      fitness: Number.POSITIVE_INFINITY,
      perFixture: {},
      termTotals: {},
    });
  }
}

export async function appendControlEvent(path, event) {
  await mkdir(dirname(path), { recursive: true });
  await appendFile(path, JSON.stringify(event) + '\n', 'utf8');
}

export async function readControlEvents(path) {
  let raw;
  try {
    raw = await readFile(path, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  const events = [];
  for (const line of raw.split('\n')) {
    if (line.length === 0) continue;
    try {
      const parsed = JSON.parse(line);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        events.push(parsed);
      }
    } catch {
      // skip corrupt lines
    }
  }
  return events;
}
