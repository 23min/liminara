---
id: E-04-elixir-scaffolding
phase: 2
status: draft
---

# E-04: Elixir Project Scaffolding

## Goal

Set up the Elixir umbrella project structure, dependencies, tooling, and golden test fixtures so that subsequent epics can focus on implementation.

## Scope

**In:**

### Umbrella project (`liminara/`)
- `mix new liminara --umbrella`
- First app: `apps/liminara_core/` — the runtime kernel (all Phase 2 code lives here)
- Mix configuration: Elixir 1.18+, OTP 27+
- Dependencies: `jason` (JSON), `ex_doc` (docs)
- Dev dependencies: `credo` (linting), `dialyxir` (type checking)
- Formatter config (`.formatter.exs`)
- Credo config (`.credo.exs`)

### Golden test fixtures (`test_fixtures/`)
- Hand-written files representing a valid Liminara run on disk:
  - `events.jsonl` — 5-6 events with valid hash chain (run_started, op_started, op_completed × 2, decision_recorded, run_completed)
  - `seal.json` — run seal matching the event_hash of the final event
  - `artifacts/` — two artifact blobs in correct directory structure (`{hex[0:2]}/{hex[2:4]}/{hex}`)
  - `decisions/` — one decision record (canonical JSON)
  - `events_tampered.jsonl` — same as events.jsonl but with one modified event (for tamper detection tests)
- These fixtures are the concrete embodiment of 11_Data_Model_Spec.md
- Both the Python SDK (E-02) and Elixir runtime test suites validate against these files
- Located at repo root (`test_fixtures/`) so both implementations can access them

### Validation pipeline
- `mix format --check-formatted`
- `mix credo`
- `mix dialyzer` (initial PLT build)
- `mix test` (placeholder tests)

**Out:**
- Any runtime implementation (Artifact.Store, Event.Store, etc.)
- Phoenix or web dependencies
- Oban or Postgres

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-ES-01-umbrella | Umbrella project, liminara_core app, deps, tooling config | draft |
| M-ES-02-fixtures | Golden test fixtures (valid run + tampered run), fixture verification tests | draft |

## Success criteria

- [ ] `mix compile` succeeds with zero warnings
- [ ] `mix format --check-formatted` passes
- [ ] `mix credo` passes
- [ ] `mix dialyzer` passes
- [ ] `mix test` runs and passes (placeholder + fixture validation tests)
- [ ] Golden fixtures are valid (events.jsonl hash chain is verifiable by hand)
- [ ] Fixture directory structure matches 11_Data_Model_Spec.md exactly

## References

- Data model: `docs/analysis/11_Data_Model_Spec.md`
- Architecture: `docs/architecture/01_CORE.md`
