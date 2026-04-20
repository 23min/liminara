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

### Subagent heartbeat pattern (mandatory for long-running TDD subagents)

Subagents dispatched via `Agent` run silently from the parent session's perspective — the parent only sees the agent's final report, which can be 10–30 minutes later. That looks identical to a stuck session from a human's perspective, and humans rightly cancel what looks stuck. To prevent that failure mode, every subagent that runs TDD / tests / any multi-phase implementation work must emit a heartbeat that the parent session monitors.

**Parent session obligations (before dispatching a TDD subagent):**

1. Create the progress-log directory: `mkdir -p work/agent-history/<milestone-id>/`
2. Choose a stable log path: `work/agent-history/<milestone-id>/<phase-or-task>-progress.log`
3. Start a `Monitor` on that log **before** spawning the subagent:
   ```
   tail -f work/agent-history/<milestone-id>/<phase>-progress.log \
     | grep --line-buffered -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   ```
4. Only then dispatch the subagent with `Agent`. The subagent brief must cite the exact log path and the marker format.
5. When the subagent returns, stop the Monitor (it exits on its own when the agent finishes writing, but keep a `TaskStop` handy if it lingers).

**Subagent brief obligations:**

- Brief must include the exact log path the subagent is expected to write to.
- Brief must instruct the subagent to append one ISO-8601-timestamped line per meaningful phase boundary:
  - RED test written
  - RED test confirmed failing (with the failure reason)
  - GREEN edit made (with file:line)
  - GREEN test passing
  - per-app suite run with result (`<suite> N/M`)
  - REVIEW step started/complete
  - commit-approval prompt reached
- Brief must include a "write a final marker even on error" instruction, so an agent that hits an exception still produces a last-line signal.
- Marker format: `YYYY-MM-DDTHH:MM:SSZ <phase|note>: <short message>` (the leading timestamp is the grep anchor).

**Why this is load-bearing:**

- Without heartbeats, the human sees a spinner and cancels a working agent.
- With heartbeats, each marker becomes a notification in the main chat. The human sees progress; the parent session can intervene if markers stop arriving for too long.
- This pattern scales to any long-running automation: code-review subagents, research subagents, remote agents.

**Sizing rule of thumb:** dispatch one subagent per bug / phase / focused change rather than one monolithic milestone-size agent. Smaller dispatches mean (a) a stuck one is detected earlier, (b) heartbeat cadence stays informative, (c) the parent session can course-correct between dispatches.
