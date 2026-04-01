---
id: M-OBS-02-phoenix-scaffold
epic: E-09-observation-layer
status: done
---

# M-OBS-02: Phoenix Scaffolding + Runs Dashboard

## Goal

Add a Phoenix app (`liminara_web`) to the umbrella project and build the first LiveView pages: a runs dashboard listing all runs with their status, and a run detail page skeleton that will host the DAG visualization (M-OBS-03) and inspectors (M-OBS-04).

This milestone establishes the web foundation: routing, layout, responsive CSS, PubSub wiring, and the auto-start of Observation.Servers when a user views a run.

## Acceptance criteria

- [ ] `liminara_web` Phoenix app added to the umbrella, depends on `liminara_core`
- [ ] Minimal Phoenix setup: Endpoint, Router, LiveView, PubSub. No Ecto, no mailer, no auth.
- [ ] Root layout with responsive CSS (usable on desktop and mobile)
- [ ] `/runs` — LiveView page listing all runs (run_id, pack, status, started_at, duration)
- [ ] Runs list updates in real-time when new runs start or existing runs complete
- [ ] `/runs/:id` — LiveView page showing run detail (run_id, pack, status, timing, node count)
- [ ] Run detail page subscribes to Observation.Server PubSub updates and reflects state changes in real-time
- [ ] Observation.Server auto-starts when a user navigates to a run detail page
- [ ] Run detail page works for both active runs (live updates) and completed runs (static view)
- [ ] Basic navigation: header with link to runs list

## Tests

### LiveView tests — runs list
- Mount `/runs` page, verify it renders a list of runs
- Start a new run, verify it appears in the list without page reload
- Verify run status updates in real-time (running → completed)

### LiveView tests — run detail
- Mount `/runs/:id` for a completed run, verify it shows run metadata (status, timing, node count)
- Mount `/runs/:id` for an active run, verify it receives real-time updates
- Mount `/runs/:id` for a non-existent run, verify appropriate error handling

### Integration tests
- Navigate from runs list → run detail → back. Verify routing works.
- Start a run programmatically, open the detail page, verify Observation.Server starts and PubSub updates flow.

### Responsive tests
- Verify runs list renders correctly at desktop width (>1024px)
- Verify runs list renders correctly at mobile width (<768px)

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- DAG visualization (M-OBS-03)
- Node inspector, artifact viewer, event timeline (M-OBS-04)
- A2UI endpoint (M-OBS-05)
- Authentication or user accounts
- Polished CSS / design system (functional layout only)
- Deployment configuration

## Spec reference

- `docs/analysis/02_Fresh_Analysis.md §4.2 Why Phoenix LiveView`
- `docs/architecture/01_CORE.md §Observation`

## Related ADRs

- none yet
