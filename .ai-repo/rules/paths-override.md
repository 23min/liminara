# Path Overrides for Liminara

These override `.ai/paths.md` defaults to match Liminara's existing structure.

| Variable | Override | Reason |
|----------|---------|--------|
| `ROADMAP_PATH` | `work/roadmap.md` | Roadmap lives in work/, not root |
| `MILESTONE_PATH` | `work/epics/<epic-slug>/` | Milestones live inside their epic folder |
| `TRACKING_PATH` | `work/milestones/tracking/` | Default (unchanged) |
| `EPICS_PATH` | `work/epics/` | Default (unchanged) |
| `COMPLETED_EPICS` | `work/done/` | Completed epics move here |

## Milestone Convention

Milestones live inside their epic folder, not in a separate `work/milestones/` directory:
```
work/epics/E-10-radar/
  epic.md                    # Epic spec
  M-RAD-01-fetcher.md        # Milestone spec
  M-RAD-01-fetcher-log.md    # Session log
  M-RAD-02-extraction.md
  ...
```

Tracking docs still go to `work/milestones/tracking/` for quick lookup across epics.
