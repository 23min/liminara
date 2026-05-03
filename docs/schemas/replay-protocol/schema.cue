// replay-protocol/schema.cue
//
// Schema for ADR-REPLAY-01: the run-level replay protocol.
//
// This schema freezes the shape of:
//   - The append-only event-log stream that Liminara.Run.Server reads
//     and writes (event_type discriminator + per-type payload).
//   - The walk-order invariants `rebuild_from_events/2` and
//     `result_from_event_log/1` reduce over.
//   - The decision-injection ordering in `handle_replay_inject/2` for
//     ops whose `determinism.replay_policy: "replay_recorded"`.
//   - The partial-run re-entry shape the `{:continue, {:rebuild,
//     existing_events}}` path consumes.
//   - The replay `Run.Result` shape — same set of fields as
//     ADR-OPSPEC-01's #RunResult; this schema duplicates the type
//     constraint locally rather than importing across topics so the
//     `cue vet` invocation contract from M-CONTRACT-01 (single
//     `<topic>/schema.cue` + `<fixture>.yaml` argument pair) keeps
//     working without cross-topic CUE module wiring.
//
// Source-of-truth bindings (live runtime):
//   - runtime/apps/liminara_core/lib/liminara/run/server.ex
//     (rebuild_from_events/2 line 283, result_from_event_log/1 line
//     1001, the `{:continue, {:rebuild, existing_events}}` re-entry
//     path line 195, finish_run/2 line 770, emit_event/3 line 947).
//   - runtime/apps/liminara_core/lib/liminara/run.ex (Run.Result at
//     line 38).
//   - runtime/apps/liminara_core/lib/liminara/execution_context.ex
//     (the ExecutionContext rider that the run_started event carries
//     in payload.execution_context).
//   - runtime/apps/liminara_core/lib/liminara/decision/store.ex
//     (per-node decision + output_hashes + warnings persistence the
//     replay walker reads back via Decision.Store.get/2 and friends).
//   - runtime/apps/liminara_core/test/liminara/run/replay_test.exs
//     (reference implementation; exercises the full walk end-to-end).
//
// Conventions inherited (D-2026-04-26-036):
//   1. Bundled per-fixture entry shape: each fixture pairs an
//      event-log stream + reconstructed run_result + (optional)
//      replay_inputs snapshot in a single document.
//   2. Atom-to-string disjunctions on closed enumerations
//      (event_type, status, replay_policy, determinism class).
//   3. Type-only encoding for derived fields. `degraded` and
//      `event_count` are validated as types; the schema does not
//      assert `event_count == len(events)` or the
//      Run.Result.derive_degraded/2 rule. Runtime owns derivation.
//   4. Enum values lock to actually-used set, expand additively.
//      event_type is closed at the eight types Run.Server emits today
//      (`run_started`, `op_started`, `op_completed`, `op_failed`,
//      `decision_recorded`, `gate_requested`, `gate_resolved`, plus
//      one of three terminal types).
//   5. Optional Elixir-`nil` fields encoded as CUE `?:` optional keys.
//
// D-2026-04-26-037 reminder: absent required struct bodies are NOT a
// schema-level violation class without `cue vet -c`. Invalid fixtures
// in this cohort use leaf-field violations instead.
//
// Out of scope (per ADR-REPLAY-01 § Out of Scope):
//   - Pack-version skew during replay. The schema does NOT cross-check
//     that the replayed run's `pack_version` matches the loaded pack;
//     the `replay_of_run_id` rider on a replay run's ExecutionContext
//     is the only cross-run linkage this schema models. Cross-version
//     replay semantics live in `work/gaps.md` → "Cross-version pack
//     replay semantics."
//   - Provenance recording (pack_version + git_commit_hash on the
//     run_started event's payload). M-RUNTIME-02 owns the field;
//     this schema admits the existing `pack_id` + `pack_version` on
//     the embedded ExecutionContext but does not require a
//     `git_commit_hash`. When M-RUNTIME-02 lands, this schema gets
//     an additive bump to v1.1.0 with the new field.

package replayprotocol

// schema_version is fixed at the cohort version. Bumping the cohort
// (v1.0.0 → v1.1.0 additive, → v2.0.0 breaking) is governed by
// ADR-EVOLUTION-01 (M-CONTRACT-04) when it lands.
schema_version: "1.0.0"

// ─── Top-level fixture entry: one event-log stream + the
//     reconstructed Run.Result that walking the stream produces.
//
// Replay fixtures pair the persisted event log (the input to the
// walker) with the Result the walker derives (the output). For
// partial-run fixtures, `run_result` is null because the walker has
// not reached a terminal event — the trailing `replay_state` block
// records what `rebuild_from_events/2` reconstructs at the moment of
// re-entry.

#ReplayWalk: close({
	// The append-only event log Run.Server persists to
	// {runs_root}/{run_id}/events.jsonl. Each entry is the JSON shape
	// Event.Store.append/4 emits: event_type + payload + event_hash +
	// prev_hash + timestamp. The list is *append-order* — the walker
	// reduces in this exact order; no reordering is permitted.
	events: [...#Event]

	// The Run.Result the walker produces. Null when the fixture
	// represents a partial / mid-run state (last event is not
	// terminal).
	run_result: #RunResult | null

	// State the {:continue, {:rebuild, events}} path reconstructs at
	// re-entry. Optional — only set on partial-run fixtures so the
	// rebuilt node-state map can be validated against the schema's
	// shape without forcing every fixture to repeat the rebuild
	// outcome.
	replay_state?: #ReplayState

	// Optional replay-injection snapshot. When present, the fixture
	// represents a *replay run* (not a discovery run) and this block
	// names the source run + which nodes get inject vs re-execute vs
	// skip. Discovery-run fixtures omit it.
	replay_inputs?: #ReplayInputs

	// Cross-field invariant: when the last event is a terminal event,
	// run_result MUST be non-null and its status MUST match the
	// terminal event_type. Mirrors finish_run/2's 1:1 mapping and
	// terminal_status/2 (server.ex line 1171–1173).
	if len(events) > 0 if events[len(events)-1].event_type == "run_completed" {
		run_result: #RunResult
		run_result: status: "success"
	}
	if len(events) > 0 if events[len(events)-1].event_type == "run_partial" {
		run_result: #RunResult
		run_result: status: "partial"
	}
	if len(events) > 0 if events[len(events)-1].event_type == "run_failed" {
		run_result: #RunResult
		run_result: status: "failed"
	}
})

// ─── Event log entry ──────────────────────────────────────────────
//
// Every line in events.jsonl unifies with #Event. The eight
// event_type values are closed: anything outside this set is a
// fixture authoring error. New event types require a migration ADR
// per ADR-EVOLUTION-01.
//
// The per-type payload disjunction below pins each event_type to a
// closed payload shape. Open payload (with `...`) was rejected
// because the contract here is the persisted on-disk shape — every
// recorded field is one a downstream consumer might branch on.

#EventType:
	"run_started" |
	"op_started" |
	"op_completed" |
	"op_failed" |
	"decision_recorded" |
	"gate_requested" |
	"gate_resolved" |
	"run_completed" |
	"run_partial" |
	"run_failed"

#Event: close({
	event_type: #EventType
	// Hash chain rider. Event.Store.append/4 computes event_hash over
	// the canonical encoding of (event_type, payload, prev_hash).
	// First event has prev_hash: null.
	event_hash:  string & !=""
	prev_hash:   string | null
	// ISO-8601 UTC timestamp. Run.Server emits these via
	// DateTime.utc_now() |> DateTime.to_iso8601().
	timestamp:   string & !=""
	payload:     #Payload
	// Cross-field invariant: payload shape unifies with the variant
	// matching event_type. CUE picks the right disjunct via the
	// closed event_type discriminator.
	if event_type == "run_started" {payload: #RunStartedPayload}
	if event_type == "op_started" {payload: #OpStartedPayload}
	if event_type == "op_completed" {payload: #OpCompletedPayload}
	if event_type == "op_failed" {payload: #OpFailedPayload}
	if event_type == "decision_recorded" {payload: #DecisionRecordedPayload}
	if event_type == "gate_requested" {payload: #GateRequestedPayload}
	if event_type == "gate_resolved" {payload: #GateResolvedPayload}
	if event_type == "run_completed" {payload: #RunCompletedPayload}
	if event_type == "run_partial" {payload: #RunPartialPayload}
	if event_type == "run_failed" {payload: #RunFailedPayload}
})

// `#Payload` is the union over all per-type payloads. Each variant
// is closed; the discriminator above narrows the unification. This
// keeps the fixture surface flat (no manual tagging) while giving
// the schema enough information to enforce per-variant shape.
#Payload:
	#RunStartedPayload |
	#OpStartedPayload |
	#OpCompletedPayload |
	#OpFailedPayload |
	#DecisionRecordedPayload |
	#GateRequestedPayload |
	#GateResolvedPayload |
	#RunCompletedPayload |
	#RunPartialPayload |
	#RunFailedPayload

// ─── Per-event payload shapes (mirror server.ex emit_event/3 calls) ──

// run_started — server.ex line 212. Carries the embedded
// ExecutionContext payload (or null when the replay path failed
// without a usable source context — server.ex 218–223).
#RunStartedPayload: close({
	run_id:            string & !=""
	pack_id:           string & !=""
	pack_version:      string & !=""
	plan_hash:         string & !=""
	execution_context: #ExecutionContext | null
})

// op_started — server.ex line 440. determinism is the stringified
// atom (Atom.to_string(determinism), server.ex line 444).
#OpStartedPayload: close({
	node_id:       string & !=""
	op_id:         string & !=""
	op_version:    string & !=""
	determinism:   "pure" | "pinned_env" | "recordable" | "side_effecting"
	input_hashes:  [...string]
})

// op_completed — server.ex line 506 (replay-skip), 542 (replay-
// inject), 599 (gate-resolved), 638 (cache-hit), 675 (success),
// 1066 (rebuild_from_events output). cache_hit + duration_ms +
// warnings are always present; output_hashes + output_hashes_by_key
// are added by output_hash_payload/1 (server.ex line 1086).
#OpCompletedPayload: close({
	node_id:                 string & !=""
	cache_hit:               bool
	duration_ms:             int & >=0
	warnings:                [...#WireWarning]
	output_hashes:           [...string]
	output_hashes_by_key:    {[string]: string}
})

// op_failed — server.ex line 698 (execution error), 713 (replay
// execution-context error), 725 (missing replay recording).
#OpFailedPayload: close({
	node_id:        string & !=""
	error_type:     string & !=""
	error_message:  string & !=""
	duration_ms:    int & >=0
})

// decision_recorded — server.ex line 534 (replay-inject), 937
// (record_decisions). decision_type may be null when the op did not
// supply a discriminator (Decision.Store accepts the omission;
// `decision["decision_type"]` is nil-able).
#DecisionRecordedPayload: close({
	node_id:        string & !=""
	decision_hash:  string & !=""
	decision_type:  string | null
})

// gate_requested — server.ex line 571.
#GateRequestedPayload: close({
	node_id:  string & !=""
	prompt:   _
})

// gate_resolved — server.ex line 593. Response shape is op-defined.
#GateResolvedPayload: close({
	node_id:   string & !=""
	response:  _
})

// run_completed — server.ex finish_run/2 line 798. Outcome is fixed
// at "success" on this branch; artifact_hashes is the flat list of
// all node output hashes; warning_summary mirrors
// warning_summary_payload/2 (server.ex line 794).
#RunCompletedPayload: close({
	run_id:           string & !=""
	outcome:          "success"
	artifact_hashes:  [...string]
	warning_summary:  #WarningSummary
})

// run_partial / run_failed — server.ex finish_run/2 line 806.
// Identical payload shape per finish_run/2's 1:1 status → event
// mapping (M-WARN-04: D-2026-04-20-025 made these distinct event
// types so the discriminator survives downstream serialization).
#RunPartialPayload: close({
	run_id:           string & !=""
	error_type:       "run_failure"
	error_message:    string & !=""
	failed_nodes:     [...string]
	warning_summary:  #WarningSummary
})

#RunFailedPayload: close({
	run_id:           string & !=""
	error_type:       "run_failure"
	error_message:    string & !=""
	failed_nodes:     [...string]
	warning_summary:  #WarningSummary
})

// ─── Embedded shapes ──────────────────────────────────────────────

// ExecutionContext — mirrors Liminara.ExecutionContext (struct in
// runtime/apps/liminara_core/lib/liminara/execution_context.ex).
// All fields are nilable in the Elixir struct; the schema represents
// them as optional `?:` keys per D-2026-04-26-036 convention 5.
// run_started's payload sends these as a Map.from_struct/1 of the
// struct; when fields are nil, Jason serializes them as JSON null —
// the union with `null` accepts that shape.
#ExecutionContext: close({
	run_id?:            string | null
	started_at?:        string | null
	pack_id?:           string | null
	pack_version?:      string | null
	replay_of_run_id?:  string | null
	topic_id?:          string | null
})

// WireWarning — the JSON-keyed warning shape that crosses the
// `op_completed.warnings` field. Identical to ADR-WIRE-01's
// #WireWarning (warning_payload/1 produces the same shape on the
// run-event broadcast path as on the port wire). Severity values are
// the locked Liminara.Warning taxonomy.
#WireSeverity: "info" | "low" | "medium" | "high" | "degraded"

#WireWarning: close({
	code:               string & !=""
	severity:           #WireSeverity
	summary:            string & !=""
	cause?:             string | null
	remediation?:       string | null
	affected_outputs?:  [...string]
})

// WarningSummary — mirrors warning_summary_payload/2 (server.ex
// line 794 + 1192). Aggregates over the run's op_completed events.
#WarningSummary: close({
	warning_count:      int & >=0
	degraded_node_ids:  [...string]
})

// ─── Run.Result — terminal aggregation ─────────────────────────────
//
// Same field set as ADR-OPSPEC-01's #RunResult. Duplicated locally
// so this schema validates without cross-topic CUE module wiring (the
// `scripts/cue-vet` runner contract from M-CONTRACT-01 invokes
// `cue vet <topic>/schema.cue <fixture>.yaml` per fixture, with no
// shared package directory). The two definitions stay in sync
// through the contract-matrix wrap-time check, which verifies both
// schemas against the live Liminara.Run.Result struct.

#RunStatus: "success" | "partial" | "failed"

#RunResult: close({
	run_id:          string & !=""
	status:          #RunStatus
	outputs:         {[string]: {[string]: string}}
	event_count:     int & >=0
	node_states:     {[string]: "pending" | "waiting" | "running" | "completed" | "failed"}
	failed_nodes:    [...string]
	warning_count:   int & >=0
	degraded_nodes:  [...string]
	degraded:        bool
})

// ─── Replay-inject inputs ─────────────────────────────────────────
//
// When a fixture represents a replay run, this block names the
// source run plus the per-node policy applied at dispatch time
// (server.ex dispatch_node_by_mode/7 line 451). The schema models
// the *resolved* policy on each node — what the dispatcher chose to
// do — not the determinism class of the op (which lives in OPSPEC's
// #Determinism). The two are linked by Op.replay_policy/1
// (op_module.replay_policy_for/1).

#ReplayPolicy: "skip" | "replay_recorded" | "reexecute"

#ReplayInputs: close({
	source_run_id:  string & !=""
	// Per-node resolved replay policy. A discovery run that is being
	// replayed has every node listed here with the policy that
	// applied at its dispatch.
	per_node:       {[string]: #ReplayPolicy}
})

// ─── Replay-state snapshot for partial re-entry ────────────────────
//
// Recorded by `rebuild_from_events/2` on the
// `{:continue, {:rebuild, events}}` path when the trailing event is
// not terminal. The walker resets `:running` nodes to `:pending`
// before re-dispatching (server.ex 270–276); this block records the
// reset state so a fixture can validate the re-entry shape.

#ReplayState: close({
	prev_hash:    string | null
	event_count:  int & >=0
	node_states:  {[string]: "pending" | "waiting" | "running" | "completed" | "failed"}
	node_outputs: {[string]: {[string]: string}}
})

// Top-level: every YAML fixture under fixtures/v1.0.0/ unifies with
// #ReplayWalk. close() rejects fixtures with stray top-level keys.
#ReplayWalk
