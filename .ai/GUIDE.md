# AI-Assisted Development — User Guide

This document shows how to use the AI framework in this repo through practical, simulated conversations. It covers the two most common workflows — implementing a single feature (milestone) and planning a multi-milestone epic — and explains how to configure the framework for your needs.

> **Current limitation (2026-03-03):** GitHub Copilot does not automatically route between agents or invoke skills. You must explicitly select an agent (e.g. `@planner`, `@builder`, `@reviewer`) in the Copilot chat picker for each phase of work. Skills are read by agents when prompted, but you may need to nudge: *"Use the tdd-cycle skill"* or *"Follow the start-milestone checklist."*

> **Azure DevOps integration:** The AI assistant has access to Azure DevOps via MCP tools. It can read backlog items, create work items, link children to parents, add comments, and link PRs to work items — all from within the conversation.

> **Human in the loop:** The AI does the heavy lifting — planning, coding, testing, deploying — but **you are always in control**. The framework enforces explicit human approval before every commit, push, PR, and merge. Nothing irreversible happens without you saying so. See [Human Gates](#human-gates) for details.

---

## Table of Contents

1. [Scenario 1: Single Feature / Bug from Backlog](#scenario-1-single-feature--bug-from-backlog)
2. [Scenario 2: Epic with Multiple Milestones](#scenario-2-epic-with-multiple-milestones)
3. [Agent & Skill Quick Reference](#agent--skill-quick-reference)
4. [How the .ai Framework Works](#how-the-ai-framework-works)
5. [Appendix: Flow Charts](#appendix-flow-charts)

---

## Scenario 1: Single Feature / Bug from Backlog

A self-contained feature or bug fix that starts from the Azure DevOps backlog. Optionally, you can skip the backlog step and just describe the work directly.

### Simulated conversation

**Phase 0 — Read from backlog** *(optional, select `@builder` or `@planner`)*

> **You:** Look at Bug #4521 in the Infrastruktur project. What does it say?

The agent reads the DevOps work item, summarizes the description and acceptance criteria.

> **Agent:** Bug #4521: "Health-check endpoint returns 500 when database is unreachable." Repro steps: stop the DB, hit `/health`. Expected: 503 with status JSON. Actual: unhandled exception.

> **You:** Fix this. Use the patch skill.

**Phase 1 — Plan** *(select `@planner`)*

> **You:** Draft a milestone spec for fixing Bug #4521 — the health-check should return 503 with a JSON body when the DB is unreachable.

The planner uses the **draft-spec** skill: writes a spec with testable ACs, saves it.

> 📁 **`work/` change:** Creates `work/milestones/m-hc-01.md` (milestone spec with acceptance criteria)

> **Planner:** Spec written. 3 acceptance criteria. Approved?

> **You:** Approved.

**Phase 2 — Implement** *(select `@builder`)*

> **You:** Start milestone m-hc-01. Link it to Bug #4521.

The builder uses the **start-milestone** skill: reads the spec, creates branch and tracking doc, plans phases. Then uses **tdd-cycle** for each AC.

> 📁 **`work/` changes:**
> - Creates `work/milestones/tracking/m-hc-01-tracking.md` (tracking doc with AC checklist)
> - Updates tracking doc after each AC is completed (checks off boxes)

> **Builder:** Implementation complete. 4 tests passing, build green. Here are the staged changes: [diff summary]. Proposed commit message: `fix(api): return 503 on DB failure in health-check (m-hc-01)`. Shall I commit?

> **You:** Commit.

> **Builder:** Committed. Push to origin?

> **You:** Yes, push and create a PR. Link it to Bug #4521.

The builder pushes, creates a PR via `gh`, and links the PR to the DevOps work item.

**Phase 3 — Review** *(select `@reviewer`)*

> **You:** Review the PR for m-hc-01.

The reviewer uses the **review-code** skill, then **wrap-milestone**.

> 📁 **`work/` changes:**
> - Updates `work/milestones/tracking/m-hc-01-tracking.md` (final status)
> - Moves `work/milestones/m-hc-01.md` → `work/milestones/completed/m-hc-01.md`
> - Moves tracking doc alongside it

> **Reviewer:** Approved. All 3 ACs met. Ready to merge.

> **You:** Merge it. Rebase and merge.

The reviewer adds a comment to Bug #4521: "Fixed in PR #87, merged to main."

**Phase 4 — Deploy** *(select `@deployer`)*

> **You:** Deploy to Tau.

The deployer uses the **push-poll-fix** skill: pushes to the Azure remote, triggers the deploy pipeline, polls for results.

> **Deployer:** Pipeline succeeded. Health check passing on Tau. Bug #4521 resolved.

---

## Scenario 2: Epic with Multiple Milestones

A larger initiative broken into sequenced milestones — each independently shippable — tracked as a parent/child hierarchy in Azure DevOps.

### Simulated conversation

**Phase 1 — Plan the epic** *(select `@planner`)*

> **You:** I want to add critical flow reporting to the API. Users should be able to query critical flow data by system, filter by date range, and get summary statistics. Plan this as an epic. Create a Feature work item in Azure DevOps under the Infrastruktur project.

The planner uses the **plan-epic** skill: checks ROADMAP.md, clarifies scope, writes the epic spec. Then creates a Feature work item in DevOps.

> 📁 **`work/` changes:**
> - Creates `work/epics/critical-flow/spec.md` (epic spec)
> - Updates `ROADMAP.md` (adds epic with status `planning`)

> **Planner:** Epic spec written. Feature #4600 created in DevOps: "Critical Flow Reporting." Scope confirmed?

> **You:** Yes, approved. Break it into milestones.

The planner uses the **plan-milestones** skill: decomposes the epic, creates child Tasks in DevOps linked to the Feature.

> 📁 **`work/` change:** Updates `work/epics/critical-flow/spec.md` (adds milestone table)

> **Planner:**
> | ID | Title | DevOps Task |
> |----|-------|-------------|
> | m-cf-01 | Query schema | Task #4601 (child of Feature #4600) |
> | m-cf-02 | Query endpoint | Task #4602 (child of Feature #4600) |
> | m-cf-03 | Summary stats | Task #4603 (child of Feature #4600) |
>
> Each builds on the previous. Shall I draft the spec for M1?

> **You:** Yes, draft m-cf-01.

The planner uses the **draft-spec** skill for m-cf-01.

> 📁 **`work/` change:** Creates `work/milestones/m-cf-01.md` (milestone spec)

> **Planner:** Spec written to `work/milestones/m-cf-01.md`. 3 ACs, all testable. Please review.

> **You:** Approved.

**Phase 2 — Implement M1** *(select `@builder`)*

> **You:** Start milestone m-cf-01.

Builder uses **start-milestone** → **tdd-cycle** (repeated per AC).

> 📁 **`work/` changes:**
> - Creates `work/milestones/tracking/m-cf-01-tracking.md` (tracking doc)
> - Updates tracking doc as each AC is completed

> **Builder:** All 3 ACs done. 7 tests passing, build green. Staged changes ready. Commit message: `feat(pipeline): query schema and service interface (m-cf-01)`. Commit?

> **You:** Commit and push. Link the PR to Task #4601.

**Phase 3 — Review M1** *(select `@reviewer`)*

> **You:** Review and wrap m-cf-01.

Reviewer uses **review-code** → **wrap-milestone**: validates code, moves artifacts.

> 📁 **`work/` changes:**
> - Updates `work/milestones/tracking/m-cf-01-tracking.md` (final status, completion date)
> - Moves `work/milestones/m-cf-01.md` → `work/milestones/completed/m-cf-01.md`
> - Moves tracking doc alongside completed spec
> - Updates `work/epics/critical-flow/spec.md` (marks m-cf-01 as complete)

The reviewer updates Task #4601 state to "Done" in DevOps and adds a comment with the PR link.

> **Reviewer:** Approved and wrapped. PR ready for merge.

> **You:** Merge. Now draft spec for m-cf-02.

**Phase 4 — Repeat for M2, M3** *(select `@planner` → `@builder` → `@reviewer` for each)*

> **You:** *(to @planner)* Draft spec for m-cf-02.
>
> 📁 Creates `work/milestones/m-cf-02.md`
>
> *(approve)*
>
> *(to @builder)* Start milestone m-cf-02.
>
> 📁 Creates `work/milestones/tracking/m-cf-02-tracking.md`
>
> *(commit, push, link to Task #4602)*
>
> *(to @reviewer)* Review and wrap m-cf-02.
>
> 📁 Moves spec + tracking to `completed/`, updates epic spec
>
> *(merge, repeat for m-cf-03)*

**Phase 5 — Close the epic** *(select `@reviewer`)*

After the last milestone is merged:

> 📁 **`work/` changes:**
> - Moves `work/epics/critical-flow/` → `work/epics/completed/critical-flow/`
> - Updates `ROADMAP.md` (epic marked as complete with date)
> - Adds any deferred items to `work/gaps.md`

The reviewer updates Feature #4600 to "Done" in DevOps.

**Phase 6 — Deploy the epic** *(select `@deployer`)*

> **You:** All milestones merged. Deploy to Tau and tag a release.

Deployer uses **push-poll-fix** for deployment, then **release** for tagging.

> 📁 **`work/` change:** Creates `work/releases/critical-flow-release.md` (release summary)
> Also updates `CHANGELOG.md` and `ROADMAP.md` (epic marked as `released`).

> **Deployer:** Deployed to Tau. Tagged as v1.3.0. CHANGELOG.md updated. Health checks passing. Feature #4600 marked Done.

---

## Azure DevOps Integration Summary

The AI assistant can interact with Azure DevOps at each phase:

| Phase | DevOps action | Who |
|-------|--------------|-----|
| **Read backlog** | Fetch a Bug, Feature, or Task to understand requirements | Any agent |
| **Plan epic** | Create a Feature (or Epic) work item | @planner |
| **Plan milestones** | Create child Tasks under the Feature | @planner |
| **Implement** | Link commits/PRs to the work item | @builder |
| **Review/Wrap** | Update work item state to Done, add comments | @reviewer |
| **Deploy** | Add deployment notes to work items | @deployer |

Useful prompts:
- *"Read Bug #4521 in the Infrastruktur project"*
- *"Create a Feature in DevOps for this epic"*
- *"Create child Tasks for each milestone under Feature #4600"*
- *"Link this PR to Task #4601"*
- *"Mark Task #4601 as Done"*

---

## Human Gates

The AI framework is designed with **human-in-the-loop gates** at every critical juncture. The AI assistant will stop and wait for explicit approval before taking irreversible actions:

| Gate | When | What the AI does |
|------|------|-------------------|
| **Spec approval** | After drafting a spec | Presents the spec and waits for "Approved" |
| **Pre-commit** | After all tests pass and changes are staged | Shows the diff summary and proposed commit message, then **stops**. Does not commit until you say "commit". |
| **Pre-push** | After committing | Asks "Push to origin?" and waits. |
| **Pre-PR** | After pushing | Asks before creating a PR. |
| **Pre-merge** | After review approval | Asks which merge strategy and waits for confirmation. |
| **Pre-deploy** | Before triggering a pipeline | Confirms the target environment and waits. |

> **Your responsibility:** Before saying "commit" or "merge", **test the outcome yourself**. Run the application, verify the behavior manually, check edge cases the AI might have missed. The AI runs automated tests, but you are the final quality gate.

> **Recording gaps:** If you discover something incomplete or deferred during testing — a missing edge case, a follow-up task, a UI issue — tell the AI: *"Record this as a gap."* The AI will add it to `work/gaps.md` so it isn't lost. Gaps can later be pulled into a future milestone or addressed as patches.

---

## Roadmap

The `ROADMAP.md` file is the living backlog of planned and completed work. It grows organically through planning conversations with the AI assistant.

### How items get on the roadmap

A typical flow:

> **You:** *(to @planner)* I've been thinking about adding webhook support for critical flow alerts. What would that involve?

The planner uses the **architect** skill to brainstorm approaches, evaluate trade-offs, and document findings. At the end:

> **Planner:** Here's a summary of the approach. Want me to add this to the roadmap as a planned epic?

> **You:** Yes, add it to the roadmap but don't start it yet. Priority is lower than the current work.

The planner adds an entry to `ROADMAP.md` with status `planned` — it's now visible but not active.

### Roadmap lifecycle

| Status | Meaning |
|--------|---------|
| `planned` | Scoped and on the radar, not yet started |
| `planning` | Epic spec being drafted |
| `in-progress` | Milestones actively being implemented |
| `complete` | All milestones done and merged |
| `released` | Deployed and tagged |

### Prioritization

**You own the priority.** The AI assistant doesn't decide what to work on next — but it can help:

> **You:** I have these three epics planned. What order makes the most sense?

The planner will analyze dependencies, technical risk, and incremental value to suggest a sequence. It might say:

> **Planner:** I'd recommend: (1) Query schema first — it's foundational and other epics depend on it. (2) Webhook support — builds on the query layer. (3) Dashboard — can be done in parallel once the API surface is stable. But you should decide based on business priorities I can't see.

The final ordering is always your call. Update `ROADMAP.md` to reflect priority, and the AI will follow that order when you say *"What should I work on next?"*

---

## Agent & Skill Quick Reference

### Agents

| Agent | Select when… | Key skills |
|-------|-------------|------------|
| `@planner` | Planning, scoping, writing specs, brainstorming, research | plan-epic, plan-milestones, draft-spec, architect |
| `@builder` | Writing code, implementing features, fixing bugs | start-milestone, tdd-cycle, patch |
| `@reviewer` | Reviewing code, wrapping milestones, validating quality | review-code, wrap-milestone |
| `@deployer` | Deploying, releasing, pipeline troubleshooting | push-poll-fix, deploy-to-azure, release |

### Explicit agent selection

Since Copilot doesn't auto-route between agents, switch agents at each phase boundary:

1. **Planning phase** → select `@planner` in the chat picker
2. **Implementation phase** → select `@builder`
3. **Review phase** → select `@reviewer`
4. **Deployment phase** → select `@deployer`

You can also nudge skill usage explicitly:
- *"Use the tdd-cycle skill for this"*
- *"Follow the start-milestone checklist"*
- *"Read .ai/skills/plan-epic.md and follow it"*

---

## How the .ai Framework Works

### Architecture

The framework is a set of markdown files — agent definitions and skill checklists — that AI assistants read and follow. There is no code execution; it's pure prompting via structured documents.

```
.ai/                          ← shared framework (git submodule)
├── agents/                   ← agent role definitions (planner, builder, reviewer, deployer)
├── skills/                   ← skill checklists (plan-epic, tdd-cycle, etc.)
├── templates/                ← templates for specs and tracking docs
├── rules.md                  ← non-negotiable guardrails
├── paths.md                  ← where artifacts live
├── setup.sh                  ← one-time project initialization
├── sync.sh                   ← idempotent sync to .github/ (run after changes)
└── README.md                 ← full framework documentation

.ai-repo/                     ← project-specific overrides (repo-local, NOT in the submodule)
├── agents/                   ← override agent definitions (e.g., builder.agent.md)
├── skills/                   ← project-specific skills (e.g., deploy-to-azure.md)
├── rules/                    ← project-specific conventions
└── README.md

.github/                      ← generated platform files (Copilot reads from here)
├── agents/*.agent.md         ← Copilot agent definitions
├── skills/*/SKILL.md         ← Copilot skill references
├── rules/                    ← Copilot custom rules
└── copilot-instructions.md   ← Copilot global instructions
```

For the full framework documentation, see [.ai/README.md](.ai/README.md).

### Two layers: framework + overrides

- **`.ai/`** is a git submodule containing the shared framework. It defines the base agents, skills, and rules. You should not edit files here directly — changes go to the framework repo.
- **`.ai-repo/`** is repo-local. Files here **override** framework defaults. For example, `.ai-repo/agents/builder.agent.md` replaces the framework builder agent with a project-specific version that knows about the .NET stack, xUnit conventions, and dual remotes.

Override rules:
- An agent in `.ai-repo/agents/` with the same name replaces the framework agent
- A skill in `.ai-repo/skills/` with the same name replaces the framework skill
- New agents/skills in `.ai-repo/` are additive (they don't exist in the framework)

### Syncing to .github/

Copilot reads agents and skills from `.github/`, not from `.ai/` or `.ai-repo/`. The sync script merges both layers into `.github/`:

```bash
# After any change to .ai/ or .ai-repo/:
bash .ai/sync.sh
```

This is idempotent — safe to run repeatedly. It:
1. Generates `.github/agents/*.agent.md` wrappers from `.ai/agents/` (with frontmatter)
2. Copies `.ai/skills/*.md` → `.github/skills/<name>/SKILL.md`
3. Overlays `.ai-repo/agents/` (overrides framework agents)
4. Overlays `.ai-repo/skills/` (overrides or adds skills)
5. Copies `.ai-repo/rules/` → `.github/rules/`
6. Regenerates `copilot-instructions.md` from current inventory

### First-time setup vs ongoing sync

| Command | When to use |
|---------|-------------|
| `bash .ai/setup.sh` | First time, or to re-scaffold everything (`.github/`, `.claude/`, `.codex/`, `.ai-repo/` skeleton, `work/` dirs). Calls `sync.sh` internally. |
| `bash .ai/sync.sh` | After adding/editing agents, skills, or rules in `.ai/` or `.ai-repo/`. Only touches `.github/`. |

### Tuning for your project

To customize the AI behavior for this repo:

1. **Add a project-specific skill** — Create `.ai-repo/skills/my-skill.md` with a checklist, then run `bash .ai/sync.sh`.
2. **Override a framework agent** — Create `.ai-repo/agents/<name>.agent.md` (with Copilot frontmatter). This completely replaces the framework agent for Copilot. Run `bash .ai/sync.sh`.
3. **Add project rules** — Create `.ai-repo/rules/my-rule.md` for conventions the AI should follow (e.g., naming patterns, tech stack constraints). Run `bash .ai/sync.sh`.
4. **Change the model** — Edit the `model:` field in agent frontmatter (e.g., `model: claude-opus-4-6`).
5. **Add skill triggers** — In an agent override, add entries to the "Skill → Trigger Map" table to increase the chance the AI uses the right skill.

Full framework documentation: [.ai/README.md](.ai/README.md)

---

## Appendix: Flow Charts

### Scenario 1: Single Feature / Bug from Backlog

```
┌──────────────────────────────────────────────┐
│           AZURE DEVOPS BACKLOG               │
│  Bug #4521: "Health-check returns 500"       │
└──────────────────┬───────────────────────────┘
                   │  (read work item)
                   ▼
         ┌─────────────────┐
         │   @planner      │
         │   draft-spec    │──→ 📁 work/milestones/m-hc-01.md
         └────────┬────────┘
                  │ "Approved"
                  ▼
         ┌─────────────────┐
         │   @builder      │
         │ start-milestone │──→ 📁 work/milestones/tracking/m-hc-01-tracking.md
         │   tdd-cycle     │     (updated per AC)
         │                 │──→ Link PR to Bug #4521
         └────────┬────────┘
                  │ "Commit"
                  ▼
         ┌─────────────────┐
         │   @reviewer     │
         │  review-code    │──→ 📁 tracking doc updated (final status)
         │ wrap-milestone  │──→ 📁 spec + tracking → completed/
         │                 │──→ Bug #4521 → Done
         └────────┬────────┘
                  │ "Merge"
                  ▼
         ┌─────────────────┐
         │   @deployer     │
         │ push-poll-fix   │──→ Pipeline + health check
         └────────┬────────┘
                  │
                  ▼
            ✅ Deployed
```

### Scenario 2: Epic with Multiple Milestones

```
┌──────────────────────────────────────────────┐
│                USER REQUEST                  │
│  "Add critical flow reporting to the API"    │
└──────────────────┬───────────────────────────┘
                   │
                   ▼
         ┌──────────────────┐
         │    @planner      │
         │    plan-epic     │──→ 📁 work/epics/critical-flow/spec.md
         │                  │    📁 ROADMAP.md updated
         │                  │──→ DevOps: Feature #4600 created
         │ plan-milestones  │──→ 📁 epic spec updated (milestone table)
         │                  │──→ DevOps: Task #4601, #4602, #4603
         │                  │    (children of Feature #4600)
         └────────┬─────────┘
                  │
           ┌──────┴───────────────────────────────┐
           │  For each milestone (M1 → M2 → M3):  │
           └──────┬───────────────────────────────-┘
                  │
                  ▼
         ┌──────────────────┐
         │    @planner      │
         │    draft-spec    │──→ 📁 work/milestones/m-cf-NN.md
         └────────┬─────────┘
                  │ "Approved"
                  ▼
         ┌──────────────────┐
         │    @builder      │
         │  start-milestone │──→ 📁 work/milestones/tracking/m-cf-NN-tracking.md
         │    tdd-cycle     │     (updated per AC)
         │                  │──→ Link PR to Task #46NN
         └────────┬─────────┘
                  │ "Commit"
                  ▼
         ┌──────────────────┐
         │    @reviewer     │
         │   review-code    │──→ 📁 tracking doc (final status)
         │  wrap-milestone  │──→ 📁 spec + tracking → completed/
         │                  │    📁 epic spec updated (milestone → complete)
         │                  │──→ DevOps: Task #46NN → Done
         └────────┬─────────┘
                  │ "Merge"
                  ▼
            Loop back for next
            milestone, or…
                  │
                  ▼  (all milestones done)
         ┌──────────────────┐
         │    @reviewer     │
         │  (final wrap)    │──→ 📁 work/epics/critical-flow/ → completed/
         │                  │    📁 ROADMAP.md (epic → complete)
         │                  │    📁 work/gaps.md (deferred items)
         │                  │──→ DevOps: Feature #4600 → Done
         └────────┬─────────┘
                  │
                  ▼
         ┌──────────────────┐
         │    @deployer     │
         │  push-poll-fix   │──→ Deploy pipeline
         │     release      │──→ Tag + CHANGELOG.md
         │                  │    📁 work/releases/ (release summary)
         │                  │    📁 ROADMAP.md (epic → released)
         └────────┬─────────┘
                  │
                  ▼
        ✅ Epic deployed & released
```

### `work/` File Lifecycle Summary

```
work/
├── epics/
│   ├── critical-flow/
│   │   └── spec.md              ← created by plan-epic, updated by plan-milestones & wrap
│   └── completed/
│       └── critical-flow/       ← moved here when all milestones done
├── milestones/
│   ├── m-cf-01.md               ← created by draft-spec
│   ├── tracking/
│   │   └── m-cf-01-tracking.md  ← created by start-milestone, updated during tdd-cycle
│   └── completed/
│       ├── m-cf-01.md           ← moved here by wrap-milestone
│       └── m-cf-01-tracking.md  ← moved alongside spec
├── releases/
│   └── critical-flow-release.md ← created by release skill
└── gaps.md                      ← updated when deferred items found
```
