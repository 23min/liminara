# Project Paths

All paths are relative to workspace root. Agents and skills reference these by name.

| Variable | Path | Purpose |
|----------|------|---------|
| `ROADMAP_PATH` | `ROADMAP.md` | High-level epic list + status |
| `EPICS_PATH` | `work/epics/` | Epic specifications |
| `MILESTONE_PATH` | `work/milestones/` | Milestone specifications |
| `TRACKING_PATH` | `work/milestones/tracking/` | Milestone progress tracking |
| `GAPS_PATH` | `work/gaps.md` | Discovered gaps and deferred work |
| `DECISIONS_PATH` | `work/decisions.md` | Shared decision log (active decisions) |
| `AGENT_HISTORY_PATH` | `work/agent-history/` | Per-agent accumulated learnings |
| `CHANGELOG_PATH` | `CHANGELOG.md` | Release changelog |
| `PROVENANCE_PATH` | `provenance/` | Session provenance logs |
| `GUIDES_PATH` | `docs/guides/` | Development guides |

## Notes

- All paths use `/` separators
- Trailing `/` indicates a directory
- Epic-level docs live under `EPICS_PATH/<epic-slug>/`
- Tracking docs are separate from milestone specs
- `work/` is framework-managed; `docs/` is project-owned
