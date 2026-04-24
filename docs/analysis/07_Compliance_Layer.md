# Liminara Compliance Layer

**Date:** 2026-03-14 (updated 2026-03-16)
**Context:** How Liminara's architecture (event sourcing, content-addressing, decision records) naturally satisfies EU AI Act Article 12 requirements. Compliance is a consequence of the design, not the product. The actual value proposition is reproducibility, replay, and caching of nondeterministic computation.

---

## 1. What Article 12 Actually Requires

Article 12 of the EU AI Act mandates that all high-risk AI systems must technically allow for **automatic recording of events** over the system's lifetime. Enforcement: **2 August 2026**.

Required capabilities, with precision:

| Requirement | Exact wording | What it means technically |
|---|---|---|
| **Automatic logging** | "technically allow for automatic recording" | Not opt-in, not manual. Every run must produce a record. |
| **Tamper-resistance** | implied by "logging capabilities" in Article 12 | Logs must be verifiable as unmodified. |
| **Input traceability** | "identify situations where the AI system may present a risk" | Given an output, trace back to the exact inputs that produced it. |
| **Model version recording** | "relevant to the intended purpose" | Which model version, which prompt version, produced which output. |
| **Minimum retention** | 6 months for limited-purpose systems, longer for general-purpose | Event log and artifacts must survive for at least 6 months. |
| **Monitoring support** | "facilitating post-market monitoring" | Auditors must be able to query and inspect records. |

Crucially: Article 12 does not require a specific data format, specific database, or specific architecture. It requires that the *capability* exists. Liminara's event log + content-addressed artifacts + decision records satisfy every requirement above as architectural consequences, not bolt-ons.

Sources:
- [EU AI Act Article 12](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689), Official Journal of the EU, 2024
- [EU AI Act Article 12 Analysis](../analysis/03_EU_AI_Act_and_Funding.md)

---

## 2. The Compliance Layer Architecture

The compliance layer is **not a separate product** — it is a facade and entry point into Liminara's core: the event log, the artifact store, and the decision records. The same data model, the same hash chain, the same provenance graph. Only the *source* of events changes: instead of the Liminara scheduler emitting events, external instrumented code emits them.

Three integration models, in order of coverage vs. integration effort:

```
Coverage ←————————————————————————————————————→ Less coverage
Effort   ←————————————————————————————————————→ Less effort

Event Bridge     OTel Bridge     SDK / Decorator
(Model C)        (Model B)       (Model A)
```

### Model A: SDK / Python Decorator (lowest friction)

The instrumented code decorates existing functions. The decorator handles hashing, event emission, and decision recording transparently. The existing orchestrator (Airflow, Temporal, LangChain, raw Python) continues to work unchanged — only the decorated functions gain compliance coverage.

**What gets captured:**
- Input hash (canonical serialization of function arguments)
- Output hash (canonical serialization of return value)
- Execution timestamp and wall-clock duration
- For `@liminara.llm_call`: model name, model version, prompt hash, full response, token usage
- For `@liminara.decision`: the recorded nondeterministic choice and its input hash

**What is NOT captured automatically:**
- Steps that are not decorated
- The shape of the overall pipeline (no automatic DAG reconstruction)
- Data that flows between steps outside the decorated boundary

**Best for:** Teams that want to add compliance to specific LLM calls and critical data transformations without touching their orchestration layer.

### Model B: OpenTelemetry Bridge (medium friction)

Most modern stacks already emit OpenTelemetry traces. Liminara runs as an OTel collector consumer. Existing systems add Liminara-specific custom attributes to their spans. Liminara reconstructs the provenance graph from the span stream.

**What gets captured:**
- Everything in Model A, but via OTel attributes rather than SDK calls
- Full pipeline structure if the orchestrator emits span parent/child relationships
- Timing, status, retry counts from standard OTel

**Custom attributes required (added by existing system):**
```
liminara.input_hash: "sha256:abc123..."
liminara.output_hash: "sha256:def456..."
liminara.determinism: "pure" | "recordable" | "side_effecting"
liminara.decision: "<serialized decision payload>"   # for recordable ops only
liminara.model_id: "claude-haiku-4-5-20251001"       # for LLM calls
```

**Best for:** Teams already on OTel who want compliance without additional SDK dependencies.

### Model C: Event Bridge (highest coverage, highest effort)

The existing system emits rich events to a message bus (Kafka, RabbitMQ, HTTP webhook). Events include artifact content or artifact hashes + content store URIs. Liminara consumes events, verifies hashes, builds the full provenance graph.

**What gets captured:**
- Complete DAG provenance
- All artifact content (if pushed) or references (if content store is shared)
- Full Article 12 compliance including tamper-evident artifact chain

**Best for:** Teams building new pipelines who want compliance from the start without using Liminara as the orchestrator; or teams that can invest in event enrichment as part of a compliance project.

---

## 3. The Python Decorator Interface (Model A in Detail)

Python decorators are the correct mechanism for Model A. They are:
- Non-invasive: existing function body is unchanged
- Composable: stack multiple decorators
- Idiomatic: LangChain, FastAPI, Celery all use decorators for similar cross-cutting concerns
- Testable: can be applied or removed independently of the function under test

### Core decorators

```python
import liminara

# Pure op: same inputs always produce same output. Cacheable.
@liminara.op(name="normalize_documents", determinism="pure")
def normalize_documents(raw_docs: list[bytes]) -> list[dict]:
    # existing code, completely unchanged
    return [parse_and_clean(doc) for doc in raw_docs]

# Recordable op: nondeterministic. Records the decision.
@liminara.op(name="summarize_cluster", determinism="recordable")
def summarize_cluster(docs: list[dict], prompt_template: str) -> str:
    # existing LLM call, completely unchanged
    response = anthropic.messages.create(
        model="claude-haiku-4-5-20251001",
        messages=[{"role": "user", "content": build_prompt(docs, prompt_template)}]
    )
    return response.content[0].text

# Side-effecting op: always runs, never cached.
@liminara.op(name="deliver_briefing", determinism="side_effecting")
def deliver_briefing(briefing: str, recipient: str) -> None:
    send_email(recipient, briefing)

# LLM-specific shorthand: captures model metadata automatically.
@liminara.llm_call(name="classify_document", model="claude-haiku-4-5-20251001")
def classify(document: str) -> str:
    # model name, prompt hash, response, token usage all captured automatically
    response = anthropic.messages.create(...)
    return response.content[0].text

# Pipeline scope: groups decorated ops into a named run.
@liminara.pipeline(pack="radar", schedule="6h")
def radar_pipeline(sources: list[str]) -> str:
    raw = fetch_all(sources)         # undecorated: not captured
    normalized = normalize_documents(raw)   # captured
    summary = summarize_cluster(normalized, PROMPT)  # captured + decision recorded
    deliver_briefing(summary, "team@company.com")    # captured
    return summary
```

### What the decorator does, step by step

```
@liminara.op(name="normalize_documents", determinism="pure")
def normalize_documents(raw_docs):
    ...

On call:
1. Serialize inputs to canonical bytes (sorted keys for dicts, stable encoding)
2. Compute input_hash = SHA-256(canonical_inputs)
3. Compute cache_key = SHA-256(op_name || op_version || input_hash)
4. Check Liminara cache: hit? → return cached output, emit node_completed(cached=true)
5. Emit node_started event (with input_hash, cache_key, timestamp)
6. Execute the original function
7. Serialize output to canonical bytes
8. Compute output_hash = SHA-256(canonical_outputs)
9. Store artifact: filesystem blob at /artifacts/{output_hash[:2]}/{output_hash}
10. Store cache entry: cache_key → output_hash
11. Emit node_completed event (with output_hash, duration_ms)
12. For recordable ops: emit decision_recorded event (with full decision payload)
13. Return original output (unchanged — decorator is transparent)
```

The calling code sees no difference. The output is identical. The compliance record is produced as a side effect.

### Handling the run context

For compliance, events from multiple function calls must be grouped into a run. The decorator uses a **context variable** (Python's `contextvars`) to propagate run context without requiring it to be passed explicitly:

```python
# Option 1: explicit pipeline decorator handles context
@liminara.pipeline(pack="radar")
def radar_pipeline(sources):
    normalized = normalize_documents(sources)  # automatically associated with this run
    ...

# Option 2: explicit context manager
with liminara.run(pack="radar", run_id="manual_run_001") as run:
    normalized = normalize_documents(sources)
    summary = summarize_cluster(normalized, PROMPT)
```

---

## 4. Hash Chain — Tamper-Evidence

This is what distinguishes the compliance layer from a standard observability tool (LangSmith, Langfuse, etc.).

Each event appended to the run's event log includes the hash of the previous event:

```
Event 1: run_started
  payload: {pack: "radar", run_id: "...", timestamp: ...}
  prev_hash: "0000...0000"   ← genesis (no previous)
  event_hash: SHA-256(prev_hash || event_type || payload)

Event 2: node_started (normalize_documents)
  payload: {node_id: "...", input_hash: "sha256:abc..."}
  prev_hash: <event 1's event_hash>
  event_hash: SHA-256(prev_hash || event_type || payload)

Event 3: node_completed (normalize_documents)
  payload: {output_hash: "sha256:def...", duration_ms: 142}
  prev_hash: <event 2's event_hash>
  event_hash: SHA-256(prev_hash || event_type || payload)

...

Event N: run_completed
  payload: {final_output_hash: "sha256:xyz..."}
  prev_hash: <event N-1's event_hash>
  event_hash: SHA-256(prev_hash || event_type || payload)   ← THE RUN SEAL
```

The **run seal** (event N's hash) is a single value that cryptographically commits to the entire run history. To produce a valid seal for a tampered log, an attacker would need to recompute every subsequent hash — detectable because the seal changes.

**Verification:** Given a run's event log and its declared seal, any verifier can recompute the chain in O(N) and confirm the seal matches. No trusted third party required.

**External anchoring (optional, for maximum compliance defensibility):** The run seal can be written to a public transparency log (Certificate Transparency-style) or even a blockchain timestamp service. This proves the seal existed at a specific point in time, before any audit was requested. Analogous to notarization.

Sources:
- [Certificate Transparency RFC 9162](https://www.rfc-editor.org/rfc/rfc9162) — the reference architecture for hash-chained public audit logs
- [01_adjacent_technologies.md — Hash Chains](../research/01_adjacent_technologies.md)

---

## 5. The Article 12 Compliance Report

Given a run ID, Liminara generates a structured compliance report. Format: JSON (machine-readable for auditors' tools) + PDF summary (human-readable for review).

```json
{
  "report_version": "1.0",
  "generated_at": "2026-03-14T10:30:00Z",
  "run_id": "radar_2026-03-14_06:00",
  "pack": "radar",
  "pack_version": "1.2.0",

  "article_12_compliance": {
    "automatic_logging": true,
    "tamper_resistant": true,
    "run_seal": "sha256:final_event_hash...",
    "seal_verified": true,
    "retention_policy": "365_days",
    "retention_until": "2027-03-14"
  },

  "provenance_chain": {
    "final_output": {
      "artifact_hash": "sha256:xyz...",
      "artifact_type": "radar.briefing.v1",
      "produced_by": "summarize_cluster"
    },
    "trace": [
      {
        "node": "normalize_documents",
        "determinism": "pure",
        "input_hashes": ["sha256:abc..."],
        "output_hash": "sha256:def...",
        "cached": false,
        "duration_ms": 142
      },
      {
        "node": "summarize_cluster",
        "determinism": "recordable",
        "input_hashes": ["sha256:def..."],
        "output_hash": "sha256:ghi...",
        "decision": {
          "model": "claude-haiku-4-5-20251001",
          "prompt_hash": "sha256:jkl...",
          "response_hash": "sha256:mno...",
          "input_tokens": 340,
          "output_tokens": 142,
          "timestamp": "2026-03-14T06:03:17Z"
        }
      }
    ]
  },

  "nondeterministic_steps": [
    {
      "node": "summarize_cluster",
      "model": "claude-haiku-4-5-20251001",
      "decision_recorded": true,
      "replay_possible": true
    }
  ],

  "event_log": {
    "event_count": 12,
    "first_event": "2026-03-14T06:00:00Z",
    "last_event": "2026-03-14T06:04:33Z",
    "chain_verified": true
  }
}
```

The report directly maps to Article 12 fields:
- `automatic_logging: true` → events were captured automatically, not manually
- `tamper_resistant: true` + `seal_verified: true` → hash chain verified
- `provenance_chain.trace` → full output-to-input traceability
- `nondeterministic_steps[].model` → model version recorded for every AI decision
- `retention_until` → 6-month minimum retention documented

---

## 6. Testing the Compliance Layer

### The testing philosophy

To validate Liminara as a compliance layer, we need:
1. A **non-compliant source** — a realistic existing pipeline that produces outputs with no provenance
2. **Instrumented version** — the same pipeline with Liminara decorators added
3. **Validation** — prove the instrumented version produces identical outputs AND correct compliance records

The test must answer three questions:
- **Completeness**: did Liminara capture everything it was supposed to?
- **Correctness**: do the recorded hashes match the actual data?
- **Tamper-evidence**: does the hash chain break when the log is modified?

### The non-compliant source fixture

A realistic but simple Python script, representative of what a customer would have. Uses LangChain or raw Anthropic SDK. No provenance, no hashing, no event log.

```python
# fixtures/non_compliant_pipeline.py
# A realistic "before Liminara" pipeline.
# This is the customer's existing code. We do not modify it.

import anthropic
import hashlib

client = anthropic.Anthropic()

def fetch_document(url: str) -> str:
    """Fetch a document. Side-effecting."""
    # In tests: return fixture content based on URL hash
    return FIXTURE_DOCUMENTS[url]

def normalize_document(raw: str) -> dict:
    """Clean and structure a document. Pure."""
    return {"text": raw.strip(), "word_count": len(raw.split())}

def summarize_documents(docs: list[dict], topic: str) -> str:
    """Summarize a list of documents using an LLM. Nondeterministic."""
    prompt = f"Summarize these documents about {topic}:\n" + \
             "\n".join(d["text"] for d in docs)
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text

def run_pipeline(urls: list[str], topic: str) -> str:
    """Full pipeline: fetch → normalize → summarize."""
    raw_docs = [fetch_document(url) for url in urls]
    normalized = [normalize_document(doc) for doc in raw_docs]
    summary = summarize_documents(normalized, topic)
    return summary

# Non-compliant: produces a result with zero provenance.
if __name__ == "__main__":
    result = run_pipeline(
        urls=["https://example.com/paper1", "https://example.com/paper2"],
        topic="transformer architectures"
    )
    print(result)
    # No audit trail. No way to reproduce. No Article 12 compliance.
```

### The instrumented version

Same logic, same functions, Liminara decorators added. Function bodies are **not modified**.

```python
# fixtures/instrumented_pipeline.py
# The same pipeline, instrumented for compliance.
# The only changes: import liminara, add decorators, wrap the top-level call.

import liminara
from non_compliant_pipeline import fetch_document, normalize_document, summarize_documents

# Wrap existing functions with compliance decorators.
# The function bodies are unchanged — only the decorator is added.

fetch_compliant = liminara.op(
    name="fetch_document",
    determinism="side_effecting"
)(fetch_document)

normalize_compliant = liminara.op(
    name="normalize_document",
    determinism="pure"
)(normalize_document)

summarize_compliant = liminara.op(
    name="summarize_documents",
    determinism="recordable"
)(summarize_documents)

def run_pipeline_compliant(urls: list[str], topic: str) -> str:
    with liminara.run(pack="demo", run_id=liminara.generate_run_id()) as run:
        raw_docs = [fetch_compliant(url) for url in urls]
        normalized = [normalize_compliant(doc) for doc in raw_docs]
        summary = summarize_compliant(normalized, topic)
        return summary
```

The key property: `run_pipeline_compliant` must produce **the same output** as `run_pipeline` for the same inputs. The compliance record is a side effect, not a behavioral change.

### The validation test suite

```python
# tests/test_compliance_layer.py

import pytest
import liminara
from fixtures.non_compliant_pipeline import run_pipeline
from fixtures.instrumented_pipeline import run_pipeline_compliant

URLS = ["https://example.com/paper1", "https://example.com/paper2"]
TOPIC = "transformer architectures"

class TestOutputEquivalence:
    """The instrumented pipeline must produce identical outputs."""

    def test_same_output_for_same_inputs(self, mock_llm):
        """With a mocked LLM (deterministic), outputs must match exactly."""
        mock_llm.set_response("This is the test summary.")

        baseline = run_pipeline(URLS, TOPIC)
        compliant = run_pipeline_compliant(URLS, TOPIC)

        assert baseline == compliant

    def test_decorator_is_transparent(self, mock_llm):
        """The decorator must not alter the function's return value."""
        mock_llm.set_response("Another summary.")
        result = run_pipeline_compliant(URLS, TOPIC)
        assert isinstance(result, str)
        assert len(result) > 0


class TestCompleteness:
    """Every instrumented step must appear in the compliance record."""

    def test_all_nodes_recorded(self, mock_llm, liminara_client):
        mock_llm.set_response("Summary.")
        run = run_pipeline_compliant(URLS, TOPIC)

        events = liminara_client.get_events(run.run_id)
        node_names = {e.payload["node_name"] for e in events
                      if e.type == "node_completed"}

        assert "fetch_document" in node_names
        assert "normalize_document" in node_names
        assert "summarize_documents" in node_names

    def test_all_events_present(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        event_types = {e.type for e in liminara_client.get_events(run.run_id)}

        assert "run_started" in event_types
        assert "node_started" in event_types
        assert "node_completed" in event_types
        assert "decision_recorded" in event_types   # from summarize_documents
        assert "run_completed" in event_types


class TestCorrectness:
    """Recorded hashes must match actual data."""

    def test_input_hash_matches_actual_inputs(self, mock_llm, liminara_client):
        """The recorded input_hash must equal SHA-256 of canonical inputs."""
        mock_llm.set_response("Summary.")
        run = run_pipeline_compliant(URLS, TOPIC)

        for event in liminara_client.get_events(run.run_id):
            if event.type == "node_started" and event.payload.get("input_hash"):
                recorded_hash = event.payload["input_hash"]
                actual_data = liminara_client.get_artifact(recorded_hash)
                recomputed = liminara.hash_canonical(actual_data)
                assert recomputed == recorded_hash, \
                    f"Input hash mismatch for {event.payload['node_name']}"

    def test_output_hash_matches_actual_output(self, mock_llm, liminara_client):
        """The recorded output_hash must equal SHA-256 of the actual return value."""
        mock_llm.set_response("Specific summary content.")
        run = run_pipeline_compliant(URLS, TOPIC)

        final_event = liminara_client.get_final_output_event(run.run_id)
        stored_artifact = liminara_client.get_artifact(final_event.payload["output_hash"])
        assert stored_artifact == "Specific summary content."

    def test_decision_record_captures_model_version(self, mock_llm, liminara_client):
        mock_llm.set_response("Summary.", model="claude-haiku-4-5-20251001")
        run = run_pipeline_compliant(URLS, TOPIC)

        decisions = liminara_client.get_decisions(run.run_id)
        assert len(decisions) == 1
        assert decisions[0].model == "claude-haiku-4-5-20251001"
        assert decisions[0].input_hash is not None
        assert decisions[0].response_hash is not None


class TestTamperEvidence:
    """Modifying any event must break hash chain verification."""

    def test_unmodified_chain_verifies(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        assert liminara_client.verify_chain(run.run_id) is True

    def test_modified_event_breaks_chain(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)

        # Tamper: change the output hash of the normalize step
        liminara_client._tamper_event(
            run_id=run.run_id,
            event_index=3,   # node_completed for normalize_document
            field="output_hash",
            new_value="sha256:0000000000000000"
        )

        assert liminara_client.verify_chain(run.run_id) is False

    def test_deleted_event_breaks_chain(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        liminara_client._delete_event(run.run_id, event_index=2)
        assert liminara_client.verify_chain(run.run_id) is False

    def test_reordered_events_break_chain(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        liminara_client._swap_events(run.run_id, index_a=2, index_b=4)
        assert liminara_client.verify_chain(run.run_id) is False


class TestArticle12Report:
    """The generated compliance report must cover all Article 12 fields."""

    def test_report_generated(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        report = liminara_client.generate_compliance_report(run.run_id)
        assert report is not None

    def test_report_covers_article_12_fields(self, mock_llm, liminara_client):
        run = run_pipeline_compliant(URLS, TOPIC)
        report = liminara_client.generate_compliance_report(run.run_id)

        assert report["article_12_compliance"]["automatic_logging"] is True
        assert report["article_12_compliance"]["tamper_resistant"] is True
        assert report["article_12_compliance"]["seal_verified"] is True
        assert report["provenance_chain"]["final_output"]["artifact_hash"] is not None
        assert len(report["provenance_chain"]["trace"]) > 0
        assert len(report["nondeterministic_steps"]) == 1
        assert report["nondeterministic_steps"][0]["model"] == "claude-haiku-4-5-20251001"
        assert report["article_12_compliance"]["retention_until"] is not None

    def test_provenance_trace_is_complete(self, mock_llm, liminara_client):
        """Every step in the pipeline must appear in the trace."""
        run = run_pipeline_compliant(URLS, TOPIC)
        report = liminara_client.generate_compliance_report(run.run_id)

        traced_nodes = {step["node"] for step in report["provenance_chain"]["trace"]}
        assert "normalize_document" in traced_nodes
        assert "summarize_documents" in traced_nodes


class TestCacheBehavior:
    """Pure ops must cache across runs with identical inputs."""

    def test_pure_op_caches_on_second_run(self, mock_llm, liminara_client):
        mock_llm.set_response("Summary.")

        run1 = run_pipeline_compliant(URLS, TOPIC)
        run2 = run_pipeline_compliant(URLS, TOPIC)

        # normalize_document should cache hit on second run
        run2_events = liminara_client.get_events(run2.run_id)
        normalize_events = [e for e in run2_events
                           if e.type == "node_completed"
                           and e.payload.get("node_name") == "normalize_document"]

        assert all(e.payload.get("cached") is True for e in normalize_events)

    def test_recordable_op_does_not_cache(self, mock_llm, liminara_client):
        mock_llm.set_response("Summary.")

        run1 = run_pipeline_compliant(URLS, TOPIC)
        run2 = run_pipeline_compliant(URLS, TOPIC)

        run2_events = liminara_client.get_events(run2.run_id)
        summarize_events = [e for e in run2_events
                           if e.type == "node_completed"
                           and e.payload.get("node_name") == "summarize_documents"]

        # Recordable ops must always execute — they are nondeterministic
        assert all(e.payload.get("cached") is False for e in summarize_events)
```

### What these tests prove

| Test class | What it validates | Article 12 field |
|---|---|---|
| `TestOutputEquivalence` | Compliance is non-invasive; existing behavior unchanged | — |
| `TestCompleteness` | All steps captured automatically | "Automatic recording" |
| `TestCorrectness` | Recorded hashes match actual data | "Trace outputs to inputs" |
| `TestTamperEvidence` | Log cannot be modified without detection | "Tamper-resistant" |
| `TestArticle12Report` | Report covers all required fields | All Article 12 fields |
| `TestCacheBehavior` | Pure ops cache; nondeterministic ops don't | "Identify nondeterminism" |

---

## 7. What the Compliance Layer Is Not

To be honest about scope:

- **Not a replacement for full Liminara orchestration.** The compliance layer records what happened; full Liminara controls what happens. Replay, caching across different inputs, and dynamic DAG construction require full Liminara.
- **Not zero code change.** Model A requires adding decorators. Model B requires adding OTel attributes. Model C requires adding event emitters. There is always some integration cost.
- **Not retroactive.** You cannot generate compliant records for runs that happened before instrumentation. Compliance starts from the first instrumented run.
- **Not a guarantee of LLM determinism.** The compliance layer records decisions; it does not make LLMs deterministic. Deterministic replay requires the decision record to be injected, which is full Liminara orchestration.

---

## 8. Relationship to the Full Runtime

The compliance layer is not a standalone product — it's a natural byproduct of Liminara's architecture. Anyone could build equivalent compliance-only tooling (decorators writing JSONL with hash chains) in a weekend.

Liminara's actual value is what the compliance layer *cannot* do alone:
- **Replay**: inject stored decisions, re-run downstream with different assumptions
- **Caching**: content-addressed memoization across runs
- **Orchestration**: the scheduler loop, DAG execution, supervision

Compliance is a selling point in pitches and funding applications ("our architecture happens to satisfy Article 12"), but it is not the reason someone would choose Liminara over building their own logging.

---

*See also:*
- *[03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md) — regulatory context and funding paths*
- *[10_Synthesis.md](10_Synthesis.md) — strategic decisions and positioning*
- *[01_adjacent_technologies.md](../research/01_adjacent_technologies.md) — Certificate Transparency as reference architecture*
