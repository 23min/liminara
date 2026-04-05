---
id: E-20-execution-truth
phase: 5
status: complete
depends_on: E-11-radar
---

# E-20: Execution Truth

## Goal

Bring Liminara's runtime contract back into alignment with its thesis before more hardening code lands. After this epic, op metadata, runtime identity, side-effect boundaries, degraded-success semantics, and pack behavior all mean exactly what the runtime says they mean.

## Context

Radar has exposed several places where the current runtime contract is too loose:

- an op can be declared `:pure` while still mutating durable state
- pack code can fabricate plan-time identifiers that look like runtime identity
- production fallback behavior can yield degraded output as ordinary success
- upcoming hardening work (E-19 and E-12) still risks defining local shapes rather than extending one canonical op contract

D-2026-04-02-015 already identified the right direction: one `execution_spec/0` shape instead of callback sprawl. This epic turns that direction into sequenced work.

This epic is the first blocking slice of Phase 5c. M-RAD-04 is now closed, so E-20 is the next active hardening epic. E-19 and E-12 remain downstream consumers of the contract defined here.

## Scope

### In Scope

- Unified op shape via `execution_spec/0`
- Explicit runtime execution context owned by the runtime, not packs
- Canonical op result and warning/degraded-success contract
- Exception-only migration path from today's callbacks and `execute/1` shape to the new contract where bootability requires it
- Radar semantic cleanup where current behavior violates the intended meaning of purity, runtime identity, or degraded output
- Aligning E-19 and E-12 so they implement against this contract instead of inventing parallel ones

### Out of Scope

- Full E-19 warning/UI implementation
- Full E-12 sandbox implementation
- Recovery mode
- Topic config / multi-topic scheduling
- Generic platform abstractions not already justified by Radar

## Constraints

- Must stay bounded to Radar-proven needs before VSME
- Must preserve a migration path so existing ops do not all need to be rewritten in one step
- Compatibility shims are exceptions with explicit removal triggers, not a default dual-surface strategy
- Must not turn warnings into a second decision system
- Must not let pack code fabricate runtime-owned identity values
- Must separate semantic truth from materialized local indexes or caches

## Success Criteria

- [x] The canonical op contract is defined in a way that E-19 and E-12 can consume directly
- [x] Runtime execution context is explicitly defined and separated from plan inputs
- [x] Warning-bearing success is defined without overloading decisions or ad hoc UI state
- [x] Radar has a path to remove current semantic mismatches around dedup, run identity, and silent degraded output
- [x] Any remaining legacy callbacks are clearly marked as temporary exceptions with removal triggers rather than normalized as a second long-term surface area

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-TRUTH-01 | Execution spec + outcome design | Lock the canonical op shape, runtime execution context, and warning-bearing success contract before more hardening code lands | M-RAD-04-webui-scheduler | complete |
| M-TRUTH-02 | Core runtime contract migration | Add the new runtime structures and compatibility shims so execution and replay can operate on one truthful contract | M-TRUTH-01 | complete |
| M-TRUTH-03 | Radar semantic cleanup | Refactor Radar onto the truthful contract: side-effect boundaries, runtime identity, and degraded-output semantics | M-TRUTH-02 | complete |

## References

- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `docs/architecture/contracts/00_TRUTH_MODEL.md`
- `docs/architecture/contracts/02_SHIM_POLICY.md`
- `work/done/E-20-execution-truth/M-TRUTH-03-radar-semantic-cleanup.md`
- Decision D-2026-04-02-012: bounded Radar hardening before VSME
- Decision D-2026-04-02-013: sequencing rule
- Decision D-2026-04-02-015: unified execution spec replaces callback sprawl
- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/epics/E-12-op-sandbox/epic.md`