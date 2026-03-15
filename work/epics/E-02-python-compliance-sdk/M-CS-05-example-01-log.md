# M-CS-05-example-01 — Session Log

Append a new entry after each significant work session. Do not edit previous entries.

---

## 2026-03-15 — Session: Example 01 implementation

**Agents:** test-writer / implementer (single session, same as M-CS-04)
**Branch/worktree:** worktree-m-cs-02-hash-and-store

**Decisions made:**
- LLM call isolated in `llm.py` with lazy `import anthropic` (avoids ModuleNotFoundError in tests when anthropic not installed)
- Tests monkeypatch `llm.call_llm` with a fixed stub string — no API calls needed
- Integration tests marked with `@pytest.mark.integration`, excluded by default via addopts `-m 'not integration'`
- `--run-integration` CLI flag added to conftest.py for on-demand integration testing
- ty configured to exclude `examples/` and `tests/test_example_01*.py` (runtime sys.path imports unresolvable statically)
- `DOCUMENTS` list hardcoded (3 short strings), no file I/O
- `demo.py` imports after API key check to avoid import errors in the guard path

**Tried and abandoned:**
- Top-level `import anthropic` in `llm.py` — fails when anthropic not installed, even with mock patching (module-level import happens before patch)

**Outcome:**
- 165 tests pass (153 existing + 12 new), 3 integration tests deselected
- Full validation pipeline clean: ruff, ty, pytest at 98% coverage
- Example files: llm.py, pipeline_raw.py, pipeline_instrumented.py, demo.py, README.md

**Open / next session:**
- E-02 is complete (all 5 milestones done)
- Run demo.py with a real API key to verify end-to-end
- Next epic: E-03 LangChain Integration or E-04 Elixir Scaffolding
