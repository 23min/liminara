# Skill: Plan Epic

Scope, refine, and document a new epic.

## When to Use

User says: "Plan feature X", "Design the system for Y", "I need to build Z"

## Checklist

1. **Understand the request**
   - [ ] What problem does this solve?
   - [ ] Who benefits?
   - [ ] What are the boundaries (in-scope / out-of-scope)?

2. **Check existing context**
   - [ ] Read `ROADMAP.md` for current epics and priorities
   - [ ] Read `work/epics/` for related or overlapping epics
   - [ ] Check `work/gaps.md` for previously deferred work that fits

3. **Clarify with user** (ask, don't guess)
   - [ ] Confirm scope boundaries
   - [ ] Identify key constraints (tech stack, timeline, dependencies)
   - [ ] Agree on success criteria

4. **Assign epic ID**
   - [ ] Check `work/epics/epic-roadmap.md` for the highest existing E-xx number
   - [ ] Assign next sequential number (e.g., if E-14 exists, use E-15)
   - [ ] Epic numbering started at E-10; completed epics before E-10 are unnumbered

5. **Write epic spec**
   - [ ] Create `work/epics/E-{NN}-<epic-slug>/spec.md` using epic template
   - [ ] Set `**ID:** E-{NN}` in the spec header
   - [ ] Fill in: goal, context, scope, constraints, success criteria
   - [ ] List known risks and open questions

6. **Create ADO work item** (see `.ai-repo/rules/ado-traceability.md`)
   - [ ] Create an ADO Task for the epic with a Description linking to the spec
   - [ ] Use ADO repo URL format: `https://dev.azure.com/sdctfs/Infrastruktur/_git/Treehouse?path=/work/epics/E-{NN}-<epic-slug>/spec.md&version=GBmain`
   - [ ] Set parent to the appropriate Enabler Story (if applicable)
   - [ ] Record the ADO ID in the spec: `**ADO:** [#NNNNN](...)`

7. **Update roadmap**
   - [ ] Add epic to `ROADMAP.md` with E-xx prefix and status `planning`
   - [ ] Add to `work/epics/epic-roadmap.md` with folder path and E-xx ID

## Output

- `work/epics/E-{NN}-<epic-slug>/spec.md` — the epic specification (with ID and ADO ID)
- ADO work item created and linked
- Updated `ROADMAP.md` and `epic-roadmap.md`

## Next Step

→ `plan-milestones` to break the epic into sequenced milestones
