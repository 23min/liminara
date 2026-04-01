# AI-Assisted Development Framework v2

A lightweight, platform-agnostic framework for AI-assisted software development.

**Works with:** GitHub Copilot, Claude Code, Codex, or any AI coding assistant.

## Quick Start

```bash
# Add to your project (one-time)
git remote add ai-framework <your-framework-repo-url>
git subtree add --prefix=.ai ai-framework v2 --squash

# Initialize project structure
bash .ai/setup.sh

# That's it. Start working:
# Copilot: @planner, @builder, @reviewer, @deployer
# Claude Code: auto-delegates based on task
```

**New to the framework?** Read the [GUIDE](GUIDE.md) for end-to-end walkthrough scenarios.

## Updating the Framework

```bash
# Easiest — uses the built-in update script
bash .ai/update.sh

# Or specify a branch/tag
bash .ai/update.sh v2.1.0
```

This pulls the latest changes and re-syncs platform files automatically.

<details>
<summary>Manual update (without the script)</summary>

```bash
git subtree pull --prefix=.ai ai-framework v2 --squash
bash .ai/sync.sh
```
</details>

Why subtree over submodule? Files live directly in your repo tree — `git clone` just works, no `--recurse-submodules` dance, no detached HEAD surprises.

<details>
<summary>Alternative: git submodule (if you prefer)</summary>

```bash
# Add
git submodule add <your-framework-repo-url> .ai
bash .ai/setup.sh

# Update
cd .ai && git pull origin v2 && cd ..
git add .ai && git commit -m "chore: update ai-framework"
bash .ai/sync.sh
```

Downside: every clone needs `git clone --recurse-submodules` or `git submodule update --init`.
</details>

## How It Works

```
You describe work → AI picks the right role → follows skill checklists → produces artifacts
```

### Four Agents

| Agent | When to use | What it does |
|-------|-------------|-------------|
| **planner** | "Plan this feature", "Break this down" | Designs epics, creates milestone specs, makes architectural decisions |
| **builder** | "Implement this", "Start milestone X" | Writes code + tests (TDD), updates tracking docs |
| **reviewer** | "Review this code", "Check my changes" | Reviews code, validates tests, signs off on milestones |
| **deployer** | "Deploy this", "Release v1.2" | Manages infrastructure, CI/CD, releases |

### Skills (Checklists)

Skills are short checklists that agents follow. You don't need to invoke them — agents pick the right one based on your request:

| Skill | Trigger | Agent |
|-------|---------|-------|
| `plan-epic` | "Plan feature X", "Design the system for Y" | planner |
| `plan-milestones` | "Break this epic into milestones" | planner |
| `draft-spec` | "Write spec for milestone M1" | planner |
| `start-milestone` | "Start milestone X", "Implement M1" | builder |
| `tdd-cycle` | "Add tests for X", "Implement feature Y" | builder |
| `review-code` | "Review this PR", "Check my changes" | reviewer |
| `wrap-milestone` | "Finish milestone X", "Complete M1" | reviewer |
| `release` | "Release v1.2", "Deploy to prod" | deployer |

### Artifacts (the real contract)

Artifacts gate the work — not agent identities, not handoff ceremonies:

```
work/
  epics/           # Epic specs (what to build and why)
  milestones/      # Milestone specs (detailed what + acceptance criteria)
    tracking/      # Progress tracking (updated during implementation)
  releases/        # Release summaries (after epic completion)
```

**Rule:** If the artifact exists in the right state, you can proceed. No need to ask "which agent should I use?"

## Platform Setup

### GitHub Copilot (VS Code)

After `bash .ai/setup.sh`:
- Agents appear in the `@` picker: `@planner`, `@builder`, `@reviewer`, `@deployer`
- Instructions auto-loaded from `.github/copilot-instructions.md`
- Skills available as reference in `.github/skills/`

### Claude Code

After `bash .ai/setup.sh`:
- Agents in `.claude/agents/` — Claude auto-delegates based on task description
- Rules loaded from `.claude/rules/`
- Skills referenced from `.ai/skills/`

### Codex (headless)

Use `.ai/skills/` directly in your prompt. Codex doesn't have agent routing — give it the relevant skill checklist and artifact paths.

### Other tools

Point your tool at `.ai/` — the framework is just markdown files. Any AI assistant that can read files can follow the checklists.

## Project Paths

All artifact paths are configurable in `paths.md`:

| Path | Default | Purpose |
|------|---------|---------|
| `EPICS_PATH` | `work/epics/` | Epic specifications |
| `MILESTONE_PATH` | `work/milestones/` | Milestone specifications |
| `TRACKING_PATH` | `work/milestones/tracking/` | Progress tracking documents |
| `RELEASES_PATH` | `work/releases/` | Release summaries |
| `GAPS_PATH` | `work/gaps.md` | Discovered gaps and deferred work |
| `CHANGELOG_PATH` | `CHANGELOG.md` | Release changelog |
| `ROADMAP_PATH` | `ROADMAP.md` | High-level epic status |

## Directory Structure

```
.ai/                 ← shared framework (subtree)
├── README.md           ← you are here
├── rules.md            ← non-negotiable rules (short!)
├── paths.md            ← project path configuration
├── setup.sh            ← one-time project initialization
├── GUIDE.md            ← end-to-end walkthrough scenarios
├── agents/
│   ├── planner.md      ← designs, plans, specs
│   ├── builder.md      ← codes + tests (TDD)
│   ├── reviewer.md     ← reviews, validates, signs off
│   └── deployer.md     ← infrastructure + releases
├── skills/
│   ├── plan-epic.md
│   ├── plan-milestones.md
│   ├── draft-spec.md
│   ├── start-milestone.md
│   ├── tdd-cycle.md
│   ├── review-code.md
│   ├── wrap-milestone.md
│   └── release.md
├── templates/
│   ├── epic-spec.md
│   ├── milestone-spec.md
│   └── tracking-doc.md
└── docs/
    └── migration-v1.md ← v1 → v2 migration guide

.ai-repo/               ← project-specific (repo-local, not in submodule)
├── skills/             ← project-specific skill checklists
├── rules/              ← project-specific conventions
└── README.md
```

## Core Philosophy

1. **Artifacts over ceremonies** — Documents gate work, not agent handoffs
2. **Checklists over essays** — Skills are 30-50 lines, not 300
3. **One source of truth** — `.ai/` is canonical; platform files are pointers
4. **Platform-agnostic** — Works with any AI tool that can read markdown
5. **TDD by default** — Builder writes tests first, always
6. **Shared vs project-specific** — Framework in `.ai/` (subtree), project extensions in `.ai-repo/` (repo-local)

## Contributing

- **Framework changes** (agents, skills, rules): Edit in the ai-workflow repo, then `git subtree pull` in consuming projects
- **Project-specific skills/rules**: Add to `.ai-repo/skills/` or `.ai-repo/rules/`
- After any change: `bash .ai/sync.sh` to regenerate platform adapters

No sync scripts, no triple-copy maintenance.
