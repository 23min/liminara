# User Guide — AI-Assisted Development Framework v2

This guide explains how to use the framework for day-to-day development with any AI coding assistant.

---

## Table of Contents

1. [Concepts](#concepts)
2. [Workflow Overview](#workflow-overview)
3. [Working with Agents](#working-with-agents)
4. [The Planning Phase](#the-planning-phase)
5. [The Building Phase](#the-building-phase)
6. [The Review Phase](#the-review-phase)
7. [Releasing](#releasing)
8. [Platform-Specific Usage](#platform-specific-usage)
9. [Customization](#customization)
10. [FAQ](#faq)

---

## Concepts

### Artifacts Over Ceremonies

The framework is artifact-driven. Documents gate the work — not agent identities, not handoff protocols. If the right artifact exists in the right state, you can proceed.

| Artifact | Gates | Location |
|----------|-------|----------|
| Epic spec | Milestone planning | `work/epics/<slug>/spec.md` |
| Milestone spec (approved) | Implementation | `work/milestones/<id>.md` |
| Tracking doc (all ACs checked) | Review/wrap | `work/milestones/tracking/<id>-tracking.md` |
| Release summary | Deployment | `work/releases/<id>-release.md` |

### Four Agents, Not Nine

The framework defines four agent roles:

- **Planner** — thinks about what to build and why. Produces specs.
- **Builder** — implements code and tests. Follows TDD.
- **Reviewer** — validates quality and completeness. Closes milestones.
- **Deployer** — manages releases and infrastructure.

You don't always need to specify an agent. The AI will pick the right role based on your request. But you *can* be explicit: `@builder Start milestone m-cfdf-04`.

### Skills Are Checklists

Each skill is a short (~30-50 line) checklist the agent follows. Skills are not invoked directly — agents pick the right skill based on the task. You can read any skill to understand what the agent will do.

### TDD by Default

The builder always writes tests first:
1. Write a failing test (RED)
2. Write minimal code to pass (GREEN)
3. Clean up (REFACTOR)

This isn't optional — it's how the framework ensures quality.

---

## Workflow Overview

A typical feature goes through this lifecycle:

```
1. PLAN     — Define the epic and break it into milestones
2. SPEC     — Write detailed milestone specs with acceptance criteria
3. BUILD    — Implement each milestone (TDD, tracking docs)
4. REVIEW   — Validate code, close milestone
5. RELEASE  — Tag, changelog, deploy
```

You can start at any step. The framework adapts:

- **Starting fresh?** → Begin with planning
- **Have a spec already?** → Jump to building
- **Code is done?** → Go straight to review
- **Just need to deploy?** → Use the deployer

---

## Working with Agents

### How to Invoke

**GitHub Copilot (VS Code):**
```
@planner Plan a notification system for critical flow alerts
@builder Start milestone m-cfdf-04-ingest-logic
@reviewer Review my staged changes
@deployer Release v1.3.0
```

**Claude Code:**
```
Act as planner. Plan a notification system for critical flow alerts.
Act as builder. Start milestone m-cfdf-04-ingest-logic.
```
Or just describe the task — Claude will delegate based on the agent definitions.

**Any other AI tool:**
```
Read .ai/agents/builder.md and .ai/rules.md, then start milestone m-cfdf-04.
```

### Switching Between Agents

You can switch agents mid-session. Just address a different one:

```
@planner Write the spec for milestone M3.
(... spec is written ...)
@builder Now implement M3.
```

### What If I Don't Know Which Agent?

Just describe what you need. The AI will figure it out:

```
"I need to add a health check endpoint"
→ If there's a milestone spec: builder
→ If there's no spec yet: planner first, then builder
```

---

## The Planning Phase

### Creating an Epic

```
@planner I need to build a critical flow data pipeline that queries Azure Monitor,
evaluates SLA thresholds, and produces time series data.
```

The planner will:
1. Ask clarifying questions about scope
2. Write an epic spec at `work/epics/<slug>/spec.md`
3. Update `ROADMAP.md`
4. Suggest breaking it into milestones

### Breaking Into Milestones

```
@planner Break the critical-flow-data-foundation epic into milestones.
```

The planner will:
1. Read the epic spec
2. Propose 3-6 milestones with dependencies
3. Name them: `m-cfdf-01-query-schema`, `m-cfdf-02-fixture-export`, etc.
4. Ask for your approval on the sequence

### Writing Milestone Specs

```
@planner Write the spec for m-cfdf-04-ingest-logic.
```

The planner will:
1. Write clear acceptance criteria (testable, pass/fail)
2. Add technical notes and constraints
3. Save to `work/milestones/m-cfdf-04-ingest-logic.md`
4. Ask for your approval before marking as "approved"

**Tip:** Good acceptance criteria are specific. Not "handle errors properly" but "QueryService throws `InvalidOperationException` when workspace ID is null."

---

## The Building Phase

### Starting a Milestone

```
@builder Start milestone m-cfdf-04-ingest-logic.
```

The builder will:
1. Read the milestone spec
2. Check that build and tests pass (preflight)
3. Create/switch to branch `milestone/m-cfdf-04-ingest-logic`
4. Create a tracking doc
5. Plan implementation phases
6. Begin TDD implementation

### What TDD Looks Like

For each acceptance criterion:

```csharp
// 1. RED — Write failing test
[Fact]
public void Evaluate_P95BelowGoal_ReturnsGoalStatus()
{
    var result = _evaluator.Evaluate(50.0, _thresholds);
    Assert.Equal(SlaStatus.Goal, result);
}

// 2. GREEN — Write minimal code to pass
public SlaStatus Evaluate(double p95, SlaThresholds thresholds)
{
    if (thresholds.Goal is not null && p95 <= thresholds.Goal)
        return SlaStatus.Goal;
    // ...
}

// 3. REFACTOR — Clean up if needed
```

### Tracking Progress

The builder maintains a tracking doc at `work/milestones/tracking/<id>-tracking.md`:

```markdown
## Acceptance Criteria
- [x] AC1: SlaEvaluator returns correct status for all thresholds
- [x] AC2: QueryService executes KQL against correct workspaces
- [ ] AC3: Pipeline orchestrator merges results from both sources
```

### When the Builder Is Done

```
Implementation complete. 54 tests passing, build green.
All acceptance criteria met. Changes are staged (not committed).
Ready for review.
```

---

## The Review Phase

### Code Review

```
@reviewer Review the staged changes for milestone m-cfdf-04.
```

The reviewer will:
1. Read the milestone spec for acceptance criteria
2. Check every AC against the implementation
3. Review test quality and coverage
4. Check for regressions, security issues, convention violations
5. Produce a verdict: approve or request changes

### Wrapping a Milestone

```
@reviewer Wrap milestone m-cfdf-04.
```

The reviewer will:
1. Verify all ACs met
2. Run full test suite
3. Write a release summary at `work/releases/<id>-release.md`
4. Prepare the commit message
5. Ask for your approval to commit

---

## Releasing

```
@deployer Release v1.3.0 — Critical Flow Data Foundation
```

The deployer will:
1. Verify everything on main, tests pass
2. Update `CHANGELOG.md`
3. Create a git tag
4. Push the tag
5. Verify deployment

---

## Platform-Specific Usage

### GitHub Copilot (VS Code)

**Setup:** `bash .ai/setup.sh` generates `.github/agents/*.agent.md`

**Agents** appear in the `@` picker. Type `@planner`, `@builder`, etc.

**Skills** are available as reference files in `.github/skills/`.

**Instructions** are loaded from `.github/copilot-instructions.md` automatically.

**Tips:**
- Copilot's `runSubagent` can delegate to another agent mid-task
- Copilot reads agent files when you use `@agent_name`
- If Copilot doesn't pick up a skill automatically, say "Read `.ai/skills/tdd-cycle.md` and follow it"

### Claude Code

**Setup:** `bash .ai/setup.sh` generates `.claude/rules/` and `.claude/agents/`

**Agents** are auto-loaded by Claude based on `.claude/agents/` files.

**Rules** from `.claude/rules/ai-framework.md` are loaded on every session.

**Tips:**
- Claude auto-delegates to agents based on the task description
- Claude can read `.ai/` files directly — just reference the path
- For explicit agent mode: "Act as the builder agent defined in `.ai/agents/builder.md`"

### Codex (OpenAI)

**Setup:** `bash .ai/setup.sh` generates `.codex/instructions.md`

**Usage:** Codex reads `.codex/instructions.md` for context. Reference specific skill files in your prompt:

```
Read .ai/skills/start-milestone.md and .ai/agents/builder.md.
Start milestone m-cfdf-04-ingest-logic.
```

### Any Other AI Tool

The framework is just markdown files. Any AI that can read files can follow it:

```
Read these files for context:
- .ai/rules.md (guardrails)
- .ai/paths.md (artifact locations)
- .ai/agents/builder.md (your role)
- .ai/skills/start-milestone.md (what to do)

Now: start milestone m-cfdf-04-ingest-logic.
```

---

## Customization

### Adding a Project-Specific Skill

Create a file in `.ai/skills/`:

```markdown
# Skill: Deploy to Azure

Project-specific deployment workflow.

## Checklist

1. **Pre-deploy**
   - [ ] Verify on main branch
   - [ ] Push to azure remote: `git push azure main`

2. **Trigger pipeline**
   - [ ] Run `./scripts/run-pipeline.sh --pipeline-id 3186`
   - [ ] Poll for completion

3. **Verify**
   - [ ] Run health check: `./infrastructure/scripts/health-check.sh`
```

Then re-run `bash .ai/setup.sh` to update platform adapters.

### Adding a Custom Agent

Create a file in `.ai/agents/` following the same format as existing agents. Re-run setup.

### Changing Paths

Edit `.ai/paths.md` to change where artifacts are stored.

### Project-Specific Rules

Add project rules to the bottom of `.github/copilot-instructions.md` (after the auto-generated section) or to `.claude/rules/project.md`. These are preserved across setup runs if you keep them outside the auto-generated markers.

---

## FAQ

### Do I have to use all four agents?

No. Use whichever agent fits your task. For a quick bug fix, just use the builder. For a new feature, you might use planner → builder → reviewer.

### Can I skip the planning phase?

Yes. If you have a clear spec already, jump straight to `@builder Start milestone X`. The framework adapts to where you are.

### What if the AI doesn't follow the checklist?

Say: "Read `.ai/skills/<skill-name>.md` and follow the checklist step by step." Being explicit helps.

### How do I switch between Copilot and Claude?

Both read from the same `.ai/` source. Run `bash .ai/setup.sh` once and both platforms are configured. Your artifacts (specs, tracking docs, code) are the same regardless of which AI tool you use.

### What about Cursor / Windsurf / other editors?

The framework is editor-agnostic. Point your tool at `.ai/` and it works. You may need to create a platform adapter (similar to `.codex/instructions.md`) that tells the tool where to find the framework files.

### How do I update the framework?

```bash
# If using git subtree:
git subtree pull --prefix=.ai ai-framework v2 --squash

# If using git submodule:
cd .ai && git pull origin v2 && cd ..

# Then regenerate platform adapters:
bash .ai/setup.sh
```

### What happened to the sync script?

v1 had a complex sync script that copied files three ways. v2 replaces this with `setup.sh` which generates minimal pointer files. The source of truth is always `.ai/`. No more triple-copy maintenance.

### What happened to the 9 agents?

They've been consolidated:
- **planner** ← architect + planner + documenter (planning docs)
- **builder** ← implementer + tester (TDD combines both)
- **reviewer** ← tester (review mode) + documenter (wrap-up docs)
- **deployer** ← deployer (unchanged)
- **explorer** → just use search tools directly (not a real agent)
- **researcher** → just use web search directly (not a real agent)
- **maintainer** → covered by deployer + planner as needed

### What happened to the 17 skills?

Consolidated to 8 essential skills, each 30-50 lines instead of 100-300. The workflow is the same — just less ceremony.
