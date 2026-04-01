# Rules

Non-negotiable guardrails for every AI-assisted session.

## Commits — HARD GATE

> **🛑 NEVER run `git commit` or `git push` without explicit human approval.**
>
> This is the single most important rule in the entire framework.
> No agent, skill, or workflow may bypass it. No shortcut, no "obvious next step,"
> no "the user said continue" — NONE of these count as approval to commit or push.
>
> **What counts as approval:** The human explicitly says words like
> "commit", "go ahead and commit", "push it", "merge it", "yes, commit."
>
> **What does NOT count:** "continue", "ok", "looks good", "next step",
> "finish up", or any other general instruction.

### Required workflow before every commit:
1. Stage the changes (`git add`)
2. Show the user what will be committed (`git diff --staged --stat` or file list)
3. Propose the commit message
4. **STOP and wait for the human to say "commit"**
5. Only then run `git commit`
6. **STOP and wait for approval before `git push`**

### Commit format:
- Use Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`
- Add AI co-author trailer: `Co-authored-by: GitHub Copilot <noreply@github.com>`
  - This identifies the commit as AI-assisted — never use a human name here
- Keep subject line under 72 characters, imperative mood

## Code Quality

- Tests must be deterministic — no external network calls, no time-dependent assertions
- TDD by default: write failing test → make it pass → refactor
- Prefer minimal, precise edits over broad refactors
- Build and test must pass before any handoff or PR

## Security

- Never paste secrets, tokens, or credentials into prompts, docs, or logs
- No customer data or PII in examples — use sanitized fixtures
- New dependencies require human approval; flag packages < 1 year old or < 100 stars

## Devcontainer Safety

- **Never blindly kill all processes on port 8080** — the devcontainer port-forwarder listens there. Killing it destroys the session.
- To free port 8080, only kill `dotnet` processes: filter by process name before sending signals.
- Use the `kill-port-8080` VS Code task (runs automatically before `run` task) — it filters safely.
- Send SIGTERM first, wait, then SIGKILL only if the process is still alive. Never start with `kill -9`.

## Documentation

- Keep docs aligned when touching contracts or schemas
- Use Mermaid for diagrams (not ASCII art)
- Repository language: English

## Git

- No history-rewriting or destructive git operations unless explicitly instructed
- Check for dirty submodule pointers before committing

## Decisions, Gaps & Memory

- Architectural decisions → `work/decisions.md` (shared, structured entries with status)
- Discovered gaps → add to `work/gaps.md`, defer by default
- Agent learnings → `work/agent-history/<agent>.md` (per-agent, append-only)
- When history files exceed ~200 lines, summarize older entries and archive

## Session Provenance

> Before proposing a commit on main, write a provenance session log in `provenance/`.

- **File:** `provenance/YYYY-MM-DD-<slug>.md` (use the `session-log` template)
- **Narrative sections** (Summary, Work Done, Decisions, Problems, Key Files, Follow-up) — write from conversation context. This always works.
- **Metadata table** (session ID, tokens, duration, models, MCP servers) — extract from the JSONL session file if the workspace storage mount is available. If not, skip gracefully.
- **Extraction script:** `.ai/scripts/extract-session-metadata.mjs <path-to-jsonl>` can generate the metadata table for backfill or when the agent can't read the JSONL directly.
- One provenance file per session. Multi-day sessions use the start date.
- Only create provenance files for sessions that produce commits — don't log pure Q&A or research.

## Conflict Resolution

When instructions conflict, precedence is:
1. Explicit user directive in current session
2. Project-specific docs (ROADMAP.md, project config)
3. This rules file
4. Agent/skill defaults

When in doubt: ask the user.
