---
id: E-03-langchain-integration
phase: 1
status: draft
---

# E-03: LangChain Integration

## Goal

A working LangChain RAG application instrumented with the Liminara Python SDK. Demonstrates that adding Liminara compliance to an existing LangChain application is a one-line change. Serves as onboarding to LangChain concepts and as a compelling demo for the compliance pitch.

## Context: What is LangChain?

LangChain is a Python framework for building applications that use LLMs. Instead of calling the Claude API directly, you use LangChain's abstractions: chains connect LLMs to prompt templates, retrievers, parsers, and tools. The value proposition is composability — swap models, add RAG, add memory, add tool use by composing pre-built components.

The canonical LangChain application is a **RAG (Retrieval-Augmented Generation) pipeline**: load documents → split into chunks → embed into a vector store → when a user asks a question, retrieve relevant chunks → stuff them into a prompt → ask the LLM → return the answer.

LangChain has ~28M downloads/month and provides a `BaseCallbackHandler` interface that fires events on LLM start/end, chain start/end, and errors. The `LiminaraCallbackHandler` hooks into this interface to record events and decisions automatically.

## Scope

**In:**

### LiminaraCallbackHandler (`integrations/python/liminara/integrations/langchain.py`)
- Implements `BaseCallbackHandler` from `langchain_core`
- Hooks:
  - `on_llm_start` → records `op_started` event with model ID and prompt hash
  - `on_llm_end` → records `decision_recorded` event with response, token usage; records `op_completed`
  - `on_chain_start` → records `op_started` for the chain
  - `on_chain_end` → records `op_completed` for the chain
  - `on_llm_error` / `on_chain_error` → records `op_failed` events
- One-line integration: `chain.invoke(query, config={"callbacks": [LiminaraCallbackHandler()]})`

### Example 02: RAG pipeline (`integrations/python/examples/02_langchain/`)
- **Corpus:** Three Liminara docs (08_Article_12_Summary.md, 10_Synthesis.md, 01_CORE.md)
- **Embedding:** Local sentence-transformers (no API key needed, runs on CPU)
- **Vector store:** ChromaDB (embedded, persists to disk, no server)
- **LLM:** Claude Haiku via `langchain-anthropic`
- **Interface:** Interactive REPL + single-question mode via CLI argument
- `run.py` — main entry point:
  - Loads and chunks documents on first run (persists ChromaDB index)
  - Subsequent runs reuse the index
  - Each question is a separate Liminara run
  - Prints answer + run metadata (run_id, event count, seal)
  - On exit: shows how many runs recorded, reminds about `liminara list`
- `setup_index.py` — separate script to rebuild the vector index if needed

### Tests (`integrations/python/tests/test_langchain.py`)
- Callback handler records correct event types for a LangChain chain invocation
- Decision records capture model ID, prompt hash, token usage
- Hash chain is valid across a RAG pipeline run
- `liminara report` works on a LangChain-instrumented run

### Dependencies (additional to E-02)
- `langchain-core`, `langchain-anthropic`, `langchain-community`
- `langchain-chroma` (ChromaDB integration)
- `sentence-transformers` (local embeddings)
- `chromadb`

**Out:**
- MCP server interface
- Web UI (Streamlit/Gradio)
- Production RAG features (reranking, hybrid search, conversation memory)
- Voyage AI or other cloud embedding providers

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-LC-01-callback-handler | LiminaraCallbackHandler implementing BaseCallbackHandler, with tests | draft |
| M-LC-02-rag-pipeline | RAG pipeline with ChromaDB + local embeddings + Claude Haiku, interactive REPL | draft |
| M-LC-03-integration-test | End-to-end: ask questions, verify runs recorded, verify compliance reports | draft |

## Success criteria

- [ ] `uv run python examples/02_langchain/run.py` launches interactive REPL
- [ ] User can ask questions about Liminara docs and get relevant answers
- [ ] Each question produces a Liminara run with valid hash chain
- [ ] `liminara list` shows all runs from the session
- [ ] `liminara report <run_id> --format human` shows LLM model, tokens, and Article 12 checklist
- [ ] Adding instrumentation to the RAG pipeline is a one-line change (adding the callback)
- [ ] Works with only `ANTHROPIC_API_KEY` set (embeddings are local)

## References

- Depends on: E-02 (Python Compliance SDK)
- Demo tool design: `docs/analysis/09_Compliance_Demo_Tool.md` § LangChain integration
- Compliance layer: `docs/analysis/07_Compliance_Layer.md` § Model A
- LangChain callbacks: https://python.langchain.com/docs/how_to/custom_callbacks/
- ChromaDB: https://docs.trychroma.com/
- sentence-transformers: https://www.sbert.net/
