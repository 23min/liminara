---
id: M-LC-02-rag-pipeline
epic: E-03-langchain-integration
status: draft
---

# M-LC-02: RAG Pipeline with Interactive REPL

## Goal

Build a working RAG (Retrieval-Augmented Generation) application that lets you ask questions about Liminara's documentation, instrumented with the Liminara callback handler. This is both the demo and an onboarding to LangChain concepts.

## Context: What this RAG pipeline does

1. **Load** three Liminara docs (Article 12 summary, Synthesis, CORE architecture)
2. **Split** them into chunks (~500 tokens each)
3. **Embed** each chunk using a local embedding model (sentence-transformers)
4. **Store** embeddings in ChromaDB (local, file-based vector database)
5. **On each question:** retrieve the most relevant chunks → build a prompt ("Given this context, answer this question") → send to Claude Haiku → return the answer
6. **Record** every LLM call as a Liminara run via the callback handler

## Acceptance criteria

### Index setup (`examples/02_langchain/setup_index.py`)

- [ ] Loads three markdown files from `docs/`:
  - `docs/analysis/08_Article_12_Summary.md`
  - `docs/analysis/10_Synthesis.md`
  - `docs/architecture/01_CORE.md`
- [ ] Splits documents using LangChain's `RecursiveCharacterTextSplitter` (chunk size ~500 chars, overlap ~50)
- [ ] Embeds chunks using `sentence-transformers` (model: `all-MiniLM-L6-v2` — small, fast, good enough)
- [ ] Stores in ChromaDB with persistence to `examples/02_langchain/.chroma/`
- [ ] Runnable standalone: `uv run python examples/02_langchain/setup_index.py`
- [ ] Idempotent: re-running rebuilds the index (deletes and recreates collection)

### Interactive REPL (`examples/02_langchain/run.py`)

- [ ] On startup: loads ChromaDB index (runs `setup_index.py` automatically if index doesn't exist)
- [ ] Prints: document count, chunk count, "Type a question, or 'quit' to exit."
- [ ] Single-question mode: `uv run python examples/02_langchain/run.py "What does Article 12 require?"`
- [ ] Interactive mode: `uv run python examples/02_langchain/run.py` → prompt loop
- [ ] Each question:
  - Creates a new Liminara run
  - Retrieves top 3-5 relevant chunks from ChromaDB
  - Builds prompt with retrieved context + question
  - Calls Claude Haiku via `langchain-anthropic`
  - Prints the answer
  - Prints run metadata: `[Run {run_id} | {n} events | seal: sha256:{first 8 chars}...]`
- [ ] On quit: prints summary ("N runs recorded. Run 'liminara list' to see them.")
- [ ] Uses `LiminaraCallbackHandler` — one line in the chain config

### RAG chain construction

- [ ] Uses LangChain's `ChatAnthropic` with `claude-haiku-4-5-20251001`
- [ ] Retriever: ChromaDB retriever with `k=4` (return 4 most relevant chunks)
- [ ] Prompt template: simple "Given the following context, answer the question" pattern
- [ ] Chain: retriever → prompt template → LLM → output parser (string)
- [ ] Uses LCEL (LangChain Expression Language) for chain composition: `retriever | prompt | llm | parser`

### README (`examples/02_langchain/README.md`)

- [ ] Explains what RAG is (2-3 sentences)
- [ ] Explains what LangChain is (2-3 sentences)
- [ ] How to run: prerequisites (ANTHROPIC_API_KEY), install, run
- [ ] Expected output: example questions and answers
- [ ] How to inspect runs: `liminara list`, `liminara report`, `liminara verify`
- [ ] Explains the one-line Liminara integration (where the callback handler is added)

## Out of scope

- Conversation memory (each question is independent)
- Reranking or hybrid search
- Multiple embedding models or cloud embeddings
- Web UI
- Production error handling (basic try/except is fine)

## Spec reference

- `docs/analysis/09_Compliance_Demo_Tool.md` § Example 02
- ChromaDB getting started: https://docs.trychroma.com/docs/overview/getting-started
- LangChain RAG tutorial: https://python.langchain.com/docs/tutorials/rag/
- sentence-transformers: https://www.sbert.net/docs/sentence_transformer/pretrained_models.html
