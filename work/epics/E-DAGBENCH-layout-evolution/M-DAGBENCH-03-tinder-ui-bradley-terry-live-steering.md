---
id: M-DAGBENCH-03-tinder-ui-bradley-terry-live-steering
epic: E-DAGBENCH-layout-evolution
status: complete
depends_on: M-DAGBENCH-02-ga-loop-islands-regression-guard
approved_at: 2026-04-08
---

# M-DAGBENCH-03: Tinder UI + Bradley-Terry Refit + Live Steering

## Goal

Add human aesthetic preference to the GA without contaminating selection: a Tinder-style pairwise voting page reads thumbnails from a live run, votes append to `run/tinder.jsonl`, and every K generations the GA refits the energy-term weights via a Bradley-Terry-style preference model with temporal decay. Pause / protect / kill controls let an operator steer a focused voting session. After this milestone, ~50 votes produce a visible, stable weight shift that alters the next generation's elite — on unseen graphs, not just the ones the operator voted on.

## Context

M-DAGBENCH-02 shipped a headless island GA with per-generation snapshots, regression guard, gallery, and a working run loop. Since then, several follow-on chores have cleaned and tightened the substrate M-03 builds on:

- **Calibration chore (`1daa360`):** smoothed `envelope` and `repel_*` energy cliffs; re-baselined the default weights so no single term dominates the gradient at baseline; integration test tightened from `bestMean ≤ baselineMean` to strict `<`.
- **Sensitivity analysis + genome cleanup (2026-04-08, D-2026-04-08-026):** empirical sensitivity script (`bench/scripts/sensitivity.js`) measured every Tier 1 field's effect on scalar fitness. **7 of the original 15 fields produced zero delta** — `render.trunkY` (translation-invariant in every energy term), `render.progressivePower`, `render.cornerRadius`, and the 4 `lane.weight_*` fields. They were removed. Tier 2 was also removed entirely: `routing_primitive` is locked to bezier in the evaluator's DEFAULT_RENDER, and the other two Tier 2 fields were never consumed. **Tier 1 is now 8 live fields**: `render.layerSpacing`, `render.mainSpacing`, `render.subSpacing`, `render.scale`, `energy.stretch_ideal_factor`, `energy.repel_threshold_px`, `energy.channel_min_separation_px`, `energy.envelope_target_ratio`.
- **Introgression migration (D-2026-04-08-027):** islands are now "random subpopulations with ring-topology migration" rather than "one population per routing primitive." Default: 3 islands, migrate every 10 generations, rate 0.05 (1 individual per 20-pop island per event). Migrants are picked via tournament (best individuals migrate) and placed in the next island on the ring with their `island` field rewritten.
- **Determinism relaxation (D-2026-04-08-024):** the bench GA no longer asserts byte-identical snapshots across runs. What it asserts is *convergence within tolerance*. Seeded PRNG stays for debugging, but tests don't assert exact reproducibility. Vote-count temporal decay in M-03's BT refit remains the recommendation for interpretability but is no longer forced by the determinism contract.
- **Bench scope lock (D-2026-04-08-025):** metro-map DAG layouts only. `layoutFlow` (process-mining / Celonis-style with info cards) and `layoutHasse` are explicitly out of scope. The `bend` term stays in the energy function — it correctly measures smooth passage of routes through station waypoints, which is the right metric for the metro-map aesthetic.

M-03 closes the human-in-the-loop gap on top of that substrate. The epic constraint is that steering is **indirect**: votes must not bias selection inside a generation (that would overfit to the exact graphs the voter saw). Instead, votes refit the scalar energy's term weights, and the GA's normal selection/elitism machinery operates on the new weighted sum. Weights generalize across graphs; per-individual preferences do not.

Everything M-03 adds lives in `dag-map/bench/` alongside the M-02 runner. The runner itself is extended, not replaced: a new `bench/scripts/tinder.js` entry point hosts both a minimal HTTP server (for the UI and vote ingest) and the GA loop in a single Node process. A single-process design avoids cross-process coordination for pause/protect/kill events and lets votes, weight refits, and GA generations share in-memory state safely. The existing `bench/scripts/run.js` headless path remains and stays green.

## Acceptance Criteria

1. **Pairwise vote log**
   - [ ] Votes append to `bench/run/<run-id>/tinder.jsonl` as one JSON line per vote
   - [ ] Each line carries `{ts, run_id, generation, left_id, right_id, winner, voter_note?}` where `winner ∈ {"left", "right", "skip", "tie"}`
   - [ ] Append-only; no in-place edits; truncated or corrupt lines are reported and skipped on read
   - [ ] Appends are single-writer (only the server process writes; browser tabs never touch the file)
   - [ ] Round-trip test: write N votes, read them back, identical structure and order

2. **Bradley-Terry-style weight refit with temporal decay** (`bench/ga/refit.mjs`)
   - [ ] `refitWeights({votes, individuals, priorWeights, halfLifeVotes, regularization})` returns an updated weight vector
   - [ ] Each non-skip, non-tie vote is modeled as a preference `winner ≻ loser` with likelihood `logistic(w · (terms(loser) - terms(winner)))` (lower energy = winner, so preferred individuals have lower weighted sum)
   - [ ] Skip and tie votes are logged but do NOT contribute to the likelihood in M-03
   - [ ] **Temporal decay is in vote-count space, not wall-clock.** Vote `i` contributes weight `2^(-(N - i) / halfLifeVotes)` where `N` is the total non-trivial vote count at refit time. Vote-count decay is chosen over wall-clock for interpretability ("recent votes matter more than old votes" is a cleaner mental model than "votes decay with calendar days"); the previous determinism-based justification is moot since the bench GA no longer asserts strict byte-identical reproducibility (D-2026-04-08-024).
   - [ ] Refit solves an L2-regularized convex objective toward the prior weights; regularization strength is configurable (default keeps small vote counts from swinging weights wildly)
   - [ ] Refit output is clamped so no term weight goes below zero — weights are penalty magnitudes, and a negative weight would flip a term into a reward and break the energy contract. A test asserts the clamp fires when the unconstrained solution would produce a negative value.
   - [ ] Degenerate cases handled: zero new votes, all-skip votes, or fewer than `minVotesForRefit` (default 5) non-trivial votes → return the prior unchanged with a structured reason
   - [ ] Refit is **stable** (small input changes produce small weight changes) and **reproducible given the same inputs** at the level of normal float math. A formal byte-identical test is not required but a "two refits on the same inputs produce identical vectors in one session" test is cheap and worth having.
   - [ ] **Refit operates on the 8 live Tier 1-derived weight entries** (stretch, bend, crossings, monotone, envelope, channel, repel_nn, repel_ne). The prior for the refit is the current working weight vector (`bench/config/default-weights.json` at run start, or the most recent per-generation weight snapshot after any previous refit).

3. **Refit schedule and weight history**
   - [ ] Refit runs every `refitEveryGenerations` generations (default 5, configurable)
   - [ ] If the refit changes the weights, the new vector is written to `bench/run/<run-id>/weights/gen-NNNN.json` and the in-memory weights used by the next generation's `scoreChild` swap to the new vector
   - [ ] If the refit does not change the weights (not enough new votes, or all votes agreed with the prior), the previous vector is reused and no new file is written
   - [ ] Each generation's existing `scores.json` snapshot gains a `weightsFile` field naming the active weight file so the run's weight history is self-documenting
   - [ ] Rollback: a separate helper reads any prior weight file and re-runs the refit from a chosen checkpoint (useful when a vote session proves catastrophic)

4. **Live steering HTTP server** (`bench/scripts/tinder.js`)
   - [ ] `node scripts/tinder.js --run-id <id> --seed <int> --generations <n> [--port 8765]` launches a single Node process that runs the GA and serves the Tinder UI
   - [ ] The server uses only Node core (`node:http`, `node:fs`, `node:path`, `node:url`); no new dependencies in `bench/package.json`
   - [ ] Routes:
     - `GET /` → serves `bench/web/tinder/index.html`
     - `GET /static/*` → serves files under `bench/web/tinder/`
     - `GET /state` → returns JSON `{runId, generation, paused, voteCount, votesSinceLastRefit, currentWeights, pair?}` where `pair` is the current pair to vote on (or `null` when no pair is available yet)
     - `GET /svg/:individualId/:fixtureId` → serves the pre-rendered SVG from the active generation's gallery directory
     - `POST /vote` → accepts `{leftId, rightId, winner, voter_note?}`, appends to `tinder.jsonl`, returns the next pair
     - `POST /control` → accepts `{action, ...}` for `pause`, `resume`, `protect`, `unprotect`, `kill`
   - [ ] The server listens on the configured port (default 8765) and prints the URL on startup
   - [ ] SIGINT exits cleanly: current generation finishes, snapshot is written, HTTP server closes, process exits 0
   - [ ] Pair selection is deterministic under a seeded PRNG: given the same generation's elite, the same seed, and the same vote history, the server selects the same next pair every time

5. **Tinder UI** (`bench/web/tinder/`)
   - [ ] Static `index.html` + `app.mjs` + `style.css`, hand-maintained, no build step
   - [ ] Loads the current pair from `GET /state` on load and after each vote
   - [ ] Shows two elite layouts side-by-side (SVG via `GET /svg/...`) with island labels and generation numbers beneath each
   - [ ] Keyboard shortcuts: `←` = left wins, `→` = right wins, `↓` = tie, `space` = skip
   - [ ] Footer shows: run id, current generation, votes since last refit, total votes, current weight vector (one-line numeric summary)
   - [ ] Pause / resume / protect / kill buttons map to `POST /control` calls with the currently-highlighted individual as the target
   - [ ] Gracefully shows "no pair available — waiting for next generation" when the server has no new elites to compare
   - [ ] DOM smoke test (JSDOM) asserts the root element, key handlers, and state-endpoint contract

6. **Pause / protect / kill controls** (`bench/ga/control.mjs`)
   - [ ] `createControlState()` returns a mutable state carrying `{paused, abortRequested, protectedGenomes, killedIds}`
   - [ ] `POST /control {action: "pause"}` sets `paused=true`; the GA loop halts at the next generation boundary until `paused` flips back to false (cooperative, via a resolvable promise awaited between generations)
   - [ ] `POST /control {action: "protect", id}` stores a deep clone of the named individual's genome in `protectedGenomes` keyed by a stable label
   - [ ] Each generation's initial population includes one clone per protected genome, injected in place of a tournament-bred slot so island size stays constant. Protection therefore persists as an immortal ancestor across generations even though individual IDs change per generation.
   - [ ] `POST /control {action: "kill", id}` removes the named individual from the current generation's population immediately; the ID goes into `killedIds` and subsequent lookups filter it out. Kill does NOT track lineage across generations — the individual's genome simply stops breeding, and its influence decays naturally through selection.
   - [ ] Each control action appends a structured event to `bench/run/<run-id>/control.jsonl`
   - [ ] Unit tests for `control.mjs` cover pause/resume, protect/unprotect, kill, and protected-genome injection into a synthetic population

7. **Runner integration** (`bench/ga/runner.mjs` extensions)
   - [ ] `runGA` accepts an optional `controlState` argument. When present, the runner:
     - Awaits `controlState.paused` flipping to false between generations
     - Consults `controlState.killedIds` and skips killed individuals during `advanceGeneration`
     - Injects one clone per `protectedGenomes` entry into each generation's initial population (replacing the last tournament-bred slot so island size stays constant)
     - Returns early when `controlState.abortRequested` becomes true, after writing the current generation's snapshot
   - [ ] `runGA` accepts an optional `onGenerationComplete({generation, islands, bestEver, runDir, currentWeights})` async hook called after each snapshot write
   - [ ] All existing `runGA` tests stay green — the new parameters are optional and the default path is unchanged
   - [ ] One new runner test uses a synthetic `controlState` to exercise pause/resume across two generations and verify protected genomes survive a regression-guard sweep that would otherwise evict them

8. **Steering does not bypass selection**
   - [ ] Votes never directly modify selection or fitness
   - [ ] The only path from a vote to a selection decision is via the refitted weight vector consumed by `scoreChild`
   - [ ] A grep-style source test asserts `ga/operators.mjs`, `ga/generation.mjs`, and `ga/islands.mjs` contain no reference to `tinder.jsonl`, the vote log, or the refit module

9. **Visible weight shift from a focused vote session**
   - [ ] Integration test: seed a `tinder.jsonl` with at least 50 votes that consistently prefer layouts with a specific term's value being low; run the refit; assert that term's weight increases above its prior value by at least a documented minimum delta (e.g., 10%)
   - [ ] Assert the refitted weights, when used in the next generation's `scoreChild`, produce at least one elite individual whose ID differs from the unsteered control run

10. **End-to-end convergence with a vote log**
   - [ ] Given a fixed seed, fixed config, and a fixed pre-populated `tinder.jsonl`, two independent runs reach comparable final fitness within a documented tolerance (default 10% on the best-individual fitness) AND produce comparable final weight vectors (L2 distance within tolerance)
   - [ ] Integration test pre-populates a vote log before starting the runner, runs to completion twice, and asserts the final fitness + final weights are within tolerance
   - [ ] This replaces the earlier "byte-identical" contract (D-2026-04-08-024). The bench is a developer tool; convergence is what we actually care about.

## Scope

### In Scope

- `tinder.jsonl` append-only log with single-writer discipline
- Single-process Node server hosting both the UI and the GA loop
- Static hand-maintained Tinder UI (plain ES modules, no build step)
- Bradley-Terry-style preference refit with vote-count temporal decay, L2 regularization toward the prior, and zero-clamping
- Weight history (`bench/run/<run-id>/weights/gen-NNNN.json`) and rollback helper
- Pause / protect / kill controls via HTTP with persistent genome-based protection
- Runner extensions: `controlState`, `onGenerationComplete`, protected-genome injection
- Per-generation weight-file bookkeeping in `scores.json`

### Out of Scope

- Multi-user or remote Tinder sessions — this is a local dev tool, no authentication, no CORS
- Wall-clock temporal decay (decay is strictly in vote-count space for reproducibility)
- Direct selection bias from votes (explicitly forbidden — enforced by a grep-style source test)
- Tie handling in the BT likelihood (ties and skips are logged but not consumed by the refit in M-03; future refinement)
- Automatic UI bundling, hot reload, or framework dependencies — the UI is plain ES modules served from disk
- Replacement of the repo-level `bench/config/default-weights.json` — refits write to per-run weight files; the global default is untouched
- Cross-run vote reuse (each run has its own `tinder.jsonl`; migrating votes across runs is a follow-up)
- Live editing of individual genomes from the UI (only whole-individual protect/kill)
- Kill-lineage tracking across generations (kill is single-generation; influence decays through natural selection)
- External corpora (Tier C) — M-DAGBENCH-04
- Any change to the `runGA` determinism contract when no `controlState` or `onGenerationComplete` is supplied

## Dependencies

- M-DAGBENCH-02 complete: `runGA`, island model, regression guard, `scoreIndividual`, gallery writer
- Calibration chore (`1daa360`) — smoothed energy cliffs and re-baselined default weights
- Sensitivity + genome cleanup chore (2026-04-08) — Tier 1 is 8 live fields, Tier 2 removed, `bend`/`crossings`/`monotone` kept as-is, ring-topology introgression migration added, determinism relaxed. See D-2026-04-08-024 through D-2026-04-08-027.
- `dag-map`'s `dagMap()` convenience (already used by the gallery writer) — the Tinder server reuses the same render path

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tinder fatigue: too few votes to shift weights | Med | Vote-count temporal decay so few-but-recent votes still matter; default `refitEveryGenerations=5` so refits happen frequently; UI shows progress to next refit |
| BT refit becomes unstable with sparse votes | High | L2 regularization toward the prior; minimum-votes-for-refit gate (default 5); zero-clamping; weight history allows rollback |
| Refit produces a negative weight that flips a penalty into a reward | High | Post-optimization clamp to `≥ 0`; explicit test that the clamp fires when the unconstrained solution would go negative |
| Single-process server starves the GA loop or vice versa | Med | GA runs in the Node event loop between `await`s; HTTP handlers are non-blocking; per-individual scoring already chunks the generation work into many small awaits |
| Wall-clock decay would break determinism | Med | Decay is strictly in vote-count space; a determinism test pre-populates `tinder.jsonl` and asserts byte-identical refits across runs |
| Protect-by-genome leaks memory across long runs | Low | Protect is intentional and few per session; capacity limit (default 16) caps total protected genomes |
| Pair selection overfits to one island's taste | Med | Pair selection alternates same-island and cross-island pairs under a seeded PRNG; deterministic across runs with the same vote history |
| Operator clicks vote into the energy function as a 9th term | Med | Grep-style source test asserts `operators.mjs`/`generation.mjs`/`islands.mjs` never reference the vote log or refit module |
| `tinder.jsonl` append race between multiple browser tabs | Low | Single-writer discipline: only the server process writes to the log; browser tabs always go through `POST /vote` |
| Refit's optimizer needs hyperparameter tuning per session | Med | Use a closed-form or warm-started Newton iteration with fixed step count, not an ad-hoc gradient loop — keeps the refit deterministic and parameter-free beyond L2 λ |
| Server port conflicts with another local process | Low | Configurable `--port`; default 8765 (high range, low collision likelihood); error message names the port if `EADDRINUSE` |

## Test Strategy

- **`refit.mjs` unit tests** with hand-constructed synthetic vote logs:
  - Single-term-preferring vote set: refit moves only that term's weight in the expected direction
  - Prior-preserving vote set (every vote agrees with the prior): refit returns the prior unchanged
  - Empty / all-skip / below-minimum vote logs: refit returns the prior with a structured "no refit" reason
  - Would-be-negative weight: clamped to zero, test asserts the clamp fires
  - Temporal decay: vote log with a stale dissenting vote and many recent concurring votes → refit moves toward concurring
  - Determinism: two refits with the same inputs are byte-identical
- **`control.mjs` unit tests**: pause/resume, protect/unprotect, kill, protected-genome injection into a synthetic population, control event log round-trip
- **Runner integration tests** (extending `ga/__tests__/runner.test.mjs`): synthetic `controlState` pauses between generations and then resumes; protected genomes survive a regression-guard sweep that would otherwise evict them; killed IDs do not reappear in the next generation
- **HTTP server smoke tests** (`scripts/__tests__/tinder.test.mjs`): spin up the server on an ephemeral port, issue `GET /`, `GET /state`, `POST /vote` with a known pair, `POST /control {action: "pause"}`, assert state transitions and vote-log appends
- **Steering integration test**: 50 synthetic votes preferring a specific term → refit produces measurable weight delta → next generation produces a different elite from the unsteered control run
- **End-to-end determinism**: pre-populate `tinder.jsonl`, run twice, deep-diff per-generation snapshots and weight history
- **No-direct-bias source test**: grep `ga/operators.mjs`, `ga/generation.mjs`, `ga/islands.mjs` and assert no reference to `tinder.jsonl`, `refit`, or vote-related identifiers
- **Tinder UI**: lightweight DOM smoke test (JSDOM) that loads `index.html`, calls the bootstrap, and asserts key elements + keyboard handlers are wired

## Deliverables

- `dag-map/bench/ga/refit.mjs` — Bradley-Terry-style weight refit with L2 regularization, vote-count temporal decay, and zero-clamping
- `dag-map/bench/ga/control.mjs` — pause / protect / kill state machine
- `dag-map/bench/ga/runner.mjs` — extended with `controlState`, `onGenerationComplete`, and protected-genome injection
- `dag-map/bench/scripts/tinder.js` — HTTP server + GA driver entry point
- `dag-map/bench/web/tinder/index.html`, `app.mjs`, `style.css` — static UI (hand-maintained, no build step)
- `dag-map/bench/run/<run-id>/tinder.jsonl` — vote log (gitignored runtime artifact)
- `dag-map/bench/run/<run-id>/weights/gen-NNNN.json` — per-refit weight snapshots (runtime artifact)
- `dag-map/bench/run/<run-id>/control.jsonl` — control event log (runtime artifact)
- Tracking doc: `work/epics/E-DAGBENCH-layout-evolution/M-DAGBENCH-03-tracking.md`

## Validation

- `cd dag-map/bench && npm test` — full suite green; refit, control, runner-extension, server-smoke, steering integration, end-to-end determinism, and no-direct-bias source tests all pass
- `cd dag-map && npm test` — dag-map main package (285 tests) still green
- Manual smoke: `node scripts/tinder.js --run-id manual-smoke --seed 1 --generations 20 --port 8765`, open `http://localhost:8765`, cast ~10 votes across the refit boundary, observe weights change in the footer and persist to `bench/run/manual-smoke/weights/gen-0005.json`
- No new dependencies in `dag-map/package.json` or `dag-map/bench/package.json` — refit and HTTP server are both written against Node core
- Selection code path contains no reference to the vote log or refit module outside the documented weight-injection point in `runGA`

## References

- `work/epics/E-DAGBENCH-layout-evolution/epic.md` — especially the "Human steering via Bradley-Terry weight refit" and "Live steering architecture" paragraphs under Approach
- `work/epics/E-DAGBENCH-layout-evolution/M-DAGBENCH-02-ga-loop-islands-regression-guard.md` — the GA this milestone steers
- `work/epics/E-DAGBENCH-layout-evolution/M-DAGBENCH-01-energy-function-corpus-evaluator.md` — the energy function whose weights are being refit
- `dag-map/bench/ga/runner.mjs` — current runner that will be extended
- `dag-map/bench/config/default-weights.json` — the prior weight vector that refits start from
- Bradley-Terry model: classical pairwise comparison model; the refit here is equivalent to an L2-regularized logistic regression where features are per-term score differences between paired individuals
