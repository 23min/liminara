# Changelog

All notable changes to Liminara will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project has not yet cut a tagged release; everything to date lives under
[Unreleased].

## [Unreleased]

### Added

- **E-21 umbrella + peer-children pack-contract structure.** Pack contribution
  contract (E-21) split into umbrella epic plus four peer-epic children:
  E-24 Contract Design (active), E-25 Runtime Pack Infrastructure (planning),
  E-26 Pack DX (planning), E-27 Radar Extraction + Migration (planning).
  Connected via framework-native `parent: E-21` frontmatter on each child.
  See `work/decisions.md` D-2026-04-26-034.
- **M-CONTRACT-01 Contract-TDD tooling** (E-24, complete 2026-04-25). CUE in
  the devcontainer, `cue vet` script + pre-commit hook with the
  schema-evolution loop, the `docs/schemas/<topic>/fixtures/v<N>/{valid,invalid}/`
  fixture-library convention, the `.ai-repo/skills/design-contract.md`
  authoring overlay, and the `.ai-repo/rules/contract-design.md` reviewer rule.
  Fixture library is empty by design at wrap; M-CONTRACT-02 lands the first
  ADRs + schemas.
- **Doc-tree taxonomy reorganization** (E-22, complete 2026-04-24).
  `docs/governance/` for prose authoring rules, `docs/schemas/` for CUE schemas
  with co-located fixtures, `docs/architecture/` for live/decided-next design,
  `docs/decisions/` for ADRs (Nygard form, `NNNN-<slug>.md` filename pattern),
  `docs/research/` for exploration, `docs/history/` for archived material,
  `docs/analysis/` for strategic analysis. ADR-0003 documents the bind-me /
  inform-me register split.
- **Warnings & Degraded Outcomes** (E-19, complete 2026-04-21). First-class
  `:partial` terminal status with `run_partial` event type alongside
  `run_completed` / `run_failed`; per-node warnings on the fallback path; UI
  surfaces degraded outcomes consistently across CLI, Phoenix LiveView, and
  A2UI observation channels.
- **Execution-spec truth** (E-20, complete 2026-04-22). Unified
  `execution_spec/0` shape (`identity` / `determinism` / `execution` /
  `isolation` / `contracts` sections) replaces callback sprawl. M-TRUTH-01
  shipped the canonical Elixir-side contract; M-TRUTH-03 migrated Radar dedup
  to `:side_effecting` with `cache_policy: :none` + `replay_policy:
  :replay_recorded`.
- **Doc-lint bootstrap** (`docs/index.md`, `docs/log.md`, `metrics.json`,
  `docs/badges/*.svg`). First ever full pass on 2026-04-26: 86 docs cataloged,
  doc_health 79.
- **Filed upstream framework issues:**
  - [ai-workflow#99](https://github.com/23min/ai-workflow/issues/99) — Parent–child epic shape (`parent:` frontmatter +
    `child_of` edge); phase 1 landed via PR #101 and consumed by Liminara to
    execute the E-21 migration.
  - [ai-workflow#106](https://github.com/23min/ai-workflow/issues/106) — `diff-roadmap` false-positive on bare status
    keywords inside epic-description prose.
  - [ai-workflow#77](https://github.com/23min/ai-workflow/issues/77) — RFC: per-entity FSMs + LLM/engine boundary
    lifecycle architecture (deeper than #68 wiring); local design-history
    snapshot at `docs/architecture/proposals/lifecycle-fsm-engine.md`.

### Changed

- **`.ai/` framework submodule** advanced from `eff4e2a` (`wf-graph-v0.5.0`)
  to `3fce1cb` (`wf-graph-v0.9.0`) over the course of multiple bumps. Notable
  framework features now consumed:
  - `wf-graph` 0.9.0 with `add-epic`, `add-milestone`, `promote`, `rename`
    verbs and `child_of` edge support.
  - `contract-verify` 0.1.0 binary + `verify-contracts` skill (will activate
    when M-CONTRACT-02 lands the first contract bundles).
  - `check-contract-bundles` 0.1.0 binary + `workflow-audit §13`
    contract-bundle drift detection.
  - `design-contract` skill (tech-neutral) + CUE recipe + `contract:`
    frontmatter fields on the ADR template.
  - `wrap-milestone` and `wrap-epic` route status through `wf-graph promote`
    and gate on `verify-contracts` + reference-impl reality.
  - Updated `workflow-audit` with §7.2 capability-overlap and §7.3
    referenced-epic-absence checks.
- **Sub-epic anti-pattern retired in favor of native parent–child epics**
  (D-2026-04-22-029 superseded by D-2026-04-26-034). The previous shape —
  sibling-file specs under one folder + `composed_of:` listings — is replaced
  by umbrella + peer-epic children with `parent:` frontmatter. The umbrella
  retains the unifying narrative; each child is a normal peer epic with its
  own folder, branch, milestones, and lifecycle.
- **Branch model** for the active E-21 family: `epic/E-24-contract-design`
  carries the merged M-CONTRACT-01 work (renamed from
  `epic/E-21-pack-contribution-contract`). Future child epics get their own
  branches as they become active.
- **Fixture-library layout** converged on the upstream framework's
  `valid/invalid/` subdirectory split (`docs/schemas/<topic>/fixtures/v<N>/{valid,invalid}/`).
  Captured in D-2026-04-25-033.
- **ADR convention** locked to filename `NNNN-<slug>.md` (no `ADR-` prefix on
  disk) + frontmatter `id: ADR-NNNN` (4-digit zero-padded). Existing ADRs
  renamed accordingly. See D-2026-04-23-030.

### Fixed

- **`run_partial` event-type alignment.** `Run.Server.finish_run/2` previously
  emitted `run_failed` for both `:failed` and `:partial` terminal statuses,
  collapsing the warning signal across Phoenix LiveView, A2UI, and the runs
  index. Now emits `run_partial` distinctly; every consumer carries an
  explicit clause. (D-2026-04-20-025; M-WARN-04 phase 2.)
- **Radar dedup determinism contract.** Op was advertised `:pure` while
  mutating LanceDB history. Reclassified to `:side_effecting` with
  `cache_policy: :none` and `replay_policy: :replay_recorded`. (D-2026-04-05-023;
  M-TRUTH-03.)
- **Contract-tightening shim policy.** Production code does not carry
  accept-both fallback clauses to tolerate legacy fixture shapes; non-compliant
  fixtures get migrated to the spec, not the other way around. (D-2026-04-20-026.)

### Removed

- **`work/_templates/`** (all four entries — `ADR.md`, `epic.md`,
  `milestone.md`, `milestone-log.md`). Framework templates at
  `.ai/templates/{adr,epic-spec,milestone-spec,tracking-doc}.md` are now
  authoritative; `.ai-repo/templates/` left empty by design.
- **`docs/architecture/contracts/`** subtree. Doc-tree reorganization
  (M-DOCS-02) moved CUE schemas to `docs/schemas/` and the contract-matrix
  index to `docs/architecture/indexes/contract-matrix.md`.

### Security

- **Pending dependabot follow-through** under a future security epic
  (`work/gaps.md` "Dependabot: security vulnerabilities in Python
  dependencies"). One high (`lxml` XXE, GHSA-vfmq-68hx-4jfw) and one medium
  (`langchain-text-splitters` SSRF redirect bypass, GHSA-fv5p-p927-qmxr)
  open in `runtime/python/` and `integrations/python/` respectively. Neither
  exploitable in current usage patterns; planned bulk-resolution rather than
  one-off patches.

---

Older epics that landed before this changelog was started (E-01 through E-18,
E-22) are recorded in `work/done/` as completed-epic archives with their own
tracking docs; their narrative is in `work/roadmap.md`'s validated-phase
sections.
