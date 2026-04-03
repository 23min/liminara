---
name: patch
description: "Patch/chore skill for one-off fixes, tweaks, or maintenance tasks not tracked as epics or milestones. Can be linked to a GitHub or Azure DevOps issue."
---
<!-- AUTO-GENERATED from source by sync.sh — do not edit manually -->

# Skill: Patch/Chore

This skill enables the workflow to:
- Handle one-off fixes, UI tweaks, or maintenance tasks
- Link work to a GitHub Issue or Azure DevOps task
- Keep the codebase healthy and responsive to small requests

## Workflow
1. Read and understand the linked issue/task (GitHub or DevOps)
2. Create a descriptive branch (fix/..., patch/..., chore/...)
3. Implement the change, run tests, stage files
4. 🛑 **STOP — show staged changes and proposed commit message. Wait for human to say "commit".**
5. Commit and push (only after explicit human approval)
6. Open a PR (prefer "Rebase and merge")
7. Reference the issue/task in PR and commit message
8. Merge and clean up the branch (only after human approval)
9. **Record learnings** — if this fix revealed a pattern, pitfall, or convention worth remembering:
   - Append to `work/decisions.md` if a decision was made (use the standard format)
   - Append to `work/agent-history/<agent>.md` with a brief note on what was learned

## Example Triggers
- "Fix login button alignment (see GitHub Issue #123)"
- "Patch: update copyright year"
- "Chore: remove unused config (DevOps Task #456)"

## Best Practices
- Keep the scope focused and the branch short-lived
- Always reference the issue/task for traceability
- Use clear, conventional branch names