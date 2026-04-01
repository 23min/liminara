# Skill: Review Code

Review changes for correctness, quality, and completeness.

## When to Use

Code changes are ready for review. User says: "Review this", "Check my changes", "Review PR"

## Checklist

1. **Understand the scope**
   - [ ] What milestone or task do these changes address?
   - [ ] Read the milestone spec / acceptance criteria
   - [ ] Read the tracking doc for implementation notes

2. **Review the diff**
   - [ ] Check changed files (`git diff --staged` or PR diff)
   - [ ] Verify each change serves the stated goal
   - [ ] Flag unrelated changes

3. **Correctness**
   - [ ] Logic is correct for stated requirements
   - [ ] Edge cases are handled (null, empty, boundary)
   - [ ] Error handling is adequate
   - [ ] No off-by-one errors, race conditions, or resource leaks

4. **Tests**
   - [ ] Tests exist for each acceptance criterion
   - [ ] Tests are deterministic
   - [ ] Tests cover both happy path and edge cases
   - [ ] No tests were removed without justification

5. **Conventions**
   - [ ] Naming follows project conventions
   - [ ] File placement follows project structure
   - [ ] No hardcoded values that should be configurable
   - [ ] No secrets or PII

6. **Documentation**
   - [ ] README updated if public API changed
   - [ ] Inline comments for non-obvious logic
   - [ ] Tracking doc reflects implementation

7. **Verdict**
   - [ ] **Approve** — changes are correct and complete
   - [ ] **Request changes** — list specific issues with file/line references
   - [ ] **Questions** — need clarification before deciding

## Output

Review summary with:
- Verdict (approve / request changes)
- Specific findings (file, line, issue, suggestion)
- Overall assessment
