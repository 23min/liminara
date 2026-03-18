---
id: E-03-langchain-integration
phase: 1
status: done
---

# E-03: LangChain Integration

## Goal

Prove that the Liminara Python SDK integrates with LangChain via a callback handler, and build a working RAG application as both a demo and a learning exercise. Introduces embeddings (fastembed), vector search (LanceDB), and LangChain's chain composition — all tools that transfer directly to the Radar pack later.

## Scope

**In:**

### LiminaraCallbackHandler (`liminara/integrations/langchain.py`)
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
- **Embedding:** fastembed (onnxruntime-based, lightweight, no PyTorch)
- **Vector store:** LanceDB (file-based, embeddable — same store Radar will use)
- **LLM:** Claude Haiku via `langchain-anthropic`
- **Interface:** Interactive REPL + single-question mode via CLI argument
- `run.py` — main entry point
- `setup_index.py` — separate script to rebuild the vector index

### Tests
- Callback handler unit tests (event types, decision records, hash chain)
- End-to-end integration test (RAG pipeline → events → CLI → report)

### Dependencies (additional to E-02)
- `langchain-core`, `langchain-anthropic`, `langchain-community`
- `fastembed` (onnxruntime-based embeddings, ~50-100MB, no PyTorch)
- `lancedb` (file-based vector database)

**Out:**
- MCP server interface
- Web UI (Streamlit/Gradio)
- Production RAG features (reranking, hybrid search, conversation memory)
- PyTorch / sentence-transformers

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-LC-01-callback-handler | LiminaraCallbackHandler implementing BaseCallbackHandler, with tests | done |
| M-LC-02-rag-example | RAG pipeline with LanceDB + fastembed + Claude Haiku, interactive REPL, end-to-end validation | done |

## Success criteria

- [x] `uv run python examples/02_langchain/run.py` launches interactive REPL
- [x] User can ask questions about Liminara docs and get relevant answers
- [x] Each question produces a Liminara run with valid hash chain
- [x] `liminara list` shows all runs from the session
- [x] `liminara report <run_id> --format human` shows LLM model, tokens, and provenance
- [x] Adding instrumentation to the RAG pipeline is a one-line change (adding the callback)
- [x] Works with only `ANTHROPIC_API_KEY` set (embeddings are local via fastembed)

## References

- Depends on: E-02 (Python SDK)
- Demo tool design: `docs/analysis/09_Compliance_Demo_Tool.md` § LangChain integration
- Compliance layer: `docs/analysis/07_Compliance_Layer.md` § Model A
- LangChain callbacks: https://python.langchain.com/docs/how_to/custom_callbacks/
- LanceDB: https://lancedb.github.io/lancedb/
- fastembed: https://github.com/qdrant/fastembed
