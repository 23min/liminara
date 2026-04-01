# Skill: TDD Cycle

Test-driven development workflow for implementing acceptance criteria.

## When to Use

During milestone implementation. For each acceptance criterion or feature unit.

## Checklist

### RED — Write failing test

- [ ] Write test(s) that describe the expected behavior
- [ ] Test names follow convention: `MethodName_Scenario_ExpectedResult`
- [ ] Use project's test framework (xUnit, Jest, pytest, etc.)
- [ ] Use mocks/stubs for external dependencies
- [ ] Run tests → confirm they **FAIL** for the right reason

### GREEN — Make it pass

- [ ] Write the **minimum** code to make the test pass
- [ ] Don't add features the test doesn't require
- [ ] Run tests → confirm they **PASS**
- [ ] Check no other tests broke

### REFACTOR — Clean up

- [ ] Remove duplication
- [ ] Improve naming
- [ ] Extract methods/classes if needed
- [ ] Run tests → confirm still **GREEN**

### Update Tracking

- [ ] Check off the acceptance criterion in tracking doc
- [ ] Note any decisions or deviations

## Anti-patterns

- Writing code before tests
- Writing tests that can't fail
- Skipping the refactor step
- Testing implementation details instead of behavior
- Tests that depend on execution order

## Test Quality Checks

- [ ] Tests are deterministic (no randomness, no clock, no network)
- [ ] Tests are independent (no shared mutable state)
- [ ] Tests cover edge cases (null, empty, boundary values)
- [ ] Test names explain what is being tested
