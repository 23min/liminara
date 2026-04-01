# Migration Guide: v1 → v2

This guide helps you migrate from the v1 AI-Assisted Development Framework to v2.

---

## What Changed and Why

### Problem: v1 Was Too Complex

v1 had 9 agents, 17+ skills (100-300 lines each), a sync script that copied files three ways, and a rigid handoff chain. This created friction:

- Skills were essays, not actionable checklists
- Too many agents created artificial boundaries
- The sync script (`sync-all.sh`) produced triple copies with 17 "overwritten" warnings
- Handoff ceremonies felt like bureaucracy, not productivity

### Solution: v2 Is Minimal

| Aspect | v1 | v2 |
|--------|----|----|
| Agents | 9 | 4 |
| Skills | 17+ (100-300 lines) | 8 (30-50 lines) |
| Source files | ~60 files across 3 directories | ~20 files in `.ai/` |
| Sync mechanism | Complex `sync-all.sh` script | Simple `setup.sh` (generates pointers) |
| Platform support | Copilot + Claude (fragile sync) | Copilot + Claude + Codex + any tool |
| Instructions file | ~200 lines of embedded rules | Pointer: "read `.ai/rules.md`" |

---

## Agent Mapping

| v1 Agent | v2 Agent | Notes |
|----------|----------|-------|
| architect | **planner** | Architecture decisions are planning |
| planner | **planner** | Unchanged |
| documenter | **planner** / **reviewer** | Planning docs → planner; wrap-up docs → reviewer |
| implementer | **builder** | Renamed, TDD built-in |
| tester | **builder** / **reviewer** | TDD (writing tests) → builder; review → reviewer |
| explorer | *(removed)* | Use search tools directly |
| researcher | *(removed)* | Use web search directly |
| maintainer | **deployer** | Infrastructure maintenance → deployer |
| deployer | **deployer** | Unchanged |

---

## Skill Mapping

| v1 Skill | v2 Skill | Notes |
|----------|----------|-------|
| epic-refine | **plan-epic** | Simplified and merged |
| epic-start | **plan-epic** | Merged into plan-epic |
| milestone-plan | **plan-milestones** | Renamed |
| milestone-draft | **draft-spec** | Renamed |
| milestone-start | **start-milestone** | Renamed |
| red-green-refactor | **tdd-cycle** | Renamed, simplified |
| code-review | **review-code** | Renamed |
| milestone-wrap | **wrap-milestone** | Renamed |
| epic-wrap | **wrap-milestone** | Merged (wrap last milestone = wrap epic) |
| release | **release** | Unchanged |
| session-start | *(removed)* | Just start working |
| context-refresh | *(removed)* | Read rules.md and paths.md |
| gap-triage | *(removed)* | Add to gaps.md directly |
| framework-review | *(removed)* | Ad-hoc task |
| post-mortem | *(removed)* | Ad-hoc task |
| roadmap | **plan-epic** | Merged |
| branching | **start-milestone** | Integrated into start-milestone |

---

## File Structure Changes

### v1 Structure (remove these)

```
.ai/
├── agents/           ← 9 agent files
├── skills/           ← 17+ skill files, each 100-300 lines
│   └── inactive/     ← deprecated skills
├── instructions/
│   └── ALWAYS_DO.md  ← 200+ lines of rules
├── docs/             ← framework docs
├── config/           ← model assignments, sync config
├── scripts/          ← sync-all.sh, init-project.sh
└── templates/        ← project templates

.github/
├── copilot-instructions.md  ← giant generated file
├── agents/                  ← copies of .ai/agents
└── skills/                  ← copies of .ai/skills

.claude/
├── rules/                   ← copies of instructions
└── agents/                  ← copies of .ai/agents
```

### v2 Structure (keep these)

```
.ai/
├── README.md          ← framework overview
├── rules.md           ← guardrails (~50 lines)
├── paths.md           ← path configuration
├── setup.sh           ← generates platform pointers
├── agents/            ← 4 agent files (~40 lines each)
├── skills/            ← 8 skill files (~40 lines each)
├── templates/         ← 3 templates
└── docs/
    ├── guide.md       ← comprehensive user guide
    └── migration-v1.md ← this file

.github/               ← auto-generated pointers (not copies)
.claude/               ← auto-generated pointers (not copies)
.codex/                ← auto-generated pointers (not copies)
```

---

## Migration Steps

### 1. Install v2 (alongside v1)

v2 lives in `.ai/` so it doesn't conflict with v1 files. You can run both side by side.

```bash
# If v2 is on a branch of your .ai submodule:
cd .ai && git checkout v2 && cd ..

# If v2 is a new subtree:
git subtree add --prefix=.ai ai-framework v2 --squash
```

### 2. Run setup

```bash
bash .ai/setup.sh
```

This generates new platform adapter files. Your existing `.github/copilot-instructions.md` will be overwritten with a pointer version.

### 3. Verify

- Open VS Code → type `@planner` → should see the agent
- Read `.github/agents/planner.agent.md` → should point to `.ai/agents/planner.md`
- Read `.claude/rules/ai-framework.md` → should point to `.ai/rules.md`

### 4. Preserve project-specific content

If you had project-specific instructions at the bottom of `.github/copilot-instructions.md`, add them back below the auto-generated section.

If you had project-specific rules in `.claude/rules/`, keep them as separate files (e.g., `.claude/rules/project.md`).

### 5. Remove v1 files (when ready)

Once you're confident v2 works, clean up:

```bash
# Remove v1 agent/skill copies from platform dirs
rm -f .github/agents/*-v1.agent.md  # if you renamed them
rm -rf .github/skills/*/             # v1 skill directories
rm -f .claude/rules/ALWAYS_DO.md
rm -f .claude/rules/PROJECT_PATHS.md

# Remove v1 framework files (if not using submodule)
rm -rf .ai/agents .ai/skills .ai/instructions .ai/config .ai/scripts .ai/docs .ai/templates
```

If using a submodule, just update the submodule to the v2 branch.

### 6. Update your workflow docs

Replace references to v1 agents/skills with v2 equivalents:
- "Use `@implementer`" → "Use `@builder`"
- "Follow `milestone-start` skill" → "Follow `start-milestone` skill"
- "Read `.ai/instructions/ALWAYS_DO.md`" → "Read `.ai/rules.md`"

---

## Artifact Compatibility

**Your existing work artifacts are fully compatible.** v2 uses the same directory structure for epics, milestones, tracking docs, and releases:

```
work/
├── epics/
├── milestones/
│   └── tracking/
└── releases/
```

No migration needed for these files.

---

## FAQ

### Can I run v1 and v2 side by side?

Yes. v2 lives in `.ai/` which doesn't conflict with v1's `.ai/agents/`, `.ai/skills/`, etc. However, the platform adapter files (`.github/copilot-instructions.md`, etc.) will be overwritten when you run `setup.sh`.

### Will my v1 custom skills still work?

You'll need to convert them to v2 format (shorter checklist style) and place them in `.ai/skills/`. The format is simpler — see existing v2 skills as examples.

### What about the sync script?

Delete it. `setup.sh` replaces it entirely. Instead of copying 60 files, it generates ~10 pointer files.
