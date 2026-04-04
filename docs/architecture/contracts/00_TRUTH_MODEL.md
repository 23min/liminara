---
title: Documentation Truth Model
doc_type: contract-governance
truth_class: live
status: active
owner: architecture
last_reviewed: 2026-04-04
source_of_truth:
  - docs/architecture/contracts/01_CONTRACT_MATRIX.md
  - docs/architecture/contracts/02_SHIM_POLICY.md
  - work/decisions.md
---

# Documentation Truth Model

Liminara has to be provable, not merely plausible. The repository therefore distinguishes between current truth, approved next truth, and preserved history instead of letting them drift into the same folder.

## Truth classes

| `truth_class` | Meaning | What it may contain | What it may not do |
|---------------|---------|---------------------|--------------------|
| `live` | Current contract or current behavior description | Active architecture docs, source maps, data-model specs, rule sources | Describe future intent as if it already exists |
| `decided_next` | Approved next-state contract not yet fully implemented | Epic/milestone specs, blocking architecture plans such as E-20 | Override live code about what exists today |
| `historical` | Archived snapshot, superseded plan, or completed design record | Prior architecture snapshots, design notes, completed-plan context | Serve as current authority |
| `exploration` | Hypothesis, vision, or research direction | Brainstorming, visions, speculative design language | Be cited as an approved contract |

## Resolution order

1. Current runtime behavior comes from live code, tests, and canonical persistence specs.
2. Approved next-state behavior comes from active epic/milestone specs plus `decided_next` architecture docs.
3. Program sequencing comes from `work/roadmap.md`. The `CLAUDE.md` Current Work section is an operational handoff summary and must agree with the roadmap; it never overrides it.
4. `docs/history/` and exploratory research provide context only. They never win a conflict.

## Folder rules

- `docs/architecture/` contains only `live` or `decided_next` material.
- `docs/history/` stores historical snapshots and superseded design notes, mirroring the original folder when useful.
- `docs/research/` and `docs/brainstorm/` may remain exploratory, but they should not be treated as committed runtime contracts.

## Frontmatter schema

All files in `docs/architecture/` and `docs/history/` should carry frontmatter.

Required keys for active docs:

```yaml
---
title: Short document title
doc_type: architecture | contract-governance | architecture-plan
truth_class: live | decided_next
status: active
owner: team or subsystem
last_reviewed: YYYY-MM-DD
source_of_truth:
  - repo/relative/path
---
```

Required keys for archived docs:

```yaml
---
title: Short document title
doc_type: architecture-history
truth_class: historical
status: archived
owner: history
archived_on: YYYY-MM-DD
snapshot_date: YYYY-MM-DD
superseded_by:
  - repo/relative/path
---
```

Optional keys for both:

- `related_decisions`
- `related_epics`
- `notes`

## Completion vs quality

Completion markers answer "was this milestone or phase executed?"

Quality and semantic authority answer "is this still the truth?"

Those are separate questions. A completed epic may still point at historical context. A historical document may remain useful without staying authoritative.

## Change discipline

- Update the contract matrix when a contract surface changes ownership or status.
- Move stale architecture material into `docs/history/` instead of leaving it beside active contracts.
- If `CLAUDE.md` Current Work drifts from `work/roadmap.md`, update `CLAUDE.md` to match; the roadmap wins.
- Update `.ai-repo/` sources and run `./.ai/sync.sh` for instruction changes; generated files are outputs, not primary edit targets.