---
title: Contract Matrix
doc_type: contract-governance
truth_class: live
status: active
owner: architecture
last_reviewed: 2026-04-04
source_of_truth:
  - work/roadmap.md
  - work/done/E-20-execution-truth/epic.md
  - work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md
---

# Contract Matrix

This matrix records where each major contract surface is authoritative today, where the approved next-state contract lives, and which files are now historical context only.

| Surface | Live source | Approved next | Historical / supporting context | Drift guard |
|---------|-------------|---------------|----------------------------------|-------------|
| Program sequencing and current handoff | `work/roadmap.md` | Active epic and milestone specs under `work/epics/` | `docs/history/architecture/02_PLAN.md` | `CLAUDE.md` Current Work is a handoff summary and must agree with the roadmap; archived phase plans are not current sequencing authority |
| Runtime execution contract | `runtime/apps/liminara_core/lib/liminara/op.ex`, `runtime/apps/liminara_core/lib/liminara/executor.ex`, `runtime/apps/liminara_core/lib/liminara/run/server.ex` | `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`, `work/done/E-20-execution-truth/epic.md`, `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`, `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md` | `docs/history/architecture/03_PHASE3_REFERENCE.md` | Placeholder structs do not override the live callback contract until E-20 migrates runtime execution |
| Artifact, event, and decision persistence model | `docs/analysis/11_Data_Model_Spec.md`, `runtime/apps/liminara_core/lib/liminara/artifact/store.ex`, `runtime/apps/liminara_core/lib/liminara/event/store.ex`, `runtime/apps/liminara_core/lib/liminara/decision/store.ex` | E-20 and later hardening epics when event payloads gain execution-context or warning fields | Historical storage-plan references in completed epics | Persistence changes must keep the Phase 0 data model explicit and versioned |
| Warning and degraded-success contract | No first-class runtime warning contract yet; current behavior is ordinary success or failure only | `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`, `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`, `work/epics/E-19-warnings-degraded-outcomes/epic.md` | Radar fallback behavior and prior notes | Warning/degraded runtime work starts after M-TRUTH-02; no UI-only or decision-shaped warning side channel is allowed |
| Sandbox and isolation contract | `runtime/apps/liminara_core/lib/liminara/executor/port.ex` | Decision D-2026-04-02-011, Decision D-2026-04-02-019, `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`, `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`, `work/epics/E-19-warnings-degraded-outcomes/epic.md`, `work/epics/E-12-op-sandbox/epic.md` | Earlier executor assumptions in completed Radar work | Isolation metadata must mirror `execution_spec/0.isolation` field names, and partial enforcement must surface through canonical warnings |
| Radar cross-run history and dedup semantics | `runtime/apps/liminara_radar/lib/liminara/radar/ops/dedup.ex`, `runtime/python/src/ops/radar_dedup.py` | `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`, `work/done/E-20-execution-truth/epic.md` | `docs/history/architecture/05_RADAR_CEP_NOTES.md` | Materialized indexes are derived working state, not the semantic source of truth |
| Observation and visualization semantics | `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex`, `runtime/apps/liminara_web/` | Future observation epics as they are approved | `docs/history/architecture/04_OBSERVATION_DESIGN_NOTES.md`, `docs/history/architecture/06_VISUALIZATION_DESIGN.md`, `docs/history/architecture/07_TIDEPOOL_VISION.md` | Historical design notes can inspire UI work but cannot define current runtime payloads |
| AI workflow and repo guardrails | `.ai/rules.md`, `.ai/paths.md`, `.ai-repo/rules/liminara.md` | New rule changes land in `.ai-repo/` and become generated outputs via `./.ai/sync.sh` | Generated instruction files | Never patch generated instruction files to change policy; patch the sources and regenerate |