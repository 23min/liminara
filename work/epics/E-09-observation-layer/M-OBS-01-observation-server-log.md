# M-OBS-01-observation-server — Session Log

## 2026-03-19 — Implementation

**Milestone:** M-OBS-01-observation-server
**Branch:** epic/E-09-observation-layer

### What was done

1. Created new umbrella app `liminara_observation` with `phoenix_pubsub` dependency.
2. TDD red phase: 94 failing tests across 3 files (view_model, server, integration).
3. TDD green phase: implemented `ViewModel` (122 lines) and `Server` (77 lines). All 94 tests pass.

### Decisions

- **New umbrella app (Option 3):** Chose to put the Observation.Server in a separate umbrella app (`liminara_observation`) rather than adding `phoenix_pubsub` to `liminara_core` or using `:pg` everywhere. Keeps core zero-external-deps. Observation depends on core, never the reverse. PubSub is correctly scoped.
- **ViewModel as pure module:** Event projection is a pure function (`apply_event/2`), not mixed into the GenServer. This makes unit testing trivial and allows reuse (e.g., a CLI observer could use ViewModel without the GenServer).
- **Dual key format handling:** ViewModel handles both atom-keyed events (from `:pg` broadcast) and string-keyed events (from `Event.Store.read_all`) via pattern-matched helpers. No normalization step needed.
- **GenServer.start (not start_link):** Server uses `GenServer.start` so callers aren't linked. Enables clean isolation testing (kill observer without crashing the test process).
- **Reverted Run.Server change:** The implementer had changed `:partial` → `:failed` in Run.Server. Reverted — `:partial` is an intentional design choice. Fixed the observation test instead.

### Open items

- None — milestone complete.
