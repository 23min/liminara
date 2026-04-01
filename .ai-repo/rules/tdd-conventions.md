# TDD Conventions for Liminara

## Test Coverage Guide (RED phase)

For each acceptance criterion, consider these categories. Not every category applies — use judgment.

**Always write:**
- **Happy path** — the criterion works as specified with valid, typical inputs
- **Edge cases** — empty inputs, single items, boundary values
- **Error cases** — invalid inputs, missing files, corrupt data, wrong types

**Write when applicable:**
- **Round-trip** — write then read back, result is identical (artifacts, events, decisions)
- **Tamper detection** — modify stored data, verify integrity checks catch it (hash chain, decision hashes)
- **Format compliance** — on-disk output matches spec exactly (key ordering, encoding, hash format, JSONL)
- **Invariants** — properties that hold regardless of input (hash chain valid after any appends, idempotent writes never duplicate)
- **Isolation** — independent runs don't interfere (separate event logs, separate seals)

## Implementation Rules (GREEN phase)

- Write the **minimum code** to make tests pass. No features beyond what tests require.
- Do not modify test files unless they have a clear bug. If you must, explain why.
- Follow the existing code style. Read neighboring files before writing new code.
- Prefer simple, direct code over clever abstractions. Three similar lines > premature helper.
- Do not add docstrings, comments, or type annotations beyond what's needed for clarity.
- Keep dependencies minimal. Do not add packages without human approval.

## Code Review Format (REVIEW phase)

Produce a structured review:

```
## Summary
One paragraph: overall assessment (approve / request changes).

## Issues
- [severity: high/medium/low] Description. File:line.

## Suggestions
- Non-blocking improvements worth considering.

## Checklist
- [ ] All acceptance criteria covered
- [ ] Tests verify spec compliance
- [ ] Validation pipeline passes
- [ ] Commit message follows convention
- [ ] No unnecessary complexity
```

## Test Framework Conventions

- **Elixir**: ExUnit, `tmp_dir` for filesystem ops, `@tag` for test categories
- **Python**: pytest, `tmp_path` for filesystem ops, fixtures in `conftest.py`
- **JavaScript**: node:test or vitest, deterministic (no network, no time-dependent)
- Test names should read as specifications, not describe implementation
