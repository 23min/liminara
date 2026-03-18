---
id: M-LC-02-rag-example
epic: E-03-langchain-integration
status: done
---

# M-LC-02: RAG Example with End-to-End Validation

## Goal

Build a working RAG application that lets you ask questions about Liminara's documentation, instrumented with the callback handler from M-LC-01. Verify the full stack works end-to-end: LangChain → LiminaraCallbackHandler → event log → CLI → report.

This is both a learning exercise (first time working with embeddings, vector search, and LangChain chains) and the second demo example for the SDK.

## Context: What this RAG pipeline does

1. **Load** three Liminara docs (Article 12 summary, Synthesis, CORE architecture)
2. **Split** them into chunks (~500 chars each)
3. **Embed** each chunk using fastembed (onnxruntime, no PyTorch, ~100MB)
4. **Store** embeddings in LanceDB (file-based vector database, same store Radar will use)
5. **On each question:** retrieve the most relevant chunks → build a prompt → send to Claude Haiku → return the answer
6. **Record** every LLM call as a Liminara run via the callback handler

## Acceptance criteria

### Index setup (`examples/02_langchain/setup_index.py`)

- [x] Loads three markdown files from `docs/`:
  - `docs/analysis/08_Article_12_Summary.md`
  - `docs/analysis/10_Synthesis.md`
  - `docs/architecture/01_CORE.md`
- [x] Splits documents using LangChain's `RecursiveCharacterTextSplitter` (chunk size ~500 chars, overlap ~50)
- [x] Embeds chunks using fastembed (`all-MiniLM-L6-v2` model)
- [x] Stores in LanceDB at `examples/02_langchain/.lancedb/`
- [x] Runnable standalone: `uv run python examples/02_langchain/setup_index.py`
- [x] Idempotent: re-running rebuilds the index

### Interactive REPL (`examples/02_langchain/run.py`)

- [x] On startup: loads LanceDB index (runs `setup_index.py` automatically if index doesn't exist)
- [x] Prints: document count, chunk count, "Type a question, or 'quit' to exit."
- [x] Single-question mode: `uv run python examples/02_langchain/run.py "What does Article 12 require?"`
- [x] Interactive mode: `uv run python examples/02_langchain/run.py` → prompt loop
- [x] Each question:
  - Creates a new Liminara run
  - Retrieves top 4 relevant chunks from LanceDB
  - Builds prompt with retrieved context + question
  - Calls Claude Haiku via `langchain-anthropic`
  - Prints the answer
  - Prints run metadata: `[Run {run_id} | {n} events | seal: sha256:{first 8 chars}...]`
- [x] On quit: prints summary ("N runs recorded. Run 'liminara list' to see them.")
- [x] Uses `LiminaraCallbackHandler` — one line in the chain config

### RAG chain construction

- [x] Uses LangChain's `ChatAnthropic` with `claude-haiku-4-5-20251001`
- [x] Retriever: LanceDB retriever with `k=4` (return 4 most relevant chunks)
- [x] Prompt template: simple "Given the following context, answer the question" pattern
- [x] Chain: retriever → prompt template → LLM → output parser (string)

### End-to-end validation

- [x] `liminara list` shows runs from a REPL session
- [x] `liminara verify <run_id>` passes (exit code 0) for each run
- [x] `liminara report <run_id> --format json` produces valid JSON with all fields
- [x] `liminara report <run_id> --format human` produces readable output
- [x] Report shows: Claude Haiku model ID, token usage, hash chain status
- [x] Three sequential questions produce three independent, valid runs
- [x] Manual tampering of an event in JSONL causes `liminara verify` to fail

### README (`examples/02_langchain/README.md`)

- [x] Explains what RAG is (2-3 sentences)
- [x] How to run: prerequisites (ANTHROPIC_API_KEY), install, run
- [x] Expected output: example questions and answers
- [x] Explains the one-line Liminara integration (where the callback handler is added)

## Tests

- `test_rag_integration.py`:
  - Full pipeline run produces valid Liminara events
  - CLI commands work on LangChain-produced runs
  - Report includes LangChain-specific metadata (model ID, tokens)
  - Verify detects tampering in LangChain-produced runs

## Out of scope

- Conversation memory (each question is independent)
- Reranking or hybrid search
- Multiple embedding models
- Web UI
- Performance testing

## Spec reference

- `docs/analysis/09_Compliance_Demo_Tool.md` § Example 02
- LanceDB Python docs: https://lancedb.github.io/lancedb/
- fastembed: https://github.com/qdrant/fastembed
- LangChain RAG tutorial: https://python.langchain.com/docs/tutorials/rag/
