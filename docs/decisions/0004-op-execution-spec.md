---
id: ADR-0004
working_id: ADR-OPSPEC-01
title: Codify the canonical op execution spec as a CUE contract
status: accepted
date: 2026-04-26
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
contract:
  schema: docs/schemas/op-execution-spec/schema.cue
  fixtures: docs/schemas/op-execution-spec/fixtures/v1.0.0/
  worked_example: docs/schemas/op-execution-spec/fixtures/v1.0.0/valid/recordable-with-warnings-partial.yaml
  reference_implementation: runtime/apps/liminara_core/lib/liminara/execution_spec.ex:45
  schema_version: "1.0.0"
---

# ADR-0004 — Codify the canonical op execution spec as a CUE contract

## Context

M-TRUTH-01 (E-20, merged) locked the canonical Elixir-side execution contract: `Liminara.ExecutionSpec` with five sections (`identity`, `determinism`, `execution`, `isolation`, `contracts`); `Liminara.OpResult` (`outputs`, `decisions`, `warnings`); and rules for how warnings, decisions, and execution context flow through op invocation.

E-19 (Warnings & Degraded Outcomes, merged) locked the warning-bearing terminal-event taxonomy: `Run.Server.finish_run/2` emits `run_completed` on `:success`, `run_partial` on `:partial`, `run_failed` on `:failed`, each carrying a `warning_summary` payload. M-WARN-01 locked `Liminara.Warning`'s severity taxonomy and required + optional fields. M-WARN-04 (D-2026-04-20-026) locked the on-the-wire string-keyed shape of warning payloads against the post-incident pressure that produced `bug_005`.

These shapes are settled in Elixir. Downstream consumers — the PackLoader (E-25), the SDK + DX layer (E-26), Radar's extracted form (E-27), and the future admin-pack (E-22) — must bind to the same shape, but today the only definition lives in Elixir source. A Python op or a third-party tool inspecting `op_completed` / `run_completed` events has no machine-checkable specification of the shape it should emit, and no way to fail loudly when it drifts. Schema drift therefore arrives as runtime exceptions (the M-WARN-04 `bug_005` cycle), not as authoring-time validation failures.

This ADR codifies the M-TRUTH-01 + E-19 + M-WARN-01 contract as a CUE schema with a versioned fixture cohort. It does not change runtime semantics. It does not introduce shims (per D-2026-04-20-026). It is schema-freezing only.

The alternative — leaving the contract in Elixir source as the sole source of truth — was viable while there was one consumer (the runtime). With the SDK, PackLoader, the admin-pack proxy, and Radar's extracted form all binding to the same shape, the cost of schema drift across consumers exceeds the cost of authoring + maintaining the CUE schema. The Elixir struct remains the runtime source of truth; the CUE schema is an additional cross-language verification surface that derives from it.

## Decision

**Adopt `docs/schemas/op-execution-spec/schema.cue` as the machine-checkable contract for `ExecutionSpec`, `OpResult`, `Warning`, `Run.Result`, and the `run_completed` / `run_partial` / `run_failed` terminal events.**

The schema mirrors the live Elixir source field-for-field. Field rename or shape divergence between live source and schema is a contract-matrix wrap-time check failure (per `.ai-repo/rules/liminara.md` Contract matrix discipline).

Sub-decisions:

- **Schema topic name: `op-execution-spec`.** Matches the canonical contract surface name in the contract matrix. The shorter `op-spec` was considered but conflicts with the looser informal use of "op spec" in non-canonical prose; `op-execution-spec` is unambiguous.
- **Fixture cohort `v1.0.0/`.** First populated cohort under the layout convention M-CONTRACT-01 shipped. Future additive evolution bumps minor (`v1.1.0/`); breaking evolution bumps major (`v2.0.0/`) and lands a deprecation ADR per ADR-EVOLUTION-01 (M-CONTRACT-04).
- **Atom-to-string encoding.** Elixir atoms (`:pure`, `:none`, `:success`) encode as plain strings on the YAML/JSON wire; the schema uses string disjunctions, not regexp matching. This matches the existing `warning_payload/1` stringification in `run.ex` and the JSON shape in `Run.Server`'s emitted events.
- **Closed schemas throughout.** Every `#Definition` uses `close()` so a fixture with a typo'd or wishfully-added field fails vet. The five `ExecutionSpec` sections are fixed; the three terminal-event variants are fixed; the severity taxonomy is fixed. New sections or new severity values require a migration ADR.
- **One fixture = one realistic scenario.** Each fixture pairs an `execution_spec` + `op_result` + `run_result` + `terminal_event`, exercising the contract end-to-end in a single readable shape. The alternative — separate fixture trees per type — was rejected because the cross-field invariants (status ↔ event_type; warning_count ↔ degraded_nodes) only show up in a paired shape.
- **Cross-field invariant on status ↔ event_type.** The schema enforces `run_result.status == "success"` ↔ `terminal_event.event_type == "run_completed"` (and the partial / failed variants) so a fixture that drifts the two apart fails vet. `finish_run/2` is the runtime source-of-truth for this mapping.
- **`degraded` consistency is not enforced cross-field.** The Elixir struct derives `degraded` from `(status, warning_count)` via `Run.Result.derive_degraded/2`. A CUE invariant could mirror that, but it would force every fixture to either trust runtime derivation or duplicate the rule. The schema only checks the type; runtime owns the derivation. This is a deliberate asymmetry and is documented in the schema comment.

## Consequences

**What becomes easier:**

- Python ops + the SDK + admin-pack proxy can vet their emitted shapes against `op-execution-spec/schema.cue` before sending them to the runtime. Schema drift surfaces at authoring time.
- The pre-commit hook + `scripts/cue-vet` (M-CONTRACT-01) walks the fixture library on every commit; a schema bump that breaks a historical fixture fails the hook and prevents the silent-rejection failure mode the schema-evolution loop is designed to catch.
- Downstream ADRs (REPLAY-01, WIRE-01) that reference the same `Warning`, `OpResult`, and terminal-event shapes can cite this schema rather than re-defining the shape.
- The contract matrix has a concrete row for `op-execution-spec` with a live-source path that does not rot when `execution_spec.ex` is touched (the schema sits alongside, not inside, the live source).

**What becomes harder:**

- Every change to `execution_spec.ex` / `op_result.ex` / `warning.ex` / `run.ex` (Result) / `run/server.ex` (terminal events) now also touches `docs/schemas/op-execution-spec/schema.cue` and possibly the v1.0.0 fixture cohort. The contract-matrix wrap-time check catches drift but does not auto-update the schema. Authors who rename a field in Elixir without updating the CUE schema discover it at wrap.
- The CUE schema's atom-to-string convention is a crossing point developers must internalise. A Python op emits `"pure"`; the Elixir runtime stores `:pure`. The two encodings never appear in the same context, but the convention has to be taught once.
- Evolution policy is now load-bearing on a schema authored before ADR-EVOLUTION-01 (M-CONTRACT-04) is written. ADR-EVOLUTION-01 must specify a compatibility algorithm that handles the v1.0.0 cohort retroactively; the comment in the schema's `schema_version` field marks this dependency explicitly.

**What we accept:**

- The schema lags Elixir-source changes by one edit. The contract-matrix wrap-time check is the forcing function; until the framework's `verify-contracts` integration lands (deferred per the parent epic), authoring discipline is the gate.
- One terminal-event variant — `run_partial` — has the same payload shape as `run_failed`. The schema represents them as separate variants because the `event_type` is the discriminator downstream consumers branch on; collapsing them would lose that signal.
- Per-content-type payload schemas (what's inside an `outputs.summary` artifact) are out of scope. ADR-CONTENT-01 (M-CONTRACT-04) owns the content-type namespace shape; the per-payload schemas are demand-driven per pack.

## Schema-backed contract

The `contract:` frontmatter block names the bundle. Each piece tests a different property of the contract:

- **`schema`** — `docs/schemas/op-execution-spec/schema.cue`. The authoritative shape. Cited in the `op-execution-spec` row of `docs/architecture/indexes/contract-matrix.md` (added by M-CONTRACT-02's matrix-pass).
- **`fixtures`** — `docs/schemas/op-execution-spec/fixtures/v1.0.0/`. Three valid fixtures (one realistic — Radar's `claude_complete` op emitting a degraded warning during a run that ends `:partial`; one boundary-edge — a pure deterministic CSV-parse op with no warnings / decisions; one alternate-terminal — a side-effecting Gmail-fetch op whose run fails). Five invalid fixtures, each exercising a distinct violation class: out-of-taxonomy `determinism.class`, out-of-taxonomy `severity`, missing required Warning field, status ↔ event_type mismatch, undeclared sixth ExecutionSpec section, missing `warning_summary` on a terminal event.
- **`worked_example`** — the realistic fixture `docs/schemas/op-execution-spec/fixtures/v1.0.0/valid/recordable-with-warnings-partial.yaml` is the worked example. Its YAML body is the ADR's worked example verbatim; the Worked example section below quotes it without modification (per the M-CONTRACT-02 fixture-parity rule).
- **`reference_implementation`** — `runtime/apps/liminara_core/lib/liminara/execution_spec.ex:45`, the five-section `defstruct` that defines `Liminara.ExecutionSpec`. This is an *existing* implementation citation (per Assertion 4 in `.ai-repo/rules/contract-design.md`), not a scheduled-to-exist one. The schema mirrors this struct field-for-field; the four secondary references below are also live runtime citations.
- **`schema_version`** — `1.0.0`. The first frozen cohort. Bumping this requires either an additive change (minor bump, fixtures stay in `v1.0.0/`, new fixtures land in `v1.1.0/`) or a breaking change (major bump + deprecation ADR per ADR-EVOLUTION-01 when it lands in M-CONTRACT-04).

### Worked example

The `claude_complete` op (a recordable LLM call from Radar's pack) runs against a cluster of articles, returns a structured summary, records its LLM-decision provenance, and emits a degraded warning because `max_tokens` was hit before the response completed. A sibling op (`publish_briefing`) fails. The run terminates `:partial`. This is the entire OPSPEC contract surface in one scenario:

```yaml
execution_spec:
  identity:
    name: "claude_complete"
    version: "0.3.0"
  determinism:
    class: "recordable"
    cache_policy: "none"
    replay_policy: "replay_recorded"
  execution:
    executor: "port"
    entrypoint: "claude_complete"
    timeout_ms: 30000
    requires_execution_context: true
  isolation:
    env_vars:
      - "ANTHROPIC_API_KEY"
    network: "tcp_outbound"
    bootstrap_read_paths:
      - "packs/radar/python"
    runtime_read_paths: []
    runtime_write_paths: []
  contracts:
    inputs:
      cluster_articles: "radar.cluster_articles@1"
      prompt_template: "text:1"
    outputs:
      summary: "radar.cluster_summary@1"
    decisions:
      may_emit: true
    warnings:
      may_emit: true

op_result:
  outputs:
    summary: "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b"
  decisions:
    - decision_type: "llm_match"
      decision_hash: "sha256:8d23cf6c86e834a7aa6eded54c26ce2bb2e74903"
      model_id: "claude-3-5-sonnet-20241022"
      prompt_hash: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4"
      response_hash: "sha256:a665a45920422f9d417e4867efdc4fb8a04a1f3f"
      token_usage:
        input_tokens: 1240
        output_tokens: 380
  warnings:
    - code: "llm_partial_response"
      severity: "degraded"
      summary: "LLM returned a truncated cluster summary; max_tokens hit before completion"
      cause: "max_tokens=512 exceeded by claude-3-5-sonnet-20241022"
      remediation: "raise max_tokens to 1024 in pack config or shorten prompt"
      affected_outputs:
        - "summary"

run_result:
  run_id: "radar-20260420T060000-d4e5f6a7"
  status: "partial"
  outputs:
    cluster_summary:
      summary: "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b"
  event_count: 11
  node_states:
    cluster_summary: "completed"
    publish_briefing: "failed"
  failed_nodes:
    - "publish_briefing"
  warning_count: 1
  degraded_nodes:
    - "cluster_summary"
  degraded: true

terminal_event:
  event_type: "run_partial"
  run_id: "radar-20260420T060000-d4e5f6a7"
  error_type: "run_failure"
  error_message: "one or more nodes failed"
  failed_nodes:
    - "publish_briefing"
  warning_summary:
    warning_count: 1
    degraded_node_ids:
      - "cluster_summary"
```

What each part means in domain terms:

- **`execution_spec`** — Radar's `claude_complete` op declares itself as a `recordable` LLM call: outputs are not content- addressed (LLM responses are nondeterministic), so cache_policy is `none` and replay_policy is `replay_recorded` (replay injects the stored decision rather than re-calling the API). It runs as a Python op via `:port`, requires the runtime's `execution_context` (so the op gets `run_id` + `pack_version` for replay provenance), and declares it may emit both decisions and warnings.
- **`op_result`** — the op succeeded and produced a single artifact (the cluster summary, content-addressed by SHA-256). Its decision payload records the LLM call's provenance: model id, prompt hash, response hash, and token usage — enough for a future replay to reconstruct the same answer without re-calling the API. The single warning has `severity: "degraded"`, the highest severity in the locked taxonomy that still describes successful output rather than failure.
- **`run_result`** — the run as a whole. Two nodes: `cluster_summary` completed (the op above), `publish_briefing` failed (a sibling op the schema doesn't show, but whose failure flips the run from `:success` to `:partial`). `warning_count: 1` and `degraded_nodes: ["cluster_summary"]` are derived from the warning above; `degraded: true` is derived from `(status, warning_count)` via `Run.Result.derive_degraded/2`.
- **`terminal_event`** — the single event Run.Server emits at run termination. `event_type: "run_partial"` because the run ended in `:partial` (per `finish_run/2`'s 1:1 status → event mapping). The `warning_summary` payload mirrors `run_result`'s `warning_count` + `degraded_nodes`, so downstream observation consumers (LiveView, A2UI) can render the degraded signal without reading the run's full event log.

### Reference implementation

Primary citation: [`runtime/apps/liminara_core/lib/liminara/execution_spec.ex:45`](../../runtime/apps/liminara_core/lib/liminara/execution_spec.ex) — `defstruct [:identity, :determinism, :execution, :isolation, :contracts]`. The five-section ExecutionSpec; the schema's `#ExecutionSpec` mirrors it field-for-field.

Secondary citations (each is a live runtime implementation, not a scheduled-to-exist one):

- [`runtime/apps/liminara_core/lib/liminara/op_result.ex:12`](../../runtime/apps/liminara_core/lib/liminara/op_result.ex) — `defstruct outputs: %{}, decisions: [], warnings: []`. The schema's `#OpResult` mirrors this.
- [`runtime/apps/liminara_core/lib/liminara/warning.ex:15`](../../runtime/apps/liminara_core/lib/liminara/warning.ex) — `@severities [:info, :low, :medium, :high, :degraded]`. The schema's `#Severity` mirrors this list.
- [`runtime/apps/liminara_core/lib/liminara/run.ex:57`](../../runtime/apps/liminara_core/lib/liminara/run.ex) — `Run.Result` `defstruct`. The schema's `#RunResult` mirrors its field set; `Run.Result.derive_degraded/2` (lines 91–93) is the derivation rule the schema does not itself enforce.
- [`runtime/apps/liminara_core/lib/liminara/run/server.ex:770`](../../runtime/apps/liminara_core/lib/liminara/run/server.ex) — `defp finish_run(state, status)`. The 1:1 status → event_type mapping that the schema's cross-field invariant mirrors. The `warning_summary_payload/2` helper at line 1240 is the source of the `#WarningSummary` shape.

### Anchored admin-pack citation

**Secondary reference (forward-looking, per Assertion 1 in `.ai-repo/rules/contract-design.md`):**

`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §8 — Decision recording` is the load-bearing anchor. The section enumerates seven recordable decision types (`classification_choice`, `auto_match`, `llm_match`, `human_confirm`, `human_no_match`, `no_doc_apply`, `vendor_canonicalize`) — each with a payload shape and the op that emits it — and then names the three replay behaviours by determinism class (pure → re-execute, recordable → inject, side_effecting → skip). This is the same `determinism.class` enumeration the OPSPEC schema freezes; the same `decisions.may_emit: true` predicate; the same `replay_policy` outcomes. Admin-pack's bookkeeping flow exercises every dimension of the OPSPEC contract: pure ops (CSV/XLSX parsers in `liminara-ops-bank`), pinned_env (`tesseract_ocr`), recordable (`claude_complete`, `cascade_resolver`), and side_effecting (Gmail fetch, filesystem ops in `liminara-ops-fs`).

A complementary anchor — `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §5 — Provider Op libraries` — names individual ops by their declared determinism class on real bookkeeping work (`pdfplumber_extract (pure)`, `tesseract_ocr (pinned_env)`, `claude_complete (recordable)`, `gmail_fetch_attachment (side_effecting)`). This anchor demonstrates the OPSPEC contract's expressivity across the four-class taxonomy in a concrete pack.

This citation is admin-pack-secondary to Radar-primary. Radar today exercises the OPSPEC contract through its recordable ops at `runtime/apps/liminara_radar/lib/liminara/radar/ops/summarize.ex:10` (`def determinism, do: :recordable`) and `runtime/apps/liminara_radar/lib/liminara/radar/ops/llm_dedup_check.ex`, and through the per-op execution-spec builders at `runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex` that emit the canonical five-section shape this ADR codifies. The worked example above and the cohort's three valid fixtures deliberately use op names sourced from `bookkeeping-pack-on-liminara.md §5 — Provider Op libraries` (`csv_to_transactions (pure)` at line 222, `claude_complete (recordable)` at line 199, `gmail_fetch_attachment (side_effecting)` at line 189) — one per determinism class — so the cohort's worked-example surface is pressure-tested against the secondary consumer (admin-pack) rather than re-rendering Radar's existing ops. Radar's op shape is exercised by the primary citations above; admin-pack's op shape is exercised by the fixtures themselves. The two-pack pressure prevents this ADR from being a one-pack abstraction at both citation and worked-example layers.

## Validation

The schema, fixtures, and worked example all vet locally:

```sh
$ ./scripts/cue-vet
$ echo $?
0
```

Field-for-field correspondence with the live Elixir source is the contract-matrix wrap-time check. A future rename in `execution_spec.ex` that doesn't update `schema.cue` is caught by the matrix audit before the milestone wraps.

The schema-evolution loop in `scripts/cue-vet` walks every fixture in `docs/schemas/op-execution-spec/fixtures/v1.0.0/` against the HEAD schema on every commit (via the pre-commit hook) and on every `scripts/cue-vet` no-args invocation. A schema change that breaks an existing fixture either reverts the change or lands a deprecation ADR
+ major version bump per ADR-EVOLUTION-01 (when M-CONTRACT-04 lands).

## References

- **M-TRUTH-01 spec (canonical Elixir contract):** `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
- **E-19 epic (warning + terminal-event taxonomy):** `work/done/E-19/epic.md`
- **M-WARN-01 spec (warning shape detail):** `work/done/E-19/M-WARN-01-runtime-warning-contract.md`
- **Parent sub-epic spec:** `work/epics/E-24-contract-design/epic.md`
- **Owning milestone:** `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md`
- **Contract-matrix index (row added by M-CONTRACT-02 wrap-pass):** `docs/architecture/indexes/contract-matrix.md`
- **Reviewer rule (the four assertions):** `.ai-repo/rules/contract-design.md`
- **Authoring overlay (Liminara bindings on the upstream skill):** `.ai-repo/skills/design-contract.md`
- **Decision log entries:**
  - `D-2026-04-20-025` — `run_partial` is a first-class terminal event type. Locks the three-event taxonomy this schema codifies.
  - `D-2026-04-20-026` — No backward-compat shims for in-flight contract fixes. The schema reflects the M-WARN-04-corrected shape (string-keyed warning payloads), not the legacy shape.
  - `D-2026-04-22-028` — ADR working-keyword IDs in frontmatter (now superseded by D-030 on filename, retained for the `working_id:` convention).
  - `D-2026-04-23-030` — ADR filename `NNNN-<slug>.md`, ID `ADR-NNNN`. This ADR is `0004-op-execution-spec.md` per the convention; the working-keyword ID `ADR-OPSPEC-01` lives in `working_id:`.
- **Live runtime sources mirrored:**
  - `runtime/apps/liminara_core/lib/liminara/execution_spec.ex` — `Liminara.ExecutionSpec` and its five sub-modules.
  - `runtime/apps/liminara_core/lib/liminara/op_result.ex` — `Liminara.OpResult`.
  - `runtime/apps/liminara_core/lib/liminara/warning.ex` — `Liminara.Warning` (locked severity taxonomy).
  - `runtime/apps/liminara_core/lib/liminara/run.ex` — `Run.Result` (`derive_degraded/2` derivation rule).
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex` — `finish_run/2`, `warning_summary_payload/2`.
- **Admin-pack secondary anchors (E-22-pending allowance):**
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §8 — Decision recording`
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §5 — Provider Op libraries`
