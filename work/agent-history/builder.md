# Builder Agent History

## E-10: Port Executor (2026-04-01)

### Patterns that worked
- TDD cycle worked cleanly: protocol tests first, then execution tests, then integration
- Putting Python project at `runtime/python/` with `uv` — transparent venv management
- `{packet, 4}` framing: BEAM handles length prefix automatically on send, just send raw payload via `Port.command`
- Self-configuring executor: `default_python_root/0` resolves from app config or `__DIR__` — Run.Server needs no changes

### Pitfalls
- `kill` is a shell built-in in Debian slim containers — use `:os.cmd/1` not `System.cmd("kill", ...)`
- `sys.exit()` in Python raises `SystemExit(BaseException)`, not caught by `except Exception`. Added explicit `SystemExit` catch in runner. For true crash tests, use `os._exit(42)`.
- Cache tests need explicit ETS table passed via `cache: ctx.cache` — the supervised Cache GenServer may not be running in tests
- `VIRTUAL_ENV` env var from `integrations/python/` causes uv warnings — harmless but noisy
- Python's built-in `hash()` is process-salted. Do not use it for deterministic fixture seeds when tests spawn subprocesses or compare values across runs.

### Conventions established
- Op modules declare `:port` executor via optional `executor/0` callback
- Op modules declare Python op name via optional `python_op/0` callback
- Python test ops live in `runtime/python/src/ops/test_*.py`
- Elixir test op wrappers live in `test/support/test_port_ops.ex`

## M-RAD-06: Replay Correctness (2026-04-03)

### Patterns that worked
- Store output_hashes alongside decisions for replay — avoids reconstructing outputs from decision content
- Backward compat via format sniffing: JSON object → wrap in list; JSON with `"decisions"` key → new format
- Optional `env_vars/0` callback on op modules — no behaviour change needed, `function_exported?/3` check in executor
- `RadarReplayTestPack` with literal fixture items — tests full Python port pipeline without network calls
- Characterization test (`ReplayGapPack`) for unit-level replay, separate Radar test for pipeline-level

### Pitfalls
- Both `run.ex` (sync) and `run/server.ex` (async) have independent replay paths — must update both
- `uv run` sets its own `VIRTUAL_ENV` in child process — can't test "VIRTUAL_ENV absent", only "host value doesn't leak"
- Env whitelist without op-declared vars silently breaks API key access — test suite stays green but live runs fail
- Marking ACs done without the required test is worse than leaving them open — reviewers catch it
- Run only changed test files during TDD; full core suite takes 15+ seconds (server stress/timeout tests)

### Conventions established
- Decision file format: `{"decisions": [...], "output_hashes": {...}}` per node_id
- Op modules can declare `env_vars/0` returning a list of env var names to preserve through port executor
- Radar test packs live in `apps/liminara_radar/test/support/`
- `mix.exs` needs `elixirc_paths` override for test support files to compile

## M-RAD-04: Web UI + Scheduler (2026-04-03)

### Patterns that worked
- Starting with GenServer (pure logic, no UI deps) before LiveView pages — fastest TDD cycle
- `Decision.Store.get_outputs/3` for keyed artifact lookup — events only store flat hash lists
- Config-gated supervisor children: `if enabled, do: [child_spec], else: []` in application.ex
- `Application.get_env` overrides in test setup + `on_exit` cleanup — clean isolation for LiveView tests

### Pitfalls
- Event payload `output_hashes` is `Map.values(hash_map)` — a flat list, not a keyed map. Tests with `%{"key" => hash}` pass but real runs fail. Always use Decision.Store for keyed lookups.
- Cross-app module references (web → radar) cause "undefined module" warnings unless `mix.exs` declares the umbrella dependency
- `Artifact.Store.get/2` needs the 2-arity (direct) form with explicit store_root, not the 1-arity GenServer form, when reading from configurable paths

### Conventions established
- Radar LiveView pages live in `apps/liminara_web/lib/liminara_web/live/radar_live/`
- Global nav bar in `app.html.heex` layout (not per-page inline nav)
- Scheduler is config-gated: `config :liminara_radar, :scheduler, enabled: true, daily_at: ~T[06:00:00]`
- Sources config path configurable via `config :liminara_radar, :sources_path`

## M-TRUTH-01: Execution Spec + Outcome Design (2026-04-04)

### Patterns that worked
- For a design milestone, limited shared-struct codification plus focused contract tests is acceptable when the purpose is only to freeze canonical names, defaults, and field shapes.
- Use the milestone spec plus downstream epic references to decide scope boundaries, not an opportunistic next implementation step.
- On a dirty milestone branch, close with scoped validation of the touched contract files and record unrelated umbrella blockers explicitly instead of broadening the milestone to fix off-scope drift.

### Pitfalls
- Suggesting legacy callback bridges or tuple/JSON result normalizers inside M-TRUTH-01 blurs the design milestone into M-TRUTH-02.
- Placeholder or newly codified structs are schema-freezing artifacts until live runtime paths consume them; do not describe that as completed migration.

## M-TRUTH-02: Core Runtime Contract Migration (2026-04-04)

### Patterns that worked
- Add one focused contract test file for the new bridge surface before touching the run paths; it exposed the executor/API breakpoints cleanly without dragging replay into the first red phase.
- When moving from legacy tuples to `OpResult`, migrate `Run` and `Run.Server` in the same slice. Changing the executor first and the runtimes later creates wide but shallow failures.
- Persisting gate output hashes is required for replay of gate-backed recordable nodes; replay is not only about decisions.
- `Code.ensure_loaded?/1` is necessary before `function_exported?/3` when test support modules define optional callbacks like `execution_spec/0`.

### Pitfalls
- `Run.Server.await/2` can fall back to the event log after the server exits; if that fallback returns empty outputs, concurrent-run tests fail even though execution succeeded.
- Decision store supervised tests still reflected the old single-record API; the runtime had already moved to list semantics and test expectations had to follow that contract.
- Environment-level lint tools may not exist in the devcontainer even when the runtime uses `uv`; validate Python syntax with available language tooling and record missing executables explicitly.
- Moving runtime execution onto canonical `execution_spec` is incomplete if cacheability and cache keys still read legacy callbacks; cache behavior has to migrate in the same slice as executor dispatch.
- `Run.Server.await/2` needs an event-log fallback after `DOWN`, not only after an empty registry lookup, or normal process exit can still race result delivery and surface false errors.
- Warning emission paths need to handle both `Liminara.Warning` structs and plain maps during the transition; serializing only structs leaves inline/task warning-bearing successes crash-prone.
- Once execution switches to canonical spec identity, decision persistence has to switch too or provenance diverges between `op_started` events and stored decision records.
- Canonical cache migration is not complete until `cache_policy` itself is authoritative; using determinism class alone still breaks explicit-spec ops that intentionally declare `cache_policy: :none`.
- Replay migration is not complete until `replay_policy` itself is authoritative; using determinism class alone still breaks explicit-spec ops that intentionally override replay behavior.
- Canonical execution migration is not complete until executor defaults honor `execution.timeout_ms`; task and port paths each had their own hidden fallback timeout and both needed explicit regressions.
- Runtime-level support for canonical `executor: :task` needs tests above direct `Executor.run/3`; otherwise `Run.execute` and `Run.Server` can both miss the required task supervisor even while executor unit tests stay green.
- If synchronous `Run.execute` cannot resolve a runtime contract surface such as gates, it still needs an explicit failure path and event emission. Leaving the tuple unmatched just converts a product gap into a crash.
- The execution-context contract is stricter than provenance-only tracking: replayed context-aware ops must reuse the stored source context fields (`run_id`, `started_at`, pack identity) and only add replay provenance, or replay stops being reproducible.
- Python warning bridges should drop unknown keys by default; a fixed allowlist without a catch-all turns harmless schema expansion into runtime failure.
- If a replayed context-aware run is missing `execution_context.json`, fail explicitly instead of regenerating a replacement context. Silent fallback turns storage drift into nondeterministic replay semantics.
- Recordable replay is not contract-complete until warnings are persisted and re-emitted alongside decisions and output hashes; otherwise discovery and replay diverge on degraded-success surfaces.
- If the runtime cannot yet compute the canonical `env_hash` for `pinned_env`, disable caching for that policy rather than reusing plain content-addressed keys and claiming stronger semantics than the code enforces.
- Explicit replay failure paths should avoid persisting synthetic recovery artifacts; otherwise a later restart can accidentally promote a failure fallback into apparent canonical truth.
- Missing-source-context handling on replay cannot be a global switch. Only plans with context-aware ops should suppress replay-owned execution-context persistence and `run_started` payloads; pure replays still need their own replay context recorded even when the source file is gone.
- Source execution-context requirements are node-path dependent, not just plan dependent. Context-aware nodes that replay via stored decisions or skip execution do not need the source context file, while reexecuted context-aware nodes still do.
- `execution_context.json` parsing must fail closed as runtime data, not as process crashes. Treat malformed JSON or missing required fields as explicit invalid replay context rather than letting `Jason.decode!` take down the store or server.
- Shape validation matters as much as syntax validation for runtime-owned JSON. A valid scalar like `123` is still invalid execution context and must be rejected before helper code assumes an enumerable map.
- Optional runtime-identity fields need validation too. Accept only `nil` or binaries for fields like `replay_of_run_id` and `topic_id`; otherwise malformed persisted context can still leak through a superficially valid JSON object.
- `replay_recorded` is only safe without the source execution context if the stored replay artifacts are actually present. If decision/output replay data is missing, fail closed rather than silently dropping into live execution with synthesized context.
- For crash recovery, the canonical recovery source is the earliest `run_started.payload.execution_context`, not whichever `execution_context.json` happens to be on disk after restarts. File-based recovery can drift under supervisor restarts.
- Execution-context-aware ops cannot safely use plain content-addressed cache keys. If execution context is not part of the cache key yet, mark those ops uncached or unrelated runs will leak runtime identity through cache hits.
- Full-suite supervision tests should not assume `Liminara.Run.DynamicSupervisor` is empty after other runtime tests have executed; assert child shape, not pristine suite order.
- In `Run.Server`, synchronous failure branches inside `dispatch_ready/1` must not call `maybe_complete/1` mid-batch. Ready siblings may still need dispatch, and early completion can emit duplicate terminal events for one run.
- Keep replay error taxonomy separated by missing artifact type: missing `execution_context.json` should surface `missing_replay_execution_context`, while missing stored decisions/output hashes should stay `missing_replay_recording`.

## M-TRUTH-03: Radar Semantic Cleanup (2026-04-05)

### Patterns that worked
- Treat the Radar pack boundary as a contract freeze surface: one explicit spec helper (`Liminara.Radar.Ops.Specs`) made it practical to migrate every current Radar op to `execution_spec/0` in one coherent slice instead of leaving half the pack on runtime derivation.
- For runtime-owned identity, update the plan shape and the consuming op in the same red/green cycle. Removing synthetic `run_id` inputs without moving `ComposeBriefing` to `execute/2` just leaves dead wiring or false positives.
- Side-effecting ops can still truthfully replay through `replay_policy: :replay_recorded`; that was the right fit for Radar dedup because replay should inject stored outputs rather than skip downstream data or rerun LanceDB mutation.
- Dedup boundary tests need two separate assertions: repeated live runs must not cache across mutable history, and replay must reuse recorded outputs even after live history has changed.
- End-to-end Radar replay tests that pass through `Summarize` should explicitly unset `ANTHROPIC_API_KEY`; otherwise the suite becomes environment-sensitive and can drift between degraded-warning coverage and live LLM behavior.
- If a pack does not have historical state yet, require an explicit no-history literal like `history_basis: "none"` instead of threading inert placeholder payloads such as `historical_centroid: []`; the contract stays truthful and future extension points remain obvious.
- Once a pack has explicit execution specs everywhere, delete the legacy `executor/0`, `python_op/0`, and `env_vars/0` hints from the pack modules too; leaving them behind keeps the migration technically green but semantically half-finished.

### Pitfalls
- `function_exported?/3` can still lie in contract tests unless the module is loaded first. Use `Code.ensure_loaded/1` in explicit-spec assertions for pack modules, not only in runtime helpers.
- LanceDB table objects do not expose the list API you might expect from search results; in Python tests, read rows through `table.search(...).limit(...).to_list()` rather than assuming the table itself has `to_list()`.
- Runtime-context-aware Python ops should test persisted fields directly at the storage layer. It is easy to believe context plumbing works because outputs look right while stored metadata still falls back to wall clock or plan-local defaults.
- Once degraded fallback paths move from synthetic decisions to warnings, replay assertions must compare discovery provenance to replay provenance instead of assuming discovery always emits `decision_recorded` events.
- Missing-data scoring defaults need an explicit output marker. A silent fallback score for missing or invalid publication dates is another form of semantic drift unless the ranked artifact says that recency used a fallback basis.
- Existing behavior tests often prove the data content but not the wire contract. Add one cheap `set(result.keys())` assertion per untouched Python op family when retiring a bridge so canonical-shape drift cannot hide behind green feature tests.

## M-PACK-A-01: Liminara-project Contract-TDD tooling (2026-04-25)

### Patterns that worked
- For non-runtime milestones (devcontainer toolchain, scripts, hooks, prose authoring guides), POSIX shell tests with `mktemp -d` sandboxes proved fast and reliable. No mix/test framework involvement — each AC's test runs in seconds, scoped to one concern, easy to read and audit. The umbrella build/test pathology that the project rules flag as load-bearing didn't apply to this milestone at all.
- Mock-on-PATH for external binaries (`cue` in this case) is the right shape for testing scripts that wrap a binary. Override `PATH` in the test, drop a 5-line shell script that mimics the binary's exit-code behavior under controlled conditions. Real-binary integration is covered transitively elsewhere (here: AC2's runtime install step proved cue 0.16.1 actually works against the cue-lang/cue release).
- For shell-tooling tests, write the failure-detection mock with a tight, file-local heuristic (basename match, not full-path match). The first version of this milestone's mock matched substrings anywhere in the path, which produced false positives when sandbox directory names happened to contain the trigger token (`repo-bad-fixture/...`). Tightening to basename-only fixed it cleanly.
- For idempotent installer tests, byte-equality via `cmp -s file1 file2` is more reliable than `[ "$(cat A)" = "$(cat B)" ]`. The shell `$(cat ...)` form strips trailing newlines from one side of the comparison, producing false-mismatch failures even when the files are byte-identical.
- For sandboxed git-hook tests, `git init` per scenario in `mktemp -d` was clean and fast. No risk of polluting the real `.git/`. `git config commit.gpgsign false` + a fake user.email/name keeps tests deterministic.
- Decision recording before code-writing pays for itself. When upstream framework PR #72 closed mid-milestone with a fixture-layout convention different from what AC6 had just shipped, writing D-2026-04-25-033 first (decision-log entry) + spec amendments (M-PACK-A-01 + parent sub-epic) before any code refactor kept the trail honest. Code refactor was then mechanical against a locked spec.
- For prose-binding deliverables (skills, rules, READMEs), grep-based structural tests are the right level. Test that required references appear (paths, decision IDs, principle phrases); leave content quality to wrap-time review. Don't try to grep for "good prose."
- For long milestones with multiple ACs, commit at logical boundaries (here: AC1–AC6 in one commit, AC7+AC8 in a second) rather than one monolithic commit. Two squashable commits read more cleanly in `git log` than one mega-commit, and provide intermediate rollback points if a later AC's design needs to revisit an earlier AC's shape.

### Pitfalls
- `wf-graph apply --patch` for status flips updates `work/graph.yaml` correctly but skips the spec-frontmatter portion when consumer repos use the flat `<id>-<slug>.md` layout (vs. folder-form `<id>/spec.md`). Hand-edit the frontmatter as a workaround. Filed upstream as ai-workflow#80.
- Markdown bold `**X**` can break grep-based tests when reflow puts `**X is\nrejected.**` on two lines. Either reflow to single line or use a multi-line-aware test (`grep -Pzo` etc.). Single-line reflow is simpler.
- The Bash tool's working directory persists across calls, but `cd` inside a single Bash command leaks into subsequent calls if the command exits with cwd != original. Lost ~30s diagnosing a "scripts/tests not found" before realizing my earlier `cd .ai && git log` left the shell in `.ai/`. Either use absolute paths or wrap in `( cd X && ... )` subshells to scope cwd changes.
- A `printf '%s' "$VAR" > file` writes the variable's bytes verbatim including any trailing newline; `$(cat file)` strips trailing newlines from the file's content. The asymmetry breaks straightforward equality checks. Materialize the expected content into a tmpfile and use `cmp -s` instead.
- Designing an "invalid fixture must fail" sub-walk in a schema-evolution loop requires a different exit-code semantics from the "valid fixture must pass" sub-walk. Splitting the loop into two structurally-mirrored sub-walks (each with its own format-string for regressions) is cleaner than threading branching exit-code expectation logic inside a single loop.
- When upstream framework convention changes mid-milestone, the cost of converging-now vs. converging-later is shaped by the data the milestone has accumulated. M-PACK-A-01 happened to ship with an empty fixture library; the layout reshape cost ~30 lines of refactor + tests. After M-PACK-A-02a lands its first fixtures, the same reshape would cost a multi-fixture migration. The lesson: when the trigger arrives during a milestone whose data is still empty, take the convergence cost immediately.

### Conventions established
- POSIX shell tests for non-runtime milestones live under `scripts/tests/test-<thing>.sh`. Each test is self-contained, exits non-zero with a `FAIL: <description>` line on first failure, prints `PASS: <one-line summary>` on success.
- `scripts/cue-vet`'s no-arg loop walks `docs/schemas/<topic>/fixtures/v<N>/{valid,invalid}/` with mirrored exit-code expectations. The structure is a permanent convention going forward; M-PACK-A-02a's fixtures land into this shape.
- The `<framework>` (upstream) + `<liminara overlay>` pattern for skills: never duplicate upstream content in the overlay; reference upstream by path and add only the project-specific bindings on top. AC7's `.ai-repo/skills/design-contract.md` is the template for future overlay skills.
- Reviewer-rule files (`.ai-repo/rules/*.md`) bound to a specific authoring skill should live next to the skill in the test-grep convention: AC8's `test-contract-design-rule.sh` includes a "no upstream-workflow-heading duplication" check that prevents reviewer rules from drifting into authoring guides.
