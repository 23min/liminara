---
id: ADR-0005
working_id: ADR-WIRE-01
title: Codify the port wire protocol as a CUE contract
status: accepted
date: 2026-04-26
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
contract:
  schema: docs/schemas/wire-protocol/schema.cue
  fixtures: docs/schemas/wire-protocol/fixtures/v1.0.0/
  worked_example: docs/schemas/wire-protocol/fixtures/v1.0.0/valid/recordable-llm-summarize.yaml
  reference_implementation: runtime/python/src/ops/radar_summarize.py:42
  schema_version: "1.0.0"
---

# ADR-0005 — Codify the port wire protocol as a CUE contract

## Context

`Liminara.Executor.Port` (`runtime/apps/liminara_core/lib/liminara/executor/port.ex`) spawns a Python process and exchanges JSON over stdio framed by the BEAM `{packet, 4}` length-prefix transport. The protocol consists of four messages — request, success, success-with-decisions / success-with-warnings, error — documented in the module's `@moduledoc` and verified end-to-end by every Radar Python op shipped today (`runtime/python/src/ops/radar_*.py`).

The wire protocol has been stable for several milestones. M-RUN-01 added the optional `context` rider on the request to carry an `%ExecutionContext{}` (port.ex:74–79). M-WARN-04 (D-2026-04-20-026) locked the on-the-wire warning payload as **string-keyed JSON with stringified atom values**: `warning_payload/1` (`runtime/apps/liminara_core/lib/liminara/run.ex:710` and `runtime/apps/liminara_core/lib/liminara/run/server.ex:1192`) flattens an Elixir `%Liminara.Warning{}` struct into the JSON shape LiveView and A2UI consumers can ingest without crashing. The pre-fix path (atom-keyed broadcast) is the regression `bug_005` named. M-WARN-04 deleted that path and locked the post-fix shape; this ADR records the result.

These shapes are settled in Elixir. Downstream consumers — every Python op (Radar today, admin-pack tomorrow), the future Python SDK (E-26), the `liminara-test-harness` (E-26), and any third-party tool inspecting captured wire frames in fixture replays — all bind to the same shape. Today the only specification of that shape is the `port.ex` `@moduledoc` plus the actual Python+Elixir code. A Python op that drifts (emits an atom-keyed warning, omits an `id` field, picks a `status` value the runtime doesn't understand) discovers the failure at runtime, in production, against a slow-feedback loop — exactly the cycle M-WARN-04's `bug_005` exemplified.

This ADR codifies the wire protocol as a CUE schema with a versioned fixture cohort. It does not change runtime semantics; it does not introduce shims (per D-2026-04-20-026); it is schema-freezing only.

The alternative — leaving the wire protocol's specification in the `port.ex` `@moduledoc` — was viable while there was one consumer shape (Radar's Python ops) and one author. With the SDK + test harness + admin-pack proxy + Radar extraction all binding to the same wire surface, the cost of schema drift across consumers exceeds the cost of authoring + maintaining the CUE schema. `port.ex` and `liminara_op_runner.py` remain the runtime source of truth; the CUE schema is an additional cross-language verification surface that derives from them.

## Decision

**Adopt `docs/schemas/wire-protocol/schema.cue` as the machine-checkable contract for the JSON message shapes `Liminara.Executor.Port` exchanges with Python ops over `{packet, 4}` framed stdio.**

The schema mirrors the live runtime — `port.ex` (`encode_request/3`, `decode_response/1`, `normalize_success/1`), `liminara_op_runner.py` (`read_message`, `write_message`, `handle_request`), and `warning_payload/1` (the wire shape of warnings, divergent from `%Liminara.Warning{}`'s atom-keyed Elixir struct). Field rename or shape divergence between live source and schema is a contract-matrix wrap-time check failure (per `.ai-repo/rules/liminara.md` Contract matrix discipline).

Sub-decisions:

- **Schema topic name: `wire-protocol`.** Matches the canonical contract surface name in the milestone spec's *Contract matrix changes* section. The shorter `wire` was considered but is ambiguous — Liminara has multiple wire boundaries (port, A2UI WebSocket, future HTTP); `wire-protocol` qualified by contract-matrix context unambiguously refers to the port surface.
- **Bundled per-fixture entry shape (`#Exchange`).** Each valid fixture pairs a request and its corresponding response in one document. This inherits convention 1 from D-2026-04-26-036 and encodes the correlation invariant `request.id == response.id` inside the schema's unification rather than in prose. The alternative — separate request and response fixture trees — was rejected because the correlation is the contract's central invariant; severing it from the fixture shape weakens what the schema captures.
- **Mutually-exclusive success / error response shapes via disjunction.** `#Response: #SuccessResponse | #ErrorResponse`. The two shapes share `id` and `status` but diverge on body content: success carries `outputs` (+ optional `decisions`, `warnings`); error carries `error`. `close()` on each branch rejects fixtures that mix them (e.g. an error response with `outputs`). This matches `port.ex:50–55`'s pattern matching, which dispatches on `status` alone — a malformed response with both shapes would be silently misrouted; the schema makes the violation explicit.
- **String-keyed warnings on the wire (post-M-WARN-04).** The schema's `#WireWarning` is the JSON shape `warning_payload/1` produces, not `%Liminara.Warning{}`'s Elixir struct shape. The in-process struct shape is the OPSPEC contract surface (see ADR-OPSPEC-01's `#Warning`); the wire shape is its serialized form. The two are deliberately separate — when an Elixir consumer reads from `:pg` broadcast or replay, it gets the wire shape, not the struct. This is the asymmetry M-WARN-04 named.
- **Atom-to-string disjunctions, not regex `=~` patterns.** Severity is `"info" | "low" | "medium" | "high" | "degraded"`. Inherits D-2026-04-26-036 convention 2.
- **Optional `?:` keys for nilable / sometimes-omitted fields.** `context?` on the request, `decisions?` and `warnings?` on the success response, all optional. Inherits D-2026-04-26-036 convention 5. `decisions?` and `warnings?` are sometimes-omitted because `op_runner.py:73–76` only sets them when the op's return dict carries them — an op that emits no decisions sees the key absent on the wire, not present-with-empty-list.
- **Decisions are open structs, severity-style enums for warnings.** `#Decision: { decision_type?: string, ... }` — open because each pack chooses its decision payload shape (the runtime's Decision.Store appends node_id/op_id/op_version/recorded_at server-side; the *wire* shape is op-specific). Severity in `#WireWarning` is closed because Liminara's warning taxonomy is locked at five values. Inherits D-2026-04-26-036 convention 4.
- **`outputs` content is opaque.** `outputs: {[string]: _}` — every per-payload schema is owned by ADR-CONTENT-01 (M-CONTRACT-04) and by the per-op contract bindings, not by this wire-level schema.

## Consequences

**What becomes easier:**

- Python ops + the future SDK + admin-pack proxy + the `liminara-test-harness` can vet their request/response shapes against `wire-protocol/schema.cue` before integration. Schema drift surfaces at authoring time, not as a runtime exception in production.
- The pre-commit hook + `scripts/cue-vet` (M-CONTRACT-01) walks the fixture library on every commit; a schema bump that breaks a historical fixture fails the hook before merge.
- ADR-OPSPEC-01's `#Warning` and this ADR's `#WireWarning` are documented as separate surfaces with a documented serialization relationship (`warning_payload/1`). A reader inspecting a captured wire frame can refer to `wire-protocol/schema.cue`; a reader inspecting an in-process Elixir warning refers to `op-execution-spec/schema.cue`. Neither schema needs to know about the other; the relationship lives in `run.ex` / `run/server.ex` — the runtime owns the boundary, as D-2026-04-26-036 convention 3 prescribes.
- Future test-harness fixtures (E-26 `liminara-test-harness`) reuse the same valid/invalid YAML files as input — the schema becomes the contract between the harness's "fake op" generator and the runtime's port.

**What becomes harder:**

- Every change to `port.ex` (request/response shape) or `liminara_op_runner.py` (its mirror) or `warning_payload/1` (the serialization step) now also touches `docs/schemas/wire-protocol/schema.cue` and possibly the v1.0.0 fixture cohort. The contract-matrix wrap-time check catches drift but does not auto-update the schema.
- Two warning shapes — in-process (`%Liminara.Warning{}`) and on-wire (`warning_payload/1` output) — must be remembered. Contributors writing Python ops emit the wire shape; contributors writing Elixir-internal warning emitters emit the struct shape. The two cross at `warning_payload/1`. This was already true before the schema; the schema codifies the boundary.
- Evolution policy is now load-bearing. ADR-EVOLUTION-01 (M-CONTRACT-04) must specify a compatibility algorithm for the v1.0.0 wire-protocol cohort retroactively, same as for OPSPEC.

**What we accept:**

- The schema lags runtime changes by one edit. The contract-matrix wrap-time check is the forcing function; until the framework's `verify-contracts` integration lands, authoring discipline is the gate.
- CUE cannot trivially express "this struct field must be present but may be empty." A success response without an `outputs` key evaluates as compatible (CUE defaults the absent struct to `{}`). The runtime side (`port.ex:243`'s `normalize_success/1`) crashes on this shape; the schema does not catch it. This is a deliberate asymmetry: schema validates shape *constraints*, runtime validates *presence-of-bodies*. We tracked the alternative — using `!_` markers or `_present: bool` sentinels — and judged the cost (every fixture would carry a sentinel field, polluting the YAML surface) higher than the benefit (a single missing-outputs variant the runtime crashes on within milliseconds anyway). Listed in `work/gaps.md` if a future schema evolution wants to revisit it.
- The schema does not enforce the JSON-roundtrip equivalence between `Map.from_struct(execution_context)` (Elixir-side, atom keys + atom values) and the JSON shape Python sees (string keys
  + string values). That equivalence is owned by `Jason.encode!` on the Elixir side; the schema only validates the JSON-shaped end of the round trip.

## Schema-backed contract

The `contract:` frontmatter block names the bundle. Each piece tests a different property of the contract:

- **`schema`** — `docs/schemas/wire-protocol/schema.cue`. The authoritative shape. Cited in the `wire-protocol` row of `docs/architecture/indexes/contract-matrix.md` (added by M-CONTRACT-02's matrix-pass).
- **`fixtures`** — `docs/schemas/wire-protocol/fixtures/v1.0.0/`. Four valid fixtures (one realistic — Radar's `radar_summarize` with an LLM-fallback warning + decision; one boundary-edge — the `echo` op with no decisions or warnings; one warning-only — a recordable op succeeds with a degraded warning but no decisions; one error response — a Python traceback). Six invalid fixtures, each exercising a distinct violation class: missing request `id`, out-of-enum `status`, error response carrying `outputs`, request-response correlation-id mismatch, severity outside the locked taxonomy, and missing request `op` discriminator.
- **`worked_example`** — the realistic fixture `docs/schemas/wire-protocol/fixtures/v1.0.0/valid/recordable-llm-summarize.yaml` is the worked example. Its YAML body is the ADR's worked example verbatim; the *Worked example* section below quotes it without modification (per the M-CONTRACT-02 fixture-parity rule).
- **`reference_implementation`** — `runtime/python/src/ops/radar_summarize.py:42` — the `execute` function that exercises every dimension of the wire protocol on real Radar work today: it consumes a request with `execution_context`, returns successful `outputs`, records LLM decisions, and emits warnings on the placeholder / LLM-error paths. This is an *existing* implementation citation (per Assertion 4 in `.ai-repo/rules/contract-design.md`), not a scheduled-to-exist one. The Elixir side primary citation is [`runtime/apps/liminara_core/lib/liminara/executor/port.ex:65`](../../runtime/apps/liminara_core/lib/liminara/executor/port.ex) (`encode_request/3`); the warning-payload boundary where the wire shape diverges from the struct shape is at [`runtime/apps/liminara_core/lib/liminara/run.ex:710`](../../runtime/apps/liminara_core/lib/liminara/run.ex) (`warning_payload/1`, mirrored at [`runtime/apps/liminara_core/lib/liminara/run/server.ex:1192`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex)).
- **`schema_version`** — `1.0.0`. The first frozen cohort. Bumping this requires either an additive change (minor bump, fixtures stay in `v1.0.0/`, new fixtures land in `v1.1.0/`) or a breaking change (major bump + deprecation ADR per ADR-EVOLUTION-01 when it lands in M-CONTRACT-04).

### Worked example

Radar's `radar_summarize` op (a recordable LLM call from Radar's pack, source `runtime/python/src/ops/radar_summarize.py`) runs against a single-cluster input, falls back to a placeholder summary because `ANTHROPIC_API_KEY` is not configured, records its provenance as a `cluster_summary` decision, and emits a degraded warning describing the placeholder. The runtime's `Liminara.Executor.Port` issues the request with an attached `%ExecutionContext{}` (M-RUN-01); the Python runner returns a single response with `outputs`, `decisions`, and `warnings` together. This is the entire wire-protocol contract surface in one exchange:

```yaml
request:
  id: "9f86d081884c7d65"
  op: "radar_summarize"
  inputs:
    clusters: "[{\"cluster_id\":\"c-1\",\"label\":\"AI safety\",\"items\":[{\"title\":\"Anthropic publishes update\",\"source_id\":\"techcrunch\",\"clean_text\":\"...\"}]}]"
  context:
    run_id: "radar-20260420T060000-d4e5f6a7"
    started_at: "2026-04-20T06:00:00Z"
    pack_id: "radar"
    pack_version: "0.1.0"
    replay_of_run_id: null
    topic_id: null

response:
  id: "9f86d081884c7d65"
  status: "ok"
  outputs:
    summaries: "[{\"cluster_id\":\"c-1\",\"summary\":\"Anthropic published an update on its safety frameworks...\",\"key_takeaways\":[\"...\"],\"degraded\":false}]"
    decisions: "[{\"decision_type\":\"cluster_summary\",\"cluster_id\":\"c-1\"}]"
  decisions:
    - decision_type: "cluster_summary"
      cluster_id: "c-1"
      cluster_label: "AI safety"
      item_count: 1
      summary: "Anthropic published an update on its safety frameworks..."
      rationale: "haiku summary"
  warnings:
    - code: "radar_summarize_placeholder"
      severity: "degraded"
      summary: "Using placeholder summaries because Anthropic access is unavailable"
      cause: "ANTHROPIC_API_KEY is not configured"
      remediation: "Configure ANTHROPIC_API_KEY to enable live summaries"
      affected_outputs:
        - "summaries"
```

What each part means in domain terms:

- **`request`** — the Elixir side calls `Liminara.Executor.Port.run("radar_summarize", inputs, execution_context: ctx)`; `encode_request/3` (port.ex:65) builds the JSON object with the generated correlation `id`, the op module name, the inputs map (note that pack-level inputs are *already* JSON strings here — `clusters` is a stringified JSON array because the Radar pack chose that on-wire encoding), and the `context` rider serialized from `Map.from_struct/1`. The whole object is `Jason.encode!`'d and length-framed before being sent down the port.
- **`response`** — the Python runner (`liminara_op_runner.py`) decodes the request, dispatches to `ops.radar_summarize.execute`, and serializes the returned dict back through `write_message`. `id` echoes the request; `status: "ok"` is the success branch; `outputs` carries Radar's two stringified-JSON outputs; `decisions` is the recorded provenance the op chose to surface (only set because `op_runner.py:73` saw `"decisions"` in the return dict); `warnings` is set the same way (`op_runner.py:75`).
- **Decision shape** — Radar's `cluster_summary` decision is an open object: every key besides the conventional `decision_type` discriminator is op-specific. The schema's `#Decision` is intentionally open to admit per-pack shapes; ADR-CONTENT-01 (M-CONTRACT-04) owns the namespace for any future per-decision- type schemas.
- **Warning shape** — every key is a string, severity is the stringified atom (`"degraded"`, not `:degraded`). This is the shape `warning_payload/1` produces from a `%Liminara.Warning{}` struct on the Elixir side; the Python runner emits the same shape natively. The two converge at the wire boundary.

### Reference implementation

Primary citation: [`runtime/python/src/ops/radar_summarize.py:42`](../../runtime/python/src/ops/radar_summarize.py) — the `execute(inputs)` entry point. This op is the most-load- bearing exercise of the wire protocol Radar runs today: a real LLM call with provenance recording, a placeholder fallback that emits a degraded warning, and per-cluster outputs. Every dimension of the wire protocol — request `inputs` + `context` intake, success response with `outputs`, decision recording, and warning emission — is exercised on real work in this single op.

Elixir-side primary citation (the runtime end of the same protocol): [`runtime/apps/liminara_core/lib/liminara/executor/port.ex:65`](../../runtime/apps/liminara_core/lib/liminara/executor/port.ex) — `encode_request/3`, the canonical request builder. The companion `decode_response/1` (port.ex:91) and `normalize_success/1` (port.ex:243) close the loop. The module's `@moduledoc` documented four message shapes; the actual code in the same module surfaces a fifth case implicitly — error responses patterned on (port.ex:53) — but the four-shape `@moduledoc` is the authored reference and the schema mirrors the same four shapes (request, success, success-with-decisions / -warnings, error).

Wire-shape divergence point: [`runtime/apps/liminara_core/lib/liminara/run.ex:710`](../../runtime/apps/liminara_core/lib/liminara/run.ex) — `warning_payload/1`. This is the function that flattens `%Liminara.Warning{}` (atom-keyed Elixir struct, the OPSPEC `#Warning` shape) into the JSON-string-keyed shape the wire uses (this ADR's `#WireWarning`). The mirror at [`runtime/apps/liminara_core/lib/liminara/run/server.ex:1192`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) is the same helper duplicated for `Run.Server`'s broadcast path; both call into `stringify_warning_map/1` (line 720 / 1202). The duplication is itself a known minor smell — see *Reviewer notes* below — but it does not affect the contract.

### References to related contracts

- **ADR-OPSPEC-01** — defines `#Warning`, the in-process Elixir struct shape. This ADR's `#WireWarning` is the post- `warning_payload/1` JSON form of the same warning. The two schemas live in separate topics deliberately: OPSPEC describes what an op emits *as a struct*, wire-protocol describes what crosses the port *as JSON*. The function at `run.ex:710` is the one-way bridge.
- **`response.warnings`** in this schema and **`op_result.warnings`** in OPSPEC are the same warning, observed at two different surfaces — wire (this ADR) and post-decode in-process (OPSPEC).
- **`request.context`** mirrors `%Liminara.ExecutionContext{}` from M-RUN-01, serialized via `Map.from_struct/1`. The shape is validated structurally by this ADR's `#ExecutionContext`; its *behaviour* (which ops require it, what fields they read) is in the OPSPEC schema's `execution.requires_execution_context: bool`.

### Anchored admin-pack citation

ADR-WIRE-01 is a Radar-only ADR per the parent sub-epic's *ADRs produced* table (line 90 in `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`). It has no admin-pack secondary; the secondary column in that table is `—`. This is per the reviewer rule `.ai-repo/rules/contract-design.md` *Assertion 3* exception: the wire protocol is the existing Radar implementation surface, and a single-pack abstraction is acceptable here because the protocol is the JSON-over-stdio crossing every pack must use anyway — admin-pack will exercise the same bytes Radar does, not a different shape.

## Validation

The schema, fixtures, and worked example all vet locally:

```sh
$ ./scripts/cue-vet
$ echo $?
0
```

Field-for-field correspondence with the live runtime (`port.ex` + `liminara_op_runner.py` + `warning_payload/1`) is the contract-matrix wrap-time check. A future rename in any of those files that doesn't update `schema.cue` is caught by the matrix audit before the milestone wraps.

The schema-evolution loop in `scripts/cue-vet` walks every fixture in `docs/schemas/wire-protocol/fixtures/v1.0.0/` against the HEAD schema on every commit (via the pre-commit hook) and on every `scripts/cue-vet` no-args invocation. A schema change that breaks an existing fixture either reverts the change or lands a deprecation ADR + major version bump per ADR-EVOLUTION-01 (M-CONTRACT-04).

## References

- **Parent sub-epic spec:** `work/epics/E-24-contract-design/epic.md`
- **Owning milestone:** `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md`
- **Predecessor ADR (shares Warning shape):** `docs/decisions/0004-op-execution-spec.md` — defines `#Warning` as the Elixir-struct surface; this ADR's `#WireWarning` is its serialized form.
- **Contract-matrix index (row added by M-CONTRACT-02 wrap-pass):** `docs/architecture/indexes/contract-matrix.md`
- **Reviewer rule (the four assertions):** `.ai-repo/rules/contract-design.md` — note Assertion 3 exception: ADR-WIRE-01 is Radar-only, no admin-pack secondary (matches the parent sub-epic's *ADRs produced* table line 90, which carries `—` in the secondary column).
- **Authoring overlay (Liminara bindings on the upstream skill):** `.ai-repo/skills/design-contract.md`
- **Decision log entries:**
  - `D-2026-04-20-026` — No backward-compat shims for in-flight contract fixes. The schema reflects the M-WARN-04-corrected shape (string-keyed warning payloads), not the legacy shape. The invalid fixture `warning-severity-out-of-taxonomy.yaml` exists to make the rejection of out-of-taxonomy severities explicit.
  - `D-2026-04-22-028` — ADR working-keyword IDs in frontmatter (now superseded by D-030 on filename, retained for the `working_id:` convention).
  - `D-2026-04-23-030` — ADR filename `NNNN-<slug>.md`, ID `ADR-NNNN`. This ADR is `0005-port-wire-protocol.md` per the convention; the working-keyword ID `ADR-WIRE-01` lives in `working_id:`.
  - `D-2026-04-26-036` — CUE encoding conventions ratified for M-CONTRACT-02. This ADR inherits all five conventions (bundled per-fixture entry, atom-to-string disjunctions, type-only for derived fields, locked enums, optional `?:` keys).
- **Live runtime sources mirrored:**
  - `runtime/apps/liminara_core/lib/liminara/executor/port.ex` — the canonical Elixir-side wire protocol. `encode_request/3`, `decode_response/1`, `normalize_success/1`, `receive_response/2`, the `@env_whitelist` clean-environment discipline, and the `{packet, 4}` framing decisions.
  - `runtime/python/src/liminara_op_runner.py` — the canonical Python-side wire protocol. `read_message`, `write_message`, `handle_request`. Same protocol, different language.
  - `runtime/apps/liminara_core/lib/liminara/run.ex` — `warning_payload/1` at line 710. The serialization function that bridges OPSPEC's `#Warning` and this ADR's `#WireWarning`.
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex` — `warning_payload/1` mirror at line 1192. The same helper re-defined for `Run.Server`'s `:pg`-broadcast code path.
  - `runtime/python/src/ops/radar_summarize.py` — the reference implementation cited above; demonstrates every wire-protocol dimension on real Radar work.

## Reviewer notes

Two minor live-source observations not worth blocking the bundle on but worth recording for downstream readers:

1. The `port.ex` `@moduledoc` (lines 7–10) documents four message shapes — Request, Success, Decisions (success-with-decisions), Error. The schema-bundle here also accounts for **success-with- warnings** as an additional protocol shape, surfaced from `liminara_op_runner.py:75` where `warnings` is conditionally added to the response dict alongside `decisions`. The `port.ex` `@moduledoc` is older than M-WARN-04 by several milestones; it does not lie, but it under-describes by one shape. A follow-up doc-fix to `@moduledoc` is a good candidate to keep the prose-side and schema-side mutually anchored, and is recorded in the decision-log candidates section of this bundle's progress log.
2. `warning_payload/1` is duplicated across `run.ex` and `run/server.ex` — they are byte-identical. Neither calls the other; both call private `stringify_warning_map/1` helpers that are also byte-identical. The duplication is a runtime-side smell, not a contract concern; the schema is unaffected and a future refactor that consolidates them does not change the wire contract.
