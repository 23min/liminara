---
id: ADR-0006
working_id: ADR-REPLAY-01
title: Codify the run-level replay protocol as a CUE contract
status: accepted
date: 2026-04-26
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
contract:
  schema: docs/schemas/replay-protocol/schema.cue
  fixtures: docs/schemas/replay-protocol/fixtures/v1.0.0/
  worked_example: docs/schemas/replay-protocol/fixtures/v1.0.0/valid/radar-discovery-with-decision-and-warning-partial.yaml
  reference_implementation: "runtime/apps/liminara_core/lib/liminara/run/server.ex:283 (primary — `defp rebuild_from_events/2`); end-to-end demonstration at runtime/apps/liminara_core/test/liminara/run/replay_test.exs:45 + runtime/apps/liminara_core/test/liminara/run/crash_recovery_test.exs:111"
  schema_version: "1.0.0"
---

# ADR-0006 — Codify the run-level replay protocol as a CUE contract

## Context

Liminara records every run as a JSONL event log under `{runs_root}/{run_id}/events.jsonl`. The events are the source of truth for what happened: every state transition (`op_started`, `op_completed`, `op_failed`, `decision_recorded`, `gate_requested`, `gate_resolved`) plus exactly one terminal event (`run_completed` / `run_partial` / `run_failed`) is appended in order, hash-chained against its predecessor, and persisted before the next operation continues. This event log is read in three contexts:

1. **Discovery rebuild after server crash** — when a `Run.Server` GenServer restarts mid-run, `init/1` reads the existing log and the `{:continue, {:rebuild, existing_events}}` path (`runtime/apps/liminara_core/lib/liminara/run/server.ex:195`) reduces the log into a state, resets in-flight `:running` nodes to `:pending`, and re-dispatches.
2. **Result reconstruction post-hoc** — when an external caller queries `Run.Server.await/2` after the GenServer has terminated (or against a run from a prior session), `result_from_event_log/1` (`server.ex:1001`) walks the persisted log and re-derives a `Run.Result` without needing the GenServer to be alive.
3. **Replay-of-source-run execution** — when `Run.execute/2` is called with a `:replay` option naming a prior run_id, the dispatcher consults each op's `replay_policy` and either skips the op (side-effecting), re-executes it (pure), or injects the recorded decision and outputs from the source run's `Decision.Store` (recordable). The replay path emits its own event log, marked with `replay_of_run_id` on the embedded `ExecutionContext` rider.

These three behaviours are settled in Elixir (`run/server.ex` plus `decision/store.ex` for the recorded-data backing surface). They are exercised end-to-end every time a Liminara run starts, by the test suite at `runtime/apps/liminara_core/test/liminara/run/replay_test.exs`, which covers all three replay-policy branches (pure re-execution, recordable injection, side-effecting skip) plus the per-replay- run hash-chain isolation invariant.

Today the only specification of the protocol — the event-type discriminators, the per-event payload shapes, the walk-order invariants, the decision-injection ordering, and the partial-run re-entry shape — lives in the Elixir source itself. Downstream consumers must bind to the same shape:

- The PackLoader in **E-25** must surface the right `ExecutionContext` rider on replay so ops with `requires_execution_context: true` see the original run's metadata.
- The SDK and DX layer in **E-26** ship tooling that consumes persisted event logs (the `liminara-test-harness` replays runs against fake ops; LiveView consumers read events.jsonl on the observation path).
- **Radar's extracted form (E-27)** must satisfy the same protocol the in-tree Radar runtime exercises today.
- The future **admin-pack** (E-22) will run replays of bookkeeping workflows for audit replay (a load-bearing requirement of the bookkeeping domain — every replay must produce the same structured output as the original run, with decisions injected rather than re-elicited).

A consumer that drifts (writes an event with a typo'd `event_type`, omits the `warning_summary` from a terminal event, records a node state outside the locked five-value enumeration) discovers the failure at runtime, against a slow-feedback loop — the replay in production hangs or misroutes, and the cause shows up when an audit fails to reproduce. This is the shape of failure the contract-as-CUE pattern catches at authoring time.

This ADR codifies the run-level replay protocol as a CUE schema with a versioned fixture cohort. It does not change runtime semantics. It does not introduce shims (per D-2026-04-20-026). It is schema-freezing only.

The alternative — leaving the protocol in `server.ex` source as the sole specification — was viable while there was one consumer (the runtime reading its own logs). With the SDK + admin-pack proxy + Radar extraction + audit-replay tooling all binding to the same persisted shape, the cost of schema drift across consumers exceeds the cost of authoring + maintaining the CUE schema. `server.ex` remains the runtime source of truth; the CUE schema is an additional cross-language verification surface that derives from it.

## Decision

**Adopt `docs/schemas/replay-protocol/schema.cue` as the machine-checkable contract for the persisted event-log shape, the walk-order invariants, the decision-injection ordering, the partial-run re-entry state, and the replay `Run.Result` shape.**

The schema mirrors the live runtime — `server.ex`'s `emit_event/3` calls (one per event_type), `rebuild_from_events/2`, `result_from_event_log/1`, `finish_run/2`, the `{:continue, {:rebuild, …}}` re-entry path, plus `decision/store.ex`'s persisted decision + outputs + warnings shape. Field rename or shape divergence between live source and schema is a contract-matrix wrap-time check failure (per `.ai-repo/rules/liminara.md` Contract matrix discipline).

Sub-decisions:

- **Schema topic name: `replay-protocol`.** Matches the canonical contract surface name in the milestone spec's *Contract matrix changes* section (M-CONTRACT-02). The shorter `replay` was considered but ambiguous — Liminara has a per-op `replay_policy` (in OPSPEC) and a per-run replay protocol (this ADR); `replay-protocol` qualifies the run-wide surface unambiguously.
- **Bundled per-fixture entry shape (`#ReplayWalk`).** Each valid fixture pairs the persisted event-log stream with the `Run.Result` the walker derives (and, for partial fixtures, a `replay_state` block recording what `rebuild_from_events/2` reconstructs at the moment of re-entry). Inherits convention 1 from D-2026-04-26-036. The alternative — separate event-log fixtures and result fixtures — was rejected because the walk-order invariants (terminal_event_type ↔ run_result.status, the 1:1 finish_run/2 mapping) are the contract's load-bearing property and only show up in a paired shape.
- **Ten-value closed `#EventType` enumeration.** Locked to the exact set of event types `Run.Server` emits today (`run_started`, `op_started`, `op_completed`, `op_failed`, `decision_recorded`, `gate_requested`, `gate_resolved`, `run_completed`, `run_partial`, `run_failed`). Adding a new event type is a migration ADR per ADR-EVOLUTION-01. Inherits convention 4 from D-2026-04-26-036.
- **Per-event-type closed payload shapes.** The schema maps each `event_type` value to a single closed payload definition (e.g. `event_type: "op_completed"` → `#OpCompletedPayload`). Open payloads (with `...`) were rejected because the persisted on-disk shape is the contract — every recorded field is one a downstream consumer might branch on, and a typo'd field name written in error should fail vet, not silently pass.
- **Cross-field invariant on terminal_event_type ↔ run_result.status.** The schema enforces `last(events).event_type == "run_completed"` ↔ `run_result.status == "success"` (and partial / failed variants), mirroring `finish_run/2` (server.ex 770–781) and `terminal_status/2` (server.ex 1171–1173). A fixture that drifts the two apart fails vet. This is the schema's mirror of D-2026- 04-20-025's discriminator discipline.
- **`run_result: null` on partial fixtures.** When the trailing event is not a terminal event (the `{:continue, {:rebuild, events}}` mid-run-resume case), the walker has no result to produce yet — `run_result` is nullable, and the optional `replay_state` block records the rebuilt state at the moment the resume hands off to `dispatch_ready/1`. This is the schema shape the partial-rebuild-mid-run.yaml fixture exercises.
- **`#ReplayInputs` block for replay runs.** Replay-run fixtures carry an optional top-level `replay_inputs` block naming the source run plus the resolved per-node policy. Discovery-run fixtures omit it. The schema models the *resolved* policy — what `dispatch_node_by_mode/7` (server.ex line 451) chose — not the determinism class (which lives in OPSPEC). `#ReplayPolicy` closes to the three values that dispatcher actually branches on: `"skip" | "replay_recorded" | "reexecute"`. (M-WARN-04 + D-2026-04-20-026: the schema reflects the post-fix taxonomy; the legacy `:re_execute` atom was renamed to `Op.replay_policy_for/1`'s current return values long before this ADR, and the current spelling is what the schema locks.)
- **`Run.Result` shape duplicated locally, not imported from ADR-OPSPEC-01.** ADR-OPSPEC-01's `docs/schemas/op-execution-spec/schema.cue` defines a `#RunResult` with the same field set; this schema defines its own to keep the `scripts/cue-vet` invocation contract from M-CONTRACT-01 (single `<topic>/schema.cue` + `<fixture>.yaml` argument pair) working without cross-topic CUE module wiring. The two definitions stay in sync through the contract-matrix wrap-time check, which verifies both schemas against the live `Liminara.Run.Result` struct at `runtime/apps/liminara_core/lib/liminara/run.ex:38`. This is a documented duplication, captured here so a future reader asking "why two `#RunResult` definitions?" lands on this rationale rather than treating it as drift. Promoting it to a shared CUE package is a candidate for ADR-EVOLUTION-01 (M-CONTRACT-04) when the broader cross-topic-import question gets ratified.
- **`degraded` is type-only, not cross-field-derived.** Same asymmetry as ADR-OPSPEC-01: CUE could mirror `Run.Result.derive_degraded/2`'s rule, but doing so duplicates the live derivation in two places. Schema validates shape; Elixir owns derivation. Inherits convention 3 from D-2026-04-26-036.
- **`event_count` is type-only, not `len(events)`-cross-checked.** Same reasoning. The walker computes `event_count` over the full set of events, but a fixture's `events` list is the authoritative input — making the schema enforce `event_count == len(events)` would force fixture authors to hand-count and would catch authoring typos but not protocol errors.

## Consequences

**What becomes easier:**

- The SDK + `liminara-test-harness` (E-26) + admin-pack proxy + Radar's extracted form can vet their event-log production / consumption shapes against `replay-protocol/schema.cue`. Schema drift surfaces at authoring time.
- The pre-commit hook + `scripts/cue-vet` (M-CONTRACT-01) walks the fixture library on every commit; a schema bump that breaks a historical fixture fails the hook before merge.
- ADR-OPSPEC-01's `#OpResult.warnings` and this ADR's `op_completed.payload.warnings` are documented as the same shape at two surfaces — in-process (OPSPEC) and persisted-on- disk (this ADR). The bridge function `warning_payload/1` (`run.ex:710`) is the boundary between them; downstream consumers reading events.jsonl bind to this schema, not to OPSPEC's `#Warning`.
- Audit-replay tooling (the load-bearing admin-pack requirement) has a CUE shape it can vet a captured event log against before attempting replay. A drifted log fails fast at validation, rather than during replay execution.
- Future test-harness fixtures (E-26 `liminara-test-harness`) reuse the same valid YAML files as scenario inputs — the schema becomes the contract between the harness's "fake event log" generator and the replay-walker's input expectations.

**What becomes harder:**

- Every change to `server.ex`'s `emit_event/3` calls (event-type string, payload field name) or to `finish_run/2`'s terminal- event payload shape now also touches `docs/schemas/replay-protocol/schema.cue` and possibly the v1.0.0 fixture cohort. The contract-matrix wrap-time check catches drift but does not auto-update the schema.
- Two schemas now mirror `Liminara.Run.Result`: OPSPEC's `#RunResult` and this ADR's `#RunResult`. Both must be kept in sync with the Elixir struct and with each other. The duplication is documented above; promoting it to a shared CUE package is tracked as a candidate ADR-EVOLUTION-01 question.
- Evolution policy is now load-bearing on a third schema authored before ADR-EVOLUTION-01 (M-CONTRACT-04) is written. The retroactive-compatibility-algorithm requirement compounds.

**What we accept:**

- The schema lags runtime changes by one edit. The contract- matrix wrap-time check is the forcing function.
- The schema does not enforce the hash-chain validity invariant (`event_hash` is computed over `(event_type, payload, prev_hash)` and verified by `Event.Store.verify/2`). That invariant requires running the hashing function — a CUE schema can validate the *shape* of `event_hash` and `prev_hash` fields (string + nullability) but not the chain's correctness. Hash-chain integrity stays a runtime + test concern.
- The schema does not enforce that the event log is append-only in time (timestamps monotonically non-decreasing). Time is a property the runtime guarantees by construction (every `emit_event/3` call uses `DateTime.utc_now()`); a fixture could in principle record out-of-order timestamps, and the schema would accept it. This is a deliberate scope cut — adding the invariant would require encoding string-comparable ISO-8601 ordering, and the runtime already enforces it structurally.
- The schema admits empty `events: []`. A run with zero events is not a real protocol state (every run starts with a `run_started` event), but enforcing `len(events) >= 1` would reject the documented partial-failure-before-write edge cases the runtime never persists. The CUE constraint stays permissive; the runtime surfaces the impossibility.
- One CUE quirk applies (per D-2026-04-26-037): absent required struct bodies are not catchable by `cue vet` without `-c`, and the runner contract from M-CONTRACT-01 invokes without `-c`. The invalid fixtures in this cohort use leaf-field violations (out-of-enum values, mismatched discriminators, locked-literal violations) rather than absent-struct-body fixtures.

## Out of Scope

Two areas are deliberately not specified by this ADR:

- **Pack-version skew during replay.** Replaying a run authored against pack version X with pack version Y loaded raises a semantic question — should pure ops re-execute (potentially producing different output if op code changed)? Should recordable ops still inject the recorded decision (whose payload may now be the wrong shape for the new op version)? Should the replay refuse to start? The current `replay_policy` taxonomy does not distinguish these cases. Deferred to `work/gaps.md` → "Cross-version pack replay semantics — design space, not decided." This ADR's schema admits cross-version replay shapes (the `replay_inputs.source_run_id` is a free-form string and the embedded `ExecutionContext` may carry any `pack_version`); the protocol-level semantics of cross-version replay live in the gap entry.

- **Provenance recording in the run_started event payload.** M-RUNTIME-02 owns the requirement that a run's initial event carries the loaded pack's `git_commit_hash` (and any other provenance metadata) so an audit-replay can verify the exact pack code-as-deployed. This ADR's worked example below assumes the provenance metadata is already on the run's `run_started.payload.execution_context` block. The mechanism for putting it there — the field name, the source of the hash, the failure semantics when the hash cannot be determined — is M-RUNTIME-02's concern, not this ADR's. When M-RUNTIME-02 lands, this schema gets an additive bump to v1.1.0 with the new field; until then the schema admits the existing `pack_id` + `pack_version` fields without requiring a hash.

The forward dependency on M-RUNTIME-02 is recorded here as a contract deadline: when M-RUNTIME-02 ships its `pack_version + git_commit_hash` recording, this schema's v1.1.0 bump is the binding follow-up. The matching acceptance criterion in M-RUNTIME-02's spec, when authored, must reference this ADR.

## Schema-backed contract

The `contract:` frontmatter block names the bundle. Each piece tests a different property of the contract:

- **`schema`** — `docs/schemas/replay-protocol/schema.cue`. The authoritative shape. Cited in the `replay-protocol` row of `docs/architecture/indexes/contract-matrix.md` (added by M-CONTRACT-02's matrix-pass).
- **`fixtures`** — `docs/schemas/replay-protocol/fixtures/v1.0.0/`. Four valid fixtures (one realistic — Radar's two-node discovery run that ends `:partial` with a recorded decision and a degraded warning; one boundary-edge — a single pure op that ends `:success` with no decisions or warnings; one decision- replay — a recordable op replayed against a source run with decision injection; one partial re-entry — a mid-run state with `run_result: null` and a `replay_state` block). Five invalid fixtures, each exercising a distinct violation class: out-of-enum `event_type`, severity outside the locked taxonomy, terminal-status ↔ event_type mismatch, replay_policy outside the locked taxonomy, node-state outside the locked five-value enumeration, and `run_completed` outcome not matching its locked literal `"success"`.
- **`worked_example`** — the realistic fixture `docs/schemas/replay-protocol/fixtures/v1.0.0/valid/radar-discovery-with-decision-and-warning-partial.yaml` is the worked example. Its YAML body is the ADR's worked example verbatim; the *Worked example* section below quotes it without modification (per the M-CONTRACT-02 fixture-parity rule).
- **`reference_implementation`** — `runtime/apps/liminara_core/test/liminara/run/replay_test.exs:45`, the `describe "replay"` block whose six tests cover all three replay-policy branches (pure re-execution at line 82, recordable injection at line 58, side-effecting skip at line 103) plus the per-replay-run hash-chain isolation invariant (line 127) and the per-replay-run seal isolation (line 143). This is the integration surface that exercises the full event-log walk end-to-end on every test run; it is an *existing* implementation citation (per Assertion 4 in `.ai-repo/rules/contract-design.md`), not a scheduled-to-exist one. The four secondary references below are the live runtime sources the test suite drives.
- **`schema_version`** — `1.0.0`. The first frozen cohort. Bumping this requires either an additive change (minor bump, fixtures stay in `v1.0.0/`, new fixtures land in `v1.1.0/`) or a breaking change (major bump + deprecation ADR per ADR-EVOLUTION-01 when it lands in M-CONTRACT-04). M-RUNTIME-02's provenance-recording rollout is the named trigger for the first additive bump.

### Worked example

A Radar discovery run with two nodes runs to a `:partial` terminus. The first node, `cluster_summary`, is a recordable LLM op that completes successfully, records its `llm_match` decision, and emits a degraded warning because the LLM truncated the response (`max_tokens` hit). The second node, `publish_briefing`, is a side-effecting op that fails with a filesystem error. The run terminates `:partial` (per `finish_run/2`'s `stuck and any_failed and any_completed` branch, `server.ex:759`), emitting a `run_partial` event. The walker reduces the seven events in append order into a `Run.Result` with `status: "partial"`, one completed node, one failed node, `warning_count: 1`, and `degraded: true` (per `Run.Result.derive_degraded/2` — partial + warning_count > 0 yields degraded).

This is the entire run-level replay protocol surface in one fixture: the seven-event log, the per-event payload shapes, the hash-chain riders, the embedded `ExecutionContext`, the `run_partial` terminal taxonomy, the `warning_summary` payload, and the reconstructed `Run.Result`.

```yaml
events:
  - event_type: "run_started"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000001"
    prev_hash: null
    timestamp: "2026-04-20T06:00:00Z"
    payload:
      run_id: "radar-20260420T060000-d4e5f6a7"
      pack_id: "radar"
      pack_version: "0.1.0"
      plan_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000100"
      execution_context:
        run_id: "radar-20260420T060000-d4e5f6a7"
        started_at: "2026-04-20T06:00:00Z"
        pack_id: "radar"
        pack_version: "0.1.0"
        replay_of_run_id: null
        topic_id: "ai-safety"

  - event_type: "op_started"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000002"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000001"
    timestamp: "2026-04-20T06:00:00.010Z"
    payload:
      node_id: "cluster_summary"
      op_id: "claude_complete"
      op_version: "0.3.0"
      determinism: "recordable"
      input_hashes:
        - "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  - event_type: "decision_recorded"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000003"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000002"
    timestamp: "2026-04-20T06:00:01.234Z"
    payload:
      node_id: "cluster_summary"
      decision_hash: "sha256:8d23cf6c86e834a7aa6eded54c26ce2bb2e74903bb6bbb2f8c7d17db7c7e3a3a"
      decision_type: "llm_match"

  - event_type: "op_completed"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000004"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000003"
    timestamp: "2026-04-20T06:00:01.567Z"
    payload:
      node_id: "cluster_summary"
      cache_hit: false
      duration_ms: 1567
      warnings:
        - code: "llm_partial_response"
          severity: "degraded"
          summary: "LLM returned a truncated cluster summary; max_tokens hit before completion"
          cause: "max_tokens=512 exceeded by claude-3-5-sonnet-20241022"
          remediation: "raise max_tokens to 1024 in pack config or shorten prompt"
          affected_outputs:
            - "summary"
      output_hashes:
        - "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
      output_hashes_by_key:
        summary: "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

  - event_type: "op_started"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000005"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000004"
    timestamp: "2026-04-20T06:00:01.700Z"
    payload:
      node_id: "publish_briefing"
      op_id: "publish_to_static_site"
      op_version: "0.2.1"
      determinism: "side_effecting"
      input_hashes:
        - "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

  - event_type: "op_failed"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000006"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000005"
    timestamp: "2026-04-20T06:00:02.100Z"
    payload:
      node_id: "publish_briefing"
      error_type: "execution_error"
      error_message: "%File.Error{reason: :enoent, action: \"open\", path: \"/var/www/briefing/index.html\"}"
      duration_ms: 400

  - event_type: "run_partial"
    event_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000007"
    prev_hash: "sha256:d4e5f6a700000000000000000000000000000000000000000000000000000006"
    timestamp: "2026-04-20T06:00:02.150Z"
    payload:
      run_id: "radar-20260420T060000-d4e5f6a7"
      error_type: "run_failure"
      error_message: "one or more nodes failed"
      failed_nodes:
        - "publish_briefing"
      warning_summary:
        warning_count: 1
        degraded_node_ids:
          - "cluster_summary"

run_result:
  run_id: "radar-20260420T060000-d4e5f6a7"
  status: "partial"
  outputs:
    cluster_summary:
      summary: "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
  event_count: 7
  node_states:
    cluster_summary: "completed"
    publish_briefing: "failed"
  failed_nodes:
    - "publish_briefing"
  warning_count: 1
  degraded_nodes:
    - "cluster_summary"
  degraded: true
```

What each part means in domain terms:

- **`events[0]` (`run_started`)** — `Run.Server.handle_continue(:start_run, …)` (server.ex:202) emits this first. The payload's `execution_context` block is the rider M-RUN-01 wired through; it's the one piece of metadata recordable ops can read to know the run identity at execution time. `replay_of_run_id: null` marks this as a discovery run, not a replay. M-RUNTIME-02 will add a `git_commit_hash` field to this rider (Out-of-Scope here).
- **`events[1]` (`op_started`)** — `dispatch_node/2` (server.ex:430) emits this when the dispatcher decides to run `cluster_summary` (the OPSPEC `#Determinism.class` value `"recordable"` is stringified here per the existing `Atom.to_string/1` step at server.ex:444).
- **`events[2]` (`decision_recorded`)** — `record_decisions/3` (server.ex:921) emits one of these per recorded decision before the matching `op_completed` event. The ordering — decision first, op_completed second — is load-bearing on the replay path: `handle_replay_inject/2` (server.ex:526) re-emits the `decision_recorded` events from `Decision.Store` in the same order before re-emitting the synthetic `op_completed` for the injected output. A consumer reading the log can rely on decisions appearing before their owning op's completion.
- **`events[3]` (`op_completed`)** — `handle_node_success/4` (server.ex:659) emits this after storing outputs in the artifact store and warnings in the decision store. `cache_hit: false` because the recordable op actually invoked the LLM (a cache hit would have come from the `handle_cache_hit/3` branch at server.ex:636 with `cache_hit: true` and `duration_ms: 0`). The wire-shape warning inside `payload.warnings` is the post-`warning_payload/1` JSON form (string keys + stringified atom severity) — same shape as ADR-WIRE-01's `#WireWarning`.
- **`events[4]–[5]` (`op_started` + `op_failed` for `publish_briefing`)** — the side-effecting op runs (no replay), fails on the filesystem write, gets logged via `handle_node_failure/4` (server.ex:696). The `error_message` is `inspect/1` of the underlying reason; the schema admits this as free-form because Elixir reasons can be any term.
- **`events[6]` (`run_partial`)** — `finish_run(state, :partial)` (server.ex:760) emits this when the run is stuck with both failed and completed nodes. `event_type: "run_partial"` is the discriminator D-2026-04-20-025 split out from the prior collapsed `run_failed`-only emission so downstream consumers can tell `:partial` from `:failed` without inspecting payload fields. The `warning_summary` payload mirrors `warning_summary_payload/2` (server.ex:794) — the same shape ADR-OPSPEC-01's `#WarningSummary` codifies.
- **`run_result`** — what `result_from_event_log/1` (server.ex:1001) reconstructs by walking the seven events. `status: "partial"` matches the `run_partial` terminal type via `terminal_status/2` (server.ex:1172). `event_count: 7` matches the persisted log length. `outputs[cluster_summary][summary]` is the artifact hash from `events[3].payload.output_hashes_by_key`. `node_states[cluster_summary]: "completed"` and `node_states[publish_briefing]: "failed"` are written by `rebuild_node_states/2` (server.ex:1053). `degraded: true` is derived by `Run.Result.derive_degraded/2` from `(status: :partial, warning_count: 1)`.

### Reference implementation

Primary citation: [`runtime/apps/liminara_core/test/liminara/run/replay_test.exs:45`](../../runtime/apps/liminara_core/test/liminara/run/replay_test.exs) — the `describe "replay"` block. Six tests, each exercising one dimension of the replay protocol on real plans + ops:

- **Line 46** — `"discovery run produces output and decisions"`: the discovery half of the contract — a three-node plan (pure → recordable → side-effecting) runs to `:success` and the event log carries at least one `decision_recorded` event.
- **Line 58** — `"replay: recordable op returns same output as discovery"`: the decision-injection branch. The replay run's recordable-op output (artifact bytes from `Artifact.Store.get/2`) is byte-identical to the discovery run's. This is the contract audit-replay tooling depends on: replay reproduces, byte for byte.
- **Line 82** — `"replay: pure op re-executes and produces same output"`: the re-execution branch. Pure ops are not injected; they re-execute and produce the same output by construction (deterministic).
- **Line 103** — `"replay: side-effecting op is skipped"`: the skip branch. The `save` node's `op_completed` event has `cache_hit: true` (the synthetic skip emission at `server.ex:506`) instead of running the real side-effecting code.
- **Line 127** — `"replay run has its own valid hash chain"`: the per-replay-run isolation invariant. Replay runs get fresh `run_id`s and append-only event logs of their own, with their own validated hash chain (`Event.Store.verify/2`).
- **Line 143** — `"replay run has its own seal"`: the per-replay- run isolation invariant on the seal file (companion to the hash-chain).

This test module is the integration surface — it drives every piece of the protocol the schema codifies (event-log emission, walk-order, decision injection, partial-run shape via the side-effecting-skip path).

The mid-run-resume branch of the rebuild path (`server.ex:269` — when the last event in a recovered log is *not* a terminal `run_completed` / `run_partial` / `run_failed`, so `:running` nodes get reset to `:pending` and dispatch resumes) is exercised by a separate test module: [`runtime/apps/liminara_core/test/liminara/run/crash_recovery_test.exs:111`](../../runtime/apps/liminara_core/test/liminara/run/crash_recovery_test.exs) — `test "partial run: restart rebuilds state, dispatches remaining op"` inside the `describe "state rebuild from event log"` block. This test specifically simulates a process crash mid-run, restarts the GenServer with the partial event log, verifies that `:running`-state nodes are reset and the next scheduled op dispatches successfully, and the run reaches `:success`. The companion test at line 91 (`"completed run: restart detects completion, reports result"`) exercises the terminal-recovery branch at `server.ex:237` (the `last_type in [...]` arm); together the two tests cover both branches of the rebuild path. The `partial-rebuild-mid-run.yaml` fixture in this bundle is the schema-side analogue of crash_recovery_test.exs:111.

Live runtime secondary citations (each is a real running implementation, not test code):

- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:283`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — `defp rebuild_from_events(state, events)`. The reduce-over- events function the schema's per-event-type payload shapes mirror. Reads `event_type` + `payload`, reduces into `node_states` + `node_outputs` + `node_warning_counts` + `event_count` + `prev_hash`. The schema's `#Event.payload` cross-field invariant maps each `event_type` value to a closed payload shape that matches one of this reducer's case branches.
- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:1001`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — `defp result_from_event_log(run_id)`. The post-hoc reconstruction the schema's `run_result` shape codifies. Reads the persisted log, derives `Run.Result` via `rebuild_node_states/2` + `rebuild_outputs_from_events/2` + `warning_aggregation_from_events/1`. The schema's `#ReplayWalk.run_result` is what this function returns.
- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:195`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — the `{:continue, {:rebuild, existing_events}}` re-entry path. The branch chosen when `init/1` finds an existing event log. The handler at server.ex:230 (`handle_continue({:rebuild, events}, state)`) either reports a finished result (when the log is terminal) or resets `:running` nodes and re-dispatches (when the log is mid-run). The schema's partial-fixture shape (`run_result: null` + `replay_state` block) is what this path reconstructs.
- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:526`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — `defp handle_replay_inject(state, node_id)`. The decision- injection branch for recordable ops on the replay path. Reads `Decision.Store.get/2` + `Decision.Store.get_outputs/2` + `replay_warnings/2`, re-emits `decision_recorded` events in order, then emits the synthetic `op_completed`. The schema's decision-injection-ordering invariant (decisions before op_completed in the event log) is mirrored from this function's emission order.
- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:770`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — `defp finish_run(state, status)`. The terminal-event emitter. The schema's `#RunCompletedPayload` / `#RunPartialPayload` / `#RunFailedPayload` shapes mirror this function's status-branched payload construction. The 1:1 status → event_type mapping the schema's `#ReplayWalk` cross-field invariant enforces is locked here.

Per-store secondary citations:

- [`runtime/apps/liminara_core/lib/liminara/decision/store.ex`](../../runtime/apps/liminara_core/lib/liminara/decision/store.ex) — `Liminara.Decision.Store`. The persistence layer the replay- inject branch reads from (`get/2`, `get_outputs/2`, `get_warnings/2`). The schema does not codify the on-disk JSON shape of `decisions/{node_id}.json` (that's a per-store contract, demand-driven if it ever needs to be a separate contract surface) — but it does codify the `decision_recorded` event payload that wraps each store entry on the event-log side.
- [`runtime/apps/liminara_core/lib/liminara/execution_context.ex`](../../runtime/apps/liminara_core/lib/liminara/execution_context.ex) — `Liminara.ExecutionContext`. The struct embedded in the `run_started.payload.execution_context` field. The schema's `#ExecutionContext` mirrors this struct field-for-field.

### References to related contracts

- **ADR-OPSPEC-01** (`docs/decisions/0004-op-execution-spec.md`) — defines `#OpResult.warnings` (in-process Elixir struct shape), `#RunResult` (the Run.Result aggregation), `#WarningSummary`, and the run-terminal event taxonomy. This ADR's `#OpCompletedPayload.warnings` is the post-`warning_payload/1` JSON form of OPSPEC's `#Warning`; the `#RunResult` shape is duplicated locally (see Decision rationale) but logically the same.
- **ADR-WIRE-01** (`docs/decisions/0005-port-wire-protocol.md`) — defines `#WireWarning` (the JSON-keyed wire shape). This ADR's `#WireWarning` is the same shape; both schemas use the serialized form `warning_payload/1` produces. A recordable op that emits a warning across the port (per ADR-WIRE-01) sees that warning subsequently persisted in the event log (per this ADR) — same shape, different surface.
- **`replay_inputs.per_node` policy values** in this schema and **`determinism.replay_policy` values** in OPSPEC are linked but not identical: OPSPEC's `replay_policy` is the *declared* policy on the op spec (what the op tells the runtime); this ADR's `#ReplayPolicy` is the *resolved* policy at dispatch time (what the dispatcher chose). The two are the same set of string values but appear at different surfaces.

### Anchored admin-pack citation

ADR-REPLAY-01 is a **Radar-only ADR** per the parent sub-epic's *ADRs produced* table (line 89 in `work/epics/E-24-contract-design/epic.md`). It has no admin-pack secondary; the secondary column in that table reads `D-2026-04-05-023 (Radar run identity from ExecutionContext)`, not an anchored admin-pack citation. This is the *Assertion 3* exception captured in `.ai-repo/rules/contract-design.md` for ADRs whose primary forcing function is the existing Radar surface and whose protocol shape is the JSON-on-disk crossing every pack must use anyway. Admin-pack will exercise the same event-log shape Radar does on the audit-replay path; a separate anchored citation would imply admin-pack carries a *different* protocol shape, which it does not. The citation is intentional and recorded here per the parent-epic table.

D-2026-04-05-023 (Radar run identity from `ExecutionContext`) is the secondary reference because the schema's `#ExecutionContext` shape and the cross-run linkage via `replay_of_run_id` derive from the same M-RUN-01 + D-023 ratification of runtime-owned run identity. The ADR cites that decision as its secondary forcing function in lieu of an admin-pack anchor.

## Validation

The schema, fixtures, and worked example all vet locally:

```sh
$ ./scripts/cue-vet
$ echo $?
0
```

Field-for-field correspondence with the live runtime (`server.ex` + `decision/store.ex` + `execution_context.ex` + `run.ex` Result) is the contract-matrix wrap-time check. A future rename in any of those files that doesn't update `schema.cue` is caught by the matrix audit before the milestone wraps.

The schema-evolution loop in `scripts/cue-vet` walks every fixture in `docs/schemas/replay-protocol/fixtures/v1.0.0/` against the HEAD schema on every commit (via the pre-commit hook) and on every `scripts/cue-vet` no-args invocation. A schema change that breaks an existing fixture either reverts the change or lands a deprecation ADR + major version bump per ADR-EVOLUTION-01 (M-CONTRACT-04).

## References

- **Parent sub-epic spec:** `work/epics/E-24-contract-design/epic.md`
- **Owning milestone:** `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md`
- **Predecessor ADRs (this ADR cross-references):**
  - `docs/decisions/0004-op-execution-spec.md` — `#OpResult`, `#RunResult`, `#WarningSummary`, terminal-event taxonomy.
  - `docs/decisions/0005-port-wire-protocol.md` — `#WireWarning` (the wire-shape twin of this ADR's `#WireWarning`).
- **Contract-matrix index (row added by M-CONTRACT-02 wrap-pass):** `docs/architecture/indexes/contract-matrix.md`
- **Reviewer rule (the four assertions):** `.ai-repo/rules/contract-design.md` — note Assertion 3 exception: ADR-REPLAY-01 is Radar-only, no admin-pack secondary (matches the parent sub-epic's *ADRs produced* table line 89, which carries `D-2026-04-05-023` in the secondary column, not an admin-pack anchor).
- **Authoring overlay (Liminara bindings on the upstream skill):** `.ai-repo/skills/design-contract.md`
- **Forward dependencies:**
  - **M-RUNTIME-02** — provenance recording (pack_version + git_commit_hash on the run_started event payload). When that milestone lands, this schema gets an additive bump to v1.1.0; the matching acceptance criterion in M-RUNTIME-02's spec (when authored) is the binding deadline.
  - **`work/gaps.md` → "Cross-version pack replay semantics"** — the deferred design space for replay across pack versions.
- **Decision log entries:**
  - `D-2026-04-05-023` — Radar run identity is runtime-owned; locked the `ExecutionContext` rider this schema's `#ExecutionContext` mirrors. Secondary reference for this ADR (in lieu of an admin-pack anchor).
  - `D-2026-04-20-025` — `run_partial` is a first-class terminal event type. Locks the three-event-type taxonomy this ADR's `#EventType` enumeration includes.
  - `D-2026-04-20-026` — No backward-compat shims for in-flight contract fixes. The schema reflects the post-M-WARN-04 string-keyed warning shape, not the legacy atom-keyed shape.
  - `D-2026-04-22-028` — ADR working-keyword IDs in frontmatter (now superseded by D-030 on filename, retained for the `working_id:` convention).
  - `D-2026-04-23-030` — ADR filename `NNNN-<slug>.md`, ID `ADR-NNNN`. This ADR is `0006-replay-protocol.md` per the convention; the working-keyword ID `ADR-REPLAY-01` lives in `working_id:`.
  - `D-2026-04-26-036` — CUE encoding conventions ratified for M-CONTRACT-02. This ADR inherits all five conventions (bundled per-fixture entry, atom-to-string disjunctions, type-only for derived fields, locked enums, optional `?:` keys).
  - `D-2026-04-26-037` — CUE struct-presence quirk. This ADR's invalid fixtures use leaf-field violations rather than absent-struct-body violations.
- **Live runtime sources mirrored:**
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex` — the canonical replay implementation. `rebuild_from_events/2` (line 283), `result_from_event_log/1` (line 1001), the `{:continue, {:rebuild, existing_events}}` re-entry path (line 195), `handle_replay_inject/2` (line 526), `finish_run/2` (line 770), `emit_event/3` (line 947).
  - `runtime/apps/liminara_core/lib/liminara/run.ex` — `Run.Result` (line 38) and `Run.Result.derive_degraded/2` (line 91).
  - `runtime/apps/liminara_core/lib/liminara/execution_context.ex` — the embedded `ExecutionContext` rider in the `run_started` event payload.
  - `runtime/apps/liminara_core/lib/liminara/decision/store.ex` — the persistence layer `handle_replay_inject/2` reads back to inject decisions and warnings on the replay path.
  - `runtime/apps/liminara_core/test/liminara/run/replay_test.exs` — the reference implementation cited above; six tests exercising every dimension of the protocol on real plans.
