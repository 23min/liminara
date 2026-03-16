# Python SDK — Design and Rationale

**Date:** 2026-03-14 (updated 2026-03-16)
**Context:** Design of the Python SDK that validates Liminara's data model spec before the Elixir runtime exists. The compliance reporting it produces is a consequence of the architecture, not a standalone product.

---

## Why This Was Built First

The Python SDK was built before the Elixir runtime for two reasons:

**1. It forces the data model to be designed correctly.** The event format, artifact hash format, decision record schema, and hash chain algorithm must be defined once and shared between the Python SDK and the Elixir runtime. Building the Python SDK first forced these decisions early, when they were cheap to change.

**2. It produces a runnable demo artifact.** An investor or EIC evaluator can clone the repo, run `docker compose up`, and see Liminara's data model working against a real pipeline in under 5 minutes. This is a concrete artifact the full Elixir runtime cannot yet be.

**What this is not:** A product. The compliance layer (Article 12 reports, tamper-evidence, hash chains) is a natural consequence of Liminara's event sourcing + content-addressing + decision records. Anyone could build equivalent compliance-only tooling in a weekend. Liminara's value is reproducibility, replay, caching, and decision recording — compliance falls out for free.

---

## What the Demo Tool Proves

The demo must answer one question concisely: **"Can Liminara be integrated with an existing AI pipeline to provide Article 12 compliance without replacing that pipeline?"**

The answer is shown by running:

```bash
# Step 1: run the non-compliant pipeline — same as the customer has today
python examples/01_raw_python/pipeline.py

# Step 2: run the instrumented pipeline — same code, decorators added
python examples/01_raw_python/pipeline_compliant.py

# Step 3: compare outputs — they must be identical
# Step 4: view the compliance report
liminara-compliance report --run-id ./runs/latest

# Step 5: verify tamper-evidence
liminara-compliance verify --run-id ./runs/latest

# Step 6: attempt tampering — watch it fail
liminara-compliance tamper-test --run-id ./runs/latest
```

The demo proves: **same output + compliance record + tamper-detection.** That is the entire Article 12 story.

---

## Repository Structure

```
liminara/
├── CLAUDE.md
├── docs/
├── work/                             ← planning (future)
└── integrations/
    └── python/
        ├── README.md                 ← getting started, what this proves
        ├── pyproject.toml            ← installable as `liminara-compliance`
        ├── Dockerfile                ← run without setting up Python
        ├── docker-compose.yml        ← one command to run all examples
        │
        ├── liminara/                 ← the Python SDK
        │   ├── __init__.py
        │   ├── decorators.py         ← @liminara.op, @liminara.llm_call, @liminara.pipeline
        │   ├── hash.py               ← canonical serialization + SHA-256
        │   ├── event_log.py          ← append-only hash-chained event log (local files)
        │   ├── artifact_store.py     ← content-addressed blob storage (local filesystem)
        │   ├── decision_store.py     ← decision record storage
        │   └── report.py             ← Article 12 compliance report generator
        │
        ├── examples/
        │   ├── 01_raw_python/        ← Example 1: pure Python + Anthropic SDK
        │   │   ├── README.md
        │   │   ├── pipeline.py           ← non-compliant baseline
        │   │   └── pipeline_compliant.py ← instrumented version
        │   │
        │   └── 02_langchain/         ← Example 2: LangChain RAG pipeline
        │       ├── README.md
        │       ├── pipeline.py           ← non-compliant LangChain RAG pipeline
        │       ├── pipeline_compliant.py ← same pipeline + LiminaraCallbackHandler
        │       ├── langchain_handler.py  ← the integration (LiminaraCallbackHandler)
        │       └── documents/            ← fixture documents for the RAG demo
        │
        └── tests/
            ├── test_output_equivalence.py  ← instrumented = identical outputs
            ├── test_completeness.py        ← all steps captured
            ├── test_correctness.py         ← hashes match actual data
            ├── test_tamper_evidence.py     ← chain breaks when log is modified
            ├── test_article12_report.py    ← report covers all required fields
            └── test_cache_behavior.py      ← pure ops cache, recordable ops don't
```

---

## The Python SDK Design

### Local-file mode (no Elixir required)

The SDK writes to the local filesystem. No Elixir server, no database, no network calls. Everything is a file.

```
runs/
└── {run_id}/
    ├── events.log          ← append-only, one JSON line per event, hash-chained
    ├── manifest.json       ← run metadata: pack, start time, seal
    └── artifacts/
        ├── {hash[:2]}/
        │   └── {hash}      ← raw artifact bytes, addressed by SHA-256
        └── ...
decisions/
└── {run_id}/
    └── {node_id}.json      ← decision record: model, input_hash, response, tokens
```

This is Git's object store model applied to runs. Portable, inspectable with any text editor, no external dependencies.

**When the Elixir runtime exists:** the SDK gains a `--mode server` flag and sends events to the Liminara HTTP API instead of writing local files. The local-file format IS the protocol — the Elixir runtime reads the same file format the SDK writes. One data model, two implementations.

### The decorator interface

```python
import liminara

# Mark a function as a pure op (same inputs → same output, cacheable)
@liminara.op(name="normalize_document", determinism="pure")
def normalize_document(raw: str) -> dict:
    return {"text": raw.strip(), "word_count": len(raw.split())}

# Mark a function as a recordable op (nondeterministic, decision recorded)
@liminara.op(name="summarize", determinism="recordable")
def summarize(docs: list[dict], prompt: str) -> str:
    response = anthropic_client.messages.create(...)
    return response.content[0].text

# LLM-specific shorthand: captures model metadata automatically
@liminara.llm_call(name="classify", model="claude-haiku-4-5-20251001")
def classify(document: str) -> str:
    ...

# Group decorated ops into a named run
@liminara.pipeline(pack="demo")
def run_pipeline(inputs):
    ...
```

### Context propagation

Run context is threaded using Python's `contextvars` — no need to pass a `run` object to every function:

```python
# Option A: decorator handles context automatically
@liminara.pipeline(pack="demo")
def pipeline(inputs):
    result = normalize_document(inputs)   # automatically in this run's context
    return summarize([result], PROMPT)

# Option B: explicit context manager (for existing code you can't decorate)
with liminara.run(pack="demo") as run:
    result = normalize_document(inputs)   # automatically in this run's context
    summary = summarize([result], PROMPT)
    print(run.compliance_report())
```

---

## Example 1: Raw Python + Anthropic SDK

This is the universality demo. No framework. Works with any Python code.

**Non-compliant baseline** (`examples/01_raw_python/pipeline.py`):

```python
"""
A minimal AI pipeline. No compliance, no provenance, no audit trail.
This represents what most teams have today.
"""
import anthropic

client = anthropic.Anthropic()

DOCUMENTS = [
    "Recent advances in transformer architectures show that...",
    "A new study from MIT demonstrates that attention mechanisms...",
    "Industry adoption of large language models has accelerated...",
]

def normalize(doc: str) -> dict:
    """Clean and structure a document."""
    return {"text": doc.strip(), "word_count": len(doc.split())}

def summarize(docs: list[dict]) -> str:
    """Summarize documents using an LLM."""
    content = "\n\n".join(d["text"] for d in docs)
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=200,
        messages=[{"role": "user", "content": f"Summarize:\n{content}"}]
    )
    return response.content[0].text

def run():
    normalized = [normalize(doc) for doc in DOCUMENTS]
    summary = summarize(normalized)
    print(summary)
    # No provenance. No audit trail. Not Article 12 compliant.

if __name__ == "__main__":
    run()
```

**Instrumented version** (`examples/01_raw_python/pipeline_compliant.py`):

```python
"""
The same pipeline, instrumented for Article 12 compliance.
Two changes from the baseline:
  1. Import liminara and add decorators
  2. Wrap the top-level call in a pipeline context
The function bodies are completely unchanged.
"""
import liminara
import anthropic

client = anthropic.Anthropic()

DOCUMENTS = [
    "Recent advances in transformer architectures show that...",
    "A new study from MIT demonstrates that attention mechanisms...",
    "Industry adoption of large language models has accelerated...",
]

@liminara.op(name="normalize_document", determinism="pure")
def normalize(doc: str) -> dict:
    """Clean and structure a document. Body unchanged."""
    return {"text": doc.strip(), "word_count": len(doc.split())}

@liminara.op(name="summarize_documents", determinism="recordable")
def summarize(docs: list[dict]) -> str:
    """Summarize documents using an LLM. Body unchanged."""
    content = "\n\n".join(d["text"] for d in docs)
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=200,
        messages=[{"role": "user", "content": f"Summarize:\n{content}"}]
    )
    return response.content[0].text

@liminara.pipeline(pack="demo_raw_python")
def run():
    normalized = [normalize(doc) for doc in DOCUMENTS]
    summary = summarize(normalized)
    print(summary)
    # Same output. Now Article 12 compliant.

if __name__ == "__main__":
    result_run = run()
    print(f"\n✓ Run ID: {result_run.run_id}")
    print(f"✓ Events recorded: {result_run.event_count}")
    print(f"✓ Run seal: {result_run.seal}")
    print(f"✓ Chain verified: {result_run.chain_valid}")
    print(f"\nCompliance report: liminara-compliance report --run-id {result_run.run_id}")
```

---

## Example 2: LangChain RAG Pipeline

This is the named integration demo. LangChain is used by 1,300+ verified companies, 28M downloads/month. This shows that Liminara works with the industry's most widely deployed AI framework.

The integration mechanism: **LangChain's `BaseCallbackHandler`**. LangChain calls hooks on every LLM call, chain start/end, and tool use. The `LiminaraCallbackHandler` listens to these hooks and records decisions and artifacts. The LangChain pipeline code is **not modified**.

**The LangChain callback handler** (`examples/02_langchain/langchain_handler.py`):

```python
"""
LangChain integration for Liminara compliance.
Add `callbacks=[LiminaraCallbackHandler()]` to any LangChain chain.
No other changes required.
"""
from typing import Any
from langchain_core.callbacks import BaseCallbackHandler
import liminara


class LiminaraCallbackHandler(BaseCallbackHandler):
    """
    Intercepts LangChain events and records them as Liminara compliance data.
    Add to any chain: chain.invoke(input, config={"callbacks": [LiminaraCallbackHandler()]})
    """

    def on_llm_start(self, serialized: dict, prompts: list[str], **kwargs):
        """Called before each LLM call. Record the input."""
        self._current_input_hash = liminara.hash_canonical({
            "model": serialized.get("name"),
            "prompts": prompts,
        })
        liminara.emit_node_started(
            node_name=f"llm_{serialized.get('name', 'unknown')}",
            input_hash=self._current_input_hash,
        )

    def on_llm_end(self, response: Any, **kwargs):
        """Called after each LLM call. Record the decision."""
        output_text = response.generations[0][0].text
        liminara.record_decision(
            node_name=f"llm_{response.llm_output.get('model_name', 'unknown')}",
            input_hash=self._current_input_hash,
            model=response.llm_output.get("model_name"),
            response=output_text,
            token_usage=response.llm_output.get("token_usage", {}),
        )

    def on_chain_start(self, serialized: dict, inputs: dict, **kwargs):
        """Called when a chain starts. Record inputs as an artifact."""
        liminara.emit_node_started(
            node_name=serialized.get("name", "chain"),
            input_hash=liminara.store_artifact(inputs),
        )

    def on_chain_end(self, outputs: dict, **kwargs):
        """Called when a chain ends. Record outputs as an artifact."""
        liminara.emit_node_completed(
            output_hash=liminara.store_artifact(outputs),
        )

    def on_llm_error(self, error: Exception, **kwargs):
        liminara.emit_node_failed(error=str(error))

    def on_chain_error(self, error: Exception, **kwargs):
        liminara.emit_node_failed(error=str(error))
```

**Non-compliant LangChain pipeline** (`examples/02_langchain/pipeline.py`):

```python
"""
A standard LangChain RAG pipeline. No compliance.
Represents what a team using LangChain has today.
"""
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_community.document_loaders import TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter

llm = ChatAnthropic(model="claude-haiku-4-5-20251001")

def build_chain():
    prompt = ChatPromptTemplate.from_template(
        "Answer the question based on the context.\n\nContext: {context}\n\nQuestion: {question}"
    )
    return prompt | llm | StrOutputParser()

def run(question: str) -> str:
    # Load documents
    loader = TextLoader("documents/research_corpus.txt")
    docs = loader.load()
    splitter = RecursiveCharacterTextSplitter(chunk_size=500)
    chunks = splitter.split_documents(docs)
    context = "\n\n".join(c.page_content for c in chunks[:3])

    chain = build_chain()
    return chain.invoke({"context": context, "question": question})

if __name__ == "__main__":
    answer = run("What are the key trends in transformer architectures?")
    print(answer)
    # No provenance. Not Article 12 compliant.
```

**Instrumented version** (`examples/02_langchain/pipeline_compliant.py`):

```python
"""
The same LangChain pipeline, now Article 12 compliant.
One import added. One argument added to chain.invoke().
Nothing else changed.
"""
import liminara
from langchain_handler import LiminaraCallbackHandler
from pipeline import build_chain, load_context   # reuse the existing pipeline

def run_compliant(question: str) -> str:
    context = load_context()
    chain = build_chain()

    # The only change: add callbacks=[LiminaraCallbackHandler()]
    with liminara.run(pack="langchain_rag") as run:
        answer = chain.invoke(
            {"context": context, "question": question},
            config={"callbacks": [LiminaraCallbackHandler()]}  # ← one line added
        )
        return answer

if __name__ == "__main__":
    answer = run_compliant("What are the key trends in transformer architectures?")
    print(answer)
    # Identical output. Now Article 12 compliant.
```

---

## The CLI

A simple CLI for the demo. Runnable via `pip install liminara-compliance` or via Docker.

```bash
# List runs
liminara-compliance list

# View compliance report for a run
liminara-compliance report --run-id ./runs/abc123

# Verify the hash chain of a run (tamper-detection)
liminara-compliance verify --run-id ./runs/abc123
# → ✓ Chain verified. 12 events. Seal: sha256:f3a9...

# Run the tamper test (modifies log, verifies detection, restores)
liminara-compliance tamper-test --run-id ./runs/abc123
# → ✓ Tamper detected after modifying event 4. Chain invalid.
# → ✓ Restored to original state.

# Export Article 12 compliance report
liminara-compliance report --run-id ./runs/abc123 --format json > report.json
liminara-compliance report --run-id ./runs/abc123 --format pdf > report.pdf

# Diff two runs (compare decisions between runs)
liminara-compliance diff --run-a ./runs/abc123 --run-b ./runs/def456
```

---

## Docker: Run Without Setup

```dockerfile
# integrations/python/Dockerfile
FROM python:3.12-slim

WORKDIR /app
COPY pyproject.toml .
RUN pip install -e ".[examples]"

COPY . .

# Default: run the LangChain example and show the compliance report
CMD ["sh", "-c", "python examples/02_langchain/pipeline_compliant.py && liminara-compliance report --run-id ./runs/latest"]
```

```yaml
# integrations/python/docker-compose.yml
services:
  demo-raw-python:
    build: .
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    command: python examples/01_raw_python/pipeline_compliant.py

  demo-langchain:
    build: .
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    command: >
      sh -c "python examples/02_langchain/pipeline_compliant.py &&
             liminara-compliance report --run-id ./runs/latest"
```

Run everything: `ANTHROPIC_API_KEY=sk-... docker compose up`

---

## Relationship to the Elixir Runtime

The Python SDK is the first implementation of the Liminara data model — a reference implementation that the Elixir runtime must be compatible with. Its ongoing value is as a reference and integration layer, not as a standalone product.

**Shared data model (defined once, implemented twice):**

```
Event format:     JSON, one line per event, each with prev_hash and event_hash
Artifact format:  Raw bytes, stored at {store_path}/{hash[:2]}/{hash}
Decision format:  JSON, one file per decision, {run_id}/{node_id}.json
Hash algorithm:   SHA-256 of canonical bytes (sorted keys, deterministic encoding)
Run seal:         SHA-256 of the final event's event_hash field
```

When the Elixir runtime is built, it can:
- Read event logs written by the Python SDK (same format)
- Serve an HTTP API that the Python SDK can send to (server mode)
- Generate compliance reports from its own event log using the same algorithm

The Python SDK ships first. The Elixir runtime becomes the production backend. Same data model throughout.

---

## Development Sequence

```
Phase 1: Python SDK (standalone, no Elixir)
  1a. Define data model (event format, artifact format, hash algorithm)
  1b. Implement liminara/hash.py, event_log.py, artifact_store.py
  1c. Implement liminara/decorators.py (@liminara.op, @liminara.pipeline)
  1d. Implement liminara/report.py (Article 12 compliance report)
  1e. Write example 01 (raw Python + Anthropic SDK)
  1f. Write test suite (all 6 test classes)
  1g. Write example 02 (LangChain RAG + LiminaraCallbackHandler)
  1h. CLI + Dockerfile

Phase 2: Integration with Elixir runtime (after runtime exists)
  2a. Add HTTP API to Elixir runtime (POST /events, POST /artifacts)
  2b. Add --mode server to Python SDK
  2c. Python SDK sends to Elixir; Elixir stores and generates reports
  2d. Verify data model compatibility: Python-written logs readable by Elixir

Phase 3: Additional integrations (as needed for market)
  3a. Haystack callback handler (European market)
  3b. OpenTelemetry consumer (for OTel-native stacks)
```

---

## What This Enables

| Capability | Available after Phase 1 | Available after Phase 2 |
|---|---|---|
| Article 12 compliance for Python pipelines | ✓ | ✓ |
| LangChain integration | ✓ | ✓ |
| Tamper-evident hash-chained log | ✓ | ✓ |
| Compliance report generation | ✓ | ✓ |
| Demo runnable via Docker | ✓ | ✓ |
| Caching across runs (Elixir runtime) | — | ✓ |
| Full DAG provenance (Elixir runtime) | — | ✓ |
| Deterministic replay | — | ✓ |
| Observation UI | — | ✓ |

Phase 1 validates the data model and produces a demo artifact. The real product starts at Phase 2.

---

*See also:*
- *[08_Article_12_Summary.md](08_Article_12_Summary.md) — plain-language Article 12 explanation*
- *[07_Compliance_Layer.md](07_Compliance_Layer.md) — full compliance layer architecture and test suite*
- *[03_EU_AI_Act_and_Funding.md](03_EU_AI_Act_and_Funding.md) — funding paths and EIC strategy*
- *[10_Synthesis.md](10_Synthesis.md) — where this fits in the overall development sequence*
