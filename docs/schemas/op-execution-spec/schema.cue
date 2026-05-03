// op-execution-spec/schema.cue
//
// Schema for ADR-OPSPEC-01: the canonical op execution contract.
//
// This schema freezes the shape of:
//   - Liminara.ExecutionSpec (five sections — identity, determinism,
//     execution, isolation, contracts) per M-TRUTH-01.
//   - Liminara.OpResult (outputs, decisions, warnings) per M-TRUTH-01.
//   - Liminara.Warning (locked severity taxonomy + required + optional
//     fields) per M-TRUTH-01 / M-WARN-01.
//   - Liminara.Run.Result (status, aggregation fields, derived
//     `degraded`) per M-WARN-01 / M-WARN-04.
//   - The three run-terminal events emitted by Run.Server.finish_run/2
//     (run_completed / run_partial / run_failed) per E-19 +
//     D-2026-04-20-025.
//
// Source-of-truth bindings (live Elixir):
//   - runtime/apps/liminara_core/lib/liminara/execution_spec.ex
//   - runtime/apps/liminara_core/lib/liminara/op_result.ex
//   - runtime/apps/liminara_core/lib/liminara/warning.ex
//   - runtime/apps/liminara_core/lib/liminara/run.ex (Run.Result)
//   - runtime/apps/liminara_core/lib/liminara/run/server.ex
//     (finish_run/2 + warning_summary_payload/2)
//
// Atom-vs-string convention: Elixir atoms are encoded as plain strings
// on the YAML/JSON wire (warning_payload/1 in run.ex stringifies atom
// values). The CUE schema therefore uses string disjunctions, not the
// `=~` regexp pattern, for closed enumerations.

package opexecutionspec

// schema_version is fixed at the cohort version. Bumping the cohort
// (v1.0.0 → v1.1.0 additive, → v2.0.0 breaking) is governed by
// ADR-EVOLUTION-01 (M-CONTRACT-04) when it lands.
schema_version: "1.0.0"

// ─── Top-level fixture entry: a single op invocation framed by its
//     run-terminal event. One fixture = one realistic scenario.
#TerminalRun: close({
	execution_spec: #ExecutionSpec
	op_result:      #OpResult
	run_result:     #RunResult
	terminal_event: #TerminalEvent

	// Cross-field invariant: the terminal_event's `event_type` must
	// match the run_result.status mapping, per finish_run/2:
	//   :success -> "run_completed"
	//   :partial -> "run_partial"
	//   :failed  -> "run_failed"
	if run_result.status == "success" {terminal_event: event_type: "run_completed"}
	if run_result.status == "partial" {terminal_event: event_type: "run_partial"}
	if run_result.status == "failed" {terminal_event: event_type: "run_failed"}
})

// ─── ExecutionSpec — the five canonical sections ───────────────────

#ExecutionSpec: close({
	identity:    #Identity
	determinism: #Determinism
	execution:   #Execution
	isolation:   #Isolation
	contracts:   #Contracts
})

#Identity: close({
	// Free-form op identifier (e.g. "intake_classify"). Required.
	name: string & !=""
	// Free-form version string (e.g. "1.0.0"). Required.
	version: string & !=""
})

// Determinism class enum is locked by M-TRUTH-01 (execution_spec.ex
// `@type class` line). cache_policy + replay_policy are derived from
// the class by Op.replay_policy_for/1 + Op.cache_policy_for/1; the
// schema admits the enumerated values without forcing a specific
// derivation, leaving the runtime free to refine the mapping.
#Determinism: close({
	class:          "pure" | "pinned_env" | "recordable" | "side_effecting"
	cache_policy:   "content_addressed" | "content_addressed_with_environment" | "none"
	replay_policy:  "reexecute" | "replay_recorded" | "skip"
})

// Executor enum locked by Liminara.Executor.run/3 (`case executor`).
// timeout_ms is optional (nil-able in the Elixir struct); when present
// it must be a positive integer.
#Execution: close({
	executor:   "inline" | "task" | "port"
	entrypoint: string & !=""
	timeout_ms?: int & >0
	requires_execution_context: bool
})

// Isolation enumerates declared execution capabilities. `network`
// values today are "none" and "tcp_outbound" (the only ones used in
// runtime + tests); future capability classes (e.g. "udp_outbound",
// "fs_only") evolve additively per ADR-EVOLUTION-01.
#Isolation: close({
	env_vars:             [...string]
	network:              "none" | "tcp_outbound"
	bootstrap_read_paths: [...string]
	runtime_read_paths:   [...string]
	runtime_write_paths:  [...string]
})

// Contracts surface — what the op may emit. `inputs` and `outputs`
// here are key-name → free-form descriptor maps; per-content-type
// payload schemas are out of scope for OPSPEC (ADR-CONTENT-01 owns
// the content-type namespace shape).
#Contracts: close({
	inputs:    {[string]: _}
	outputs:   {[string]: _}
	decisions: close({may_emit: bool})
	warnings:  close({may_emit: bool})
})

// ─── OpResult — canonical successful-completion shape ──────────────

#OpResult: close({
	// Output-key → opaque value. Output content shape is per-pack and
	// not policed by this schema (per ADR-CONTENT-01 boundary).
	outputs: {[string]: _}
	// Each decision is a free-form map; Decision.Store appends node_id
	// + op_id + op_version + recorded_at server-side at record time.
	decisions: [...{...}]
	warnings:  [...#Warning]
})

// ─── Warning — locked taxonomy ─────────────────────────────────────

// Severity taxonomy is the single source-of-truth list from
// Liminara.Warning.@severities. Adding a value here requires a
// migration ADR per ADR-EVOLUTION-01.
#Severity: "info" | "low" | "medium" | "high" | "degraded"

#Warning: close({
	code:                string & !=""
	severity:            #Severity
	summary:             string & !=""
	cause?:              string
	remediation?:        string
	affected_outputs?:   [...string]
})

// ─── Run.Result — terminal aggregation ─────────────────────────────

#RunStatus: "success" | "partial" | "failed"

// `degraded` is derived from (status, warning_count) per
// Run.Result.derive_degraded/2:
//   :failed -> false (degraded = false even with warnings)
//   any other status with warning_count > 0 -> true
//   otherwise -> false
//
// CUE does not enforce this derivation; consumers must set `degraded`
// consistently. The schema only checks the type. The cross-field
// invariant could be expressed but would forbid the Elixir struct from
// being the single source of truth for derivation; we let runtime own
// the derivation and validate the consistency in Elixir.
#RunResult: close({
	run_id:          string & !=""
	status:          #RunStatus
	outputs:         {[string]: _}
	event_count:     int & >=0
	node_states:     {[string]: "pending" | "waiting" | "running" | "completed" | "failed"}
	failed_nodes:    [...string]
	warning_count:   int & >=0
	degraded_nodes:  [...string]
	degraded:        bool
})

// ─── Terminal events ───────────────────────────────────────────────
//
// finish_run/2 emits exactly one of:
//
//   run_completed (status :success):
//     %{ "run_id", "outcome" => "success", "artifact_hashes",
//        "warning_summary" }
//
//   run_partial (status :partial) and run_failed (status :failed):
//     %{ "run_id", "error_type" => "run_failure",
//        "error_message", "failed_nodes", "warning_summary" }
//
// The disjunction below mirrors that taxonomy. `warning_summary`
// shape is locked by warning_summary_payload/2.

#WarningSummary: close({
	warning_count:      int & >=0
	degraded_node_ids:  [...string]
})

#TerminalEvent: #RunCompletedEvent | #RunPartialEvent | #RunFailedEvent

#RunCompletedEvent: close({
	event_type:       "run_completed"
	run_id:           string & !=""
	outcome:          "success"
	artifact_hashes:  [...string]
	warning_summary:  #WarningSummary
})

#RunPartialEvent: close({
	event_type:      "run_partial"
	run_id:          string & !=""
	error_type:      "run_failure"
	error_message:   string & !=""
	failed_nodes:    [...string]
	warning_summary: #WarningSummary
})

#RunFailedEvent: close({
	event_type:      "run_failed"
	run_id:          string & !=""
	error_type:      "run_failure"
	error_message:   string & !=""
	failed_nodes:    [...string]
	warning_summary: #WarningSummary
})

// Top-level: every YAML fixture under fixtures/v1.0.0/ unifies with
// this constraint. Use `close()` so fixtures with stray top-level
// keys are rejected.
#TerminalRun
