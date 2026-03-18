# Example 02: LangChain RAG Pipeline

Ask questions about Liminara's documentation using retrieval-augmented generation. Documents are split into chunks, embedded locally with fastembed (no API key needed for embeddings), stored in a LanceDB vector index, and retrieved by similarity to answer your question via Claude Haiku. Every LLM call is automatically recorded as a Liminara run with a tamper-evident hash chain.

## Prerequisites

- Python 3.12+
- `ANTHROPIC_API_KEY` environment variable set
- Install with LangChain extras: `uv pip install -e ".[langchain]"`

## Usage

```bash
# Build the vector index (runs automatically on first question, or manually)
uv run python examples/02_langchain/setup_index.py

# Single question
uv run python examples/02_langchain/run.py "What does Article 12 require?"

# Interactive REPL
uv run python examples/02_langchain/run.py
```

## Expected output

```
Loaded index: 142 chunks
Type a question, or "quit" to exit.

? What does Article 12 of the EU AI Act require?

Article 12 requires providers of high-risk AI systems to implement
automatic logging capabilities...

[Run langchain-rag-a1b2c3d4 | 5 events | seal: sha256:9f3e2c1...]
```

## How Liminara instrumentation works

Adding Liminara to the pipeline is a one-line change — pass a `LiminaraCallbackHandler` in the LangChain config:

```python
from liminara.integrations.langchain import LiminaraCallbackHandler

handler = LiminaraCallbackHandler()

with run("langchain-rag", "1.0.0") as r:
    response = llm.invoke(messages, config={"callbacks": [handler]})
```

The handler automatically captures `op_started`, `decision_recorded`, and `op_completed` events for every LLM call. After the run, you can verify and inspect it:

```bash
liminara list                              # see all recorded runs
liminara verify <run_id>                   # check hash chain integrity
liminara report <run_id> --format human    # readable provenance report
```
