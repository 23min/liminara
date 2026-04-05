---
id: M-TRUTH-03-radar-semantic-cleanup
epic: E-20-execution-truth
status: complete
depends_on: M-TRUTH-02-core-runtime-contract-migration
---

# M-TRUTH-03: Radar Semantic Cleanup

## Goal

Make Radar the first pack that is fully honest on the execution-truth contract defined in M-TRUTH-01 and made runtime-real in M-TRUTH-02. After this milestone, Radar no longer mislabels side effects as pure behavior, fabricates runtime identity in pack code, or hides degraded production output behind plain success and decision-only rationale.

## Context

M-TRUTH-02 intentionally stopped at the runtime boundary. The core runtime now executes through canonical `ExecutionSpec`, `ExecutionContext`, `OpResult`, and warning transport, but Radar still carries pack-level semantic drift that the runtime bridge was not meant to normalize away:

- `Liminara.Radar.Ops.Dedup` is still declared `:pure`, while `runtime/python/src/ops/radar_dedup.py` mutates LanceDB history and stamps `created_at` with wall-clock time
- `runtime/apps/liminara_radar/lib/liminara/radar.ex` still fabricates `"radar-" <> plan_ts` and threads it through the plan as `run_id`
- `ComposeBriefing` and `RenderHtml` still treat that synthetic plan-time value as runtime identity
- Radar placeholder and safe-default paths still express degraded production behavior as ordinary success with rationale hidden in decisions or output payloads
- Radar ops still rely on legacy callback derivation and legacy Python success payload tolerance introduced in M-TRUTH-02 for bounded bootability

That is the point of this milestone. M-TRUTH-03 makes Radar the first migrated pack that tells the truth about side effects, runtime-owned context, and degraded output semantics before E-19 builds richer operator-facing warning/UI behavior on top.

## Milestone Boundary

M-TRUTH-03 may implement:

- explicit `execution_spec/0` for Radar ops where that removes reliance on the runtime legacy bridge
- truthful determinism and execution metadata for Radar ops
- refactoring of dedup/history behavior so replay and cache semantics match real side effects
- runtime-owned execution-context consumption in Radar outputs and templates
- canonical warning-bearing success or hard-failure behavior for known degraded Radar production paths
- removal or explicit reclassification of inert or misleading semantic inputs in Radar scoring
- focused Radar tests that freeze the truthful contract at the pack boundary

M-TRUTH-03 does not implement:

- run-level warning aggregation, UI badges, node inspector rendering, or observation-layer warning projection from E-19
- sandbox capability enforcement, audit hooks, Landlock, or provenance capture from E-12
- recovery mode, topic config, or broader runtime generalization work
- cross-pack migration beyond Radar

## Acceptance Criteria

1. **Radar ops expose truthful execution specs and determinism classes**
   - Radar ops that participate in this milestone export explicit `execution_spec/0` instead of depending on legacy callback derivation where practical
   - no Radar op remains declared `:pure` if it mutates durable state, depends on hidden mutable history, or stamps wall-clock-derived semantic data
   - any temporary Radar-local bridge that survives this milestone is called out explicitly as an exception with a named removal trigger rather than silently normalized as truth

2. **Dedup and history mutation align with real replay/cache boundaries**
   - Radar dedup no longer combines duplicate classification and durable LanceDB mutation under a false pure surface
   - if dedup stays as one op for this milestone, its determinism and replay/cache behavior must still tell the truth about side effects
   - if dedup is split, the boundary between history read, ambiguity handling, and history commit is explicit and test-covered
   - wall-clock-derived persistence no longer lives behind a pure contract surface

3. **Runtime identity is owned by execution context, not plan synthesis**
   - Radar plan construction no longer fabricates a value named `run_id` from `plan_ts`
   - briefing composition and rendered outputs consume runtime-owned execution context or runtime-managed output plumbing for run identity
   - any logical document identifier Radar still needs is named separately from runtime `run_id`
   - replay continues to use stored execution context rather than regenerated pack-side identity

4. **Known degraded Radar paths stop smuggling warnings through plain success**
   - known production fallback paths such as summarize placeholder mode, LLM dedup safe-default mode, and fetch-error embedding are each classified as either hard failure or canonical warning-bearing success
   - warning-worthy execution conditions are no longer represented only as decision rationale or opaque strings inside regular outputs
   - decisions remain reserved for nondeterministic choices; warnings carry degraded execution semantics where the op still produces outputs
   - the resulting pack contract is compatible with E-19 warning aggregation without requiring E-19 to reinterpret Radar-specific ad hoc payloads

5. **Radar semantic inputs and outputs reflect actual meaning**
   - inert or misleading inputs such as the hardcoded empty `historical_centroid` literal are removed, renamed, or made explicit as a truthful no-history contract
   - scoring and output metadata no longer imply stronger historical or runtime knowledge than the pack actually has
   - focused tests cover the chosen semantics for no-history ranking, missing publication dates, and degraded-but-successful paths where applicable

6. **M-TRUTH-02 temporary shims have a concrete Radar removal path**
   - the Radar pack no longer depends on M-TRUTH-02 runtime shims where the work can be completed inside this milestone
   - any remaining use of legacy callback derivation or legacy Python success payloads is enumerated explicitly in the milestone tracking doc with a follow-on removal trigger
   - the milestone leaves E-19 consuming Radar through the canonical execution/warning contract rather than through pack-specific transitional behavior

## Tests

Write tests first for Radar's semantic cleanup surface.

- Radar op contract tests for explicit `execution_spec/0` and truthful determinism/execution metadata
- Dedup tests covering classification versus history mutation boundaries, replay behavior, and cacheability semantics
- Execution-context tests proving briefing metadata and rendered outputs use runtime-owned identity in both direct and replayed runs
- Python op contract tests for summarize, LLM dedup, and fetch fallback paths using canonical `outputs` / `decisions` / `warnings` semantics or explicit hard failure
- Ranking tests covering truthful no-history behavior and missing-date handling
- Regression tests proving any removed M-TRUTH-02 shim is no longer required for the migrated Radar paths

Use the repository TDD conventions:

- happy path
- edge cases
- error cases
- replay and round-trip cases where applicable
- format-compliance assertions where runtime identity or warning payload shape is serialized into artifacts

## TDD Sequence

1. Freeze the current semantic mismatches with failing tests for dedup truthfulness, runtime identity plumbing, and degraded-path result shapes.
2. Migrate the smallest useful Radar surface to explicit `execution_spec/0` and canonical result behavior.
3. Refactor dedup/history boundaries and briefing identity plumbing until the failing tests pass without leaning on false determinism or synthetic run identity.
4. Re-run the focused Radar slice, then the broader runtime replay tests that exercise Radar through the canonical contract.

## Technical Notes

- Expected touch points:
  - `runtime/apps/liminara_radar/lib/liminara/radar.ex`
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/dedup.ex`
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/compose_briefing.ex`
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/render_html.ex`
  - `runtime/python/src/ops/radar_dedup.py`
  - `runtime/python/src/ops/radar_summarize.py`
  - `runtime/python/src/ops/radar_llm_dedup.py`
  - `runtime/python/src/ops/radar_fetch_rss.py`
  - `runtime/python/src/ops/radar_fetch_web.py`
  - `runtime/python/src/ops/radar_rank.py`
  - `runtime/python/tests/test_radar_embed_dedup.py`
  - `runtime/python/tests/test_radar_summarize.py`
  - `runtime/python/tests/test_radar_llm_dedup.py`
  - `runtime/python/tests/test_radar_fetch.py`
  - `runtime/python/tests/test_radar_rank.py`
- M-TRUTH-03 should prefer truthful classification over clever bridge logic. If an op still needs a temporary adapter, the adapter must preserve truth and carry an explicit removal trigger under `docs/architecture/contracts/02_SHIM_POLICY.md`.
- E-19 owns warning aggregation and operator-facing rendering, but M-TRUTH-03 owns making Radar emit or fail in ways that E-19 can surface without pack-specific reinterpretation.
- This milestone is allowed to leave future enhancements deferred, but it is not allowed to preserve known lies about side effects, runtime identity, or degraded success as the canonical Radar story.

## Out of Scope

- LiveView or A2UI warning presentation
- Run-level completed-with-warnings aggregation rules beyond what the runtime already carries after M-TRUTH-02
- Sandbox degraded modes or capability enforcement
- Multi-topic instance management
- Historical-centroid feature expansion beyond the truthful contract needed for current Radar ranking

## Dependencies

- M-TRUTH-02 is complete and its focused runtime validation is green
- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `docs/architecture/contracts/00_TRUTH_MODEL.md`
- `docs/architecture/contracts/02_SHIM_POLICY.md`
- `work/milestones/tracking/M-TRUTH-02-tracking.md`
- E-19 milestone dependency: `work/epics/E-19-warnings-degraded-outcomes/epic.md`

## Spec Reference

- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `work/epics/E-20-execution-truth/epic.md`
- `work/epics/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`

## Related ADRs

- D-2026-04-02-012: bounded Radar hardening before VSME
- D-2026-04-02-013: sequencing rule
- D-2026-04-02-015: unified execution spec replaces callback sprawl
- D-2026-04-04-022: architecture truth is split into live, decided-next, and historical sources