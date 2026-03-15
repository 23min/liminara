---
id: M-CS-05-example-01
epic: E-02-python-compliance-sdk
status: ready
---

# M-CS-05: Example 01 — Raw Python + Anthropic SDK

## Goal

Build a working example that demonstrates Liminara's compliance value: a simple LLM pipeline shown first without instrumentation (nondeterministic, no audit trail), then with `@op`/`@decision` decorators (nondeterministic but every decision recorded, hash-chained, tamper-evident, Article 12 compliant). A demo script runs the full arc and shows the compliance report.

This is the first runnable proof that the SDK works end-to-end against a real LLM.

## Design

### The pipeline

Three steps, minimal complexity:

1. **load** — read documents from a list (pure, deterministic)
2. **summarize** — call an LLM to summarize the documents (recordable, nondeterministic — this is the decision)
3. Return the summary

### LLM abstraction

The LLM call is isolated in a single function `call_llm(prompt: str) -> str` in a separate `llm.py` module. Default implementation uses the Anthropic SDK with `claude-haiku-4-5-20251001`. Swapping providers (OpenAI, local LLM, etc.) only requires changing this one function. Document this in the README.

### File layout

```
examples/01_raw_python/
  README.md                — what this proves, how to run, how to swap LLM providers
  llm.py                   — call_llm(prompt) -> str, Anthropic default
  pipeline_raw.py          — uninstrumented pipeline (no Liminara imports)
  pipeline_instrumented.py — same logic, @op/@decision decorators added
  demo.py                  — runs the full demo arc (see below)
```

### demo.py arc

The demo script tells the compliance story:

1. Run `pipeline_raw.run_pipeline()` — print the summary, note: "no compliance artifacts"
2. Run `pipeline_instrumented.run_pipeline()` — print the summary, show events/decisions/seal created
3. Run `pipeline_instrumented.run_pipeline()` again — different LLM response, also fully recorded
4. List all runs using the SDK — show both instrumented runs
5. Generate and print a human-readable Article 12 compliance report for the latest run
6. Print the punchline: both runs are independently auditable, decisions are stored for future replay

`demo.py` requires `ANTHROPIC_API_KEY` to be set. Prints to stdout with clear section headers.

## Acceptance criteria

### llm.py

- [ ] `call_llm(prompt: str) -> str` calls Claude Haiku and returns the response text
- [ ] Uses `anthropic.Anthropic()` client (reads `ANTHROPIC_API_KEY` from env)
- [ ] Model is `claude-haiku-4-5-20251001`
- [ ] Max tokens is 300

### pipeline_raw.py

- [ ] `DOCUMENTS` — a list of 3 short text strings (hardcoded, no file I/O)
- [ ] `load_documents() -> list[str]` — returns `DOCUMENTS`
- [ ] `summarize(docs: list[str]) -> str` — calls `call_llm` with a summarization prompt
- [ ] `run_pipeline() -> str` — calls load, summarize, returns summary
- [ ] No Liminara imports anywhere in this file
- [ ] Runnable standalone: `if __name__ == "__main__": print(run_pipeline())`

### pipeline_instrumented.py

- [ ] Imports `op`, `decision`, `run` from `liminara` and `LiminaraConfig`
- [ ] Same `DOCUMENTS` list as raw pipeline
- [ ] `load_documents()` decorated with `@op(name="load_documents", version="1.0.0", determinism="pure")`
- [ ] `summarize()` decorated with `@op(name="summarize", version="1.0.0", determinism="recordable")` and `@decision(decision_type="llm_response")`
- [ ] `run_pipeline(config: LiminaraConfig | None = None) -> tuple[str, str]` — wraps execution in `with run("example-01", "1.0.0", config=config) as r:`, returns `(summary, r.run_id)`
- [ ] Function bodies are identical to the raw pipeline — only decorators and the `run()` wrapper differ
- [ ] Runnable standalone: `if __name__ == "__main__": ...` prints summary and run_id

### demo.py

- [ ] Runs `pipeline_raw.run_pipeline()` and prints the output with a header
- [ ] Notes that no compliance artifacts were created
- [ ] Runs `pipeline_instrumented.run_pipeline()` and prints the output with a header
- [ ] Shows what was created: event count, decision count, seal hash
- [ ] Runs `pipeline_instrumented.run_pipeline()` a second time — different output, also compliant
- [ ] Lists all runs using `EventLog` or the report module
- [ ] Generates and prints a human-readable Article 12 compliance report for the latest run
- [ ] Requires `ANTHROPIC_API_KEY` — prints a clear error if not set
- [ ] Runnable: `uv run python examples/01_raw_python/demo.py`

### README.md

- [ ] Explains what this example demonstrates (the compliance story)
- [ ] Shows how to run: `uv sync --extra anthropic && ANTHROPIC_API_KEY=... uv run python examples/01_raw_python/demo.py`
- [ ] Explains how to swap LLM providers by modifying `llm.py`
- [ ] Notes that decisions are recorded for future replay (Elixir runtime)

### anthropic dependency

- [ ] `anthropic` remains an optional dependency in `pyproject.toml` (not forced on all SDK users)
- [ ] Example README clearly states `uv sync --extra anthropic` is required

## Tests

### `test_example_01.py` (~10 tests)

Tests use a **stub `call_llm`** that returns a fixed string (no API calls). The stub is injected by monkeypatching the `call_llm` function in `llm.py` via its import path in the pipeline modules. All tests run without `ANTHROPIC_API_KEY`.

**Raw pipeline tests:**
- `run_pipeline()` returns a string (with stubbed LLM)
- `load_documents()` returns the 3-element DOCUMENTS list
- No Liminara files created (no `.liminara/` directory)

**Instrumented pipeline tests:**
- `run_pipeline(config=config)` returns `(summary, run_id)` where summary is a string
- Events directory exists at `{runs_root}/{run_id}/events.jsonl`
- Event log contains `run_started`, `op_started` (x2), `decision_recorded`, `op_completed` (x2), `run_completed` — 7 events
- `op_started` for `summarize` has `determinism: "recordable"`
- A decision record exists for the summarize op
- `seal.json` exists
- Hash chain verifies
- Article 12 report shows all six fields `true`

**Equivalence test:**
- Raw and instrumented pipelines return the same summary text (with same stubbed LLM)

### `test_example_01_integration.py` (~3 tests, not run by default)

Integration tests that call the real Anthropic API. Marked with `@pytest.mark.integration` and skipped unless `ANTHROPIC_API_KEY` is set and `--run-integration` is passed.

- `pipeline_raw.run_pipeline()` returns a non-empty string
- `pipeline_instrumented.run_pipeline()` returns a non-empty summary and a valid run_id
- Generated report has `outcome: "success"` and all Article 12 fields `true`

### pytest configuration changes

- [ ] Add `integration` marker to `pyproject.toml`: `markers = ["integration: requires ANTHROPIC_API_KEY and --run-integration flag"]`
- [ ] Integration tests skipped by default: `addopts` includes `-m "not integration"`
- [ ] Can be run with: `uv run pytest -m integration --run-integration`

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Docker/docker-compose (can be added later)
- Multiple LLM provider implementations (just document the swap point)
- Replay demonstration (requires Elixir runtime)
- Colored terminal output in demo.py
- Example 02 (LangChain) — that's E-03

## Spec reference

- `docs/analysis/09_Compliance_Demo_Tool.md` — original demo design (brainstorm, not authoritative — real API differs)
- `docs/architecture/01_CORE.md` § "Discovery vs Replay"
- `docs/analysis/08_Article_12_Summary.md` — the six compliance questions

## Related ADRs

- none yet
