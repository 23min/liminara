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

## Running Tests from an AI Assistant (operational rules)

These rules exist to avoid wasted sessions waiting on tests that never report. They apply any time an AI assistant runs `mix test` (or another test runner) via a shell tool.

- **Never run the full umbrella `mix test`.** The Liminara umbrella has at least one pre-existing integration-test pathology (A2UI WebSocket / Python port) that causes the aggregate run to hang well past the 10-minute shell timeout, producing no output. Scope every invocation to a single app (`mix test apps/<app>/test`) or a specific file path.
- **Never use `run_in_background: true` for tests.** Background tasks only deliver completion notifications on the next turn boundary. An assistant that launches a background test and then says "waiting" ends its turn with nothing scheduled — no wake-up happens until the user types the next message. This looks exactly like a stuck session. Run tests in the foreground with an explicit `timeout` that matches the suite's expected wall time (e.g. 120000ms for a per-app suite).
- **Beware cross-suite test isolation flakes.** Some tests (e.g. `a2ui_provider_test`) pass in isolation but fail when run alongside other apps' suites in one `mix test` invocation. When validating, prefer per-app suites run separately rather than multi-path invocations. If per-app runs are green individually, treat the multi-path failure as a known flake rather than a regression.
- **If you must poll, use `Monitor` with a specific grep filter, not `sleep`/`run_in_background`.** Long leading `sleep` commands are blocked, and `run_in_background` does not notify mid-turn.
- **On timeout, pull the partial output and re-run with narrower scope.** Do not re-run the same hanging command with a longer timeout — diagnose what's hanging (typically a single slow file) and run the fast subset first.
