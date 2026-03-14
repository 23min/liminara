---
id: M-CS-03-decorators
epic: E-02-python-compliance-sdk
status: draft
---

# M-CS-03: Decorators and Run Context Manager

## Goal

Implement the `@op` and `@decision` decorators and the run context manager so that any Python function can be instrumented with Liminara event recording by adding a decorator.

## Acceptance criteria

### Run context manager (`run.py`)

- [ ] `with liminara.run(pack_id, pack_version) as r:` starts a new run
- [ ] On entry: creates run directory, writes `run_started` event
- [ ] On successful exit: writes `run_completed` event, computes and writes run seal to `seal.json`
- [ ] On exception: writes `run_failed` event with error info, still computes seal
- [ ] Generates run_id as `{pack_id}-{iso_timestamp}-{8 hex random}`
- [ ] Nested op calls within the run context are automatically associated with the run
- [ ] `r.run_id` is accessible within the context

### @op decorator (`decorators.py`)

- [ ] `@op(name="...", determinism="pure|pinned_env|recordable|side_effecting")` wraps a function
- [ ] On call: emits `op_started` event with node_id, op name, input hashes
- [ ] Hashes input arguments as artifacts (stores them in artifact store)
- [ ] On successful return: emits `op_completed` event with output hashes, duration_ms
- [ ] Hashes return value as artifact (stores in artifact store)
- [ ] On exception: emits `op_failed` event with error type and message
- [ ] Decorated function's return value and behavior are unchanged (transparent wrapping)
- [ ] If `determinism="recordable"`: automatically wraps return value as a decision record

### @decision decorator (`decorators.py`)

- [ ] `@decision(name="...", decision_type="llm_response|human_approval|stochastic")` wraps a function
- [ ] Records the function's return value as a decision record
- [ ] Captures additional metadata if provided (model_id, token_usage, etc.)
- [ ] Emits `decision_recorded` event with decision_hash and decision_type
- [ ] The decision record includes: node_id, op_id, inputs hash, output, decision_hash, timestamp

### Integration between components

- [ ] Decorators use the current run context (thread-local or contextvars)
- [ ] Multiple `@op` calls within a single `with run()` block share the same run
- [ ] Events are appended to the correct run's event log
- [ ] Artifacts are stored in the shared artifact store

## Example usage (what the API should look like)

```python
import liminara
from liminara.decorators import op, decision

@op(name="load_document", determinism="pure")
def load_document(path: str) -> str:
    return Path(path).read_text()

@op(name="summarize", determinism="recordable")
@decision(name="llm_summary", decision_type="llm_response")
def summarize(text: str, model: str = "claude-haiku-4-5-20251001") -> str:
    response = anthropic_client.messages.create(...)
    return response.content[0].text

@op(name="save_output", determinism="side_effecting")
def save_output(summary: str, path: str) -> None:
    Path(path).write_text(summary)

with liminara.run("example", "0.1.0") as r:
    text = load_document("input.md")
    summary = summarize(text)
    save_output(summary, "output.md")

print(f"Run {r.run_id} complete. Seal: {r.seal}")
```

## Tests

- `test_decorators.py`:
  - `@op` wraps function transparently (same input → same output)
  - `@op` emits op_started and op_completed events
  - `@op` records input and output artifacts in store
  - `@op` on exception emits op_failed event
  - `@decision` records a decision record with correct hash
  - `@decision` emits decision_recorded event
  - Decorated functions work without a run context (no-op / warning)
- `test_run.py`:
  - Run context creates run directory and events.jsonl
  - Run context emits run_started and run_completed events
  - Run context on exception emits run_failed
  - Run seal matches event_hash of run_completed event
  - seal.json is written with correct content
  - Multiple ops within one run share the run context
  - run_id format matches spec

## Out of scope

- Replay (injecting stored decisions instead of executing)
- Caching (checking cache before executing pure ops)
- CLI and report generation (M-CS-04)
- Concurrent/parallel op execution

## Spec reference

- `docs/architecture/01_CORE.md` § Five concepts (Op, Decision, Run)
- `docs/analysis/11_Data_Model_Spec.md` § Event types, § Decision records, § Run seal
- `docs/analysis/07_Compliance_Layer.md` § Model A (Python decorators)
