---
id: M-OTP-01-supervision
epic: E-08-otp-runtime
status: done
---

# M-OTP-01: Application and Supervision Tree

## Goal

Create the OTP application module and top-level supervision tree for `liminara_core`. After this milestone, `mix test` starts the application automatically, ETS tables are owned by dedicated processes (not the test process), and the supervision tree matches the design in `01_CORE.md`.

## Acceptance criteria

- [ ] `Liminara.Application` implements `Application` behaviour with `start/2`
- [ ] Supervision tree children (in start order):
  1. `Liminara.Artifact.Store` — GenServer or dedicated process owning the ETS table + filesystem root
  2. `Liminara.Event.Store` — process owning event store state (filesystem root)
  3. `Liminara.Decision.Store` — process owning decision store state
  4. `Liminara.Cache` — GenServer or dedicated process owning the ETS table
  5. `Liminara.Run.Registry` — `Registry` for mapping `run_id` → `Run.Server` PID
  6. `Liminara.Run.DynamicSupervisor` — `DynamicSupervisor` for Run.Server processes
- [ ] ETS tables are created by their owning processes, not by callers
- [ ] `mix.exs` declares `mod: {Liminara.Application, []}` so the app starts automatically
- [ ] Application starts cleanly: `Application.ensure_all_started(:liminara_core)` succeeds
- [ ] Stores accept a configurable root directory (for test isolation via `tmp_dir` or similar)
- [ ] Existing store modules are adapted to work both as supervised processes and in the current direct-call style (backward compatibility for existing tests during transition)
- [ ] All existing tests pass (may need adaptation for the new supervised startup)

## Tests

### Application startup
- Application starts without error
- All expected children are alive after startup
- Stopping the application stops all children

### Supervision tree structure
- `Liminara.Artifact.Store` is a child of the top-level supervisor
- `Liminara.Cache` ETS table exists after application start
- `Liminara.Run.Registry` is a `Registry` process
- `Liminara.Run.DynamicSupervisor` is a `DynamicSupervisor` with no children initially

### ETS table ownership
- ETS tables survive the death of a caller process (owned by the store process, not the caller)
- Restarting the Artifact.Store process recreates the ETS table

### Store configuration
- Stores use the configured root directory, not a hardcoded path
- Two test runs with different `tmp_dir` values don't interfere

### Backward compatibility
- Existing Artifact.Store tests pass (adapted for supervised startup)
- Existing Event.Store tests pass
- Existing Decision.Store tests pass
- Existing Cache tests pass

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Design notes

The current store modules (`Artifact.Store`, `Event.Store`, `Decision.Store`, `Cache`) use module-level functions that create ETS tables or write to the filesystem directly. The transition to supervised processes should:

- Wrap each store as a GenServer (or use `Agent`) that owns its ETS table and holds its root directory as state
- Keep the public API (`Artifact.Store.store/2`, `Event.Store.append/2`, etc.) unchanged — calls go through the named process
- Use `Application.get_env(:liminara_core, :store_root)` or init args for directory configuration

The key constraint: ETS tables must be owned by long-lived processes in the supervision tree, not by transient callers. This prevents table loss when a test process or Run.Server exits.

## Out of scope

- Run.Server (M-OTP-02)
- Event broadcasting (M-OTP-03)
- Crash recovery beyond basic supervisor restarts (M-OTP-04)

## Spec reference

- `docs/architecture/01_CORE.md` § "How it maps to OTP" — supervision tree diagram
- `docs/architecture/01_CORE.md` § "The BEAM-native storage stack"
