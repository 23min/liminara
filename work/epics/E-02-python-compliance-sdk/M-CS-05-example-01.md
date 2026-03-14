---
id: M-CS-05-example-01
epic: E-02-python-compliance-sdk
status: draft
---

# M-CS-05: Example 01 — Raw Python + Anthropic SDK

## Goal

Build the first example application: a simple document summarization pipeline in two versions (uninstrumented and instrumented). This is the proof that the SDK works, the basis of the demo, and the integration test for all previous milestones.

## Acceptance criteria

### Uninstrumented pipeline (`examples/01_raw_python/pipeline_raw.py`)

- [ ] Loads a text document from a file
- [ ] Sends it to Claude Haiku for summarization via the Anthropic SDK directly
- [ ] Saves the summary to an output file
- [ ] Produces no Liminara logs, events, or artifacts
- [ ] Runnable: `uv run python examples/01_raw_python/pipeline_raw.py`

### Instrumented pipeline (`examples/01_raw_python/pipeline_instrumented.py`)

- [ ] Same functional logic as the uninstrumented version
- [ ] Decorated with `@op` and `@decision` from the Liminara SDK
- [ ] Wrapped in a `with liminara.run(...)` context
- [ ] Produces: event log (JSONL), decision record, artifacts, run seal
- [ ] Runnable: `uv run python examples/01_raw_python/pipeline_instrumented.py`

### Runner (`examples/01_raw_python/run.py`)

- [ ] Runs both pipelines in sequence
- [ ] Prints a comparison: "Raw pipeline produced: [output file]. No logs."
- [ ] Then: "Instrumented pipeline produced: [same output]. Plus: N events, M artifacts, run seal sha256:..."
- [ ] Then runs `liminara verify` and `liminara report --format human` on the instrumented run
- [ ] Runnable: `uv run python examples/01_raw_python/run.py`

### Sample input

- [ ] Include a sample input document (a short text, 500-1000 words — could be an excerpt from one of the Liminara docs)
- [ ] The summarization task should be simple and produce a meaningful result

### Integration test suite (`tests/test_example_01.py`)

- [ ] Output equivalence: both pipelines produce functionally equivalent summaries (same document in, summary out — exact text may differ due to LLM nondeterminism, but both produce valid summaries)
- [ ] Completeness: instrumented run has run_started, op_started/completed for each op, decision_recorded for the LLM call, run_completed
- [ ] Hash chain: `liminara verify` passes on the instrumented run
- [ ] Report: `liminara report --format json` produces valid JSON with all Article 12 fields
- [ ] Tamper detection: modify one event in the JSONL file, `liminara verify` fails
- [ ] Transparency: removing decorators from instrumented pipeline makes it functionally identical to raw pipeline

### Environment

- [ ] Requires only `ANTHROPIC_API_KEY` environment variable
- [ ] Uses Claude Haiku (cheapest model, fast)
- [ ] README.md explains: what this example demonstrates, how to run it, expected output

## Out of scope

- LangChain integration (E-03)
- Caching or replay
- Multiple runs or batch processing
- Error handling beyond basic try/except in the pipeline

## Spec reference

- `docs/analysis/09_Compliance_Demo_Tool.md` § Example 01
- `docs/analysis/07_Compliance_Layer.md` § Model A — the decorator interface
