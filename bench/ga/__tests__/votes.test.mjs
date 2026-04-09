import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { appendVote, readVotes, VOTE_WINNERS } from '../votes.mjs';

async function withTmp(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'dag-map-bench-votes-'));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function mkVote(overrides = {}) {
  return {
    ts: '2026-04-08T12:00:00.000Z',
    run_id: 'test-run',
    generation: 1,
    left_id: 'ind-a',
    right_id: 'ind-b',
    winner: 'left',
    ...overrides,
  };
}

test('VOTE_WINNERS exports the four allowed winner values', () => {
  assert.deepEqual([...VOTE_WINNERS].sort(), ['left', 'right', 'skip', 'tie']);
});

test('appendVote creates the parent directory and file when neither exists', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'nested', 'dir', 'tinder.jsonl');
    await appendVote(path, mkVote());
    const raw = await readFile(path, 'utf8');
    assert.match(raw, /"left_id":"ind-a"/);
    assert.ok(raw.endsWith('\n'));
  });
});

test('appendVote appends to an existing file without overwriting', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    await appendVote(path, mkVote({ left_id: 'first' }));
    await appendVote(path, mkVote({ left_id: 'second' }));
    await appendVote(path, mkVote({ left_id: 'third' }));
    const raw = await readFile(path, 'utf8');
    const lines = raw.trim().split('\n');
    assert.equal(lines.length, 3);
    assert.match(lines[0], /"left_id":"first"/);
    assert.match(lines[1], /"left_id":"second"/);
    assert.match(lines[2], /"left_id":"third"/);
  });
});

test('readVotes reads back what was written, in order', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    const votes = [
      mkVote({ left_id: '1', winner: 'left' }),
      mkVote({ left_id: '2', winner: 'right' }),
      mkVote({ left_id: '3', winner: 'tie' }),
      mkVote({ left_id: '4', winner: 'skip' }),
    ];
    for (const v of votes) await appendVote(path, v);
    const result = await readVotes(path);
    assert.equal(result.votes.length, 4);
    for (let i = 0; i < votes.length; i++) {
      assert.equal(result.votes[i].left_id, votes[i].left_id);
      assert.equal(result.votes[i].winner, votes[i].winner);
    }
    assert.equal(result.skippedCount, 0);
  });
});

test('readVotes returns an empty array when the file does not exist', async () => {
  await withTmp(async (root) => {
    const result = await readVotes(join(root, 'missing.jsonl'));
    assert.deepEqual(result.votes, []);
    assert.equal(result.skippedCount, 0);
  });
});

test('readVotes skips malformed lines and reports the count', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    const bad1 = '{ not valid json';
    const good1 = JSON.stringify(mkVote({ left_id: 'good-1' }));
    const bad2 = ''; // empty line — should be silently skipped, not counted
    const good2 = JSON.stringify(mkVote({ left_id: 'good-2' }));
    const bad3 = '{"missing":"fields"}'; // parseable but missing winner
    await writeFile(path, `${bad1}\n${good1}\n${bad2}\n${good2}\n${bad3}\n`, 'utf8');
    const result = await readVotes(path);
    assert.equal(result.votes.length, 2);
    assert.equal(result.votes[0].left_id, 'good-1');
    assert.equal(result.votes[1].left_id, 'good-2');
    assert.equal(result.skippedCount, 2); // bad1 + bad3
  });
});

test('readVotes reports the line number of the first skipped line for debugging', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    const good = JSON.stringify(mkVote());
    await writeFile(path, `${good}\n{ oops\n${good}\n`, 'utf8');
    const result = await readVotes(path);
    assert.equal(result.skippedCount, 1);
    assert.ok(Array.isArray(result.skippedLines));
    assert.equal(result.skippedLines.length, 1);
    assert.equal(result.skippedLines[0].line, 2);
  });
});

test('appendVote rejects a vote whose winner is not in VOTE_WINNERS', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    await assert.rejects(
      () => appendVote(path, mkVote({ winner: 'maybe' })),
      /winner must be one of/,
    );
    // Nothing should have been written.
    await assert.rejects(() => readFile(path), /ENOENT/);
  });
});

test('appendVote rejects a vote missing required fields', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    for (const missing of ['left_id', 'right_id', 'winner', 'run_id', 'generation', 'ts']) {
      const v = mkVote();
      delete v[missing];
      await assert.rejects(
        () => appendVote(path, v),
        (err) => {
          assert.match(err.message, new RegExp(`missing.*${missing}`));
          return true;
        },
        `expected rejection for missing ${missing}`,
      );
    }
  });
});

test('round-trip: write 100 votes, read them all back, every field preserved', async () => {
  await withTmp(async (root) => {
    const path = join(root, 'tinder.jsonl');
    const winners = ['left', 'right', 'tie', 'skip'];
    const written = [];
    for (let i = 0; i < 100; i++) {
      const v = mkVote({
        left_id: `g${i}-l`,
        right_id: `g${i}-r`,
        winner: winners[i % 4],
        generation: Math.floor(i / 10),
        voter_note: i % 7 === 0 ? `note-${i}` : undefined,
      });
      await appendVote(path, v);
      written.push(v);
    }
    const result = await readVotes(path);
    assert.equal(result.votes.length, 100);
    assert.equal(result.skippedCount, 0);
    for (let i = 0; i < 100; i++) {
      assert.equal(result.votes[i].left_id, written[i].left_id);
      assert.equal(result.votes[i].right_id, written[i].right_id);
      assert.equal(result.votes[i].winner, written[i].winner);
      assert.equal(result.votes[i].generation, written[i].generation);
      if (written[i].voter_note) {
        assert.equal(result.votes[i].voter_note, written[i].voter_note);
      }
    }
  });
});
