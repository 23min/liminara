---
id: E-19-warnings-degraded-outcomes
phase: 5
status: planning
depends_on: E-11-radar
---

# E-19: Warnings & Degraded Outcomes

## Goal

Add a first-class warning and degraded-outcome contract to Liminara so that packs can no longer silently return degraded output as an ordinary success. Warnings must propagate from op execution through run events, observation state, CLI output, and UI inspectors with enough structure to explain the problem, cause, severity, remediation, and impact on produced artifacts.

## Context

Radar has now proven a real operator-trust gap: `radar_summarize.py` falls back to placeholder summaries when `ANTHROPIC_API_KEY` is missing, but the current runtime treats that as a normal success. The reason survives only inside decision content, and the observation layer currently collapses decision data down to hash and type, which makes the fallback effectively invisible in the UI.

This is not just a Radar quirk. The same problem will recur anywhere a pack chooses a safe fallback instead of a hard crash, and E-12 already anticipates degraded sandbox mode in environments where full isolation is unavailable. If Liminara does not model degraded outcomes explicitly, packs are forced to choose between:

1. lying with plain success
2. overusing hard failure for recoverable situations
3. smuggling warning semantics into decisions or output artifacts

That is not acceptable for a runtime whose value proposition is auditable, trustworthy execution.

Per D-012 and D-013, this should be handled as bounded Radar-proven hardening before VSME, not as a generic reliability platform.

## Scope

### In Scope

- A first-class warning/degraded-success concept at node and run level
- Structured warning payloads with fields such as code, severity, summary, cause, remediation, and output impact
- Event propagation from execution engine to observation projection and LiveView UI
- Run-level aggregation: completed with warnings / degraded outcome count
- Node-level inspector support for warnings and degraded decisions
- CLI surfacing for degraded runs and degraded nodes
- Radar adoption for known silent fallback paths, especially summarize placeholder mode and similar LLM fallback paths
- Artifact/briefing annotation when degraded content is present
- A reusable contract for future degraded modes, including sandbox partial enforcement in E-12

### Out of Scope

- Retry policies, backoff, circuit breakers, or automatic remediation
- Email/Slack/operator alerting
- A general health scoring platform
- Policy DSLs or rule engines for pack outcome handling
- Reworking replay correctness (E-11c owns that)
- Converting every existing soft edge in the repo to warnings in one pass

## Constraints

- Must preserve the distinction between nondeterministic decisions and execution warnings; warnings are not decisions
- Must fit the future unified execution spec direction from D-015 rather than adding callback sprawl
- Must not break existing ops that only return `{:ok, outputs}`, `{:ok, outputs, decisions}`, or `{:error, reason}`
- Must be visible in the existing run inspector and observation flow, not deferred to a future UI rewrite
- Must stay tightly scoped to proven Radar/operator needs before VSME

## Success Criteria

- [ ] Missing `ANTHROPIC_API_KEY` no longer yields an apparently normal Radar success; the summarize node and containing run are explicitly marked degraded
- [ ] Warning payloads carry enough information for an operator to answer: what happened, why, what was affected, and how to fix it
- [ ] The run detail UI shows degraded badges/counts and exposes warning cause/remediation when a problematic node is selected
- [ ] The run-level summary and CLI output clearly distinguish plain success from success with warnings
- [ ] The rendered Radar briefing indicates when placeholder or degraded content was used
- [ ] Packs have one supported way to express “completed, but degraded” without abusing either hard failure or decision records
- [ ] E-12 degraded sandbox mode can reuse the same warning contract instead of inventing separate logging semantics

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Taxonomy sprawl: warning vs degraded vs failed becomes philosophical instead of useful | High | Keep the contract minimal: hard failure, success, success with warnings. “Degraded” is an operator-facing interpretation of warning-bearing success, not a giant hierarchy. |
| Decisions and warnings get conflated | High | Keep separate fields and separate UI sections. Decisions capture nondeterministic choice; warnings capture execution quality/conditions. |
| Scope grows into a full reliability platform | High | Explicitly exclude retries, alerting, automation, and policy engines. Solve the current silent-fallback class only. |
| Packs disagree on whether a condition should warn or fail | Med | Put policy at the pack level; runtime supplies the mechanism, packs choose whether to degrade or fail. |
| UI only exposes counts, not causes | Med | Require cause/remediation visibility in the node inspector as a success criterion, not a stretch goal. |

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-WARN-01 | Runtime warning contract | Extend execution/event model with structured warnings, node/run aggregation, and tests for degraded-success semantics | E-11 | not started |
| M-WARN-02 | Observation + UI surfacing | Preserve warnings in observation projection, show badges/counts, and render cause/severity/remediation in the run inspector and timeline summaries | M-WARN-01 | not started |
| M-WARN-03 | Radar adoption | Convert known Radar silent fallback paths to explicit warnings, annotate briefings, and add pack-level tests for degraded-but-successful outcomes | M-WARN-02 | not started |

## Technical Direction

The preferred design direction is:

1. Extend the runtime result/event path so an op can succeed with warnings without overloading decision records.
2. Preserve warning metadata through observation state rather than reducing it to a hash-only view.
3. Surface warning details in the UI at both run and node level.
4. Let each pack decide whether a given condition is a warning-bearing success or a hard failure.

Likely shape:

- Op execution returns outputs plus optional warnings
- `op_completed` events carry warning payloads and a degraded flag/count
- Run state aggregates warning counts and degraded nodes
- Observation UI renders a warning section separate from decisions

This should remain compatible with D-015’s unified execution spec work. If a new execution metadata structure is introduced here, it should be a step toward that spec rather than a one-off contract.

## References

- Decision D-2026-04-02-012: hardening is limited to Radar-proven needs
- Decision D-2026-04-02-013: sequence is Radar correctness -> Radar hardening -> VSME
- Decision D-2026-04-02-015: avoid callback sprawl via unified execution spec
- Radar summarize fallback: `runtime/python/src/ops/radar_summarize.py`
- Observation projection: `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex`
- Run inspector: `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex`