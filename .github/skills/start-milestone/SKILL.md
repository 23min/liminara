# Skill: Start Milestone

Set up and begin implementing a milestone.

## When to Use

Approved milestone spec exists. User says: "Start milestone X", "Implement M1"

## Checklist

1. **Preflight**
   - [ ] Read milestone spec from `work/milestones/<milestone-id>.md`
   - [ ] Verify spec is approved (user confirmed)
   - [ ] Check build passes (`dotnet build` / `npm run build` / etc.)
   - [ ] Check existing tests pass
   - [ ] Read prior milestone code if building on previous work

2. **Update ADO work item** (see `.ai-repo/rules/ado-traceability.md`)
   - [ ] Set the milestone's ADO work item State to `Active`
   - [ ] Update the spec status to `in-progress`

3. **Branch setup**
   - [ ] If milestone belongs to an epic: ensure epic integration branch exists (`epic/E-{NN}-<epic-slug>`), create from `main` if missing, push to origin
   - [ ] Create or switch to milestone branch: `milestone/<milestone-id>` (branch from epic branch if applicable, otherwise from `main`)
   - [ ] Verify milestone branch is up to date with its base

4. **Create tracking doc**
   - [ ] Create `work/milestones/tracking/<milestone-id>-tracking.md` using template
   - [ ] List all acceptance criteria as unchecked boxes
   - [ ] Note start date and initial context

5. **Update CLAUDE.md current work section**
   - [ ] Update the `## Current Work` section in `CLAUDE.md` with:
     - Active epic name and spec path
     - Current milestone ID, title, and status
     - Current branch name
   - [ ] If the section doesn't exist, add it at the end of the file

6. **Plan implementation phases**
   - [ ] Group ACs into logical phases (1-4 phases typical)
   - [ ] Identify test strategy for each phase
   - [ ] Note implementation order

7. **Begin implementation** using `tdd-cycle`
   - [ ] Start with Phase 1
   - [ ] For each AC: write tests → implement → verify
   - [ ] Update tracking doc after each AC is complete

8. **Completion check**
   - [ ] All ACs checked in tracking doc
   - [ ] All tests passing
   - [ ] Build green
   - [ ] Stage changes (`git add`)
   - [ ] Show staged diff summary to user
   - [ ] Report: "Implementation complete. N tests passing, build green. Here are the staged changes:"
   - [ ] 🛑 **STOP — Do NOT commit. Wait for human to say "commit".**
   - [ ] **Record learnings** — append to `work/agent-history/builder.md`:
     - Patterns that worked (testing approaches, code organization)
     - Pitfalls encountered (build issues, test flakiness, API quirks)
     - Conventions established (naming, structure decisions)
   - [ ] If any decisions were made during implementation, append to `work/decisions.md`

9. **Commit and merge** (ONLY after human explicitly says "commit")
   - [ ] 🛑 Verify human said "commit" / "push" / "go ahead and commit" — not just "continue" or "ok"
   - [ ] Commit on milestone branch with descriptive message
   - [ ] 🛑 **STOP — ask before pushing.** "Push to origin?"
   - [ ] Push milestone branch
   - [ ] 🛑 **STOP — ask before merging.** "Merge into epic branch?"
   - [ ] If epic branch exists: merge milestone branch into epic branch (`--no-ff`), push epic branch
   - [ ] If standalone: milestone branch is ready for PR to `main`

## Output

- Implemented code + tests (staged, not committed)
- Tracking doc with all ACs checked
- Updated README/docs if applicable

## Next Step

→ `review-code` for code review, then `wrap-milestone`
