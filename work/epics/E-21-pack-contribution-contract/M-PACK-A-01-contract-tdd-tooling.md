---
id: M-PACK-A-01
epic: E-21-pack-contribution-contract
parent: E-21a-contract-design
status: complete
completed: 2026-04-25
depends_on: E-19-warnings-degraded-outcomes
---

# M-PACK-A-01: Liminara-project Contract-TDD tooling

## Goal

Stand up the Liminara-project-local tooling that lets contributors author CUE schemas, fixtures, and ADRs as a TDD-shaped workflow — CUE in the devcontainer, local + pre-commit `cue vet` enforcement, the schema-evolution loop, the fixture-library directory layout, and Liminara-specific skill + rule files — so M-PACK-A-02a can land its first ADRs into a working harness.

## Context

E-19 (Warnings & Degraded Outcomes) has merged; ADR-OPSPEC-01 in M-PACK-A-02a will codify its warning shape, but no schema work can begin until the tooling that validates `.cue` files and walks fixtures exists.

Today the devcontainer (`.devcontainer/Dockerfile`) installs Elixir, Python via uv, and Node, but **not** CUE. There is no shared tool-versions file at the repo root, no pre-commit hook installed under `.git/hooks/`, no `docs/schemas/` tree, and no `.ai-repo/skills/design-contract.md` or `.ai-repo/rules/contract-design.md`. The design-contract authoring workflow is presently undocumented inside this repo; the parent sub-epic spec (`work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`) defines what that workflow must enforce, but nothing yet runs it.

The generic, project-agnostic version of this tooling — a framework `design-contract` skill skeleton plus ADR template field extensions for schema path / fixtures path / worked example path / reference implementation citation — is upstream framework work tracked at [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37). M-PACK-A-01 explicitly does not block on that issue: it ships only the Liminara-local files and tooling, which stand alone if the upstream issue lands later and become overlays on it if the upstream issue lands first.

## Acceptance Criteria

1. **Shared tool-versions file at repo root**
   - A single tool-versions file at the repo root pins the CUE version used by the devcontainer, the local invocation script, the pre-commit hook, and any future CI job. Format chosen and justified in *Design Notes* below.
   - The file is the single source of truth for the CUE version: changing the pinned version requires editing only this file.
   - The file's format is mechanically parseable (line-oriented `KEY=VERSION` or equivalent) so the Dockerfile, the local script, and the hook can all read it without language-specific tooling.

2. **CUE installed in the devcontainer from the pinned version**
   - `.devcontainer/Dockerfile` installs `cue` by reading the version from the shared tool-versions file (no separate hard-coded version literal in the Dockerfile).
   - After devcontainer rebuild, running `cue version` inside the container reports the pinned version exactly.
   - Re-pinning the version in the tool-versions file and rebuilding the devcontainer changes the installed `cue` version with no other Dockerfile edits required.

3. **Local invocation: a single, named entry point**
   - One make target or shell script (path locked in *Design Notes*) runs `cue vet` against any single `.cue` file passed as an argument and, with no argument, against the full fixture library under `docs/schemas/`.
   - The entry point exits non-zero on any `cue vet` failure and prints the failing fixture path + topic schema + CUE error message in the failure-semantics format specified in the parent sub-epic's "Schema-evolution check — specification" subsection (see `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`).
   - The entry point is invocable from a fresh shell with no prior `cd`; relative paths inside the script resolve from the repo root.

4. **Pre-commit hook installed and blocking on `cue vet` violations**
   - A pre-commit hook is installable via a single, idempotent command (re-running it is a no-op, never duplicates state, and never overwrites a contributor's existing customisations destructively — locked installation mechanism specified in *Design Notes*).
   - When staged changes include any `.cue` file, the hook runs `cue vet` against every staged `.cue` file and blocks the commit on schema violation.
   - When staged changes include any fixture under `docs/schemas/<topic>/fixtures/v<N>/`, the hook runs the schema-evolution loop (see AC 5) against the affected topic(s) and blocks on violation.
   - When staged changes include neither, the hook is a no-op (does not run `cue vet` over the whole tree).
   - `git commit --no-verify` continues to bypass the hook (developer escape hatch documented in the skill onboarding).

5. **Schema-evolution loop: layered on `cue vet`, invocable as part of the same hook**
   - The schema-evolution check is implemented as a loop (shell or mix task — language locked in *Design Notes*) that walks every fixture under `fixtures/v<N>/valid/` and runs `cue vet <topic>.cue <fixture>` against each fixture's HEAD topic schema. Invalid fixtures (under `fixtures/v<N>/invalid/`) are not part of the schema-evolution invariant — they remain rejected by construction — so the schema-evolution loop walks `valid/` only.
   - The loop is invocable on demand from the same entry point as AC 3, and runs automatically inside the pre-commit hook per AC 4.
   - The loop's failure output matches the failure semantics specified in the parent sub-epic's "Schema-evolution check — specification" subsection: `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>`.
   - The loop does not implement a separate validation engine — every validation is a `cue vet` invocation. Implementation is bounded to roughly the size envisioned by the parent sub-epic spec ("~20 lines"); the `valid/invalid/` split adds a second sub-walk with mirrored exit-code expectations, which doesn't materially expand the design — if implementation grows substantially beyond the budgeted size, it is a signal the design has drifted and review must reconcile.
   - At M-PACK-A-01's wrap, the fixture library is empty: M-PACK-A-02a lands the first schemas and fixtures. The loop must run cleanly (zero fixtures = zero failures = exit 0) against an empty library.

6. **Fixture library directory-layout convention established**
   - The convention `docs/schemas/<topic>/schema.cue` (paired schema) + `docs/schemas/<topic>/fixtures/v<N>/{valid,invalid}/<name>.yaml` (fixture under its authored schema-version subdirectory, segregated by expected `cue vet` outcome) is documented as the layout the local entry point and the schema-evolution loop expect. The `valid/invalid/` split converges with the upstream framework convention from ai-workflow#37 / PR #72; rationale and trigger are recorded in `work/decisions.md` D-2026-04-25-033.
   - The `docs/schemas/` directory exists at wrap with at least one placeholder marker (e.g. a top-level `README.md` describing the layout) so M-PACK-A-02a can plug in without needing to negotiate the directory shape.
   - The local entry point and the schema-evolution loop both discover topic directories by walking `docs/schemas/*/`; adding a new topic requires no edits to the entry point or the loop.
   - The local entry point's no-arg loop runs two sub-walks with mirrored exit-code expectations: every fixture under `fixtures/v<N>/valid/` must pass `cue vet` (exit 0); every fixture under `fixtures/v<N>/invalid/` must fail `cue vet` (exit non-zero). An invalid fixture that *passes* is a regression — the schema accepted a shape the contract author declared invalid — and is reported with a distinct failure-format string. The schema-evolution loop walks `valid/` only (invalid fixtures aren't part of the forward-compat invariant; they remain rejected by construction).

7. **Liminara-local `design-contract` skill exists at `.ai-repo/skills/design-contract.md`**
   - The skill is authored as a flat `.md` source file at `.ai-repo/skills/design-contract.md` — never as a hand-written folder-form output under `.claude/skills/design-contract/`. Folder-form output is produced solely by `./.ai/sync.sh`, not by hand.
   - The skill's content is **Liminara-specific bindings only**: references to Radar's documented behaviour, admin-pack's documented requirements (`admin-pack/v2/docs/architecture/`), Liminara's contract matrix at `docs/architecture/indexes/contract-matrix.md`, and reviewer rules for cross-pack pressure. The skill explicitly states that the generic workflow skeleton (draft ADR → schema → fixtures → worked example → reference implementation → review → merge) is upstream framework work (ai-workflow#37) and overlays this Liminara-local file once it lands.
   - The skill includes the pre-commit hook installation step as part of its onboarding checklist (the developer command from AC 4 is invoked there).
   - Wrap of this milestone does **not** require running `./.ai/sync.sh`; the source file is what the milestone ships. Generated outputs are produced by the next routine sync, not as part of this milestone's commits.

8. **Liminara-local `contract-design` rule exists at `.ai-repo/rules/contract-design.md`**
   - The rule is enforceable by the reviewer agent and binds the Liminara-specific reviewer discipline declared in the parent sub-epic's success criteria: anchored admin-pack citations, contract-matrix rows verified at wrap, boundary-library violations block compile, and the cross-pack-pressure rules described in `.ai-repo/rules/liminara.md`'s "Contract matrix discipline" section.
   - The rule references — by file path — the contract-matrix index at `docs/architecture/indexes/contract-matrix.md` and the parent sub-epic spec at `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`, so reviewer agents can chase citations without re-deriving them.
   - The rule does not duplicate generic-CUE-workflow content; that is the upstream framework skill's concern.

## Constraints

- **No code moves.** No file under `runtime/` is modified. No app under `runtime/apps/` gains, loses, or reshapes a module. The runtime executes exactly as it does at the start of this milestone.
- **No ADR content, schema, or fixture is authored in this milestone.** ADR-MANIFEST-01, ADR-PLAN-01, and the rest of the ADR set listed in the parent sub-epic's "ADRs produced" table are owned by M-PACK-A-02a/b/c. M-PACK-A-01 lands the harness; M-PACK-A-02a is the first to land artifacts into it.
- **No framework template edits.** `.ai/templates/adr.md` is not modified. ADR template field extensions are upstream framework work (ai-workflow#37); this milestone authors no overlay equivalents.
- **No CI changes.** `.github/workflows/` is not modified. Repo-wide CI integration is a separate, deferred initiative; the shared tool-versions pin from AC 1 is the future-CI hand-off mechanism.
- **No compatibility shims.** Per repo policy in `.ai-repo/rules/liminara.md`, shims are banned. The generic-vs-Liminara split for the `design-contract` skill is not a shim — it is two distinct, independently-shipped surfaces with documented overlay behaviour, not one surface preserving a lie about another.
- **No hand-written folder-form skill output.** `.claude/skills/design-contract/SKILL.md` is produced only by `./.ai/sync.sh`; it is not committed in this milestone's PR.
- **`--no-verify` remains a developer escape hatch.** This milestone does not gate the hook in a way that prevents bypass; CI-level un-bypassable enforcement is the deferred CI initiative's job.

## Design Notes

The decisions below are locked before implementation. The builder agent does not re-litigate them; if a constraint surfaces that demands a change, the builder pauses and asks rather than diverging silently.

- **Tool-versions filename and format.** Locked at **`.tool-versions`** (asdf/mise convention) at the repo root. One line per pinned tool: `<tool> <version>` (e.g. `cue 0.10.0`). Rationale: contributors with `asdf` or `mise` already installed get the pinned CUE version automatically when they `cd` into the repo; the file format is industry-standard, machine-parseable from the Dockerfile via `grep '^cue ' .tool-versions | awk '{print $2}'`, and editor-friendly. The Dockerfile parses it directly — no `mise` or `asdf` runtime is installed inside the devcontainer image; the parsing is two lines of shell. If a future tool needs a richer config than one version line, escalate to a follow-up; do not preemptively switch to `mise.toml`.
- **Local invocation entry point location.** Locked at `scripts/cue-vet` (POSIX shell) — single entry point, no Makefile dependency (the repo currently has no top-level `Makefile`), invocable from any cwd via `bash scripts/cue-vet [path]`.
- **Pre-commit hook installation mechanism.** Locked at a script under `scripts/install-cue-hook` that installs into `.git/hooks/pre-commit` idempotently: the hook script is a thin wrapper that calls `scripts/cue-vet` on the staged subset; if `.git/hooks/pre-commit` already exists from another source, the installer prints a clear notice and exits non-zero (does not silently overwrite). Re-running the installer when already installed is a no-op.
- **Schema-evolution loop language.** Locked at POSIX shell colocated with `scripts/cue-vet` — no mix task. Rationale: contributors editing schemas may not have the runtime/ Elixir build green; a shell-only loop runs in any environment with `cue` on the path. This matches the parent sub-epic's framing ("~20 lines of shell or elixir"; shell is the lighter choice).
- **Fixture-library directory-layout enforcement scope.** The convention is documented and the entry point + loop discover topics by walking `docs/schemas/*/`, but the convention is not separately validated by this milestone (no "is this a v<N> directory?" check). Validation comes from the fact that fixtures placed outside the convention will not be picked up by the loop — natural enforcement, not a second engine.
- **Skill onboarding installs the hook.** The hook is not installed automatically on devcontainer build (that would silently mutate the contributor's `.git/hooks/` without consent). Instead, `.ai-repo/skills/design-contract.md` includes the hook-install command in its onboarding checklist; contributors run it once when starting design-contract work.
- **Upstream framework dependency posture.** [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37) tracks the generic skill skeleton + ADR template extensions. M-PACK-A-01 ships a Liminara-local skill that stands alone today and overlays the generic skill if/when ai-workflow#37 lands. No conditional logic in `.ai/sync.sh` and no Liminara-side handling is needed: if upstream lands, the next sync produces a folder-form output that combines the generic skeleton with the Liminara overlay; if not, the Liminara file remains the only source.
- **Skill source-of-truth posture.** Per the memory note ("`.ai/skills/` is flat `.md` files; `.claude/skills/` is folders with `SKILL.md`") and the existing convention in `.ai-repo/skills/` (see `app-legibility.md`, `devcontainer.md`), the skill is authored as a flat `.md` only. The `./.ai/sync.sh` step that produces `.claude/skills/design-contract/SKILL.md` runs as a normal post-merge sync, not as a milestone artifact.

## Out of Scope

- **ADR template extensions.** Adding `schema_path`, `fixtures_path`, `worked_example_path`, or `reference_implementation` fields to `.ai/templates/adr.md` is upstream framework work tracked at [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37). If upstream lands first, M-PACK-A-02a's ADRs benefit directly. If upstream lands later, M-PACK-A-02a's ADR authors add the fields inline per ADR and backfill the template when upstream catches up. Either timeline is acceptable; M-PACK-A-01 does not gate either path.
- **Generic `design-contract` skill skeleton.** The reusable, language-/project-agnostic skill that any CUE-using contract project can adopt is the same upstream issue (ai-workflow#37). M-PACK-A-01 ships only the Liminara-specific overlay.
- **Repo-wide CI integration.** Adding a `cue vet` job to `.github/workflows/` is a separate, deferred initiative. The shared tool-versions file from AC 1 is the explicit hand-off mechanism: when CI lands, its `cue vet` job will read the same pin and drift between local and CI is eliminated by construction. Tracked in the parent sub-epic spec under "Future CI alignment (not gated by E-21a)".
- **Any ADR content, CUE schema, or fixture authoring.** All ADRs, schemas, and fixtures listed in the parent sub-epic's "ADRs produced" table are owned by M-PACK-A-02a (foundational), M-PACK-A-02b (running-systems), and M-PACK-A-02c (governance).
- **Contract-matrix row updates for the skill or rule files.** This milestone does not touch first-class contract surfaces (see *Contract matrix changes* below), so no rows are added, updated, or retired.
- **`./.ai/sync.sh` execution as part of this milestone.** Sync is a normal post-merge / on-demand operation, not a milestone artifact. The folder-form output `.claude/skills/design-contract/SKILL.md` is produced by the next sync run, not committed by this milestone.

## Contract matrix changes

None — this milestone does not touch contract surfaces.

Rationale: M-PACK-A-01 ships only Liminara-project-local **tooling** (devcontainer toolchain, scripts, hooks, skill, reviewer rule). It defines no schema, no wire shape, no behavioural contract over data, and no first-class contract surface as defined by `.ai-repo/rules/liminara.md`'s "Contract matrix discipline" section. The first contract-matrix row deltas in this sub-epic land in M-PACK-A-02a (foundational ADRs); M-PACK-A-02b and M-PACK-A-02c continue the deltas. Consistent with the parent sub-epic's success-criterion that "M-PACK-A-02a, M-PACK-A-02b, and M-PACK-A-02c each declare their contract-matrix row deltas as explicit acceptance criteria in the milestone spec".

## Dependencies

- **E-19 must be merged.** Per the parent sub-epic's *Dependencies* section. E-19 is currently merged on `main` (see `work/done/E-19-warnings-degraded-outcomes/`); this dependency is satisfied at the time of this spec.
- **No other milestone is a hard prereq.** M-PACK-A-01 is the first milestone in E-21a and runs against `main` (rebased onto whatever branch the sub-epic lands on per the parent epic's git workflow).
- **External dependency:** the chosen pinned CUE version must exist as a downloadable release at `cuelang.org/cue` distribution channels. Builder confirms during implementation.

## References

- Parent sub-epic spec: `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- Parent epic narrative: `work/epics/E-21-pack-contribution-contract/epic.md`
- Upstream framework issue (generic skill skeleton + ADR template extensions): [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37)
- Repo rules — contract matrix discipline + skill source convention: `.ai-repo/rules/liminara.md`
- Contract matrix index (referenced by AC 8): `docs/architecture/indexes/contract-matrix.md`
- Existing devcontainer toolchain (modified by AC 2): `.devcontainer/Dockerfile`
- Existing skill source-of-truth examples: `.ai-repo/skills/app-legibility.md`, `.ai-repo/skills/devcontainer.md`
- Reference milestone spec format: `work/done/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
