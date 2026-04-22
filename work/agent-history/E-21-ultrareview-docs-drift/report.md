# E-21 Ultrareview: Docs Drift & Spec Consistency

**Date:** 2026-04-22
**Scope:** E-21 parent epic + E-21a/b/c/d sub-epic specs vs. `docs/architecture/`, `docs/decisions/`, `work/decisions.md`, and current code.
**Method:** Read-only cross-check. Code wins when docs and specs disagree.
**Prior ultrareview:** 2026-04-21 (findings applied in commit `37b81ee`). This pass focuses on drift + internal consistency not covered by that round.

## Summary

E-21 is internally well-composed: the four sub-epics cite each other consistently, the 17-ADR split across M-PACK-A-02{a,b,c} reconciles cleanly (4+5+8 = 17), dependencies are acyclic, and the load-bearing runtime claims (`Liminara.Pack.API.*` as a re-org of M-TRUTH-01 structs, TriggerManager replacing Radar's scheduler, MultiProvider landing in `ex_a2ui` submodule) match live code. Prior ultrareview fixes in commit `37b81ee` closed the obvious gaps (ADR-FILEWATCH-01 added, LiveView escape hatch deferred, terminal event taxonomy pinned to OPSPEC).

The most load-bearing finding is **F-C1**: E-21a introduces a new ADR naming scheme (`ADR-LA-01`, `ADR-MANIFEST-01`, …) but `docs/decisions/` holds only `ADR-001` and `ADR-007` (the latter still `draft`), and no ADR template addition is spec'd. The rest is mostly a **doc-update punch list** plus second-order spec inconsistencies worth tightening before M-PACK-A-01 starts.

## Critical findings

### F-C1 [missing-adr, drift] E-21a claims an "existing ADR convention" that does not exist
- **Spec:** `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md:92` — "Each ADR lives under `docs/decisions/` following the existing ADR convention".
- **Repo state:** `docs/decisions/` holds only `ADR-001-failure-recovery-strategy.md` and `ADR-007-visual-execution-states.md` (the latter `status: draft`, dated 2026-03-23, Phase 1 shipped in M-OBS-05a but still draft). No ADR-002..ADR-006, no `docs/architecture/contracts/schemas/` or `/fixtures/` directory, no `.ai-repo/templates/ADR.md`.
- **Impact:** Two ADR schemes will coexist (numeric vs. keyword-scoped); next-numeric-ADR policy is undefined.
- **Fix:** Add an M-PACK-A-01 acceptance criterion that explicitly decides ADR-naming policy, pins a template location, and either promotes/supersedes ADR-007 (draft for ~13 months).

### F-C2 [wrong-current-state, drift] `docs/architecture/01_CORE.md` still shows a Pack and Op contract that E-21 quietly supersedes
- **Doc:** `docs/architecture/01_CORE.md:234-253` (Pack — five callbacks including optional `init/0`) and `:127-164` (Op).
- **Code (truth):** `runtime/apps/liminara_core/lib/liminara/pack.ex:9-19` defines **only four callbacks** — `id/0, version/0, ops/0, plan/1`. **No `init/0` callback exists anywhere** despite `01_CORE.md:252-253` describing how House-Compiler would use it (L725-735 repeats the fiction). `01_CORE.md` frontmatter says `truth_class: live`.
- **Fix:** Correct the `init/0` drift now (it's currently aspirational in a file that claims to be live), and add an E-21d housekeeping checklist item to retire the Pack/Op sections or mark them `decided_next` while E-21a/b are landing. Currently E-21d L85-86 only commits to updating `roadmap.md` and `CLAUDE.md`.

### F-C3 [drift] Contract matrix has no row for pack/manifest surfaces
- **Doc:** `docs/architecture/contracts/01_CONTRACT_MATRIX.md` has seven rows. No row for **manifest, plan-as-data, surface declarations, trigger declarations, FS-scope, or secrets**.
- **E-21 spec coverage:** No sub-epic spec mentions extending `01_CONTRACT_MATRIX.md`. `00_TRUTH_MODEL.md:91-93` mandates: "Update the contract matrix when a contract surface changes ownership or status." E-21 creates six new contract surfaces; the matrix will go silent.
- **Fix:** Add explicit matrix-row deliverables to M-PACK-A-02a (`manifest`, `plan-as-data`, `op-execution-spec`, `wire-protocol`), M-PACK-A-02b (`surface-declaration`, `trigger`, `file-watch`, `fs-scope`, `secrets`), M-PACK-A-02c (`registry`, `executor-taxonomy`, `schema-evolution`, `layout`, `boundary`).

### F-C4 [inconsistency, sequencing] E-21d doesn't update the `01_CONTRACT_MATRIX.md` row for Radar dedup post-extraction
- **Doc:** `01_CONTRACT_MATRIX.md:25` cites `runtime/apps/liminara_radar/lib/liminara/radar/ops/dedup.ex` and `runtime/python/src/ops/radar_dedup.py` as **live sources**.
- **Spec:** `E-21d:68-74` requires zero Radar-specific code in Liminara post-extraction. The cited files will be gone.
- **Fix:** Add to M-PACK-D-02 housekeeping: "Update `01_CONTRACT_MATRIX.md` Radar-dedup row — delete, or change live-source paths to submodule-prefixed equivalents plus document the submodule-pinning convention for live-source references."

## Medium findings

### F-M1 [inconsistency] E-21b's "Credo boundary rules wired" is mechanically incompatible with today's credo config
- **Spec:** `E-21b:82` — "Credo boundary rules (per ADR-BOUNDARY-01) wired".
- **Repo state:** `runtime/.credo.exs` has no boundary rules and no `boundary` hex dep. Vanilla Credo doesn't enforce module-access rules.
- **Fix:** Either expand M-PACK-B-01 to add `{:boundary, ...}` (or custom Credo check), or move the criterion to where the dep naturally lands. ADR-BOUNDARY-01 in M-PACK-A-02c needs to spec the enforcement mechanism.

### F-M2 [drift] D-2026-04-02-018's trigger for promoting to `PackRegistry` is outdated
- **Decision:** `work/decisions.md` D-018: "When VSME arrives and also needs instances, the pattern promotes to runtime-level PackRegistry with two real examples to design against." Still `active`.
- **Reality:** E-21 parent epic moves `PackRegistry` ahead of VSME using admin-pack (E-22) as second-pack forcing function; `roadmap.md:93-94` flags this as explicit D-012 exception.
- **Fix:** New decision entry recording the VSME → admin-pack trigger swap, with D-018 marked superseded.

### F-M3 [drift] E-21b/M-PACK-B-03 deletes Radar's scheduler GenServer but doesn't spec the observability surface
- **Code (truth):** `runtime/apps/liminara_radar/lib/liminara/radar/scheduler.ex:19-22` exposes `next_run_at/1`, `last_run_at/1`, `run_now/1` — observability APIs consumed by the Radar UI.
- **Spec:** `E-21b:76-77` and `E-21d:99-101` replace the scheduler with a `:cron` TriggerManager trigger but don't state whether `TriggerManager` exposes equivalent observation APIs. E-21d's "no behavior changes" constraint (L60, L101) is silent on whether the "next scheduled run" UI element counts.
- **Fix:** Either add `next_fire_at/2` / `last_fire_at/2` to E-21b TriggerManager success criteria, or list the next-run UI element as an explicit "no behavior changes" exception in E-21d M-PACK-D-02.

### F-M4 [shim-violation risk] E-21b permits advisory FS-scope enforcement but doesn't record a removal trigger
- **Spec:** `E-21b:45, 79, 91` — FS-scope is advisory (warning on violation, no block). Hard enforcement is "E-12."
- **Shim policy** (`02_SHIM_POLICY.md:20-28`): shims need explicit naming + removal trigger + code comment.
- **Gap:** E-21b describes advisory enforcement without classifying it — reviewers could read it either as an intermediate contract (not a shim) or a shim with missing removal trigger.
- **Fix:** Either (a) explicitly state in E-21b M-PACK-B-03 "advisory is not a shim; it is the final MVP contract strengthened in-place by E-12" or (b) register it as a shim with E-12 M-ISO-01 as the named removal trigger.

### F-M5 [drift] `01_CONTRACT_MATRIX.md` warning-contract row is stale
- **Doc:** `01_CONTRACT_MATRIX.md:23` live-source says "No first-class runtime warning contract yet".
- **Reality:** E-19 is complete, `Liminara.Warning` (`runtime/apps/liminara_core/lib/liminara/warning.ex`) and `Liminara.OpResult` are live code, `run_partial` is a first-class terminal event per D-2026-04-20-025.
- **Fix:** Refresh row before M-PACK-A-02a — ADR-OPSPEC-01 will cite this row when inheriting the warning section.

### F-M6 [missing-adr / drift] ADR-007 is still `status: draft` and Phase 1 is presumably shipped
- `docs/decisions/ADR-007-visual-execution-states.md:4` status draft; M-OBS-05a (cited as Phase 1 carrier) complete per roadmap.
- **Fix:** Audit ADRs in M-PACK-A-01 tooling milestone. Promote or supersede ADR-007.

### F-M7 [drift] Two overlapping "decisions" surfaces — no policy about which lives where
- `work/decisions.md` holds 26+ entries; `docs/decisions/` holds 2 files. E-21a adds 17 more to `docs/decisions/`. No explicit demarcation.
- **Fix:** Add acceptance criterion to M-PACK-A-01 or parent epic spec recording the `work/decisions.md` vs `docs/decisions/` policy (near-term operational decisions vs. contract-shape ADRs) in `.ai-repo/rules/contract-design.md`.

## Minor findings / nice-to-have

- **F-L1** [shim-risk] `E-21b:67, 96` describes `Pack.API.*` as "namespace reorganization" but doesn't specify whether the final state is `Liminara.Pack.API.ExecutionSpec` (with old path deleted) or old path preserved as alias.
- **F-L2** [nothing-to-do] `ADR-001:74-76` `apply_error_policy` placeholder still accurate; E-21 doesn't change retry semantics. Listed for completeness.
- **F-L3** [nice-to-have] E-21b MultiProvider work correctly targets `ex_a2ui` submodule but doesn't cross-reference `ex_a2ui/ROADMAP.md`.
- **F-L4** [editorial] E-21a's ADR-OPSPEC-01 bundles per-op `ExecutionSpec` with per-run terminal event taxonomy — arguably two ADRs (`ADR-OPSPEC-01` + `ADR-RUNEVENT-01`). Either works.
- **F-L5** [missing-adr] No dedicated replay-contract ADR among E-21a's 17. Replay semantics touch `08_EXECUTION_TRUTH_PLAN.md`, D-023, and OPSPEC's `determinism.replay_policy`. E-21a should either claim "covered by OPSPEC" explicitly or add `ADR-REPLAY-01`.

## Doc-update punch list

Required (blocking E-21 wrap):
- `docs/architecture/01_CORE.md` — Pack/Op sections: fix `init/0` drift (F-C2), flag sections `decided_next` during landing, final rewrite M-PACK-D-02.
- `docs/architecture/contracts/01_CONTRACT_MATRIX.md` — add rows for 13 new surfaces across M-PACK-A-02{a,b,c}; refresh stale warning row (F-M5); update/delete Radar-dedup row post-extraction (F-C4).
- `docs/architecture/contracts/02_SHIM_POLICY.md` — resolve advisory FS-scope classification (F-M4).
- `docs/decisions/ADR-007-visual-execution-states.md` — resolve draft status (F-M6) before M-PACK-A-01 locks ADR conventions.
- `work/decisions.md` — new entry superseding D-018 trigger (F-M2).

Recommended:
- `docs/architecture/02_PLAN.md` — add E-21 subsection alongside `08_EXECUTION_TRUTH_PLAN.md` pointer.
- `.ai-repo/rules/contract-design.md` (new) — decisions vs ADR boundary (F-M7).
- `ex_a2ui/ROADMAP.md` — MultiProvider work-item cross-reference.

## Things that checked out
- Milestone arithmetic: 4+3+3+2=12; 4+5+8=17 ADRs. Parent, E-21a, and roadmap all agree.
- E-19 dependency satisfied (complete).
- M-TRUTH-01 `execution_spec/0` shape matches live `Liminara.ExecutionSpec` struct and ADR-OPSPEC-01 inheritance is coherent.
- Terminal event taxonomy (`run_completed`/`run_partial`/`run_failed`) backed by shipped code (`run/server.ex:778-780, 1171-1173`) and D-2026-04-20-025.
- All 13 Radar ops export `execution_spec/0` — E-21b's "Radar is the live validator" claim is feasible today.
- Sub-epic sequencing E-21a → {E-21b || E-21c} → E-21d is a clean DAG with consistent `depends_on` across frontmatter + body.
- "No pack LiveView" decision from prior ultrareview is well-propagated across parent + E-21a + E-21c + E-21d.
- admin-pack forcing-function architecture docs (`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `repo-layout.md`) exist and are citable.
