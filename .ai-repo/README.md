# Project-Specific AI Configuration

This directory holds AI framework extensions specific to **this repository**.
The shared framework lives in `.ai/` (submodule). This directory is repo-local.

## Structure

```
.ai-repo/
├── config/    ← structured repo-owned artifact layout config
├── skills/    ← project-specific skill checklists
├── rules/     ← project-specific conventions and constraints
└── README.md  ← you are here
```

## Config

The canonical artifact layout for this repo lives in `.ai-repo/config/artifact-layout.json`.

Generated assistant surfaces such as `CLAUDE.md`, `.claude/`, and `.github/` should mirror that resolved layout. They are not the source of truth for where epics, milestones, roadmap files, or tracking docs live.

For Liminara specifically, the config intentionally describes a mixed layout:
- roadmap at `work/roadmap.md`
- epic specs as `epic.md` inside each epic folder
- milestone specs inside the owning epic folder
- tracking docs in `work/milestones/tracking/`

Note: the current framework validator still requires `trackingDocPathTemplate` to contain `<epic>`. The configured template therefore uses a normalizing `.../<epic>/../...` segment, but the canonical human-facing tracking location remains `work/milestones/tracking/<milestone-id>-tracking.md`.

## Skills

Add a `.md` file in `skills/` with a checklist format (see `.ai/skills/` for examples).
Project skills are automatically picked up by `bash .ai/setup.sh` and distributed
to platform adapters (Copilot, Claude, Codex).

Examples of project-specific skills:
- `deploy-to-azure.md` — deployment runbook for this project
- `run-pipeline.md` — how to trigger the CI/CD pipeline
- `data-export.md` — how to export fixture data from production

## Rules

Add a `.md` file in `rules/` for project-specific conventions:
- `tech-stack.md` — "Use xUnit, NSubstitute, .NET 9"
- `naming.md` — "Services use I{Name} interface pattern"
- `testing.md` — "All tests use [Theory] for parameterized cases"

These are referenced by platform adapters so the AI reads them automatically.
