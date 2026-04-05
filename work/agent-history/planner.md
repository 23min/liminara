# Planner Agent History

## E-20 status sync and M-TRUTH-03 draft (2026-04-05)

### Patterns that worked
- When a milestone tracking doc says implementation complete, sync `work/roadmap.md`, the epic milestone table, milestone spec frontmatter, and `CLAUDE.md` Current Work together. Updating only one of those leaves the next handoff stale.
- Draft the next milestone from the completed tracking doc plus live architecture/contract docs, then verify the concrete pack issues in code before locking acceptance criteria.

### Pitfalls
- Repo memory and summary docs can lag the tracking doc; treat the tracking doc plus live code as the authoritative completion signal.
- Subagent findings are useful for locating drift, but they still need a direct code check before they become milestone scope.

## Deferred follow-on split (2026-04-05)

### Patterns that worked
- When a milestone is deferred behind a new platform prerequisite and the parent epic is otherwise complete, give the follow-on its own epic artifact and move the milestone spec there instead of leaving a `not started` milestone inside a closed epic.