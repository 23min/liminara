---
id: E-DAGBENCH-layout-evolution
phase: 5c-parallel
status: not started
depends_on: dag-map (current main)
---

# E-DAGBENCH: Layout Evolution

## Goal

Replace manual iteration of `dag-map` layouts with a reproducible evolutionary harness: a genetic algorithm searches the layout parameter space against a physics-inspired energy functional, with human aesthetic preference fed in via a Tinder-style pairwise voting UI that refits the energy weights. After this epic, dag-map layouts on new graphs improve by running an overnight job and a few hundred votes, not 32 hand-tuned versions.

## Context

`dag-map` is the DAG visualization library used by Liminara's observation layer (E-09 / M-OBS-03). It reached its current shape through 32+ manual iterations recorded in `.scratch/metro-experiments/` (v1-v32, R1-R10). The algorithm now produces structurally correct layouts on the seed corpus, but on new graphs the silhouette, density, whitespace and label crowding still feel wrong, and manual tuning is no longer scaling.

The 21 layout rules distilled from M-OBS-03, `docs/history/architecture/06_VISUALIZATION_DESIGN.md`, the dag-visualization landscape research, and the metro-experiments summary are the constraint set. Rules 1-7 are hard structural invariants. Rules 8-21 are aesthetic and have always been weighted by intuition. This epic makes those weights an artifact rather than a memory.

This work runs in parallel with Phase 5c (E-19, E-12) on its own worktree. It does not block or interact with execution-truth work. The runtime contract is untouched.

## Approach

The harness lives in `dag-map/bench/` (gitignored in dag-map; not part of the published library). Tracking and planning live in Liminara `work/` because dag-map has no tracking workflow.

**Genetic algorithm over LLM-driven evolution.** The search space is small, mostly continuous, cheap to evaluate, and benefits from determinism and parallelism. No API dependency.

**Two-tier genome.**
- *Tier 1 (continuous, ~15 params, full GA):* `lane_spacing_px`, `trunk_offset_frac`, `departure_frac`, `curve_power`, `lane_class_weights[4]`, `repel_threshold_px`, `stretch_ideal_factor`, ...
- *Tier 2 (discrete, mutation-only, no crossover):* `route_extraction in {longest_path, max_flow, depth_balanced}`, `routing_primitive in {bezier, angular, progressive}`, `convergence_style in {exclusive, inclusive, hybrid}`.

**Island model.** Separate populations per `routing_primitive`. Cross-island comparison happens only at reporting time and inside the Tinder gallery, not during selection.

**Energy functional as fitness**, not a weighted sum of ad-hoc metrics. Physics-inspired terms: stretch (springs), repel node-node (soap bubbles), repel node-edge (label crowding), bend (least action), crossings (topological), channel separation (maze walls), monotonicity, envelope/aspect.

**Hard invariants reject pre-evaluation, not score:** forward-only edges, topological X, determinism (same genome + same DAG renders identically). Violators never reach the energy function.

**Route extraction is part of the genome, not input data.** The energy function operates on the rendered layout, so it is uniform across all corpora regardless of whether routes are hand-authored. Hand-authored routes in Tier A may drive an optional "route fidelity" *diagnostic*, but must not appear in the energy function (would overfit to authorial intent).

**Human steering via Bradley-Terry weight refit.** Pairwise Tinder votes are aggregated into a Bradley-Terry model with temporal decay (early votes do not dominate forever). Every K generations the GA refits the energy weights from accumulated votes. Indirect steering generalizes to unseen graphs better than direct selection bias.

**Live steering architecture.** GA runs as a Node process writing generations to `dag-map/bench/run/` (gitignored). A tiny static HTML page with file-watching shows pairwise thumbnails from the current elite across islands. Votes append to `run/tinder.jsonl`. Pause-and-gate, "protect forever", and "kill" buttons act on individuals.

**Regression guard.** No individual enters the elite set if it makes any single corpus fixture worse than 90% of that fixture's best-ever score. Prevents mode collapse on hard cases.

**Three-tier corpus.**
- *Tier A - aesthetic targets (5-10 DAGs):* reuse `dag-map/test/models.js` (schema: `{dag: {nodes, edges}, routes, theme, opts}`). Drives the Tinder UI.
- *Tier B - Liminara-realistic (20-50):* real pack plans from Radar and future packs. Regression-checked every generation.
- *Tier C - external benchmark (100s):* North DAGs and Random DAGs (GraphML) from graphdrawing.org. Not checked in. `make fetch-corpora` downloads on demand. Cite graphdrawing.org; academic-benchmark license.

**JS throughout.** The bench uses dag-map's real render path directly. No translation layer, no risk of the harness optimizing a different renderer than the one Liminara ships.

## Scope

### In Scope

- Energy functional design and implementation (8 physics-inspired terms)
- Single-individual evaluator over Tier A + Tier B fixtures with hard-invariant rejection
- GA loop with island model, two-tier genome, mutation-only Tier 2
- Regression guard against per-fixture best-ever scores
- Live steering harness: file-watcher, pairwise gallery, vote log
- Bradley-Terry weight refit with temporal decay
- External corpus fetcher (`make fetch-corpora`) and benchmark report against dagre / ELK
- Codifying the 21 layout rules as the evaluation reference (appendix below)
- Tracking and run artifacts under Liminara `work/` for visibility into a submodule that has no tracking workflow

### Out of Scope

- Any change to dag-map's published API or shipped defaults (a follow-up release decision, not this epic)
- Gradient refinement of elite individuals (future work)
- Beating dagre/ELK as a primary objective - Liminara aesthetic priority is rule 1, benchmark numbers are a "nice side effect"
- Touching Liminara runtime code, observation layer, or execution contract
- Hand-authored route fidelity as a fitness term (kept as diagnostic only, see Approach)
- Productionizing the bench as a long-running service - it is a developer tool, not infra

## Constraints

- Bench code is gitignored in dag-map and never enters the published package
- Hard structural invariants (rules 1, 2, 7) are rejection criteria, not weighted terms
- Tinder votes must influence weights, not directly bias selection - principled steering only
- Energy function must be uniform across all corpus tiers - no per-tier special-casing
- All randomness in the GA must be seeded so a given run is replayable (this is a Liminara project, after all)
- External corpora are downloaded on demand, never committed
- Runs in a parallel worktree; must not depend on or block E-19, E-12, or any Phase 5c milestone
- No new dependencies in the dag-map main package; bench dependencies live in `bench/package.json`
- **No auto-PR to dag-map.** Evolved parameter sets are never opened as PRs by the harness. Any adoption into dag-map main is a manual decision per release.
- **No commits without explicit human approval** — applies to the bench code, the tracking docs, and any evolved parameter artifacts.

## Success Criteria

- [ ] Energy functional implemented with all 8 terms, unit-tested per term
- [ ] Hard-invariant checker rejects any layout that violates rules 1, 2, or 7 before scoring
- [ ] GA runs headlessly overnight on Tier A + Tier B and produces an elite gallery without human input
- [ ] Tinder UI loads pairs from a live run, records votes, and triggers a visible weight refit every K generations
- [ ] Regression guard prevents mode collapse: no single Tier B fixture regresses below 90% of its best-ever score in the elite set
- [ ] An evolved parameter set, judged by the project owner against the v32/R10 baseline on Tier A, is preferred on a clear majority of fixtures
- [ ] Tier C benchmark report is reproducible from `make fetch-corpora && make bench-report`
- [ ] All randomness is seeded; rerunning a generation from its seed and genome reproduces identical layouts
- [ ] The 21 layout rules appendix is the single reference both the energy function and human reviewers cite

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Energy weights overfit to Tier A and degrade Tier B | High | Regression guard against per-fixture best-ever; Tier B checked every generation |
| Tinder fatigue: not enough votes to move BT weights meaningfully | Med | Temporal decay so few-but-recent votes still matter; pause-and-gate so a session of focused voting is high-bandwidth |
| Discrete Tier 2 changes (e.g. routing primitive) cause large fitness jumps that break selection | Med | Island model isolates each `routing_primitive`; cross-island only at reporting |
| dag-map render path performance bounds population size | Med | Profile early in M-DAGBENCH-01; parallelize evaluation across worker threads if needed |
| External corpora license / fetch reliability | Low | Cite graphdrawing.org, do not redistribute, fail gracefully if fetch unavailable |
| Roadmap placement: parallel-track epics are new for the project | Low | Listed under Phase 5c as a parallel track; revisit if it causes confusion |
| "Route fidelity" diagnostic creeps into the energy function | Med | Explicit constraint in spec; diagnostic output goes to a separate report, not the fitness scalar |
| Elite individuals look great but the chosen weights do not survive the next vote round | Med | Treat each refit as a checkpoint; keep weight history; allow rollback |

**Decisions resolved (recorded here for traceability):**
- *Roadmap placement:* parallel track under Phase 5c. Confirmed.
- *Auto-PR to dag-map main:* **No.** No auto-PRs, no auto-commits. All adoption is manual per release. Also encoded in Constraints.
- *Tier C benchmark publication:* publish the dagre/ELK comparison regardless of outcome. Transparency over score.

## Milestones (anticipated, to be detailed via plan-milestones)

| ID | Title | Summary | Depends on |
|----|-------|---------|------------|
| M-DAGBENCH-01 | Energy function + corpus + evaluator | Eight energy terms (TDD), Tier A + Tier B fixture loaders, hard-invariant checker, single-individual evaluator. The testable foundation. | - |
| M-DAGBENCH-02 | GA loop + islands + regression guard | Two-tier genome, island model per routing primitive, regression guard, headless overnight runs producing elite gallery thumbnails. | M-DAGBENCH-01 |
| M-DAGBENCH-03 | Tinder UI + Bradley-Terry refit + live steering | File-watching gallery, pairwise vote log, BT weight refit with temporal decay, pause/protect/kill controls. | M-DAGBENCH-02 |
| M-DAGBENCH-04 | External corpora + benchmark report (stretch) | `make fetch-corpora`, North + Random DAG ingestion, comparison report against dagre / ELK. | M-DAGBENCH-03 |

Future, not in this epic: gradient refinement of elite individuals; shipping evolved defaults as a dag-map release.

## References

- `dag-map/` submodule (github.com/23min/DAG-map)
- `dag-map/.scratch/metro-experiments/SUMMARY.txt` - the 32-iteration history this epic replaces
- `dag-map/test/models.js` - Tier A corpus source format
- `dag-map/docs/research/dag-visualization-landscape.md`
- `docs/history/architecture/06_VISUALIZATION_DESIGN.md`
- `work/done/E-09-observation-layer/` (M-OBS-03 in particular)
- North DAGs: `http://www.graphdrawing.org/data/north-graphml.tgz`
- Random DAGs: `http://www.graphdrawing.org/data/random-dag-graphml.tgz`

## ADRs

- (none yet - candidate ADRs may emerge from M-DAGBENCH-01 around energy term formulation)

---

## Appendix: The 21 Layout Rules

Distilled from M-OBS-03, `docs/history/architecture/06_VISUALIZATION_DESIGN.md`, `dag-map/docs/research/dag-visualization-landscape.md`, and `.scratch/metro-experiments/SUMMARY.txt`. These are the evaluation reference for both the energy function and human reviewers.

### Hard structural (invariants - rejection, not scoring)

1. **Forward-only** - every edge LTR.
2. **Topological X** - node x = topological layer.
3. **Route-based decomposition** - greedy longest-path, trunk + branches.
4. **Fixed Y per route** - no wobble.
5. **Convergence-exclusive routes** - route path excludes the convergence node; returns rendered as separate lighter edges. Eliminates V-shape dives.
6. **Interchange-by-structure** - fork vs return distinguished by structural role, not geometric distance.
7. **Deterministic** - same input, same layout.

### Classical aesthetic criteria

8. **Crossing minimization.**
9. **Bend minimization.**
10. **Flow direction respected** (subsumed by rule 1).
11. **Area efficiency vs label collision** - tension, not lexicographic priority.
12. **Mental-map preservation** across incremental updates.

### Shape and silhouette (learned from v1-v14)

13. **Diamond / lens silhouette** emerges from layer ranges - not imposed.
14. **Trunk ~23% from top**, controlled vertical spread.
15. **Lane budget ~8-9** for 60-node graphs; reuse lanes when routes do not overlap in layer space.
16. **Lane assignment by determinism class** - pure / recordable closest to trunk, side-effecting furthest.

### Aesthetic and identity

17. **Stations not rectangles** - small circles, through-hole style.
18. **Edges thin, low opacity** (0.3-0.5 default), curved.
19. **Progressive curves** - convex departure, concave return.
20. **No arrowheads** - direction conveyed by LTR flow.
21. **Metro / notebook warmth** - cream paper, IBM Plex Mono, four semantic colors mapped to determinism class.
