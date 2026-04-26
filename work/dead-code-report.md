# Dead-code Audit — 2026-04-26

**Scope:** epic change-set `main...epic/E-24-contract-design` (52 files; no active milestone branch, default-base = `main` per skill spec).
**Recipes:** elixir, python
**Tool exits:** elixir (ok), python (skipped — no files in scope)

## Recipe: elixir

**Change-set scope:** 5 files — umbrella `runtime/mix.exs` + 4 apps' `mix.exs`. No `.ex` source files touched on this branch (the E-24 epic-to-date is contract-tooling + framework + recipe scaffolding; the runtime code itself is unchanged).

**Tool run:** `cd runtime && MIX_ENV=dev mix compile --force` exited 0. The tracer surfaced **96 unused-function hints + 19 should-be-private hints** across the pre-existing tree. Per the skill's change-set discipline, none of these intersect with the files modified on this branch (mix.exs project config doesn't host the function-level code `mix_unused` traces). They are not findings of *this* audit — they form a baseline inventory for a future cleanup pass.

### Confirmed-dead suspects
*(none in change-set scope)*

### Tool-flagged-but-live
*(none in change-set scope)*

### Intentional public surface
*(none in change-set scope)*

### Needs judgement
*(none in change-set scope)*

### Blind-spot sweep
- **Orphan fixtures:** `runtime/apps/*/test/support/fixtures/` not touched; no fixture orphans introduced.
- **Stale ADRs:** ADR-0003 (`docs/decisions/0003-doc-tree-taxonomy.md`, modified) cites `docs/architecture/contract-matrix.md`, `00_TRUTH_MODEL.md`, `01_CONTRACT_MATRIX.md`, `02_SHIM_POLICY.md` — none exist on disk. Read in context: the first is named in the *rejected alternatives* section ("we considered this path"); the others are the OLD filenames being renamed *by this ADR* (lines 49–52: `X → Y` form). All correctly contextualized; **not** stale citations.
- **Helpers retained "for stability":** N/A (no `.ex` source in change-set).
- **Schema fields with no consumers:** `docs/schemas/` is README-only on this branch — schemas land in M-PACK-A-02a. No fields to sweep.
- **Deprecated aliases:** none.

### Out-of-scope baseline (informational; not part of this milestone's findings)

The 96 + 19 hints fall into four clusters worth flagging for whoever scopes the future cleanup pass. These are **not** findings of this audit — they would need their own change-set context (a milestone touching the relevant `.ex` files) to graduate to real findings. Transferring noteworthy items to `work/gaps.md` is a manual triage exercise outside this report.

- ~40 **Phoenix macro-generated** functions (`__components__/0`, `__live__/0`, `__phoenix_verify_routes__/1`, `__phoenix_component_verify__/1`, `__routes__/0`, `__forward__/1`, `__helpers__/0`, `__verify_route__/1`, `__checks__/0`, `__sockets__/0`, `__mix_recompile__?/0`). Runtime-resolved by Phoenix; expected false positives at every audit. Suppression candidates for the recipe's `unused: [ignore: …]` config if noise becomes a problem.
- ~20 **OTP `child_spec/1` / `start_link/1`** entries on `Liminara.*.Store`, `Liminara.*.Server`, `Liminara.*.Scheduler`. Invoked by supervisors; expected false positives.
- **`LiminaraWeb.__using__/1` quoted helpers** (`router/0`, `channel/0`, `controller/0`, `live_view/0`, `live_component/0`, `html/0`, `verified_routes/0`, `static_paths/0`). Used via `use LiminaraWeb, :name` — Phoenix's standard module pattern; expected false positives.
- **19 `should be private` flags worth real triage** — these are over-public functions where mix_unused saw no cross-module caller. A few worth examining when next touching that code: `Liminara.Run.Result.derive_degraded/2`, `Liminara.Plan.new/0`, `Liminara.Plan.add_node/4`, `LiminaraWeb.Router.browser/2`, `Liminara.Executor.Port.encode_request/3`, `Liminara.Event.Store.read_all/2`, `Liminara.Observation.Server.get_node/2`, `Liminara.Radar.Scheduler.ms_until_next/2`. Each becomes a finding when its file enters a milestone change-set.
- **Likely-genuine dead candidates** (similar caveat — flag at next change-set hit): `Liminara.Run.Cli.degraded_banner/1`, `Liminara.Run.Cli.maybe_print_degraded_banner/2`, `Liminara.Warning.severities/0`, `Liminara.Observation.Layout.compute/2`. Worth grep-confirming during M-PACK-A-02a if any are in scope; otherwise wait for the natural milestone that touches those files.

## Recipe: python

**Change-set scope:** 0 files. No `.py` touched on this branch.

Recipe skipped per skill spec ("if the filtered set is empty, write a per-stack section noting 'no files in scope this milestone'"). Tool not invoked; `uvx ruff` / `uvx vulture` availability remains unverified until a Python-touching milestone exercises this recipe.

### Blind-spot sweep
N/A — no Python in scope.
