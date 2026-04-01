# Changelog

All notable changes to the AI-Assisted Development Framework are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed
- **Default workflow is now Agent mode** — replaced coordinator-centric framing in generated `copilot-instructions.md` and `.claude/rules/ai-framework.md` with direct Agent mode instructions. Users work with full tool access by default; named agents (@planner, @builder, @reviewer, @deployer) remain available for focused personas.
- **Coordinator marked as optional/legacy** — `agents/coordinator.md` is still generated and available in the dropdown, but no longer the recommended default. Kept for backward compatibility during transition.
- **Routing table updated** — removed coordinator row ("general task, unclear intent"), added "Subagent?" column indicating which workflows benefit from subagent delegation vs. interactive work.

### Added
- **Subagent delegation guidance** in generated instructions — explicit section advising when to use subagents (planning/research, code review) and when not to (building/implementation, which is interactive).
- **Session Start — Load Memory** section promoted to generated instructions — previously only in coordinator agent, now available in Agent mode so `work/decisions.md` and `work/agent-history/` are loaded regardless of which agent is active.
