# Liminara — Project Rules

## What this is

Liminara is **a runtime for reproducible nondeterministic computation**. It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently. Technically: a DAG of operations producing immutable, content-addressed artifacts, with nondeterminism captured as decision records, supervised by Elixir/OTP.

## Five core concepts

- **Artifact**: immutable, content-addressed blob (SHA-256). The edges in the DAG.
- **Op**: typed function (artifacts in → artifacts out) with a determinism class (pure, pinned_env, recordable, side_effecting).
- **Decision**: recorded nondeterministic choice (LLM response, GA selection, human approval, random seed). Enables replay.
- **Run**: an execution = an append-only event log + a plan (DAG of op-nodes). Events are the source of truth.
- **Pack**: a module providing op definitions and a `plan/1` function. (Reference-data callback `init/0` is approved-next; see `docs/architecture/01_CORE.md`.)

## Tech stack

- Elixir/OTP for control plane and orchestration
- ETS for hot metadata, filesystem for artifact blobs, JSONL for event logs
- ex_a2ui (Bandit + WebSock) for A2UI observation — no Phoenix needed
- Phoenix LiveView for primary web UI
- Ports/containers for compute plane (Python ops, external tools)
- Python ops via `:port` — uv for package management, ruff for linting, ty for type checking, pytest for tests

## Working rules

- **Never make assumptions on ambiguous decisions.** If something is unclear, could go multiple ways, or has downstream consequences — stop and ask.

## Truth discipline

- `work/roadmap.md` is the only current sequencing and build-plan source.
- `.ai-repo/config/artifact-layout.json` is the canonical artifact layout source for roadmap, epic, milestone, and tracking paths. Generated assistant surfaces must mirror it rather than redefine it.
- `docs/architecture/` contains only live or decided-next architecture. Historical material belongs in `docs/history/`.
- `docs/history/` is context, not authority.
- If current behavior is disputed, live code, tests, and canonical persistence specs win.
- If approved next-state behavior is disputed, the active epic or milestone spec plus decided-next architecture docs win.
- Compatibility shims are banned by default. Any exception needs a named removal trigger in the milestone spec and tracking doc.
- To change AI instruction behavior, edit `.ai-repo/` and run `./.ai/sync.sh`. Do not hand-edit generated instruction files except for the preserved `CLAUDE.md` Current Work section.

## Doc-tree boundaries — bind-me vs. inform-me

Liminara's `docs/` tree expresses two registers. Full reasoning in
[ADR-0003](../../docs/decisions/0003-doc-tree-taxonomy.md).

**Implementation (bind-me)** — operational artifacts the AI must respect
first. These *reject wrong work*: a schema rejects invalid data; a
policy violation blocks authoring.

- `docs/governance/` — prose authoring rules for project artifacts
  (truth model, shim policy, future schema-evolution policy).
  Prose-binding on AI / human authors.
- `docs/schemas/` — CUE schemas with fixtures co-located as
  subdirectories: `docs/schemas/<topic>/schema.cue` +
  `docs/schemas/<topic>/fixtures/v<N>/`. Machine-validated via `cue vet`.

**Architecture (inform-me)** — design / reasoning artifacts the AI
reads for context when iterating. These *inform right work*: they
explain why the implementation is shaped as it is, without gating it.

- `docs/architecture/` — design prose (live or decided-next
  running-system descriptions). Supporting material (indexes,
  references, derived docs) lives in named subdirectories.
- `docs/decisions/` — ADRs (Nygard form; `NNNN-<slug>.md` filename).
- `docs/research/` — exploration and investigation notes.
- `docs/history/` — archived architecture; context, not authority.
- `docs/analysis/` — strategic and compliance analysis.

**Priority rule.** Implementation gates, architecture guides. When the
AI is doing work, it respects implementation artifacts as a hard
surface and reads architecture artifacts as context.

**Rules vs. governance.** `.ai-repo/rules/` (this file and peers)
governs *how AI operates the workflow* — TDD discipline, branch
discipline, commit conventions, contract-matrix discipline.
`docs/governance/` defines *how project artifacts behave* —
truth-source adjudication, shim allowance, schema evolution. Both are
bind-me; the difference is process vs. artifact governance.

**On the word "spec".** Liminara uses it in three narrow senses,
separated by location:

- **Milestone specs** — acceptance criteria for implementation work;
  live under `work/epics/<epic>/<id>-<slug>.md`.
- **Design-intent prose** — "what-shall-be" descriptions; land in
  `docs/architecture/` as decided-next content once approved.
- **Nygard ratification** — "why we chose X's shape"; lands in
  `docs/decisions/` as an ADR.

There is deliberately **no `docs/specs/` directory.** The word's
ambiguity is resolved by location.

**On the word "contract".** Its components live in separate
directories, not under a single `contracts/` subtree:

- Contract-matrix discipline (the policy): this file, section below.
- Contract-matrix inventory (the index): `docs/architecture/indexes/contract-matrix.md`.
- Shim policy: `docs/governance/shim-policy.md`.
- CUE schemas (machine-enforceable encoding): `docs/schemas/`.
- Fixtures (test data): `docs/schemas/<topic>/fixtures/v<N>/`.

## Author-sequenced thinking convention

Files prefixed `NN_<descriptor>.md` (two-digit numeric prefix) are
top-tier thinking docs in author sequence. The number reflects the
order in which the author worked through the material; new files
take the next available number; existing files are not renumbered.

Descriptor case differs by directory:

- `docs/architecture/`, `docs/analysis/`, `docs/brainstorm/`,
  `docs/domain_packs/` — `NN_UPPERCASE_WITH_UNDERSCORES.md`.
- `docs/research/` — `NN_lower_case_with_underscores.md`.

Supporting material under these directories (indexes, references,
derived docs) lives in named subdirectories with kebab-case
filenames. Example: `docs/architecture/indexes/contract-matrix.md`.

## Contract matrix discipline

`docs/architecture/indexes/contract-matrix.md` is the live ownership/status index for every first-class contract surface in the runtime. Drift here is silent failure: new contracts ship without rows, retired contracts leave stale rows, live-source paths rot. The following rules apply to every milestone that touches a contract surface.

- **Plan-time declaration.** Any milestone that creates, modifies, or retires a contract surface **must** include a `## Contract matrix changes` section in its spec with three bullets: rows added, rows updated, rows retired. If none apply, write "None — this milestone does not touch contract surfaces." Missing section blocks spec approval.
- **Wrap-time check.** Before wrapping a milestone that declared matrix changes, the reviewer verifies that the declared rows are present in `contract-matrix.md` with correct live-source paths. Row absence blocks wrap.
- **Live-source accuracy.** When a live-source file in a matrix row is renamed, moved, deleted, or extracted to a submodule, the same PR updates the row. Finding drift after merge is a reviewer miss and should be noted in agent history.
- **Boundary with ADRs.** A matrix row points at *what the contract is and where its live source lives*; an ADR under `docs/decisions/` explains *why the contract has that shape*. The two always cross-reference but never overlap.

Until framework issue [ai-workflow#20](https://github.com/23min/ai-workflow/issues/20) lands plan-time template support + wrap-time doc-lint enforcement, this discipline is enforced by spec review and reviewer agent attention.

## Decision records — two surfaces, one policy

The framework prescribes two decision-recording surfaces (`.ai/rules.md`, `.ai/paths.md`, `.ai/skills/wrap-epic.md`, `.ai/skills/workflow-audit.md`). This repo follows the prescribed split:

- **`work/decisions.md`** — day-to-day structured entries (id, status, context, decision, consequences) appended as work proceeds. Scope: operational, sequencing, and tactical decisions. Lightweight, fast to write, reviewed in-session.
- **`docs/decisions/NNNN-<slug>.md`** (ADRs) — heavier ratifying records surfaced at wrap-epic per `.ai/skills/wrap-epic.md` Step 2. Scope: first-class boundaries, constraint changes, shim justifications, supersessions — any decision a future reader would regret missing. Follow the Nygard pattern (Context → Decision → Consequences + Nygard-standard status vocabulary) until framework issue [ai-workflow#19](https://github.com/23min/ai-workflow/issues/19) ships a canonical template.

For ratification of constraint drift, either surface counts (per `.ai/skills/workflow-audit.md`). When in doubt between the two, ask "would a future reader regret missing the reasoning?" — if yes, write an ADR.

## Validation pipeline (per language)

Before any commit, the appropriate validation must pass:

- **Elixir**: `mix format`, `mix credo`, `mix dialyzer`, `mix test`
- **Python**: `uv run ruff check .`, `uv run ruff format --check .`, `uv run ty check`, `uv run pytest`
- **JavaScript/TypeScript**: `prettier`, `eslint`, test runner
- **dag-map** (submodule): `npm test` (274 tests)

## Commit convention

Follow Conventional Commits v1.0.0:
```
<type>(<scope>): <short summary>

<optional body>

Co-Authored-By: GitHub Copilot <noreply@github.com>
```
Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`
Always include Co-Authored-By when GitHub Copilot contributed.

## Git workflow

- One worktree per epic, not per milestone
- Epic branch: `epic/<slug>`, milestone branch: `milestone/<id>` from epic branch
- Agents never push without human approval
- Merge strategy: squash per milestone (or per epic if milestones are small)

## Submodules

- `dag-map` — DAG visualization library (github.com/23min/DAG-map)
- `ex_a2ui` — A2UI protocol library (github.com/23min/ex_a2ui)
- `proliminal.net` — Company website (github.com/23min/proliminal.net)

## Project structure

- `docs/` — research, analysis, architecture, brainstorming
- `docs/governance/` — binding artifact governance (truth model, shim policy, schema evolution)
- `docs/schemas/` — CUE schemas with fixtures co-located as `<topic>/schema.cue` + `<topic>/fixtures/v<N>/`
- `docs/architecture/` — active architecture, approved next-state plans; top-level `NN_` files are author-sequenced thinking, supporting material in subdirectories (e.g. `indexes/`)
- `docs/history/` — archived architecture and superseded design material
- `docs/analysis/` — strategic analysis, compliance, pack plans
- `docs/decisions/` — Architecture Decision Records (ADRs)
- `runtime/` — Elixir umbrella (liminara_core, liminara_observation, liminara_web)
- `work/` — epics, milestones, tracking, roadmap
- `work/done/` — completed epics

## Domain packs (target sequence)

1. **Radar** (omvärldsbevakning) — daily intelligence briefing. Next to build.
2. **VSME** — SME sustainability reporting (first compliance pack)
3. **House Compiler** — design → manufacturing.
4. **DPP** — Digital Product Passport (Feb 2027 enforcement)

