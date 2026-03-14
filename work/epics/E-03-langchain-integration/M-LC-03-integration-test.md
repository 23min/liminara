---
id: M-LC-03-integration-test
epic: E-03-langchain-integration
status: draft
---

# M-LC-03: End-to-End Integration Test

## Goal

Verify that the full stack works together: LangChain RAG pipeline → LiminaraCallbackHandler → event log → CLI → compliance report. This is the final validation that Phase 1 delivers what it promises.

## Acceptance criteria

### End-to-end flow

- [ ] Run the RAG pipeline with a known question
- [ ] `liminara list` shows the run
- [ ] `liminara verify <run_id>` passes (exit code 0)
- [ ] `liminara report <run_id> --format json` produces valid JSON with all fields
- [ ] `liminara report <run_id> --format human` produces readable output with all sections
- [ ] `liminara report <run_id> --format markdown` produces valid markdown
- [ ] Report shows: Claude Haiku model ID, token usage, hash chain status, Article 12 checklist

### Multiple runs

- [ ] Run three questions in the REPL, quit
- [ ] `liminara list` shows three runs, sorted newest first
- [ ] Each run has independent hash chains (different run_ids, different seals)
- [ ] `liminara verify` passes on all three

### Tamper detection across the full stack

- [ ] Run a question, note the run_id
- [ ] Manually modify one event in the JSONL file
- [ ] `liminara verify <run_id>` fails with clear error message
- [ ] `liminara report <run_id>` shows "Hash chain: ✗ BROKEN" in the Article 12 checklist

### Compliance report completeness

- [ ] Report for a LangChain run answers all six Article 12 questions:
  1. When? → timestamps present
  2. Input? → artifact hashes for retrieved chunks and prompt
  3. Model version? → "claude-haiku-4-5-20251001" (or whatever was used)
  4. Output? → artifact hash for the response
  5. Tamper-evident? → hash chain verification result
  6. Retrievable? → file paths on disk

### Documentation

- [ ] Both example READMEs are complete and accurate
- [ ] Running the examples with only the README instructions works (no undocumented steps)
- [ ] `integrations/python/README.md` has a quick-start section covering both examples

## Tests

- `test_integration.py`:
  - Full pipeline run produces valid Liminara events
  - CLI commands work on LangChain-produced runs
  - Report includes LangChain-specific metadata (model ID, tokens)
  - Verify detects tampering in LangChain-produced runs
  - Three sequential runs produce three independent, valid event logs

## Out of scope

- Performance testing
- Testing with models other than Claude Haiku
- Automated CI (no CI pipeline yet)

## Spec reference

- `docs/analysis/08_Article_12_Summary.md` § What Compliance Actually Looks Like
- `docs/analysis/09_Compliance_Demo_Tool.md` § Test suite
