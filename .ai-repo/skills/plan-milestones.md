# Skill: Plan Milestones

Break an epic into a sequenced set of milestones.

## When to Use

Epic spec exists. User says: "Break this into milestones", "Plan the work for epic X"

## Checklist

1. **Read the epic spec**
   - [ ] Read the epic spec from the repo's resolved artifact layout (`.ai-repo/config/artifact-layout.json`)
   - [ ] For Liminara, that means `work/epics/<epic>/epic.md`
   - [ ] Understand scope, constraints, success criteria

2. **Decompose into milestones**
   - [ ] Each milestone is independently shippable
   - [ ] Each milestone has clear, testable acceptance criteria
   - [ ] Dependencies flow forward (M1 before M2)
   - [ ] Target 1-3 days of work per milestone

3. **Sequence milestones**
   - [ ] Order by dependency (foundational first)
   - [ ] Group related work (don't scatter concerns)
   - [ ] Identify any milestones that can be parallelized

4. **Write milestone list**
   - [ ] Add milestone table to the epic spec or create a standalone plan if the repo uses one
   - [ ] For each milestone: ID, title, 1-line summary, key dependencies
   - [ ] Use the repo's resolved milestone ID pattern from `.ai-repo/config/artifact-layout.json`
   - [ ] For Liminara, milestone IDs use `M-<TRACK>-<NN>` and milestone spec filenames live at `work/epics/<epic>/<milestone-id>-<slug>.md`

5. **Confirm with user**
   - [ ] Review milestone sequence together
   - [ ] Agree on priority and order
   - [ ] Identify any scope adjustments

## Output

- Milestone plan (table in epic spec or separate doc)
- Milestone IDs ready for spec drafting

## Next Step

→ `draft-spec` for each milestone (start with M1)