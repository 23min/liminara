# M-TRUTH-01: Execution Spec + Outcome Design — Tracking

**Started:** 2026-04-03
**Completed:** 2026-04-04
**Branch:** `milestone/M-TRUTH-01`
**Spec:** `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
**Status:** complete

## Acceptance Criteria

- [x] AC1: Canonical op definition is specified
  - `execution_spec/0` is the canonical long-term surface
  - Structured sections: `identity`, `determinism`, `execution`, `isolation`, `contracts`
  - Each section has defined ownership and semantics
- [x] AC2: Runtime execution context is specified
  - Runtime-owned identity and provenance fields defined
  - Execution context separated from plan inputs
  - Pack code no longer needs to fabricate runtime metadata
- [x] AC3: Canonical result and warning contract is specified
  - Outputs, decisions, and warnings share one canonical result shape
  - Warning-bearing success modeled explicitly
  - Decisions remain distinct from warnings
- [x] AC4: Exception-only migration strategy is specified
  - Existing callbacks supported only where a documented temporary shim is required
  - Every shim has a removal trigger and owning milestone
  - Cross-language protocol transition defined for Python ops
- [x] AC5: Downstream specs are aligned
  - E-19 consumes the warning/result contract defined here
  - E-12 consumes the `isolation` section defined here
  - No downstream spec introduces a standalone callback or local shape that bypasses this contract

## Baseline

- Branch switched to `milestone/M-TRUTH-01`
- Existing planning docs from the E-20 setup are present and uncommitted
- Focused schema-freezing contract work has been validated with `mix test apps/liminara_core/test/liminara/execution_contract_structs_test.exs`
- Full umbrella validation was attempted during wrap-up, but unrelated dirty-worktree issues outside M-TRUTH-01 scope prevented a green umbrella result

## Evidence

- The milestone spec now explicitly states that shared contract structs and focused contract tests are allowed in M-TRUTH-01 only as schema-freezing artifacts.
- The same spec now explicitly defers runtime legacy callback bridges and result-normalizer implementation to M-TRUTH-02.
- `Liminara.ExecutionSpec`, `Liminara.ExecutionContext`, `Liminara.OpResult`, and `Liminara.Warning` exist in `liminara_core` as canonical shared contract structs, with a focused ExUnit file locking defaults and nested-section normalization.
- E-19 already references M-TRUTH-01 as the warning/result contract source.
- E-12 already references M-TRUTH-01 as the `execution_spec/0` and `isolation` contract source.

## Validation

- Scoped formatter validation passes for `ExecutionSpec`, `ExecutionContext`, `OpResult`, `Warning`, and the focused contract test file.
- Focused contract validation passes: `mix test apps/liminara_core/test/liminara/execution_contract_structs_test.exs` → `5 tests, 0 failures`.
- Full umbrella validation remains blocked by unrelated branch state:
  - `mix format --check-formatted && mix test` stops on unformatted runtime files outside the M-TRUTH-01 contract slice.
  - A separate `mix test` run reports 7 unrelated `liminara_web` / `Run.Server` failures on this dirty worktree.

## Implementation Phases

1. Lock the canonical `execution_spec/0` shape and runtime execution context
2. Lock the canonical `OpResult` and warning contract, including Python protocol direction
3. Write the migration strategy from legacy callbacks and tuple results
4. Align E-19 and E-12 to consume the contract directly and verify no callback sprawl remains

## Notes

- This is a design milestone. Validation is contract alignment and downstream spec coherence, not runtime code delivery yet.
- Limited shared-struct codification in `liminara_core` is allowed when it only freezes canonical names, defaults, and field shapes and is backed by focused contract tests.
- Runtime legacy bridges, tuple/JSON result normalization, and pack migration remain explicitly deferred to M-TRUTH-02.
- Truth governance lives in `docs/architecture/contracts/` and should be updated alongside this milestone.