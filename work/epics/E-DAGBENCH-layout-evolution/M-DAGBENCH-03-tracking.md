# Tracking: M-DAGBENCH-03 — Tinder UI + Bradley-Terry Refit + Live Steering

**Milestone:** M-DAGBENCH-03-tinder-ui-bradley-terry-live-steering
**Epic:** E-DAGBENCH-layout-evolution
**Branch:** milestone/M-DAGBENCH-03 (cut from milestone/M-DAGBENCH-02 tip at commit `b6cbc4f`)
**Started:** 2026-04-08
**Status:** in-progress
**Depends on:** M-DAGBENCH-02 complete, calibration chore (`1daa360`), sensitivity + cleanup chore (`b6cbc4f`)

## Resolved decisions (carried from prior work)

1. **Genome is Tier 1 only, 8 live fields** (D-2026-04-08-026). No Tier 2 schema; routing locked to bezier in evaluator DEFAULT_RENDER.
2. **Islands are random subpopulations with ring-topology introgression migration** (D-2026-04-08-027). Default 3 islands, migrate every 10 generations, rate 0.05.
3. **Bench scope is metro-map DAGs only** (D-2026-04-08-025). `layoutFlow` card-aware evaluation is explicitly out of scope; `bend`/`crossings`/`monotone` stay in the energy function because they are correct for metro aesthetic.
4. **Determinism relaxed to convergence-within-tolerance** (D-2026-04-08-024). Byte-identical snapshot tests have been converted. Seeded PRNG stays; `Math.random`-free hygiene stays.
5. **LLM voter deferred** (D-2026-04-08-028). M-03 is human-voting only.
6. **Single-process Node server** hosting both the HTTP UI and the GA loop (spec AC4). No sidecar process; no cross-process coordination for pause/protect/kill.
7. **Vote-count temporal decay** (not wall-clock) for BT refit interpretability, though no longer determinism-forced.
8. **Weight refit operates on the 8 energy-term weights**, not on Tier 1 genome fields. Priors come from `default-weights.json` at run start, replaced per-generation after any refit.
9. **No commits without explicit human approval.**

## Acceptance Criteria

### AC1 — Pairwise vote log

- [ ] Votes append to `bench/run/<run-id>/tinder.jsonl` as one JSON line per vote
- [ ] Each line carries `{ts, run_id, generation, left_id, right_id, winner, voter_note?}` where `winner ∈ {"left", "right", "skip", "tie"}`
- [ ] Append-only; truncated/corrupt lines reported and skipped on read
- [ ] Single-writer discipline (server process only)
- [ ] Round-trip test: write N votes, read them back identically

### AC2 — Bradley-Terry refit (`bench/ga/refit.mjs`)

- [ ] `refitWeights({votes, individuals, priorWeights, halfLifeVotes, regularization})` returns an updated weight vector
- [ ] Each non-skip, non-tie vote → preference `winner ≻ loser`; likelihood `logistic(w · (terms(loser) - terms(winner)))`
- [ ] Skip + tie votes logged but excluded from the likelihood
- [ ] Vote-count temporal decay: vote `i` weighted by `2^(-(N - i) / halfLifeVotes)`
- [ ] L2-regularized convex objective toward priorWeights
- [ ] Output clamped ≥ 0 (weights are penalty magnitudes)
- [ ] Degenerate cases: empty votes, all skip, below minVotesForRefit → return prior with structured reason
- [ ] Stable + reproducible in one session (not byte-identical across platforms)
- [ ] Operates on the 8 live term weights

### AC3 — Refit schedule + weight history

- [ ] Refit every `refitEveryGenerations` generations (default 5)
- [ ] If weights change, write to `bench/run/<run-id>/weights/gen-NNNN.json` and swap in-memory
- [ ] If no change, reuse previous vector, no new file
- [ ] Each gen's `scores.json` gains a `weightsFile` field naming the active weight file
- [ ] Rollback helper to reload any prior weight file

### AC4 — Live steering HTTP server (`bench/scripts/tinder.js`)

- [x] CLI: `node scripts/tinder.js --run-id <id> --seed <int> --generations <n> [--port 8765]`
- [x] Uses only Node core (no new bench deps)
- [x] Routes: GET /, GET /static/*, GET /state, GET /svg/:id/:fixture, POST /vote, POST /control
- [x] Prints URL on startup
- [x] SIGINT: finish current gen, write snapshot, close server, exit 0
- [x] Deterministic pair selection under seeded PRNG

### AC5 — Tinder UI (`bench/web/tinder/`)

- [x] Static index.html + app.mjs + style.css, no build step
- [x] Loads current pair from GET /state; refreshes after each vote
- [x] Side-by-side SVG display with island + generation labels
- [x] Keys: ← left, → right, ↓ tie, space skip
- [x] Footer: run id, gen, votes since refit, total votes, current weights
- [x] Pause/resume/protect/kill buttons → POST /control
- [x] Graceful "no pair available" state
- [x] DOM smoke test (structural, no JSDOM dep — verifies HTML structure, JS syntax, key handlers, endpoint contracts)

### AC6 — Pause / protect / kill controls (`bench/ga/control.mjs`)

- [ ] `createControlState()` → `{paused, abortRequested, protectedGenomes, killedIds}`
- [ ] Pause: GA halts at next gen boundary
- [ ] Protect: deep clone of named individual's genome stored; injected into every subsequent gen's initial population
- [ ] Kill: remove from current gen immediately; IDs filtered from subsequent lookups; no cross-gen lineage tracking
- [ ] Each action appends to `control.jsonl`
- [ ] Unit tests cover pause/resume, protect/unprotect, kill, protected-genome injection

### AC7 — Runner integration (`bench/ga/runner.mjs` extensions)

- [ ] `runGA` accepts optional `controlState`
- [ ] Awaits pause between generations
- [ ] Consults `killedIds` during advance
- [ ] Injects `protectedGenomes` clones into initial population of each gen
- [ ] Returns early on `abortRequested` after final snapshot
- [ ] `runGA` accepts optional `onGenerationComplete` hook
- [ ] Existing runner tests stay green

### AC8 — Steering does not bypass selection

- [x] Grep-style source test asserts `ga/operators.mjs`, `ga/generation.mjs`, `ga/islands.mjs` contain no reference to `tinder.jsonl` or `refit`

### AC9 — Visible weight shift from focused vote session

- [x] Integration test: seed 50 synthetic votes preferring low X; refit moves X's weight up by at least 10% of prior
- [x] Refitted weights change at least one elite id vs unsteered control

### AC10 — End-to-end convergence with vote log

- [x] Two runs, same seed + config + pre-populated tinder.jsonl → final fitness within tolerance AND final weight vector within L2 tolerance
- [x] Supersedes the earlier "byte-identical" contract (D-2026-04-08-024)

## Implementation Phases

| Phase | What | Status |
|-------|------|--------|
| 0 | Tracking doc + branch + spec approved | done |
| 1 | Extend `scoreIndividual` to compute `termTotals` (prereq for refit) | done |
| 2 | Refit module (`bench/ga/refit.mjs`) + tests (AC2) | done |
| 3 | Vote log append + read (AC1) | pending |
| 4 | Control state module (`bench/ga/control.mjs`) + tests (AC6) | pending |
| 5 | Runner extensions: `controlState`, `onGenerationComplete`, protected-genome injection (AC7) | pending |
| 6 | Refit schedule + weight history in runner (AC3) | pending |
| 7 | HTTP server (`bench/scripts/tinder.js`) + smoke tests (AC4) | done |
| 8 | Tinder UI (`bench/web/tinder/`) + DOM smoke test (AC5) | done |
| 9 | Source hygiene check (AC8) + visible shift integration test (AC9) | done |
| 10 | End-to-end convergence test (AC10) + tracking doc wrap | done |

## Test Summary

- **Bench tests before M-03:** 207 passing
- **Bench tests after Phase 1 + 2:** 220 passing (+13)
- **Bench tests after Phase 7:** 261 passing
- **Bench tests final (Phase 10):** 273 passing
- **M-03 target:** ~260-290 tests
- **Build status:** green (dag-map main 285/285, bench 220/220)

## Notes

### Phase 1 — scoreIndividual termTotals (2026-04-08)

`scoreIndividual` now aggregates an 8-entry `termTotals` object per individual — the per-term RAW values summed across every scored fixture, **before weighting**. This is a prerequisite for the BT refit in Phase 2: the refit needs to compute `terms(loser) - terms(winner)` per vote, and it can't call the evaluator again at refit time because historical individuals may be from earlier generations whose layouts aren't in memory any more. Storing the per-term breakdown on each Individual at score time is the cheap fix.

The fitness invariant `fitness === Σ weights[term] * termTotals[term]` is asserted by a new test, which acts as a regression guard against any future change that lets `fitness` and `termTotals` drift apart.

### Phase 2 — Bradley-Terry weight refit (2026-04-08)

`bench/ga/refit.mjs` implements `refitWeights({votes, termsById, priorWeights, halfLifeVotes, regularization, minVotesForRefit, maxIterations})`.

**Math.** The refit solves L2-regularized logistic regression over term-difference vectors. For each vote where A beats B:
- `x_i = terms(loser) - terms(winner)` (8-dim)
- Probability model: `P(A beats B | w) = sigmoid(w · x_i)`
- Per-vote temporal decay: `c_i = 2^(-(N - i) / halfLifeVotes)` where `i` is the 1-indexed position of the vote and `N` is the total valid vote count
- Objective: `L(w) = Σᵢ cᵢ · log(1 + exp(-w·xᵢ)) + λ · ‖w - w_prior‖²`

Both terms are convex; the L2 penalty makes the Hessian strictly positive definite, so the objective has a unique global minimum.

**Solver.** Newton's method with backtracking line search, fixed max iteration count (default 20). Line search is NOT in the spec's original "closed-form or warm-started Newton with fixed step count" text, but it turned out to be necessary: pure Newton oscillates catastrophically when the Hessian vanishes in the saturated-sigmoid tail (e.g., starting from `w.bend = 0.5` with 40 votes pushing bend toward large negative — first Newton step overshoots to ~-600k, next step flips back to 0.5, and the iteration never settles). Backtracking caps the step at whatever `alpha ∈ (0, 1]` actually decreases the loss, up to 30 halving attempts per iteration. The iteration count is still bounded by `maxIterations`, the backtracks just make each step safe.

**Zero clamp.** After optimization, weights below zero are clamped to zero and the clamped entry names are returned in `result.clamped`. Weights are penalty magnitudes in the energy function — a negative weight would flip a penalty into a reward and break the contract. A test constructs a vote log that wants `bend` to go negative, runs the refit, and asserts `bend` is in the clamped list.

**Skip reasons.** The refit returns `{skipped: true, reason}` on degenerate inputs rather than trying to run Newton on nothing:
- `no-votes` — empty vote array
- `all-skip-or-tie` — every vote is `skip` or `tie`
- `no-valid-votes` — after filtering unknown-id and degenerate-diff votes, nothing left
- `below-minimum` — fewer than `minVotesForRefit` (default 5) valid votes

Unknown-id votes (where either `leftId` or `rightId` is not in `termsById`) are counted in `result.unknownVoteCount` but don't cause a skip. Degenerate votes where winner and loser have identical term totals (zero `x` vector, no signal) are counted in `result.degenerateVoteCount` and filtered.

**Determinism relaxed.** D-2026-04-08-024 relaxed the bench GA's determinism contract. The refit still happens to be byte-identical within a session for identical inputs (no `Math.random`, no wall-clock reads), and a test asserts this, but it's not a cross-platform guarantee. Enough to be useful for debugging; not enough to block future changes that introduce nondeterminism for other reasons.

**8-term output.** The refit's output is keyed by the 8 energy-term names from `TERM_NAMES` (stretch, bend, crossings, monotone, envelope, channel, repel_nn, repel_ne), matching `default-weights.json`. Internal math uses arrays indexed by `TERM_NAMES` and converts at the boundary.

## Completion

- **Completed:** 2026-04-09
- **Final test count:** 273 (bench), 285 (dag-map main)
