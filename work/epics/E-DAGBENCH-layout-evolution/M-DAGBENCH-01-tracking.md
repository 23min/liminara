# Tracking: M-DAGBENCH-01 — Energy Function + Corpus + Evaluator

**Milestone:** M-DAGBENCH-01-energy-function-corpus-evaluator
**Epic:** E-DAGBENCH-layout-evolution
**Branch:** milestone/M-DAGBENCH-01
**Started:** 2026-04-07
**Status:** implementation-complete (awaiting review + human-approved commit)

## Resolved decisions (carried in from session brief)

1. **Tier B source path**: env var `LIMINARA_ROOT`, defaults to `../..` relative to `dag-map/bench/`. KISS.
2. **Tier B is a snapshot**, not live read. Snapshot target: `dag-map/bench/fixtures/tier-b/`. M-01 only needs the snapshot mechanism plus 1-2 sample fixtures.
3. **Code location**: `dag-map/bench/`, gitignored in the dag-map submodule. Submodule .gitignore changes need explicit human approval before commit.
4. **JS throughout**, using node:test (matching dag-map's existing convention) — no vitest dependency.
5. **No new deps** in dag-map main `package.json`. Bench-only deps live in `dag-map/bench/package.json`.
6. **No commits** of any kind without explicit human approval.
7. **Tracking path** follows the milestone spec deliverables list (`work/milestones/tracking/<epic>/<milestone-id>-tracking.md`), not the epic-folder convention used by older milestones.

## Acceptance Criteria

### AC1 — Energy terms (eight, unit-tested in isolation)

- [x] `stretch` — penalizes edges longer than `stretch_ideal_factor * topological_distance` (5 tests)
- [x] `repel_nn` — node-node repulsion, monotone in inverse distance below `repel_threshold_px` (7 tests)
- [x] `repel_ne` — node-edge repulsion (label crowding proxy) (6 tests)
- [x] `bend` — sum of squared turning angles along each rendered route (5 tests)
- [x] `crossings` — count of edge-edge crossings (5 tests)
- [x] `channel` — channel separation between parallel route bundles (6 tests)
- [x] `monotone` — penalty for any non-monotone X progression along a route (6 tests)
- [x] `envelope` — aspect-ratio / silhouette deviation from target (6 tests)
- [x] Each term has happy-path + zero-case + ordering test (all eight terms have ≥3 tests; most have 5-7)

### AC2 — Hard-invariant checker rejects pre-evaluation

- [x] Rule 1 (forward-only edges): backward edge => rejection
- [x] Rule 2 (topological X): x conflicts with topological layer => rejection
- [x] Rule 7 (determinism): two renders byte-identical, mismatch => rejection
- [x] Rejected layouts return `{rejected: true, rule, detail}` and never reach the energy function
  - Wiring from the dag-map render path into the canonical layout shape is done in `bench/evaluator/adapter.mjs` (AC4). The evaluator calls the invariant checker before scoring, so a layout that violates rules 1/2/7 bypasses the energy function.

### AC3 — Fixture loaders

- [x] Tier A loader reads `dag-map/test/models.js` and exposes `{id, dag, routes?, theme, opts}` (6 tests including loud-failure coverage)
- [x] Tier B loader reads snapshot JSON in `bench/fixtures/tier-b/` into the same shape, no routes (7 tests)
- [x] Loaders are pure: same input directory => same fixture list, same order (asserted for both tiers)
- [x] Missing/malformed fixtures fail loudly with path + reason (directory-missing, malformed-JSON, missing-field, and routes-present tests for Tier B; injected source + id assertions for Tier A)
- Tier B ships two sample fixtures: `radar-mini` (6 nodes) and `radar-branching` (9 nodes). These are synthetic stand-ins for real Radar snapshots — an `M-DAGBENCH-02` task can replace them with live pack-plan captures.

### AC4 — Single-individual evaluator

- [x] `evaluate(genome, fixture) -> {rejected, rule} | {score, terms}` at `bench/evaluator/evaluator.mjs`
- [x] Score is the weighted sum of the eight terms, default weights loaded from `bench/config/default-weights.json`
- [x] Per-term contributions returned alongside the total
- [x] Determinism verified by round-trip test (10 repeated calls byte-identical; clone-every-call test as a stronger guard)
- [x] All randomness seeded; no `Math.random` calls — test scans `evaluator.mjs` and `adapter.mjs` sources, stripping line comments, and asserts no `Math.random(` invocation
- [x] Rejection path for cyclic DAGs surfaces `{rejected: true, rule: 'render-failed', detail}`
- Adapter `bench/evaluator/adapter.mjs` projects `layoutMetro` output into the canonical shape. Longest-path layers come from dag-map's own `topoSortAndRank`, so bench layers always match dag-map semantics.
- Route polylines are straight-line polylines between route waypoints, not parsed SVG path strings. This keeps the projection deterministic and parser-free; the bend term measures bending at route waypoints, not within the rendered curve.

### AC5 — Baseline reference floor

- [x] `bench/scripts/baseline.js` scores current dag-map defaults across Tier A + Tier B (34 fixtures)
- [x] Output at `bench/run/baseline/<timestamp>/scores.json` with totals + per-term breakdowns
- [x] Re-runs produce identical per-fixture scores (timestamp differs, results do not) — test uses two different injected `now` values and asserts deep-equal on every `result` field
- [x] CLI entry: `node scripts/baseline.js` — smoke-tested end-to-end on both tiers

### AC6 — Diagnostic: route fidelity (Tier A only)

- [x] `route_fidelity(genome, fixture)` exists at `bench/diagnostics/route_fidelity.mjs` — returns `{applicable, fidelity, perRoute}` for Tier A fixtures and `{applicable: false, fidelity: null}` for Tier B
- [x] Output written to a separate `route-fidelity.json` file alongside `scores.json`; `scores.json` is grep-tested to confirm no `route_fidelity` or `fidelity` key ever appears in it
- [x] Test asserts the `evaluate` return shape contains exactly the eight energy terms and no diagnostic key

## Test Summary (milestone complete)

- **Total bench tests:** 87
- **Passing:** 87
- **Build:** green (dag-map main 285/285 still passing, bench isolated)
- **Bench runtime:** ~280ms for full suite
- Breakdown:
  - Energy terms: 46 (5+7+6+5+5+6+6+6)
  - Invariants: 6
  - Corpus (Tier A + Tier B): 13
  - Evaluator: 10
  - Baseline script: 7
  - Route-fidelity diagnostic: 5

## Notes

- Session start: branch `milestone/M-DAGBENCH-01` cut from `epic/dagbench-layout-evolution`.
- dag-map submodule pinned at `96103d70`.
- dag-map test framework: `node --test`. Bench uses the same runner — no new dependency.
- **Canonical layout shape** established by the first tests (consumed by every energy term and the invariant checker):
  `{ nodes: [{id, x, y, layer}], edges: [[from, to]], routes: [{id, nodes, points: [{x,y}, ...]}], meta: {} }`
  Projected from `layoutMetro` output by `bench/evaluator/adapter.mjs` using longest-path topological rank from dag-map's own `graph-utils.js`.
- **Submodule `bench/` is already gitignored in dag-map.** Verified: `dag-map/.gitignore` lists `bench/`, `git status` inside the submodule is clean, and the superproject shows the submodule pointer at its pinned commit. No further dag-map repo work is needed for this milestone.
- **Weights file** (`bench/config/default-weights.json`) is still a placeholder vector. The baseline output currently shows `envelope` dominating (≈1e6) on any fixture with degenerate vertical spread because `E_envelope` floors the penalty at `1e6` when `width` or `height` is 0. This is expected — calibrating weights is explicitly M-DAGBENCH-02 territory, not this milestone.
- Energy term formulas chosen:
  - `stretch`: `sum over edges of max(0, actual - ideal)^2`, where `ideal = factor * (layer_v - layer_u) * layer_spacing`. Only over-stretch is penalized — compression is free.
  - `bend`: `sum of acos(cos(theta))^2` over interior points of each route polyline, using the angle between incoming and outgoing segments. Straight = 0, 90deg = (pi/2)^2.
  - `crossings`: proper segment-segment intersection count; shared-endpoint touches are not counted (consecutive route segments naturally share endpoints). O(S^2).
  - `monotone`: for each polyline segment with `dx < 0`, pay `dx * dx`. Vertical and forward segments are free. The hard invariant already rejects illegal edge directions; this term penalizes rendered polylines that curl back inside a route.
  - `envelope`: `(log(width/height) - log(target))^2`. Log-space keeps the penalty symmetric — 2x-too-wide and 2x-too-tall are punished equally. A degenerate zero-width or zero-height bounding box falls back to a large finite penalty so the term never goes to `Infinity`.
  - `channel`: for each pair of segments from different routes whose x-projections overlap and whose unit direction vectors have dot product ≥ 0.9 (roughly parallel), penalize `(min_gap - y_separation)^2` when the smaller of the two overlap-endpoint y-gaps is below the threshold. This explicitly filters out crossings (which are the `crossings` term's job) and only catches maze-wall-style closeness.
  - `repel_nn`: `(threshold/d - 1)^2` for node pairs with `d < threshold`. Zero at the threshold boundary; monotone in `1/d` as pairs get closer. Coincident nodes are floored at `1e-6` to keep the term finite.
  - `repel_ne`: same `(threshold/d - 1)^2` form as `repel_nn`, but `d` is the closest-point distance from a node to a rendered segment that is NOT one of that segment's endpoints. Endpoint-touching pairs are skipped; otherwise every legitimate edge-to-its-own-node meeting would inflate the term to saturation.
- Invariant checker uses a stricter rule 1 than the appendix literally requires — it enforces forward in BOTH layer AND x, because rule 2 (topological x) reinforces the same direction. If the evaluator later surfaces layouts where x-order is legal but the layer ordering already implies forwardness, we can relax this.
- **Tier B snapshot mechanism** is file-based: `bench/fixtures/tier-b/*.json` with the canonical `{id, dag, theme, opts}` shape (no `routes`). Ships 2 synthetic sample fixtures (`radar-mini`, `radar-branching`) that exercise the loader and evaluator. Replacing them with real Radar pack-plan snapshots is a follow-up task for M-DAGBENCH-02, not this milestone.
- **Adapter design decision:** route polylines in the canonical shape are straight-line polylines between route waypoints (the authored `route.nodes` positions), NOT parsed SVG `d` strings from dag-map's `routePaths`. Rationale: (1) parser-free and deterministic, (2) `bend` measures bending at route waypoints where it matters structurally, (3) same semantics under `angular`, `bezier`, or `metro` routing so the genome-level routing primitive decision is free to change without silently altering bench scores. Documented in `bench/evaluator/adapter.mjs`.
- **Baseline output is gitignored along with the rest of `bench/`.** A fresh baseline was regenerated at the end of this session as a smoke check; it lives under `bench/run/baseline/<timestamp>/`. Do not rely on it existing in a clean checkout — regenerate with `node scripts/baseline.js`.

## Completion

- **Completed:** all six ACs (AC1–AC6) implemented, tested, and tracked
- **Final test count:** 87 bench tests, 100% passing; dag-map main 285/285 still green
- **Deferred to M-DAGBENCH-02 (not blocking M-01 wrap):**
  - Calibrating the default weight vector (currently placeholders; envelope's DEGENERATE_PENALTY will want revisiting once real fixtures are scored)
  - Real Radar pack-plan snapshots for Tier B (2 synthetic fixtures ship)
  - Profiling the render-path throughput to decide whether M-02 needs worker-thread parallelization
