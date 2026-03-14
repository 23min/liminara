---
id: E-02-python-compliance-sdk
phase: 1
status: draft
---

# E-02: Python Compliance SDK

## Goal

A standalone Python SDK that instruments any Python code with Liminara-format event logging, decision recording, and compliance reporting. Installable via `uv`. No Elixir dependency. Produces Article 12 compliance reports from recorded runs.

Includes Example 01 (raw Python + Anthropic SDK) as the proof that it works.

## Scope

**In:**

### SDK core (`integrations/python/liminara/`)
- `decorators.py` — `@op(determinism=...)` and `@decision` decorators that wrap functions with event recording
- `event_log.py` — JSONL append-only event log with hash chain (per 11_Data_Model_Spec.md)
- `artifact_store.py` — content-addressed filesystem blob store (SHA-256, sharded directories)
- `decision_store.py` — decision record storage (canonical JSON, one file per recordable op)
- `hash.py` — SHA-256 hashing, canonical JSON serialization (RFC 8785), hash chain computation
- `report.py` — Article 12 compliance report generator
- `run.py` — run context manager (start run, collect events, compute seal)
- `config.py` — store root, runs root, configurable paths

### CLI (`integrations/python/liminara/cli.py`)
- `liminara list` — list all recorded runs (run_id, timestamp, event count, seal)
- `liminara verify <run_id>` — verify hash chain integrity of a run's event log
- `liminara report <run_id>` — generate Article 12 compliance report
  - `--format json` (default) — machine-readable JSON
  - `--format human` — colored terminal output with checkmarks
  - `--format markdown` — markdown document

### Example 01 (`integrations/python/examples/01_raw_python/`)
- A simple pipeline: load a document → summarize with Claude Haiku → save output
- Two versions of the same pipeline:
  - `pipeline_raw.py` — uninstrumented (no Liminara, just plain Python + Anthropic SDK)
  - `pipeline_instrumented.py` — same logic, wrapped with `@op` and `@decision` decorators
- `run.py` — runs both, shows the difference
- The uninstrumented version produces no logs. The instrumented version produces a full event log, decision records, artifacts, and a compliance report.

### Test suite (`integrations/python/tests/`)
- Output equivalence: instrumented pipeline produces identical functional output to uninstrumented
- Hash chain integrity: each event's prev_hash matches previous event's event_hash
- Tamper detection: modify an event, verify detects it
- Completeness: every op execution produces start + complete events
- Report correctness: generated report answers all six Article 12 questions

### Project setup
- `pyproject.toml` with `uv` as the package manager
- `uv.lock` for reproducible installs
- Python 3.12+
- Dependencies: `anthropic`, `click` (CLI), `canonicaljson` (RFC 8785)

**Out:**
- LangChain integration (E-03)
- Docker container
- Web UI
- Elixir runtime integration
- `liminara diff` and `liminara tamper-test` CLI commands (later)

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-CS-01-project-setup | Python project scaffolding, pyproject.toml, uv, directory layout | draft |
| M-CS-02-hash-and-store | SHA-256 hashing, canonical JSON, artifact store, event log with hash chain | draft |
| M-CS-03-decorators | @op and @decision decorators, run context manager, decision recording | draft |
| M-CS-04-cli-and-report | CLI (list, verify, report), Article 12 report generator (json/human/markdown) | draft |
| M-CS-05-example-01 | Raw Python + Anthropic SDK example (uninstrumented vs instrumented), test suite | draft |

## Success criteria

- [ ] `uv run python examples/01_raw_python/run.py` works with only `ANTHROPIC_API_KEY` set
- [ ] Uninstrumented and instrumented pipelines produce identical functional output
- [ ] `liminara list` shows recorded runs
- [ ] `liminara verify <run_id>` passes on unmodified runs
- [ ] `liminara report <run_id> --format human` shows a convincing Article 12 compliance report
- [ ] `liminara report <run_id> --format markdown` produces a clean markdown document
- [ ] All on-disk formats match `docs/analysis/11_Data_Model_Spec.md` exactly
- [ ] Test suite passes: equivalence, hash chain, tamper detection, completeness, report correctness

## References

- Data model: `docs/analysis/11_Data_Model_Spec.md`
- Demo tool design: `docs/analysis/09_Compliance_Demo_Tool.md`
- Compliance layer architecture: `docs/analysis/07_Compliance_Layer.md`
- Article 12 requirements: `docs/analysis/08_Article_12_Summary.md`
- Architecture: `docs/architecture/01_CORE.md` § Five concepts, § Caching
