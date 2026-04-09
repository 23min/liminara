# M-EVOLVE-01 Tracking: Pipeline Refactoring

**Status:** Complete
**Started:** 2026-04-09
**Branch:** milestone/M-EVOLVE-01

## Acceptance Criteria

### AC1: Pipeline structure
- [x] `layoutMetro` delegates to strategy functions: `extractRoutes`, `orderNodes`, `reduceCrossings`, `assignLanes`, `refineCoordinates`
- [x] Each strategy function has documented input/output contract
- [x] Strategy functions selected via `options.strategies` with sensible defaults

### AC2: Default strategies reproduce current behavior
- [x] All 285 dag-map tests pass without modification
- [x] Byte-level comparison: 33 equivalence tests confirm identical output on all Tier A fixtures

### AC3: Strategy registry
- [x] `strategies/` directory under `dag-map/src/`
- [x] Each slot has a `default`/`none` implementation matching current behavior
- [x] Registry maps strategy names to functions via `registerStrategy`/`getStrategy`

### AC4: Pipeline is extensible
- [x] Adding a new strategy = write function + call `registerStrategy(slot, name, fn)`
- [x] No changes to layoutMetro's public interface

### AC5: Clean extraction
- [x] Route extraction logic in `strategies/extract-routes-default.js`
- [x] BFS lane allocation in `strategies/assign-lanes-default.js`
- [x] No-op slots: `order-nodes-none.js`, `reduce-crossings-none.js`, `refine-coordinates-none.js`
- [x] Pipeline wiring via `strategies/registry.js` and `strategies/index.js`

## Progress Log

| Date | AC | Note |
|------|----|------|
| 2026-04-09 | — | Milestone started |
| 2026-04-09 | AC1-5 | Pipeline refactored: 7 strategy files, registry, equivalence tests. 318 dag-map + 316 bench = 634 tests all green. |
