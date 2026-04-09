---
id: M-EVOLVE-01-pipeline-refactoring
epic: E-EVOLVE-layout-pipeline
status: in-progress
depends_on: []
---

# M-EVOLVE-01: Pipeline Refactoring

## Goal

Decompose `layoutMetro` from a monolithic 542-line function into a pipeline of named, swappable strategy functions — without changing any behavior. After this milestone, each algorithmic step is a separate function that can be replaced with an alternative implementation.

## Context

`layoutMetro` currently executes 6 tightly coupled steps inline. Route extraction, Y-assignment, and node positioning are interleaved with hardcoded heuristics. This milestone extracts each step into a named function with a clear input/output contract, wires them together through a strategy registry, and proves behavioral equivalence via the existing 285 dag-map tests.

No new algorithms are added. The only strategies are the current ones, extracted and named.

## Acceptance Criteria

1. **Pipeline structure**
   - [ ] `layoutMetro` delegates to a sequence of strategy functions: `assignLayers`, `extractRoutes`, `orderNodes`, `reduceCrossings`, `assignYPositions`, `refineCoordinates`, `buildRoutePaths`
   - [ ] Each strategy function has a documented input/output contract (JSDoc or equivalent)
   - [ ] Strategy functions are selected via an `options.strategies` object with sensible defaults

2. **Default strategies reproduce current behavior**
   - [ ] All 285 dag-map tests pass without modification
   - [ ] A byte-level comparison test: default-strategy pipeline produces identical layout JSON as the current monolithic function on all Tier A fixtures

3. **Strategy registry**
   - [ ] A `strategies/` directory under `dag-map/src/` holds strategy implementations
   - [ ] Each strategy slot has a `none` or `default` implementation matching current behavior
   - [ ] The registry maps strategy names to functions: `{ nodeOrdering: { none: fn, ... }, crossingReduction: { none: fn, ... }, ... }`

4. **Pipeline is extensible**
   - [ ] Adding a new strategy requires only: (a) writing the function, (b) registering it by name
   - [ ] No changes to layoutMetro's public interface (same input DAG + options, same output shape)

5. **Clean extraction**
   - [ ] `longestPathIn` and route extraction logic extracted to `strategies/route-extraction.mjs` (or `.js`)
   - [ ] BFS lane allocation extracted to `strategies/lane-assignment.mjs`
   - [ ] Node positioning extracted to `strategies/positioning.mjs`
   - [ ] Occupancy tracking logic separated from lane allocation heuristics

## Scope

### In Scope

- Extracting each step of layoutMetro into a named function
- Creating the strategy registry and options.strategies interface
- Behavioral equivalence tests (byte-level comparison on Tier A)
- Documentation of each strategy function's contract

### Out of Scope

- New algorithms (barycenter, median, etc.) — that's M-EVOLVE-02
- Changes to layoutHasse or layoutFlow
- Changes to the bench genome — that's M-EVOLVE-03
- Performance optimization

## Dependencies

- E-DAGBENCH complete (bench harness available for regression testing)

## Test Strategy

- All 285 existing dag-map tests pass (unchanged)
- New byte-level equivalence test: run all Tier A fixtures through old and new codepaths, assert identical JSON output
- All 315+ bench tests pass (the evaluator still works against the refactored layoutMetro)

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tight coupling between steps makes extraction hard | Med | Extract incrementally (one step at a time), run full test suite after each |
| Route extraction and Y-assignment share state in subtle ways | Med | Map the data flow explicitly before extracting; intermediate state as explicit objects |

## Deliverables

- `dag-map/src/strategies/` directory with extracted strategy functions
- Refactored `layout-metro.js` that delegates to the strategy pipeline
- Byte-level equivalence tests
- Updated bench tests (if any imports changed)
