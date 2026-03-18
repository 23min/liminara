# M-LC-02-rag-example — Session Log

Append a new entry after each significant work session. Do not edit previous entries.

---

## 2026-03-16 — Session: Implement RAG pipeline and integration tests

**Agents:** Claude Opus 4.6
**Branch/worktree:** e03-langchain-integration (../liminara-e03-langchain)

**Decisions made:**
- Used fastembed `all-MiniLM-L6-v2` for embeddings — CPU-only, ~23MB, no PyTorch dependency
- LanceDB as file-based vector store — same tooling Radar will use later
- `ask_question()` extracted as testable function accepting optional `llm` and `config` params for dependency injection
- Tests use `FakeListChatModel` from langchain-core to avoid API calls — validates the plumbing without real LLM
- Retrieval done manually via fastembed + LanceDB search (not via LangChain retriever abstraction) — simpler, more explicit
- `sys.path` manipulation in test file to import example scripts; excluded from ty check

**Outcome:**
- 13 new tests, all passing. 197 total tests pass (184 existing + 13 new).
- Full validation pipeline clean: ruff check, ruff format, ty check, pytest.
- setup_index.py, run.py (REPL + single-question), README all complete.

---

## 2026-03-18 — Session: Close out M-LC-02 and E-03

**Agents:** Claude Opus 4.6
**Branch/worktree:** e03-langchain-integration (../liminara-e03-langchain)

**Decisions made:**
- Added `test_rag_integration.py` to ty src exclude (imports example scripts via sys.path, not resolvable as modules)
- Wrote full README for example 02 covering RAG explanation, usage, expected output, and one-line integration
- Checked all acceptance criteria for M-LC-02, updated milestone/epic/roadmap status

**Outcome:**
- Both milestones done. Epic E-03 closed.
- Phase 1 (Python SDK / Data Model Validation) complete.
