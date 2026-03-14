---
id: M-CS-04-cli-and-report
epic: E-02-python-compliance-sdk
status: draft
---

# M-CS-04: CLI and Article 12 Compliance Report

## Goal

Implement the CLI commands (`list`, `verify`, `report`) and the compliance report generator so that recorded runs can be inspected, verified, and reported on from the terminal.

## Acceptance criteria

### CLI framework (`cli.py`)

- [ ] Built on Click
- [ ] `liminara --help` shows available commands
- [ ] `--store-root` option to override default store location (default: `.liminara/`)
- [ ] Commands read from the store root to find runs

### `liminara list`

- [ ] Lists all recorded runs, sorted by timestamp (newest first)
- [ ] Columns: run_id, started_at, event_count, seal_status (sealed/unsealed/failed)
- [ ] Empty store: prints "No runs found." (not an error)

### `liminara verify <run_id>`

- [ ] Reads `events.jsonl` for the given run
- [ ] Verifies hash chain: each event's prev_hash matches previous event's event_hash
- [ ] Verifies run seal: seal.json's run_seal matches event_hash of last event
- [ ] On success: prints "Hash chain verified. N events, chain intact."
- [ ] On failure: prints which event broke the chain, what was expected vs actual
- [ ] Exit code 0 on success, 1 on failure

### `liminara report <run_id>`

- [ ] Reads events, decisions, and seal for the given run
- [ ] Generates Article 12 compliance report answering six questions:
  1. When did this operation occur? → run start/end timestamps
  2. What was the input? → input artifact hashes, sizes, types
  3. Which model version processed it? → model ID and version from decision records
  4. What was the output? → output artifact hashes, sizes, types
  5. Has the log been modified? → hash chain verification result
  6. Can I retrieve this in 6 months? → file paths, retention note
- [ ] `--format json` (default): machine-readable JSON object
- [ ] `--format human`: colored terminal output with headers, checkmarks, summary table
- [ ] `--format markdown`: markdown document with headers, tables, checklist

### Report generator (`report.py`)

- [ ] `generate_report(run_id, store_root)` → returns a report data structure (dict)
- [ ] Report includes: run metadata, operation list with determinism classes and durations, artifact inventory, decision summary (model, tokens), hash chain status, Article 12 checklist
- [ ] `format_json(report)` → JSON string
- [ ] `format_human(report)` → colored terminal string
- [ ] `format_markdown(report)` → markdown string

### Human-readable output example

```
Run: example-2026-03-14T10:30:00-a1b2c3d4
Pack: example (v0.1.0)
Started: 2026-03-14T10:30:00.000Z
Completed: 2026-03-14T10:30:12.342Z
Events: 8
Hash chain: ✓ intact (8/8 events verified)
Run seal: sha256:9f2e...

Operations:
  load_document     pure           cached    120ms
  summarize         recordable     executed  3,420ms
    Model: claude-haiku-4-5-20251001
    Input tokens: 1,024  Output tokens: 512
  save_output       side_effecting executed  45ms

Artifacts:
  sha256:a1b2... (12,340 bytes)
  sha256:c3d4... (2,100 bytes)

Article 12 Compliance:
  ✓ Automatic event recording (8 events)
  ✓ Tamper-evident log (hash chain intact)
  ✓ Input/output traceability (2 artifacts)
  ✓ Model version recorded (claude-haiku-4-5-20251001)
  ✓ Nondeterminism identified (1 recordable op)
  ✓ Logs retained on disk
```

## Tests

- `test_cli.py`:
  - `liminara list` with no runs → "No runs found."
  - `liminara list` with recorded runs → correct output
  - `liminara verify` on valid run → exit code 0, success message
  - `liminara verify` on tampered run → exit code 1, error details
  - `liminara verify` on nonexistent run → error message
  - `liminara report` with `--format json` → valid JSON with all required fields
  - `liminara report` with `--format human` → includes all sections
  - `liminara report` with `--format markdown` → valid markdown with headers and tables
- `test_report.py`:
  - Report includes all six Article 12 answers
  - Report correctly identifies recordable ops and their models
  - Report reflects hash chain status (pass and fail cases)

## Out of scope

- `liminara diff` (comparing two runs)
- `liminara tamper-test` (deliberately corrupting a run)
- Web-based report viewer
- PDF report output

## Spec reference

- `docs/analysis/08_Article_12_Summary.md` § What Compliance Actually Looks Like (six questions)
- `docs/analysis/09_Compliance_Demo_Tool.md` § CLI commands
- `docs/analysis/11_Data_Model_Spec.md` § Run seal, § Event types
