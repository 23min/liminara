# M-TRUTH-03: Radar Semantic Cleanup — Tracking

**Started:** 2026-04-05
**Completed:** 2026-04-05
**Branch:** `milestone/M-TRUTH-03`
**Spec:** `work/epics/E-20-execution-truth/M-TRUTH-03-radar-semantic-cleanup.md`
**Status:** complete

## Acceptance Criteria

- [x] AC1: Radar ops expose truthful execution specs and determinism classes
  - export explicit `execution_spec/0` for the touched Radar ops where practical
  - remove false `:pure` declarations from ops that mutate durable state, depend on hidden mutable history, or stamp wall-clock-derived semantic data
  - treat any surviving Radar-local bridge as an explicit exception with a named removal trigger
- [x] AC2: Dedup and history mutation align with real replay/cache boundaries
  - stop presenting duplicate classification plus durable LanceDB mutation behind a false pure surface
  - make the boundary between history read, ambiguity handling, and history commit truthful and test-covered
  - remove wall-clock-derived persistence from any pure contract surface
- [x] AC3: Runtime identity is owned by execution context, not plan synthesis
  - remove plan-time synthetic `run_id` generation from Radar plan construction
  - consume runtime-owned execution context in briefing composition and rendered outputs
  - separate any logical document identifier from runtime `run_id`
  - preserve stored runtime identity on replay rather than regenerating pack-side values
- [x] AC4: Known degraded Radar paths stop smuggling warnings through plain success
  - classify summarize placeholder mode, LLM dedup safe-default mode, and fetch-error embedding as either hard failure or canonical warning-bearing success
  - stop hiding warning-worthy execution conditions only in decisions or opaque output strings
  - keep decisions for nondeterministic choices and warnings for degraded execution semantics
- [x] AC5: Radar semantic inputs and outputs reflect actual meaning
  - remove, rename, or make explicit inert semantic inputs such as the empty `historical_centroid` literal
  - keep scoring/output metadata honest about historical and runtime knowledge
  - cover no-history ranking, missing publication dates, and degraded-but-successful semantics with focused tests
- [x] AC6: M-TRUTH-02 temporary shims have a concrete Radar removal path
  - stop depending on M-TRUTH-02 runtime shims where the work fits inside this milestone
  - enumerate any remaining legacy callback derivation or legacy Python success payload usage with explicit follow-on removal triggers
  - leave E-19 consuming Radar through the canonical execution/warning contract rather than pack-local transitional behavior

## Baseline

- Branch created from `epic/E-20-execution-truth`: `milestone/M-TRUTH-03`
- Focused start validation is green:
  - `cd runtime && mix test apps/liminara_radar/test`
  - `cd runtime/python && /workspaces/liminara/runtime/python/.venv/bin/python -m pytest tests/test_radar_embed_dedup.py tests/test_radar_summarize.py tests/test_radar_llm_dedup.py tests/test_radar_fetch.py tests/test_radar_rank.py tests/test_radar_cluster.py tests/test_radar_normalize.py`
- M-TRUTH-02 runtime migration is complete; remaining drift is Radar-local semantic truth around dedup, runtime identity plumbing, degraded-success surfaces, and temporary bridge reliance

## Implementation Phases

1. Freeze current semantic drift with failing tests
   - Elixir contract tests for runtime-owned identity and touched explicit execution specs
   - Python tests for warning-bearing success, degraded-path shapes, and dedup truthfulness
2. Migrate truthful Radar execution surfaces
   - add explicit `execution_spec/0` to the touched Radar ops
   - remove synthetic plan-time `run_id` plumbing and consume runtime-owned execution context instead
3. Refactor stateful dedup and degraded-path behavior
   - make classification versus durable history mutation boundaries honest and test-covered
   - migrate summarize, LLM dedup, and fetch fallback paths onto canonical warning/failure semantics
4. Remove Radar reliance on M-TRUTH-02 transitional behavior and verify replay
   - close or explicitly track every remaining Radar use of legacy callback derivation or legacy Python success payload tolerance
   - rerun focused Radar/runtime replay coverage after the pack surface is truthful

## Transitional Surfaces To Remove Or Track

- Radar pack callback-derivation bridge
  - Status: closed for current Radar ops in this slice; all Radar ops now export explicit `execution_spec/0`, and Radar port ops no longer export legacy `executor/0`, `python_op/0`, or `env_vars/0` hints
  - Remaining follow-on trigger: remove `Liminara.Op.derive_execution_spec/1` from core once non-Radar test/support modules stop using legacy callback derivation (`runtime/apps/liminara_core/test/support/test_port_ops.ex` and `runtime/apps/liminara_core/test/liminara/executor/dispatch_test.exs` are the current known users)
- Legacy Python success payload tolerance still exists for Radar Python ops
  - Status: closed for current Radar Python ops; focused Python tests now freeze canonical top-level success keys across embed, dedup, cluster, normalize, rank, summarize, LLM dedup, and fetch paths
  - Remaining follow-on trigger: if non-Radar Python port ops ever depend on non-canonical payloads, migrate them before removing any leftover compatibility assumptions from core port test fixtures

## Progress

- [x] Slice 1: runtime-owned run identity
  - `Radar.plan/1` no longer synthesizes `run_id` inputs for `dedup` or `compose_briefing`
  - `ComposeBriefing` now exports explicit `execution_spec/0`, requires runtime execution context, and emits runtime-owned `run_id` in briefing artifacts
  - `Dedup` now exports an explicit side-effecting `execution_spec/0` with `replay_policy: :replay_recorded` and consumes runtime context for persisted `run_id` and `started_at`
  - replay coverage still passes with identical rendered HTML, proving runtime-owned identity is reused from stored execution context rather than regenerated pack-side
  - validation: `mix test apps/liminara_radar/test` and focused Python Radar pytest files are green on `milestone/M-TRUTH-03`
- [x] Slice 2: explicit Radar specs and truthful dedup boundaries
  - every current Radar op now exports explicit `execution_spec/0`, freezing executor, determinism, replay, and execution-context requirements at the pack boundary
  - `Dedup` remains one op for this milestone, but its cache and replay boundaries are now covered explicitly: repeated live runs re-execute against updated LanceDB history, while replay injects recorded outputs instead of re-running against mutated history
  - runtime-context persistence for dedup is test-covered at the Python level, proving persisted `run_id` and `created_at` come from runtime-owned context rather than wall clock on the canonical execution path
  - validation: focused AC1/AC2 Elixir contract/replay slice is green, full `mix test apps/liminara_radar/test` is green, and focused Radar Python pytest files are green
- [x] Slice 3: degraded Radar paths now emit canonical warnings instead of synthetic decisions
  - `radar_summarize` placeholder mode and LLM-error fallback now return warning-bearing success with empty top-level decisions; replay preserves the degraded warning payload instead of inventing `decision_recorded` events
  - `radar_llm_dedup` safe-default and API-error fallbacks now emit canonical warnings while keeping items deterministically, rather than smuggling degraded semantics through synthetic decisions
  - `radar_fetch_rss` and `radar_fetch_web` exception paths now emit structured warnings on success so degraded fetches are visible at the execution contract boundary
  - the end-to-end Radar replay test now forces the no-key summarize path, keeping replay coverage deterministic and explicitly asserting warning preservation alongside decision preservation
  - validation: `mix test apps/liminara_radar/test/liminara/radar/ops/degradation_warning_test.exs`, `mix test apps/liminara_radar/test/liminara/radar/replay_test.exs`, full `mix test apps/liminara_radar/test`, and focused Radar Python pytest files are green
- [x] Slice 4: rank now uses an explicit no-history contract instead of fake historical state
  - `Radar.plan/1` and the replay fixture pack now pass `history_basis: "none"` to `rank`, replacing the inert `historical_centroid: []` literal
  - `radar_rank` fails closed unless the caller declares `history_basis`, making the current no-history contract explicit instead of implicit placeholder data
  - ranked cluster outputs now include `scoring_context` with `history_basis` and `reference_time`, and ranked items include `publication_status` plus `score_breakdown` so missing or invalid dates are visible in the output contract
  - validation: `pytest tests/test_radar_rank.py`, `mix test apps/liminara_radar/test/liminara/radar/pack_test.exs apps/liminara_radar/test/liminara/radar/replay_test.exs`, full `mix test apps/liminara_radar/test`, and focused Radar Python pytest files are green
- [x] Slice 5: Radar no longer depends on the M-TRUTH-02 legacy bridge surfaces
  - Radar port ops no longer export legacy `executor/0`, `python_op/0`, or `env_vars/0` callbacks; their canonical execution specs now carry entrypoint and environment requirements directly
  - focused Python contract assertions freeze that Radar Python ops emit only canonical top-level result keys (`outputs`, plus `decisions`/`warnings` where applicable), so E-19 can consume Radar without pack-local response reinterpretation
  - core bridge comments now explicitly describe the remaining non-Radar/test compatibility path instead of implying Radar still depends on it
  - validation: `mix test apps/liminara_radar/test/liminara/radar/op_contract_test.exs`, `pytest tests/test_radar_embed_dedup.py tests/test_radar_cluster.py tests/test_radar_normalize.py tests/test_radar_rank.py`, full `mix test apps/liminara_radar/test`, and focused Radar Python pytest files are green

## Notes

- This milestone starts from a green focused Radar baseline on the epic branch, not from a fresh contract-design pass.
- E-19 depends on this cleanup making Radar emit truthful execution and warning semantics without pack-specific reinterpretation.
- Final focused validation for the completed milestone is green:
  - `cd runtime && mix test apps/liminara_radar/test`
  - `cd runtime/python && /workspaces/liminara/runtime/python/.venv/bin/python -m pytest tests/test_radar_embed_dedup.py tests/test_radar_summarize.py tests/test_radar_llm_dedup.py tests/test_radar_fetch.py tests/test_radar_rank.py tests/test_radar_cluster.py tests/test_radar_normalize.py`