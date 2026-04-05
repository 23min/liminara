# Reviewer Agent History

## M-TRUTH-03 Wrap (2026-04-05)

### Patterns that worked
- Treat the milestone tracking doc as the completion source of truth, then align the epic spec, roadmap, and `CLAUDE.md` before merging.
- If the last milestone in an epic is done, mark the epic complete on the roadmap and in the epic spec even when the next epic has not been started yet.

### Pitfalls
- A clean milestone branch and green focused tests do not mean the wrap is done; `CLAUDE.md`, the epic status table, and roadmap checkboxes can still be stale.
- Do not archive an epic folder to `work/done/` just because the final milestone merged into the epic branch; that move should happen when the epic itself is being closed out of active branch workflow.