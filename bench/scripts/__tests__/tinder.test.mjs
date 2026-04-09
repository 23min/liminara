import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import http from 'node:http';

import {
  parseTinderArgs,
  selectPair,
  createTinderServer,
} from '../tinder.js';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-tinder-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function fetch(url, opts = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(url, {
      method: opts.method ?? 'GET',
      headers: opts.headers ?? {},
    }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body, headers: res.headers }));
    });
    req.on('error', reject);
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

// ── parseTinderArgs ─────────────────────────────────────────────────────

test('parseTinderArgs parses required flags and applies defaults', () => {
  const args = parseTinderArgs(['--run-id', 'test', '--seed', '42', '--generations', '10']);
  assert.equal(args.runId, 'test');
  assert.equal(args.seed, 42);
  assert.equal(args.generations, 10);
  assert.equal(args.port, 8765);
});

test('parseTinderArgs accepts --port override', () => {
  const args = parseTinderArgs(['--run-id', 'r', '--seed', '1', '--generations', '5', '--port', '9000']);
  assert.equal(args.port, 9000);
});

// ── selectPair ──────────────────────────────────────────────────────────

test('selectPair returns a pair of distinct individuals from the elite', () => {
  const elite = [
    { id: 'a', fitness: 1 },
    { id: 'b', fitness: 2 },
    { id: 'c', fitness: 3 },
  ];
  const pair = selectPair(elite, 42, []);
  assert.ok(pair, 'should return a pair');
  assert.notEqual(pair.left.id, pair.right.id);
  assert.ok(elite.some((e) => e.id === pair.left.id));
  assert.ok(elite.some((e) => e.id === pair.right.id));
});

test('selectPair is deterministic: same inputs produce same pair', () => {
  const elite = [
    { id: 'a', fitness: 1 },
    { id: 'b', fitness: 2 },
    { id: 'c', fitness: 3 },
    { id: 'd', fitness: 4 },
  ];
  const p1 = selectPair(elite, 42, []);
  const p2 = selectPair(elite, 42, []);
  assert.equal(p1.left.id, p2.left.id);
  assert.equal(p1.right.id, p2.right.id);
});

test('selectPair returns null when fewer than 2 elite', () => {
  assert.equal(selectPair([{ id: 'a', fitness: 1 }], 1, []), null);
  assert.equal(selectPair([], 1, []), null);
});

test('selectPair avoids already-voted pairs', () => {
  const elite = [
    { id: 'a', fitness: 1 },
    { id: 'b', fitness: 2 },
    { id: 'c', fitness: 3 },
  ];
  // Vote on a-b and a-c, leaving only b-c.
  const voted = [
    { left_id: 'a', right_id: 'b', winner: 'left' },
    { left_id: 'a', right_id: 'c', winner: 'right' },
  ];
  const pair = selectPair(elite, 1, voted);
  assert.ok(pair);
  const ids = [pair.left.id, pair.right.id].sort();
  assert.deepEqual(ids, ['b', 'c']);
});

test('selectPair returns null when all pairs have been voted on', () => {
  const elite = [
    { id: 'a', fitness: 1 },
    { id: 'b', fitness: 2 },
  ];
  const voted = [{ left_id: 'a', right_id: 'b', winner: 'left' }];
  assert.equal(selectPair(elite, 1, voted), null);
});

// ── Server smoke tests ──────────────────────────────────────────────────

// Minimal scoreChild for server tests.
async function stubScoreChild({ id, genome }) {
  let fitness = 0;
  for (const v of Object.values(genome.tier1)) fitness += v * v;
  const termTotals = {};
  return { id, genome, fitness, perFixture: { stub: fitness }, termTotals };
}

test('server responds to GET /state with JSON', async () => {
  await withTmp(async (root) => {
    // Create minimal web dir so static serving doesn't error.
    const webDir = join(root, 'web', 'tinder');
    await mkdir(webDir, { recursive: true });
    await writeFile(join(webDir, 'index.html'), '<html></html>');

    const { server, gaPromise } = await createTinderServer({
      seed: 1,
      generations: 3,
      port: 0, // OS-assigned port
      config: {
        populationSize: 4,
        eliteCount: 2,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'smoke',
      scoreChild: stubScoreChild,
      webRoot: webDir,
    });

    try {
      const addr = server.address();
      const res = await fetch(`http://127.0.0.1:${addr.port}/state`);
      assert.equal(res.status, 200);
      const state = JSON.parse(res.body);
      assert.equal(state.runId, 'smoke');
      assert.ok('generation' in state);
      assert.ok('paused' in state);
    } finally {
      server.close();
      await gaPromise.catch(() => {});
    }
  });
});

test('server POST /vote appends a vote and returns next pair or null', async () => {
  await withTmp(async (root) => {
    const webDir = join(root, 'web', 'tinder');
    await mkdir(webDir, { recursive: true });
    await writeFile(join(webDir, 'index.html'), '<html></html>');

    const { server, gaPromise } = await createTinderServer({
      seed: 1,
      generations: 4,
      port: 0,
      config: {
        populationSize: 4,
        eliteCount: 2,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'vote-test',
      scoreChild: stubScoreChild,
      webRoot: webDir,
    });

    try {
      const addr = server.address();
      // Get the current state to find a valid pair.
      const stateRes = await fetch(`http://127.0.0.1:${addr.port}/state`);
      const state = JSON.parse(stateRes.body);
      if (state.pair) {
        const voteRes = await fetch(`http://127.0.0.1:${addr.port}/vote`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            left_id: state.pair.left.id,
            right_id: state.pair.right.id,
            winner: 'left',
          }),
        });
        assert.equal(voteRes.status, 200);
        const voteBody = JSON.parse(voteRes.body);
        assert.ok('pair' in voteBody, 'vote response should include next pair');
      }
    } finally {
      server.close();
      await gaPromise.catch(() => {});
    }
  });
});

test('server POST /control pause/resume toggles paused state', async () => {
  await withTmp(async (root) => {
    const webDir = join(root, 'web', 'tinder');
    await mkdir(webDir, { recursive: true });
    await writeFile(join(webDir, 'index.html'), '<html></html>');

    const { server, gaPromise } = await createTinderServer({
      seed: 1,
      generations: 3,
      port: 0,
      config: {
        populationSize: 4,
        eliteCount: 2,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'ctrl-test',
      scoreChild: stubScoreChild,
      webRoot: webDir,
    });

    try {
      const addr = server.address();
      // Pause
      const pauseRes = await fetch(`http://127.0.0.1:${addr.port}/control`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'pause' }),
      });
      assert.equal(pauseRes.status, 200);
      // Check state
      const stateRes = await fetch(`http://127.0.0.1:${addr.port}/state`);
      const state = JSON.parse(stateRes.body);
      assert.equal(state.paused, true);
      // Resume
      await fetch(`http://127.0.0.1:${addr.port}/control`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'resume' }),
      });
      const stateRes2 = await fetch(`http://127.0.0.1:${addr.port}/state`);
      const state2 = JSON.parse(stateRes2.body);
      assert.equal(state2.paused, false);
    } finally {
      server.close();
      await gaPromise.catch(() => {});
    }
  });
});

test('server returns 404 for unknown routes', async () => {
  await withTmp(async (root) => {
    const webDir = join(root, 'web', 'tinder');
    await mkdir(webDir, { recursive: true });
    await writeFile(join(webDir, 'index.html'), '<html></html>');

    const { server, gaPromise } = await createTinderServer({
      seed: 1,
      generations: 2,
      port: 0,
      config: {
        populationSize: 4,
        eliteCount: 1,
        tournamentSize: 2,
        tier1MutationStrength: 0.1,
        regressionThreshold: 0.9,
      },
      outRoot: root,
      runId: 'r404',
      scoreChild: stubScoreChild,
      webRoot: webDir,
    });

    try {
      const addr = server.address();
      const res = await fetch(`http://127.0.0.1:${addr.port}/nonexistent`);
      assert.equal(res.status, 404);
    } finally {
      server.close();
      await gaPromise.catch(() => {});
    }
  });
});
