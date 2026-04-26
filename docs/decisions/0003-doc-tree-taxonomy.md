---
id: ADR-0003
title: Adopt bind-me/inform-me doc-tree taxonomy
status: accepted
date: 2026-04-24
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
---

# ADR-0003: Adopt bind-me/inform-me doc-tree taxonomy

## Context

The triggering question was small: `migrate.sh §3.1e` keeps flagging three unset path fields (`researchPath` / `architecturePath` / `specsPath`) in `.ai-repo/config/artifact-layout.json`. Silencing the check looked like a two-line diff.

Walking the `specsPath` value surfaced a deeper issue: this repo uses the word "spec" for at least three different artifact types, and the proposed location `docs/specs/` would reinforce the ambiguity. Pulling on that thread exposed two further issues:

- `docs/architecture/contracts/` is a legacy grouping that bundles three first-class doc types (policies, indexes, future schemas) under a single "contracts" label and buries them under `architecture/`, which per the truth discipline is supposed to hold "only live or decided-next architecture prose."
- The repo has no articulated distinction between artifacts the AI must *obey* when doing work, and artifacts the AI *reads for context* when iterating on design. The distinction exists implicitly — the shim policy binds authoring, `cue vet` will bind schemas, the truth model binds truth-source adjudication — but the directory structure doesn't express it.

The timing matters. E-21 (Pack Contribution Contract) is about to generate roughly 14 ADRs, 14 CUE schemas, multiple fixture sets, and several policy docs, all currently planned to land under the deep `docs/architecture/contracts/` path. Once those artifacts exist, the rename is several times the work it is now.

This ADR articulates the missing register distinction, fixes the misnamed grouping, and pre-routes E-21's downstream artifacts to coherent homes.

## Decision

**Organize `docs/` along two registers — bind-me (implementation) and inform-me (architecture) — and route each artifact class to the directory that matches its register.**

Two registers, each with multiple artifact classes:

**Implementation (bind-me)** — operational artifacts the AI must respect first. These *reject wrong work*: a schema rejects invalid data; a policy violation blocks authoring.

- `docs/governance/` — prose authoring rules for project artifacts (truth model, shim policy, future schema-evolution policy). Prose-binding on AI / human authors.
- `docs/schemas/` — CUE schemas with fixtures co-located as subdirectories: `docs/schemas/<topic>/schema.cue` + `docs/schemas/<topic>/fixtures/v<N>/`. Machine-validated via `cue vet`.

**Architecture (inform-me)** — design and reasoning artifacts the AI reads for context when iterating. These *inform right work*: they explain why the implementation is shaped as it is, without gating it.

- `docs/architecture/` — design prose (live or decided-next running-system descriptions).
- `docs/decisions/` — ADRs in Nygard form.
- `docs/research/` — exploration and investigation notes.
- `docs/history/` — archived architecture; context, not authority.
- `docs/analysis/` — strategic and compliance analysis.

**Priority rule:** implementation gates, architecture guides.

### Sub-decisions implied by the taxonomy

1. **Three files leave `docs/architecture/contracts/`.** Two are policies and move to `docs/governance/`; one is an inventory and moves to `docs/architecture/indexes/`.
   - `00_TRUTH_MODEL.md` → `docs/governance/truth-model.md`.
   - `02_SHIM_POLICY.md` → `docs/governance/shim-policy.md`.
   - `01_CONTRACT_MATRIX.md` → `docs/architecture/indexes/contract-matrix.md` — the matrix is primarily an inventory of contract surfaces (live source, approved next, drift guard), not a policy. The *discipline* of keeping it current is policy and stays in `.ai-repo/rules/liminara.md`; the matrix file itself is architecture-level inventory. E-24's planned `pack-contract-index` is the same artifact and is dropped from the plan; the renamed matrix is the index.
   - The empty `docs/architecture/contracts/` directory is removed.

2. **`docs/governance/` is for project-artifact governance; `.ai-repo/rules/` remains for AI/workflow process discipline.** Both are bind-me, but they bind different things. Rules in `.ai-repo/rules/` govern *how AI operates the workflow* (TDD, commit conventions, branch discipline); governance in `docs/governance/` defines *how project artifacts behave* (truth-source adjudication, shim allowance, schema evolution). The new rule text in `.ai-repo/rules/liminara.md` makes this distinction explicit.

3. **No `docs/specs/`.** The word "spec" is used in three narrow senses, separated by location: milestone specs live in `work/epics/`; design-intent prose lives in `docs/architecture/` once decided; Nygard ratification lives in `docs/decisions/`. Each sense has a natural home; a separate `specs/` directory would reintroduce the ambiguity.

4. **Schemas and fixtures co-locate.** `docs/schemas/<topic>/schema.cue` + `docs/schemas/<topic>/fixtures/v<N>/`. Single tree, single walk to read a contract and its examples.

5. **`NN_<descriptor>.md` formalized as the author-sequenced thinking convention.** Two-digit prefix encodes the order in which the author worked through the material. Applies in `docs/architecture/`, `docs/analysis/`, `docs/brainstorm/`, `docs/domain_packs/`, and `docs/research/`. Descriptor case differs by directory: uppercase-with-underscores in the first four; lowercase-with-underscores in `docs/research/`. Supporting material under these directories (indexes, references, derived docs) lives in named subdirectories with kebab-case filenames — example: `docs/architecture/indexes/contract-matrix.md`.

6. **`specsPath` is omitted from `.ai-repo/config/artifact-layout.json`.** The framework's three-way split of architect-skill output (research / architecture / specs) does not survive the truth discipline — a "decided-but-not-architecture" tier doesn't exist coherently. The framework removes `specsPath` upstream (M-DOCS-01); Liminara declines to configure it in the meantime. `migrate.sh §3.1e` continues to fire as an informational note until the framework PR lands.

## Alternatives considered

- **Keep the legacy `docs/architecture/contracts/` grouping and rename only conceptually.** Rejected: leaves the misclassification baked in. As E-21 generates downstream artifacts, every new schema and fixture would inherit a path that says "contracts" when the directory really holds three different things.

- **`docs/policies/` instead of `docs/governance/`.** Rejected as the directory name, but file names retain the `-policy` suffix where the artifact is a policy. The directory name `governance/` distinguishes from `.ai-repo/rules/` (process); individual instruments inside can still be policies (shim-policy.md, future schema-evolution-policy.md). Other names considered and rejected: `docs/rules/` (collides register-wise with `.ai-repo/rules/`), `docs/discipline/` (too abstract), `docs/binding/` (unusual).

- **Treat the contract matrix as a policy (move to `docs/governance/`).** Rejected: the file is 80% inventory (surface | live source | approved next | historical context) and 20% per-row drift-guard rules. By the taxonomy's own definition (a matrix row says *what the contract is and where its live source lives*; an ADR says *why*), the matrix is architecture-level inventory. The discipline rules around keeping it current are policy and stay in repo rules.

- **Split the matrix into governance + architecture (inventory + discipline).** Rejected as unnecessary surgery: the discipline already lives separately in `.ai-repo/rules/liminara.md` "Contract matrix discipline" section. The matrix file itself doesn't need splitting.

- **`docs/specs/` as a top-level directory for the architect skill's spec output.** Rejected: re-introduces the three-senses-of-spec ambiguity the rule text is explicitly resolving.

- **`specsPath: docs/architecture/`** (point architect-skill spec output into the curated architecture tree). Rejected: dilutes the quality bar of `docs/architecture/`, which holds curated live or decided-next prose. Architect output includes pre-ratification drafts.

- **`specsPath: docs/architecture/specs/`** (subfolder). Rejected in favor of removing `specsPath` upstream; the third class doesn't survive truth discipline regardless of which directory hosts it.

- **Top-level split for schemas and fixtures (`docs/schemas/` + `docs/fixtures/`).** Rejected: fixtures only exist in relation to a schema. Two top-level trees mean two-walk reads with no payoff. Co-location matches how schema repositories are typically organized (JSON Schema test suites, OpenAPI examples).

- **`docs/architecture/contract-matrix.md` at the top level (no `indexes/` subdir).** Rejected: top level of `docs/architecture/` is reserved for `NN_` author-sequenced thinking. Indexes and references are a different artifact class and live in subdirectories. `indexes/` may stay a one-file dir for a while; that's fine. Future indexes get a clear home.

- **Bulk-rename existing `NN_UPPERCASE.md` files in `docs/architecture/` to kebab-case.** Rejected as scope creep. The `NN_` convention is intentional (author-sequenced thinking); legacy files keep their numbers. New supporting material uses kebab in subdirs.

- **Leave `docs/architecture/contracts/` empty stub or symlink for backward compatibility.** Rejected: stubs and symlinks add layers; the redirect note in `docs/governance/README.md` is a cleaner bridge for frozen-record followers.

- **Sweep frozen surfaces (`work/done/`, `work/agent-history/`, prior `work/decisions.md` entries) to update old paths.** Rejected per the policy reaffirmed in D-2026-04-22-028: session records are accurate at time of writing and are not authoritative for current behavior. The redirect note bridges 404 risk.

## Consequences

**What becomes easier:**

- Artifact classes are legible at the directory level. A reader scanning `docs/` sees the bind-me / inform-me split immediately.
- The contract matrix has a coherent home (architecture-level inventory) and the discipline that maintains it has a coherent home (repo rules). The two pieces no longer pretend to be one artifact.
- E-21's downstream artifacts (schemas, fixtures, governance docs, ADRs) land at paths that accurately describe what they are. Fewer "where does this go?" decisions per artifact.
- The three senses of "spec" are disambiguated by location without needing per-document framing.
- Future structural articulation (e.g., the architect skill's spec/research split) has a clear precedent for what "register" means.

**What becomes harder:**

- Frozen surfaces (work/done/, work/agent-history/, prior decisions) link to old paths and now 404 unless the reader follows a redirect. The redirect note in `docs/governance/README.md` mitigates but doesn't eliminate this; some cognitive tax persists.
- Until the framework PR lands (M-DOCS-01), `migrate.sh §3.1e` continues to fire an advisory note about `specsPath` being unset.
- Generated framework adapters (`.claude/skills/wf-doc-lint/SKILL.md` and others) carry references to the old `01_CONTRACT_MATRIX.md` filename until the framework PR softens those example references and is re-synced. The references are example-pattern text, not hardcoded contracts; the staleness is cosmetic.

**What we accept:**

- A migration cost of two milestones (M-DOCS-01 framework prep + M-DOCS-02 doc-tree reorg) and ~40 reference substitutions across roughly 14 live files.
- The redirect stub in `docs/governance/README.md` lives long-term and is removable in a future cleanup once 404 risk feels vestigial.
- E-21 inherits maintenance of the renamed contract matrix (no separate pack-contract-index file); E-24's plan is amended in M-DOCS-02 Commit 4.

**Trigger to revisit:**

- When a new artifact class arises that doesn't fit either register cleanly (e.g., generated documentation, runtime-mutable data references, telemetry schemas).
- When the bind-me set grows to a point where one umbrella directory feels crowded (e.g., if `docs/governance/` reaches ten or more instruments and starts needing internal grouping).
- When external link traffic to old `docs/architecture/contracts/*` paths becomes non-trivial (unlikely; repo is not public).

## Validation

The taxonomy holds if every new bind-me artifact has a clear home in `docs/governance/` or `docs/schemas/`, and every new inform-me artifact has a clear home under one of the existing inform-me directories. A new artifact that needs neither is a signal to re-examine the register split.

Periodic check (annual or on major epic transitions): does the directory layout still match the artifact reality? If a directory has accumulated artifacts of mixed classes, surface that drift via `workflow-audit` or in epic-wrap review.
