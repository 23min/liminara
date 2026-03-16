---
id: M-CS-04-cli-and-report
epic: E-02-python-compliance-sdk
status: done
---

# M-CS-04: CLI and Article 12 Compliance Report

## Goal

Implement the CLI commands (`list`, `verify`, `report`) and the Article 12 compliance report generator so that recorded runs can be inspected, verified, and reported on from the terminal. The report answers six compliance questions derived from EU AI Act Article 12.

## Included change to `decorators.py`

As part of this milestone, add `"determinism": determinism` to the `op_started` event payload in `decorators.py`. This is a one-line additive change — existing M-CS-03 tests still pass (they check for specific keys, not exclusivity). `11_Data_Model_Spec.md` has been updated to include `determinism` in the `op_started` payload keys.

## Acceptance criteria

### Report generator (`report.py`)

- [x] `generate_report(runs_root, run_id, store_root=None)` returns a report dict
- [x] Report structure has top-level keys: `report_version`, `generated_at`, `run_id`, `pack_id`, `pack_version`, `started_at`, `completed_at`, `outcome`, `event_count`, `operations`, `artifacts`, `decisions`, `hash_chain`, `article_12`
- [x] `report_version` is `"1.0"`
- [x] `generated_at` is current UTC timestamp (ISO 8601, millisecond precision)
- [x] `run_id`, `pack_id`, `pack_version` extracted from `run_started` event payload
- [x] `started_at` is timestamp of `run_started` event
- [x] `completed_at` is timestamp of last event (read directly from the event's `timestamp` field — works for both `run_completed` and `run_failed`)
- [x] `outcome` is `"success"` or `"failed"` based on last event type
- [x] `event_count` is total number of events in the log
- [x] `operations` is a list of dicts, one per op (paired from `op_started`/`op_completed` events), each with: `node_id`, `op_id`, `op_version`, `determinism`, `duration_ms`, `cache_hit`, `input_hashes`, `output_hashes`, `has_decision` (true if a `decision_recorded` event exists for this `node_id`)
- [x] `artifacts` is a list of all unique artifact hashes collected from `input_hashes` in `op_started` events and `output_hashes` in `op_completed` events, each with: `artifact_hash`, `size_bytes` (read from store, or `null` if `store_root` not provided)
- [x] `decisions` is a list of dicts, one per decision, each with: `node_id`, `decision_type`, `decision_hash`
- [x] `hash_chain` dict with: `verified` (bool), `error` (str or null), `run_seal` (str from seal.json, or null if no seal)
- [x] `article_12` dict with six boolean/string fields answering compliance questions (see below)
- [x] Handles failed runs (no seal.json) — `hash_chain.run_seal` is `null`, report still generates
- [x] Raises `FileNotFoundError` if run directory does not exist

### Article 12 compliance fields

The `article_12` dict answers six questions from `docs/analysis/08_Article_12_Summary.md`:

- [x] `logging_automatic` (bool): true if events exist (the SDK records automatically)
- [x] `tamper_evident` (bool): true if `hash_chain.verified` is true
- [x] `inputs_traceable` (bool): true if all ops have `input_hashes` in their `op_started` events
- [x] `outputs_traceable` (bool): true if all completed ops have `output_hashes`
- [x] `decisions_recorded` (bool): true if every op that has a `decision_recorded` event has a valid `decision_hash` (i.e., all nondeterministic choices were captured). Note: actual model version strings are an M-CS-05 concern; this field checks that decisions exist, not their content.
- [x] `logs_retained` (bool): always true (files exist on disk; retention enforcement is deferred)

### Report formatters

- [x] `format_json(report)` returns a JSON string (pretty-printed with 2-space indent, sorted keys)
- [x] `format_human(report)` returns a plain-text string with headers, checkmarks, and summary
- [x] `format_markdown(report)` returns a markdown string with headers, tables, and checklist

### Human-readable format specification

```
Run: {run_id}
Pack: {pack_id} (v{pack_version})
Started: {started_at}
Completed: {completed_at}
Outcome: {outcome}
Events: {event_count}
Hash chain: {checkmark} intact
Run seal: {run_seal or "none (run failed)"}

Operations:
  {op_id:<20} {determinism:<16} {cache_status:<10} {duration_ms}ms  {decision_note}
  ...

Artifacts: {count} unique
  {artifact_hash} ({size_bytes} bytes)
  ...

Article 12 Compliance:
  {checkmark} Automatic event recording ({event_count} events)
  {checkmark} Tamper-evident log (hash chain intact)
  {checkmark} Input traceability ({n} ops with recorded inputs)
  {checkmark} Output traceability ({n} ops with recorded outputs)
  {checkmark} Decisions recorded ({n} decisions)
  {checkmark} Logs retained on disk
```

Checkmarks: use unicode `\u2713` for pass, `\u2717` for fail.

### Markdown format specification

- H1: `# Compliance Report: {run_id}`
- H2 sections: Run Metadata, Operations, Artifacts, Article 12 Compliance
- Operations as a markdown table: `| Op | Determinism | Cache | Duration | Decision |`
- Article 12 as a checklist: `- [x] Automatic event recording` or `- [x] ...`

### CLI commands (`cli.py`)

- [x] Built on Click (already scaffolded)
- [x] `liminara --help` shows available commands
- [x] All commands accept `--runs-root` option (default: `.liminara/runs`)
- [x] `report` command also accepts `--store-root` option (default: `.liminara/store/artifacts`) for artifact size lookup

### `liminara list`

- [x] Lists all recorded runs found in `{runs_root}/*/events.jsonl`
- [x] Sorted newest first (reverse alphabetical by run directory name, which is timestamp-sortable by design)
- [x] Columns: `run_id`, `started_at`, `events`, `status` (sealed/unsealed/failed)
- [x] `status` is `sealed` if `seal.json` exists, `failed` if last event is `run_failed`, `unsealed` otherwise
- [x] Empty store: prints `No runs found.` to stderr, exit code 0
- [x] Output is plain text, one line per run, columns aligned

### `liminara verify <run_id>`

- [x] Reads `events.jsonl` for the given run
- [x] Verifies hash chain using `EventLog.verify()`
- [x] If `seal.json` exists: also verifies `run_seal` matches `event_hash` of last event
- [x] On success: prints `Hash chain verified. {N} events, chain intact.` to stdout
- [x] On success with seal: also prints `Run seal: {run_seal}`
- [x] On failure: prints which event broke the chain and what was expected vs actual, to stderr
- [x] Exit code 0 on success, 1 on failure
- [x] Nonexistent run: prints `Run not found: {run_id}` to stderr, exit code 1

### `liminara report <run_id>`

- [x] `--format json` (default): prints JSON report to stdout
- [x] `--format human`: prints human-readable report to stdout
- [x] `--format markdown`: prints markdown report to stdout
- [x] Nonexistent run: prints `Run not found: {run_id}` to stderr, exit code 1

## Tests

### `test_report.py` (~15 tests)

Tests use a helper that creates a run with known ops and decisions (using the `run()` context manager and `@op`/`@decision` decorators from M-CS-03), then generates a report.

- `generate_report` returns dict with all required top-level keys
- `report_version` is `"1.0"`
- `run_id`, `pack_id`, `pack_version` match the test run
- `started_at` and `completed_at` are valid ISO 8601 timestamps
- `outcome` is `"success"` for normal run
- `outcome` is `"failed"` for run that raised
- `operations` list has correct count and fields per op
- `operations` entries include `determinism` and `has_decision` fields
- `decisions` list has correct count and fields
- `hash_chain.verified` is `true` for untampered run
- `hash_chain.run_seal` matches seal.json
- All six `article_12` fields are `true` for a complete run
- `article_12.tamper_evident` is `false` for a tampered run
- `format_json` returns valid JSON with all keys
- `format_human` contains all section headers and checkmarks
- `format_markdown` contains markdown headers and table

### `test_cli.py` (~12 tests)

Tests use Click's `CliRunner` for isolated invocation.

- `liminara list` with no runs → output contains `No runs found.`, exit code 0 (message to stderr)
- `liminara list` with two runs → shows both run_ids, correct columns
- `liminara list` runs are sorted newest first
- `liminara verify` on valid run → exit code 0, output contains `verified`
- `liminara verify` on tampered run → exit code 1, output contains error detail
- `liminara verify` on nonexistent run → exit code 1, output contains `not found`
- `liminara verify` shows seal when seal.json exists
- `liminara report` default format is JSON → valid JSON output
- `liminara report --format human` → contains `Article 12 Compliance` header
- `liminara report --format markdown` → contains `# Compliance Report`
- `liminara report` on nonexistent run → exit code 1
- `liminara --help` shows list, verify, report commands

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- `liminara diff` (comparing two runs)
- `liminara tamper-test` (deliberately corrupting and restoring a run)
- PDF report output
- Web-based report viewer
- Colored terminal output (plain unicode checkmarks suffice; color can be added later)
- Retention policy enforcement (always report `logs_retained: true`)
- Artifact content type detection (not stored in events; would need op metadata)

## Spec reference

- `docs/analysis/08_Article_12_Summary.md` — the six compliance questions
- `docs/analysis/09_Compliance_Demo_Tool.md` — CLI design, demo workflow
- `docs/analysis/07_Compliance_Layer.md` — report structure, compliance layer architecture
- `docs/analysis/11_Data_Model_Spec.md` — event types, seal format, directory layout

## Related ADRs

- none yet
