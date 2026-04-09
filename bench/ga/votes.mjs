// votes.mjs — append-only JSONL vote log for the Tinder UI.
//
// One line per vote. Single-writer discipline: only the server process
// writes to the log; browser tabs always go through POST /vote. Appends
// use Node's `fs.appendFile`, which opens with O_APPEND — on POSIX, a
// single write smaller than PIPE_BUF (typically 4096 bytes) is atomic,
// and a vote line is well under that threshold.
//
// Reads recover from corrupt lines: malformed JSON or structurally
// invalid records are skipped and counted, not fatal. The good-faith
// assumption is that any corrupt line is from a partial crash during
// shutdown, and the surrounding valid votes should still be usable.
//
// The vote schema is validated on append so garbage can't enter the log
// through the API:
//
//   {
//     ts:         ISO-8601 string
//     run_id:     string
//     generation: integer
//     left_id:    string
//     right_id:   string
//     winner:     'left' | 'right' | 'skip' | 'tie'
//     voter_note: string (optional)
//   }

import { appendFile, readFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export const VOTE_WINNERS = ['left', 'right', 'skip', 'tie'];

const REQUIRED_FIELDS = ['ts', 'run_id', 'generation', 'left_id', 'right_id', 'winner'];

function validateVote(vote) {
  if (!vote || typeof vote !== 'object') {
    throw new Error('appendVote: vote must be an object');
  }
  for (const field of REQUIRED_FIELDS) {
    if (vote[field] === undefined || vote[field] === null) {
      throw new Error(`appendVote: vote is missing required field "${field}"`);
    }
  }
  if (!VOTE_WINNERS.includes(vote.winner)) {
    throw new Error(
      `appendVote: winner must be one of ${JSON.stringify(VOTE_WINNERS)}, got ${JSON.stringify(vote.winner)}`,
    );
  }
  if (typeof vote.ts !== 'string') {
    throw new Error('appendVote: ts must be a string');
  }
  if (typeof vote.run_id !== 'string') {
    throw new Error('appendVote: run_id must be a string');
  }
  if (!Number.isInteger(vote.generation)) {
    throw new Error('appendVote: generation must be an integer');
  }
  if (typeof vote.left_id !== 'string' || typeof vote.right_id !== 'string') {
    throw new Error('appendVote: left_id and right_id must be strings');
  }
}

export async function appendVote(path, vote) {
  validateVote(vote);
  await mkdir(dirname(path), { recursive: true });
  const line = JSON.stringify(vote) + '\n';
  await appendFile(path, line, 'utf8');
}

function isStructurallyValid(obj) {
  if (!obj || typeof obj !== 'object') return false;
  for (const field of REQUIRED_FIELDS) {
    if (obj[field] === undefined || obj[field] === null) return false;
  }
  if (!VOTE_WINNERS.includes(obj.winner)) return false;
  return true;
}

export async function readVotes(path) {
  let raw;
  try {
    raw = await readFile(path, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return { votes: [], skippedCount: 0, skippedLines: [] };
    throw err;
  }
  const lines = raw.split('\n');
  const votes = [];
  const skippedLines = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.length === 0) continue; // blank lines (including trailing EOF newline) are not errors
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch (err) {
      skippedLines.push({ line: i + 1, reason: 'parse-error', message: err.message });
      continue;
    }
    if (!isStructurallyValid(parsed)) {
      skippedLines.push({ line: i + 1, reason: 'invalid-shape' });
      continue;
    }
    votes.push(parsed);
  }
  return { votes, skippedCount: skippedLines.length, skippedLines };
}
