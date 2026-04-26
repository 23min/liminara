# `docs/schemas/` — CUE schemas + co-located fixtures

This is the fixture library for Liminara's contract surfaces. Every
first-class contract (manifest, plan, op-spec, surfaces, triggers, file-
watch, fs-scope, secrets, content-types, replay, …) gets a paired CUE
schema and a versioned fixture set here. ADRs under `docs/decisions/`
explain *why* each contract has its shape; this tree carries *what* the
contract is, in machine-checkable form.

Per topic: a single HEAD schema at `<topic>/schema.cue`, plus a
fixture set under `<topic>/fixtures/v<N>/{valid,invalid}/<name>.yaml`.
Fixtures are split by expected `cue vet` outcome: `valid/` fixtures
must pass; `invalid/` fixtures must fail. Fixtures freeze at the
schema version they were authored against. The layout converges with
the upstream framework convention from
[ai-workflow#37](https://github.com/23min/ai-workflow/issues/37) /
PR #72; rationale lives in `work/decisions.md` D-2026-04-25-033.

The layout, validation runner, and schema-evolution discipline below are
fixed conventions for the duration of E-21. They were locked in
M-CONTRACT-01 (the contract-TDD tooling milestone) and the first schemas +
fixtures land in M-CONTRACT-02.

## Layout

```
docs/schemas/
  <topic>/
    schema.cue                       # paired CUE schema for <topic>
    fixtures/
      v<N>/                          # schema-version subdirectory
        valid/                       # cue vet must accept (exit 0)
          <name>.yaml
        invalid/                     # cue vet must reject (exit non-zero)
          <name>.yaml
      v<N+1>/
        valid/
          <name>.yaml
        invalid/
          <name>.yaml
```

- **`<topic>`** is the contract identifier — usually the dotted-lower
  form of the corresponding ADR's subject (e.g. `manifest`, `plan`,
  `op-spec`, `content-namespace`). A new contract = a new top-level
  directory under `docs/schemas/`.
- **`schema.cue`** is the HEAD schema for the topic. It carries a
  `schema_version` field; bump per ADR-EVOLUTION-01's discipline (additive
  changes stay backward-compatible, breaking changes bump major + land a
  deprecation ADR).
- **`fixtures/v<N>/valid/`** holds fixtures authored against schema
  version `<N>` that the schema must continue to accept. They prove
  the schema accepts the right shape. Fixtures are **frozen at their
  authored version** — when a schema evolves, *new* fixtures go into a
  *new* `v<N+1>/valid/` directory; old fixtures stay in `v<N>/valid/`.
  The schema-evolution loop validates every historical valid fixture
  against HEAD `schema.cue` to catch unintended breaking changes.
- **`fixtures/v<N>/invalid/`** holds fixtures the schema must reject.
  They prove the schema's permissiveness has been thought through. An
  invalid fixture that *passes* `cue vet` is a regression — the schema
  silently accepted a shape declared invalid. Invalid fixtures are not
  part of the schema-evolution forward-compat invariant; they remain
  rejected by construction across schema versions.
- **At least one of each.** Every contract surface must ship at least
  one valid fixture and at least one invalid fixture. Without invalid
  fixtures, "the schema accepted something we didn't intend" goes
  untested — and that's the dominant contract-bug class.

Fixture filename — choose something descriptive (`canonical.yaml`,
`with-secrets.yaml`, `multi-plan.yaml` for valid; `missing-required.yaml`,
`wrong-type.yaml` for invalid). No naming gate beyond the `.yaml`
extension.

## Local validation

A single entry point runs both modes:

```sh
scripts/cue-vet path/to/file.cue       # vet a single CUE file
scripts/cue-vet                        # walk this whole library
                                       # (the schema-evolution loop)
```

The no-arg form runs two sub-walks per topic with mirrored exit-code
expectations: `valid/` fixtures must pass, `invalid/` fixtures must
fail. A regression in either direction emits a distinct format string.

Standard failure (a valid fixture rejected by `cue vet`):

```
<fixture path> fails against <topic>.cue at <schema path>: <CUE error>
```

Inverted failure (an invalid fixture accepted by `cue vet`):

```
<fixture path> in invalid/ unexpectedly passed against <topic>.cue at <schema path>
```

Both formats are pinned by the parent sub-epic spec
(`work/epics/E-21-pack-contribution-contract/E-24-contract-design.md` →
*Schema-evolution check — specification*).

## Pre-commit enforcement

The pre-commit hook (installed once via `scripts/install-cue-hook`) runs
`cue vet` on staged `.cue` files and runs the schema-evolution loop
when staged files include any fixture under
`docs/schemas/<topic>/fixtures/v<N>/`. The hook is a no-op when neither
condition is met, and `git commit --no-verify` continues to bypass it.
See the design-contract skill (`.ai-repo/skills/design-contract.md`) for
onboarding details.

## Topic discovery is automatic

Adding a new topic requires *no* edits to `scripts/cue-vet` or the
pre-commit hook — both walk `docs/schemas/*/` to find topic directories
and `docs/schemas/<topic>/fixtures/v*/*.yaml` to find fixtures. Drop a
new directory matching the layout above and the validation runner picks
it up.

## Status (as of M-CONTRACT-01 wrap)

This library is **empty by design**. M-CONTRACT-01 ships only the layout
convention, the runner, and the hook. M-CONTRACT-02 lands the first
schemas + fixtures (`manifest`, `plan`, `op-spec`, `replay`, `wire`),
followed by M-CONTRACT-03 (`surface`, `trigger`, `file-watch`, `fs-scope`,
`secrets`) and M-CONTRACT-04 (`content-namespace`, `executor`,
`schema-evolution`, `multi-plan`, `pack-layout`, `pack-registry`,
`language-agnostic`, `boundary`).
