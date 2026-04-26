# Contract Design — reviewer rule (Liminara)

This rule is enforced by the **reviewer agent** at PR review time on
any PR that lands or modifies a Liminara contract surface (ADR + CUE
schema + fixtures + worked example + reference implementation). It
codifies four reviewer-discipline assertions specific to Liminara that
the upstream tech-neutral skill at `.ai/skills/design-contract.md`
deliberately does not carry.

## Rule scope

This rule defines **what the reviewer enforces**. The upstream skill at
`.ai/skills/design-contract.md` defines **what the contract author
follows**. The Liminara overlay at `.ai-repo/skills/design-contract.md`
binds upstream's workflow to Liminara's path and policy choices.
Together: skill teaches authoring; this rule enforces reviewer-side
acceptance gates.

The rule does not duplicate the upstream 7-step workflow — chasing
that cross-reference is the author's job and the upstream skill's
content. A reviewer reading this file should land on four
assertions, not a workflow walkthrough.

## Assertion 1 — Pack-level ADRs cite admin-pack with file + section anchor

The pack-level ADRs in E-21 (ADR-MANIFEST-01, ADR-PLAN-01,
ADR-OPSPEC-01, ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01,
ADR-FSSCOPE-01, ADR-SECRETS-01, ADR-CONTENT-01, ADR-LAYOUT-01,
ADR-REGISTRY-01, ADR-MULTIPLAN-01) must each cite a **specific file +
section anchor** inside `admin-pack/v2/docs/architecture/`. Format:
`<file>.md §<section> — <description>` (e.g.
`bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`). A
generic "see admin-pack" reference fails this assertion.

**E-22-pending allowance.** `admin-pack/v2/docs/architecture/` becomes
a real submodule in E-22, after E-21 wraps. The cited anchor target
may not yet exist on disk during E-21 review. The reviewer accepts the
citation as a contract-for-future-content if and only if (a) the
file + section anchor is named with specificity, and (b) the
description articulates *what* the cited section is expected to
provide. Vague placeholders (`admin-pack-design.md §TBD`) fail this
assertion. The substance of the citation is verified against
materialized admin-pack content at E-22 by the same reviewer rule.

ADRs whose secondary reference is *not* admin-pack (ADR-LA-01,
ADR-WIRE-01, ADR-BOUNDARY-01, ADR-EXECUTOR-01, ADR-EVOLUTION-01) are
not subject to this anchored-citation gate. Their secondary reference
must still be substantive and not TBD; the reviewer applies a
weaker variant of the same discipline.

## Assertion 2 — Contract-matrix rows verified at wrap

Per `.ai-repo/rules/liminara.md` *Contract matrix discipline* (the
project rule that establishes the matrix), every milestone that
creates, modifies, or retires a contract surface declares its row
deltas in the milestone spec's `## Contract matrix changes` section.
The reviewer at wrap-milestone time:

- Verifies that every row declared in the spec's *Contract matrix
  changes* section landed in `docs/architecture/indexes/contract-matrix.md`
  with the correct columns (contract name, owning ADR, live-source
  path, status).
- Checks that the live-source path actually exists at the cited
  location (no rotted paths from a renamed or moved live source).
- Flags absent rows or rotted paths as **wrap-blocking**. The
  milestone does not wrap until the matrix matches its declared
  deltas.

For milestones that explicitly declare "None — this milestone does
not touch contract surfaces," the reviewer verifies the milestone
indeed didn't touch any first-class contract surface (a defensive
check against silent contract creation).

## Assertion 3 — Radar-primary / admin-pack-secondary structure

Pack-level contract ADRs in E-21 must structure their references as
two tiers:

- **Primary reference:** the Radar surface that exercises this
  contract today, cited as `<file>:<line>` into `runtime/apps/...`
  (or another committed source location). The cited code must
  demonstrate the contract on real work today, not in a test or mock.
- **Secondary reference:** the admin-pack surface that will exercise
  the contract once admin-pack is authored, cited per Assertion 1.

A pack-level ADR with only a Radar reference and no admin-pack
secondary fails this assertion as a **one-pack abstraction** — a
shape derived from a single consumer rarely survives the second
consumer's pressure, and the secondary reference is the cheapest
forcing function against designing-for-Radar. The reviewer either
requires the secondary reference to be added, or rejects the ADR.

ADRs that are deliberately Radar-only (ADR-WIRE-01 covers Radar's
existing port wire protocol; ADR-EXECUTOR-01 covers Radar's existing
`:inline` + `:port` taxonomy) are exceptions captured in the parent
sub-epic spec's *ADRs produced* table. The reviewer accepts the
exception when the table marks the ADR as primary-Radar-only with
secondary "—".

## Assertion 4 — Reference-implementation citation shapes

The `contract.reference_implementation` frontmatter field on a
contract-backed ADR must take one of two acceptable shapes.
**TBD is rejected.** "Built later" is rejected. "Something demo-ish
in a future epic" is rejected.

- **Existing implementation:** `<file>:<line>` citation into a
  committed source location (typically `runtime/apps/...`). The cited
  code must be a real, running implementation today — not test code,
  not a mock, not a draft branch.
- **Scheduled-to-exist implementation:** a Liminara milestone ID
  (`M-PACK-B-01b`, `M-PACK-C-03`, etc.) **plus** the named file or
  module the milestone will create. "Built in M-PACK-C-03" is too
  abstract; "`examples/file_watch_demo` built in M-PACK-C-03" is
  acceptable. The named-file binding is the contract deadline.

Acceptable scheduled references in E-21 (already vetted against the
parent sub-epic's *Technical direction* §4):

- `examples/file_watch_demo` — E-26 M-PACK-C-03 (ADR-FILEWATCH-01).
- The admin-pack-shape proxy pack — E-25 M-PACK-B-01b loaded /
  M-PACK-B-03 executed (secondary validator for multi-trigger +
  multi-plan ADRs).
- Radar generated `pack.yaml` shim — E-25 M-PACK-B-01b (validator of
  ADR-MANIFEST-01's CUE schema against Radar's real shape).

The reviewer at wrap-milestone time of the *cited* milestone (not
the ADR's own milestone) verifies the named file/module materialized.
Reference-impl deadlines that slip beyond their cited milestone get
either re-cited (with a follow-up decision-log entry) or the
authoring ADR is reopened.

## What the reviewer does not enforce

- **Authoring workflow steps.** The 7-step bundle-as-PR discipline
  (draft ADR → schema → valid + invalid fixtures → worked example →
  reference implementation → verify locally → open PR) is enforced by
  the upstream skill's checklist that the contributor follows.
  Reviewer side: the bundle either lands intact in the PR or doesn't.
  Missing artifacts in the PR are flagged as bundle-incomplete; the
  reviewer doesn't re-walk the workflow.
- **Per-CUE-language idioms.** Constraint syntax, `close()` discipline,
  default-merging gotchas, code-generation pipelines — all handled by
  the upstream recipe at `.ai/docs/recipes/design-contract-cue.md`.
  The reviewer reads `cue vet` output, not the contributor's CUE.
- **Schema-evolution-loop pass.** The pre-commit hook + CI both gate
  on this; by the time review starts, the loop has passed. The
  reviewer asserts the discipline (Assertion 2's wrap-time check
  covers it indirectly) but doesn't re-run the loop.

## References

- Upstream tech-neutral skill: `.ai/skills/design-contract.md`
- Upstream CUE recipe: `.ai/docs/recipes/design-contract-cue.md`
- Liminara authoring overlay (AC7):
  `.ai-repo/skills/design-contract.md`
- Contract-matrix index:
  `docs/architecture/indexes/contract-matrix.md`
- Contract-matrix discipline (parent rule):
  `.ai-repo/rules/liminara.md` *Contract matrix discipline* section
- Parent sub-epic spec:
  `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`
- Layout-convergence decision: `work/decisions.md` D-2026-04-25-033
