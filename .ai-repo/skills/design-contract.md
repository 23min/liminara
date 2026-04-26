# Design Contract — Liminara overlay

Liminara-specific bindings on top of the upstream `design-contract`
skill. The upstream skill (at `.ai/skills/design-contract.md`) carries
the tech-neutral 7-step workflow and the discipline behind each step;
this overlay adds the Liminara-local conventions, paths, and reviewer
expectations that don't generalize.

The upstream skill landed via [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37)
/ PR #72 (2026-04-25), with three deliverables: the tech-neutral
skill body, the first concrete recipe at
`.ai/docs/recipes/design-contract-cue.md` (which lifts Liminara's
E-21 work), and an additive `contract:` frontmatter block on
`.ai/templates/adr.md`. Read both upstream files first, then this
overlay; this overlay does not duplicate the workflow steps.

## Read in this order

1. `.ai/skills/design-contract.md` — the workflow shape + rationale.
2. `.ai/docs/recipes/design-contract-cue.md` — concrete CUE commands
   and conventions.
3. **This file** — Liminara path overrides + reviewer discipline.
4. `.ai-repo/rules/contract-design.md` — Liminara reviewer rule
   (enforced by the reviewer agent at PR review time).

## Liminara path overrides

Upstream defaults schemas and fixtures to `docs/architecture/contracts/`.
Liminara overrides this top-level prefix to `docs/schemas/` (the
`docs/architecture/contracts/` tree was retired in M-DOCS-02 per the
E-22 doc-tree taxonomy work). Beyond the prefix, Liminara matches
upstream's convention.

| Artifact | Liminara path |
|---|---|
| Authoritative schema | `docs/schemas/<topic>/schema.cue` |
| Valid fixtures | `docs/schemas/<topic>/fixtures/v<N>/valid/<name>.yaml` |
| Invalid fixtures | `docs/schemas/<topic>/fixtures/v<N>/invalid/<name>.yaml` |
| Worked example | inline in the ADR body, or `docs/architecture/contracts-examples/<topic>-walkthrough.md` if the example is large enough to merit its own file |

The `valid/invalid/` split converged with upstream's convention —
[`work/decisions.md` D-2026-04-25-033](../../work/decisions.md) carries
the rationale and the trigger date. Every contract surface ships at
least one of each: valid fixtures prove the schema accepts the right
shape; invalid fixtures prove its permissiveness has been thought
through. Without invalid fixtures, "the schema accepted something we
didn't intend" goes untested.

ADR target directory: `docs/decisions/`. ADR filename:
`NNNN-<slug>.md` (no `ADR-` prefix on disk; `id: ADR-NNNN` in
frontmatter). Per [D-2026-04-23-030](../../work/decisions.md). E-21's
keyword-scoped placeholder IDs (`ADR-MANIFEST-01`, etc.) become real
`ADR-NNNN` numbers when authored — grep `docs/decisions/` for the next
free number.

## Local validation

Liminara wraps the per-fixture vet loop and the schema-evolution check
in a single entry point:

```sh
scripts/cue-vet path/to/file.cue       # vet a single .cue file
scripts/cue-vet                        # walk the whole library:
                                       #   valid/ → must pass
                                       #   invalid/ → must fail
```

Pre-commit enforcement installs once with `scripts/install-cue-hook`.
The hook runs `cue vet` on staged `.cue` files and the schema-
evolution loop when staged fixtures fall under the canonical
`(valid|invalid)/` segment. `git commit --no-verify` continues to
bypass (developer escape hatch — CI-level un-bypassable enforcement
is the deferred CI initiative's job).

The `docs/schemas/README.md` placeholder documents the layout for
contributors who land here without reading the spec. M-PACK-A-02a
lands the first schemas + fixtures.

## Reviewer discipline

Liminara has four reviewer-attention rules that don't generalize and
therefore live here rather than upstream. The full statements live in
`.ai-repo/rules/contract-design.md`; this section names them so the
authoring contributor knows what the reviewer will check.

### 1. Anchored admin-pack citations on every pack-level ADR

Every pack-level ADR (ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01,
ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01,
ADR-SECRETS-01, ADR-CONTENT-01, ADR-LAYOUT-01, ADR-REGISTRY-01,
ADR-MULTIPLAN-01) cites a **specific file + section anchor** inside
`admin-pack/v2/docs/architecture/` — e.g.
`bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`. Not a
generic "see admin-pack" reference.

Today, `admin-pack/v2/docs/architecture/` is a future submodule (E-22,
after E-21 wraps). The cited anchor target may not yet exist on disk.
Authoring posture: **record the intended anchor anyway**. The ADR's
admin-pack citation is the contract for what E-22's authoring will
satisfy. The reviewer at E-22 follows every E-21 ADR's admin-pack
citation, reads the cited section in the now-real submodule, and
judges whether the E-21 ADR's design genuinely satisfied the cited
need. Anchors that don't materialize in admin-pack (or materialize
with content that doesn't match the citation) are a contract failure
caught at E-22 — but the discipline is established now, in this
overlay's authoring pattern, not retroactively.

ADRs whose secondary reference is *not* admin-pack (ADR-LA-01,
ADR-WIRE-01, ADR-BOUNDARY-01, ADR-EXECUTOR-01, ADR-EVOLUTION-01) are
not subject to this anchored-citation gate, but their secondary
reference still has to be substantive — not a TBD or generic gesture.

### 2. Contract-matrix row at wrap, every contract surface

Per `.ai-repo/rules/liminara.md` *Contract matrix discipline*: every
ADR that creates, modifies, or retires a contract surface lands a row
in `docs/architecture/indexes/contract-matrix.md` as part of the same
PR. The row carries the contract name, the live-source path of the
authoritative schema, the owning ADR, and the status. Rows pointing
at stale or moved live-source paths are a reviewer miss.

The milestone spec's `## Contract matrix changes` section declares
what rows the milestone will add/update/retire; the wrap-time check
verifies they actually landed.

### 3. Radar-primary, admin-pack-secondary reference structure

Liminara contract surfaces are exercised by Radar today. Admin-pack is
the time-displaced second-pack forcing function (it runs in E-22, but
its architecture docs at `admin-pack/v2/docs/architecture/` are
read-from for citation discipline during E-21 itself). Every
pack-level contract ADR's references therefore look like:

- **Primary reference:** the Radar surface that exercises this
  contract today (file:line citation into `runtime/apps/...`).
- **Secondary reference:** the admin-pack surface that will exercise
  this contract once it's authored (anchored citation into
  `admin-pack/v2/docs/architecture/` per rule 1).

A contract derived from Radar alone, with no admin-pack secondary
reference, is flagged as a **one-pack abstraction** at review and
either acquires the secondary reference or gets rejected. The
abstraction shape that survives one consumer rarely survives the
second; the secondary reference is the cheapest insurance against
designing-for-Radar.

### 4. Reference-implementation citations

Two acceptable shapes for the `contract.reference_implementation`
frontmatter field per the upstream skill's step 5:

- **Existing implementation:** `<file>:<line>` citation into
  `runtime/apps/...` or another committed source location. The cited
  code must demonstrate the contract on real work today. Pure-mock or
  test-only citations don't count.
- **Scheduled-to-exist implementation:** a Liminara milestone ID
  (`M-PACK-B-01b`, `M-PACK-C-03`, etc.) **plus** the named file or
  module the milestone will create. "Built in M-PACK-C-03" is too
  abstract; "`examples/file_watch_demo` built in M-PACK-C-03" is
  acceptable. The named-file binding is the deadline.

Acceptable scheduled references in E-21:
- `examples/file_watch_demo` (E-26 M-PACK-C-03; ADR-FILEWATCH-01).
- The admin-pack-shape proxy pack (E-25 M-PACK-B-01b loaded /
  M-PACK-B-03 executed; secondary validator for multi-trigger +
  multi-plan ADRs).
- Radar generated `pack.yaml` shim (E-25 M-PACK-B-01b; validator of
  ADR-MANIFEST-01's CUE schema against Radar's real shape).

TBD or "something demo-ish later" is rejected at review.

## Onboarding checklist

First-time contract author:

- [ ] Read `.ai/skills/design-contract.md` (workflow + discipline).
- [ ] Read `.ai/docs/recipes/design-contract-cue.md` (CUE commands +
      gotchas).
- [ ] Read this file (Liminara overrides + reviewer rules).
- [ ] Read `.ai-repo/rules/contract-design.md` (the rule the reviewer
      enforces; AC8).
- [ ] Skim `.ai-repo/rules/liminara.md` *Contract matrix discipline*
      (the matrix-row obligation).
- [ ] Run `bash scripts/install-cue-hook` once. Re-running is a no-op.
- [ ] When ready to author, draft the ADR with the upstream
      `templates/adr.md` `contract:` frontmatter block; pin the
      Liminara paths from the table above.

## Cross-references

- Parent sub-epic spec:
  `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`
- Contract matrix index:
  `docs/architecture/indexes/contract-matrix.md`
- Contract-matrix-discipline rule:
  `.ai-repo/rules/liminara.md` (search for "Contract matrix
  discipline")
- Reviewer rule (AC8):
  `.ai-repo/rules/contract-design.md`
- Layout convergence decision:
  `work/decisions.md` D-2026-04-25-033

## Sync caveat

This file is the **source of truth**. The folder-form skill output at
`.claude/skills/design-contract/SKILL.md` is generated by
`./.ai/sync.sh`; never hand-edit it. To update the overlay, edit this
file and run `bash .ai/sync.sh`. (Wrapping M-PACK-A-01 does not
require running sync — generated outputs are produced by the next
routine sync, not as part of this milestone's commits.)
