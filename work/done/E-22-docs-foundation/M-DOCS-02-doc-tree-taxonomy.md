---
id: M-DOCS-02-doc-tree-taxonomy
epic: E-22-docs-foundation
status: complete
depends_on: M-DOCS-01-framework-prep
completed: 2026-04-24
---

# M-DOCS-02: Doc-tree Taxonomy — Execute the Reorg

## Goal

Execute the bind-me / inform-me doc-tree reorg specified in [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md): move three legacy files out of `docs/architecture/contracts/` into their taxonomically correct homes, articulate the taxonomy in rule text, update `artifact-layout.json`, propagate semantic adjustments into E-21 planning, and retroactively prefix `docs/research/` files with the `NN_` convention.

## Context

M-DOCS-01 has merged and landed: the framework no longer requires `specsPath`, and the `01_CONTRACT_MATRIX.md` example references in framework skill docs have been softened. Liminara's `.ai/` submodule pointer is bumped and adapters are regenerated against the aligned framework.

M-DOCS-02 is the main event — the Liminara-side execution of the taxonomy. All deliberation on what to move, where, and why, is already locked in ADR-0003 (accepted alternatives + rejected alternatives documented there). This milestone is five atomic commits of surgical file-tree surgery, plus the reference sweep and rule-text articulation that make the new structure legible.

## Acceptance Criteria

1. **`docs/governance/`** exists and contains exactly three files at milestone close: `truth-model.md` (from `00_TRUTH_MODEL.md`), `shim-policy.md` (from `02_SHIM_POLICY.md`), and `README.md` (discovery table + redirect stub). The files' prose content is unchanged from the originals except for path self-references (first-line titles and internal cross-references to the other moved files).

2. **`docs/architecture/indexes/contract-matrix.md`** exists and contains the content of the former `01_CONTRACT_MATRIX.md` verbatim (only first-line title updated if it currently embeds the old numeric prefix). `docs/architecture/contracts/` does not exist.

3. **`.ai-repo/rules/liminara.md`** contains a new *Doc-tree boundaries* section and a new *Author-sequenced thinking convention* section. The *Contract matrix discipline* section's path pointer is updated to `docs/architecture/indexes/contract-matrix.md`. The *Project structure* list includes `docs/governance/` and `docs/schemas/` (the schemas entry describes the co-located fixture shape) and drops any now-dead entries.

4. **`bash .ai/sync.sh` regenerates cleanly** after the rule-text edits. Expected outputs: `CLAUDE.md` *Project-Specific Rules* section, `.claude/rules/ai-framework.md`, and `.github/copilot-instructions.md` all pick up the new sections and updated pointers with no un-preserved edits to the *Current Work* section of `CLAUDE.md`.

5. **`.ai-repo/config/artifact-layout.json`** contains `researchPath: docs/research/` and `architecturePath: docs/architecture/`. `specsPath` is not present. `bash .ai/migrate.sh` produces no advisory for any of `researchPath`, `architecturePath`, or `specsPath`.

6. **Zero live references** to `docs/architecture/contracts/` remain after Commit 1. Validation command (all must return empty):
   ```
   grep -rln "docs/architecture/contracts" --include="*.md" --include="*.json" --include="*.sh" \
     --exclude-dir=work/done --exclude-dir=work/agent-history --exclude-dir=.ai
   ```
   Exclusions: `.ai/` (framework source, M-DOCS-01 territory) and the two frozen-surface directories (per epic constraint).

7. **E-21 planning prose** (`work/epics/E-21-pack-contribution-contract/` — `epic.md` and all four sub-epic specs) reflects the reorg: no references to `docs/architecture/contracts/*`; no plan for a separate `pack-contract-index.md` (inherits the renamed contract-matrix); every schema/fixture path reference uses the co-located shape `docs/schemas/<topic>/{schema.cue, fixtures/v<N>/}`.

8. **Every `.md` file in `docs/research/`** is prefixed `NN_<lower_case_with_underscores>.md` per the order table in Commit 5 below. The two PDFs live in `docs/research/literature/` under their current filenames.

9. **The working proposal doc** `work/proposals/docs-layout-reorg.md` no longer exists (cleared from the working tree at M-DOCS-01 close-out; was never committed).

10. **ADR-0003 status** flips from `proposed` to `accepted` (done at epic wrap, not per-commit; listed here for acceptance-audit completeness).

## Commit sequence

Five atomic commits, executed in order. Each is independently `git revert`-safe.

### Commit 1 — `chore(docs): reorg doc-tree per bind-me/inform-me taxonomy`

**Goal.** Physical file moves + governance README + mechanical reference sweep across all live files. Leaves the repo in a state where the directory structure matches ADR-0003 but the rule text still describes the old shape (that is Commit 2's scope).

**File operations:**

```bash
# Create target directories (git will create them implicitly when the moves land)
mkdir -p docs/governance docs/architecture/indexes docs/research/literature

# Move the two policies to governance
git mv docs/architecture/contracts/00_TRUTH_MODEL.md docs/governance/truth-model.md
git mv docs/architecture/contracts/02_SHIM_POLICY.md docs/governance/shim-policy.md

# Move the contract matrix to its architecture-level index home
git mv docs/architecture/contracts/01_CONTRACT_MATRIX.md docs/architecture/indexes/contract-matrix.md

# Move the two PDFs to research/literature
git mv "docs/research/Designing Sound - Andy Farnell.pdf" "docs/research/literature/Designing Sound - Andy Farnell.pdf"
git mv "docs/research/MiroFish_ Swarm-Intelligence with 1M Agents That Can Predict Everything _ by Agent Native _ Mar, 2026 _ Medium.pdf" "docs/research/literature/MiroFish_ Swarm-Intelligence with 1M Agents That Can Predict Everything _ by Agent Native _ Mar, 2026 _ Medium.pdf"

# Remove the now-empty source directory (should succeed; rmdir fails on non-empty)
rmdir docs/architecture/contracts/
```

Note: the superseded working proposal doc `work/proposals/docs-layout-reorg.md` was never committed (always untracked); it was cleared from the working tree at M-DOCS-01 close-out once its content had been absorbed into ADR-0003 + M-DOCS-02 spec + M-DOCS-02 tracking. No `git rm` is needed; the path will not exist at M-DOCS-02 start.

**New file to author — `docs/governance/README.md`:**

```markdown
# Governance

Binding authoring rules for Liminara's project artifacts. See
[ADR-0003](../decisions/0003-doc-tree-taxonomy.md) for the full
bind-me / inform-me taxonomy.

## Instruments

| File | Purpose |
|------|---------|
| [truth-model.md](truth-model.md) | How Liminara adjudicates between competing truth sources (live code, specs, history). |
| [shim-policy.md](shim-policy.md) | When a backward-compatibility shim is allowed (and how it must be removed). |

Related architecture-level inventory:
- [docs/architecture/indexes/contract-matrix.md](../architecture/indexes/contract-matrix.md) — ownership and status of every first-class contract surface.

## Moved from `docs/architecture/contracts/`

The following files were relocated under ADR-0003. Frozen records
(work/done/, work/agent-history/, decisions.md entries D-001–D-030)
that link to the old paths are not rewritten; use this table to
resolve them.

| Old path | New path |
|----------|----------|
| `docs/architecture/contracts/00_TRUTH_MODEL.md` | `docs/governance/truth-model.md` |
| `docs/architecture/contracts/02_SHIM_POLICY.md` | `docs/governance/shim-policy.md` |
| `docs/architecture/contracts/01_CONTRACT_MATRIX.md` | `docs/architecture/indexes/contract-matrix.md` |
```

**Internal self-reference updates inside moved files:**

- `docs/governance/truth-model.md` — first-line title if it embeds the `00_` prefix or contains path self-references to other moved files; update any cross-reference to `02_SHIM_POLICY.md` → `shim-policy.md` (relative path within `docs/governance/`).
- `docs/governance/shim-policy.md` — same, for cross-references to `00_TRUTH_MODEL.md` → `truth-model.md` (relative path within `docs/governance/`).
- `docs/architecture/indexes/contract-matrix.md` — first-line title if it embeds the `01_` prefix.

**Mechanical reference sweep** across all live files listed below. Each old path is replaced with its new path. Run a final grep-validation gate after the sweep.

| File to sweep | Refs to old paths |
|---|---|
| `README.md` | `00_TRUTH_MODEL`, `01_CONTRACT_MATRIX`, `02_SHIM_POLICY`, `docs/architecture/contracts/` |
| `CLAUDE.md` | Same (note: *Current Work* section preserved; only mechanical refs touched) |
| `.ai-repo/rules/liminara.md` | `01_CONTRACT_MATRIX`, `docs/architecture/contracts/` (path pointer only; the rule-text articulation is Commit 2) |
| `docs/architecture/01_CORE.md` | `00_TRUTH_MODEL`, `01_CONTRACT_MATRIX` |
| `docs/architecture/02_PLAN.md` | `00_TRUTH_MODEL`, `01_CONTRACT_MATRIX`, `02_SHIM_POLICY`, `docs/architecture/contracts/` |
| `docs/architecture/08_EXECUTION_TRUTH_PLAN.md` | `01_CONTRACT_MATRIX`, `02_SHIM_POLICY`, `docs/architecture/contracts/` |
| `work/gaps.md` | `00_TRUTH_MODEL`, `01_CONTRACT_MATRIX`, `02_SHIM_POLICY`, `docs/architecture/contracts/` |
| `work/epics/E-21-pack-contribution-contract/epic.md` | Verify count during sweep |
| `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md` | `01_CONTRACT_MATRIX`, `docs/architecture/contracts/` |
| `work/epics/E-21-pack-contribution-contract/E-21b-runtime-pack-infrastructure.md` | `02_SHIM_POLICY`, `docs/architecture/contracts/` |
| `work/epics/E-21-pack-contribution-contract/E-21d-radar-extraction-and-migration.md` | `01_CONTRACT_MATRIX`, `02_SHIM_POLICY`, `docs/architecture/contracts/` |

Substitutions:
- `docs/architecture/contracts/00_TRUTH_MODEL.md` → `docs/governance/truth-model.md`
- `docs/architecture/contracts/02_SHIM_POLICY.md` → `docs/governance/shim-policy.md`
- `docs/architecture/contracts/01_CONTRACT_MATRIX.md` → `docs/architecture/indexes/contract-matrix.md`
- `docs/architecture/contracts/schemas/<topic>.cue` → `docs/schemas/<topic>/schema.cue` (E-21 planning prose only)
- `docs/architecture/contracts/fixtures/<topic>/<version>/` → `docs/schemas/<topic>/fixtures/v<N>/` (E-21 planning prose only)
- `docs/architecture/contracts/pack-contract-index.md` (E-21a planned) → collapse reference; the renamed contract-matrix is the index (semantic adjustment — see Commit 4)
- `docs/architecture/contracts/schema-evolution.md` (E-21d planned) → `docs/governance/schema-evolution-policy.md`
- `docs/architecture/contracts/admin-pack-readiness.md` (E-21d planned) → `docs/analysis/admin-pack-readiness.md`
- Bare directory references `docs/architecture/contracts/` → context-dependent (usually `docs/architecture/indexes/` for matrix-index talk, `docs/governance/` for policy talk, or `docs/schemas/` for schema talk; pick by surrounding sentence)

**Validation gate before commit:**

```bash
grep -rln "docs/architecture/contracts" --include="*.md" --include="*.json" --include="*.sh" \
  --exclude-dir=work/done --exclude-dir=work/agent-history --exclude-dir=.ai
# Must return empty output.
```

Generated adapter files (`.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`, `.claude/skills/…`, `.github/skills/…`) are *not* manually edited. They regenerate in Commit 2.

### Commit 2 — `docs(rules): articulate doc-tree boundaries and NN_ convention`

**Goal.** Articulate the bind-me / inform-me taxonomy and the `NN_` convention in `.ai-repo/rules/liminara.md`; regenerate adapters.

**Edits to `.ai-repo/rules/liminara.md`:**

Insert a new section after `## Truth discipline` and before `## Contract matrix discipline`:

```markdown
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
```

**Updates to the `## Contract matrix discipline` section** (existing lines 39-48):

- Replace the opening sentence's path: `docs/architecture/contracts/01_CONTRACT_MATRIX.md` → `docs/architecture/indexes/contract-matrix.md`.
- Any other occurrences of the old path in this section get the same substitution.

**Updates to the `## Project structure` list** (existing lines 94-103):

```diff
 ## Project structure
 
 - `docs/` — research, analysis, architecture, brainstorming
+- `docs/governance/` — binding artifact governance (truth model, shim policy, schema evolution)
+- `docs/schemas/` — CUE schemas with fixtures co-located as `<topic>/schema.cue` + `<topic>/fixtures/v<N>/`
 - `docs/architecture/` — active architecture, approved next-state plans; top-level `NN_` files are author-sequenced thinking, supporting material in subdirectories (e.g. `indexes/`)
 - `docs/history/` — archived architecture and superseded design material
 - `docs/analysis/` — strategic analysis, compliance, pack plans
 - `docs/decisions/` — Architecture Decision Records (ADRs)
 - `runtime/` — Elixir umbrella (liminara_core, liminara_observation, liminara_web)
 - `work/` — epics, milestones, tracking, roadmap
 - `work/done/` — completed epics
```

**Regeneration:**

```bash
bash .ai/sync.sh
```

Regenerated files to commit alongside the source edits:
- `CLAUDE.md` (Project-Specific Rules section; Current Work section preserved)
- `.claude/rules/ai-framework.md`
- `.github/copilot-instructions.md`

**Validation gate:**
- `git diff --stat` shows only the expected files touched.
- The regenerated *Current Work* section of `CLAUDE.md` is identical to pre-commit.
- No manual edits to generated adapter files are needed.

### Commit 3 — `chore(config): add researchPath and architecturePath to artifact-layout.json`

**Goal.** Make research and architecture output destinations explicit in config; deliberately omit `specsPath` (framework removed it in M-DOCS-01).

**Diff to `.ai-repo/config/artifact-layout.json`:**

```diff
 {
   "roadmapPath": "work/roadmap.md",
   "epicRootPath": "work/epics/",
   "epicSpecFileName": "epic.md",
   "milestoneSpecPathTemplate": "work/epics/<epic>/<milestone-id>-<slug>.md",
   "trackingDocPathTemplate": "work/milestones/tracking/<epic>/../<milestone-id>-tracking.md",
   "completedEpicPathTemplate": "work/done/<epic>/",
   "epicIdPattern": "E-{NN}[optional-letter]",
-  "milestoneIdPattern": "M-<TRACK>-<NN>"
+  "milestoneIdPattern": "M-<TRACK>-<NN>",
+  "researchPath": "docs/research/",
+  "architecturePath": "docs/architecture/"
 }
```

**Commit message body** references ADR-0003 sub-decision 6 and the framework PR merged in M-DOCS-01 (include the upstream PR URL when available).

**Validation gate:**

```bash
bash .ai/migrate.sh
```

No advisory output mentioning `researchPath`, `architecturePath`, or `specsPath`.

### Commit 4 — `docs(E-21): semantic adjustments per docs-layout reorg`

**Goal.** Update E-21 planning prose where the reorg's semantic decisions (not mechanical paths — those were swept in Commit 1) change scope or content.

**Semantic adjustments to make:**

1. **Drop the planned separate `pack-contract-index.md`.** Per ADR-0003 sub-decision 1, the renamed `contract-matrix.md` is the index. Locations to update:
   - `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md` — any acceptance criterion, surfaces-touched entry, or context reference to a separate `pack-contract-index.md` is replaced by "inherits maintenance of `docs/architecture/indexes/contract-matrix.md`." If the existing spec's *Contract matrix changes* section declared a planned row addition for the pack-contract-index as a surface, that declaration is removed (no new surface; the existing matrix *is* the index).

2. **Schema + fixture paths co-located.** Any E-21 prose describing separate top-level `docs/schemas/` and `docs/fixtures/` trees, or planning `docs/architecture/contracts/fixtures/`, is rewritten to `docs/schemas/<topic>/{schema.cue, fixtures/v<N>/}`.

3. **Governance directory name.** Any E-21 prose referencing `docs/policies/` (left over from earlier drafts) updates to `docs/governance/`.

4. **Schema-evolution policy destination.** Any E-21d reference to `docs/architecture/contracts/schema-evolution.md` → `docs/governance/schema-evolution-policy.md` (if not already swept in Commit 1).

5. **Admin-pack readiness doc destination.** Any E-21d reference to `docs/architecture/contracts/admin-pack-readiness.md` → `docs/analysis/admin-pack-readiness.md`.

**Files to review (walk each; edit if it contains semantic references matching the list above):**

- `work/epics/E-21-pack-contribution-contract/epic.md`
- `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- `work/epics/E-21-pack-contribution-contract/E-21b-runtime-pack-infrastructure.md`
- `work/epics/E-21-pack-contribution-contract/E-21c-pack-dx.md`
- `work/epics/E-21-pack-contribution-contract/E-21d-radar-extraction-and-migration.md`

**Validation gate:**

- E-21 planning files have no references to `docs/policies/`, `docs/fixtures/` (as a top-level dir), `pack-contract-index.md`, or `docs/architecture/contracts/`.
- Any "contract index" reference in E-21 prose points at `docs/architecture/indexes/contract-matrix.md`.

### Commit 5 — `chore(docs): prefix docs/research files per git-creation order`

**Goal.** Apply the `NN_<lower_case>.md` author-sequenced convention to `docs/research/` markdown files retroactively, using earliest git-creation date (alphabetical tie-break within same-commit batches).

**Ordering table** (derived from `git log --diff-filter=A --follow --format='%aI' -- <file> | tail -1`, with alphabetical tie-break within identical commit timestamps):

| New name | Current name | Earliest commit date |
|----------|--------------|----------------------|
| `01_adjacent_technologies.md` | `ADJACENT_TECHNOLOGIES.md` | 2026-03-14 |
| `02_a2ui_finding.md` | `a2ui_finding.md` | 2026-03-14 |
| `03_artifact_store_design.md` | `artifact_store_design.md` | 2026-03-14 |
| `04_build_vs_buy.md` | `build_vs_buy.md` | 2026-03-14 |
| `05_house_compiler_context.md` | `house_compiler_context.md` | 2026-03-14 |
| `06_project_origins.md` | `project_origins.md` | 2026-03-14 |
| `07_flowtime_liminara_convergence.md` | `flowtime_liminara_convergence.md` | 2026-03-19 |
| `08_graph_execution_patterns.md` | `graph_execution_patterns.md` | 2026-03-19 |
| `09_supply_chain.md` | `supply_chain.md` | 2026-03-19 |
| `10_cue_language.md` | `cue_language.md` | 2026-03-22 |
| `11_zvec.md` | `zvec.md` | 2026-03-22 |
| `12_a2ui_assessment.md` | `a2ui_assessment.md` | 2026-04-01 |
| `13_agent_frameworks_landscape.md` | `agent_frameworks_landscape.md` | 2026-04-01 |
| `14_alternative_computation_models.md` | `alternative_computation_models.md` | 2026-04-01 |
| `15_dataflow_systems_and_liminara.md` | `dataflow_systems_and_liminara.md` | 2026-04-01 |
| `16_mirofish_population_simulation.md` | `mirofish_population_simulation.md` | 2026-04-01 |
| `17_flyte_architecture.md` | `flyte_architecture.md` | 2026-04-02 |
| `18_scale_and_distribution_strategy.md` | `scale_and_distribution_strategy.md` | 2026-04-02 |

**Operations:**

```bash
# For each row of the table above:
git mv docs/research/<current_name> docs/research/<new_name>
# Then sweep references to the old basenames across live files (next step).
```

**Reference sweep** across live files (excluding `work/done/`, `work/agent-history/`, and `.ai/`). For each of the 18 files in the table, replace references to the old basename with the new prefixed basename. The most-referenced files are `ADJACENT_TECHNOLOGIES.md` (9 refs), `graph_execution_patterns.md` (6 refs), `cue_language.md` (5 refs); the full per-file reference list is in the M-DOCS-02 tracking doc's pre-flight section. Five files have zero live references and require only the rename.

**Validation gate:**

```bash
# No live references to any un-prefixed basename remain:
for basename in ADJACENT_TECHNOLOGIES.md a2ui_finding.md artifact_store_design.md build_vs_buy.md house_compiler_context.md project_origins.md flowtime_liminara_convergence.md graph_execution_patterns.md supply_chain.md cue_language.md zvec.md a2ui_assessment.md agent_frameworks_landscape.md alternative_computation_models.md dataflow_systems_and_liminara.md mirofish_population_simulation.md flyte_architecture.md scale_and_distribution_strategy.md; do
  grep -rln --include="*.md" --exclude-dir=work/done --exclude-dir=work/agent-history --exclude-dir=.ai "$basename"
done
# Must return empty output.
```

PDFs in `docs/research/literature/` are not renamed; their prior `git mv` in Commit 1 is the only change.

## Constraints

- **M-DOCS-01 must be complete** — framework PR merged, submodule bumped, adapters regenerated — before this milestone begins.
- **Frozen surfaces are not rewritten.** `work/done/`, `work/agent-history/`, and `work/decisions.md` entries D-001 through D-030 keep their old paths. The redirect stub in `docs/governance/README.md` bridges 404s. This policy is load-bearing (per D-2026-04-22-028) and must not be relaxed during execution.
- **Generated adapter files are not hand-edited.** Any drift in `.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`, `.claude/skills/**`, or `.github/skills/**` is resolved by running `bash .ai/sync.sh`. Manual edits would be overwritten.
- **The `Current Work` section of `CLAUDE.md`** must be preserved across Commit 2's sync regeneration. This is the framework's own adapter-preservation rule (`.ai/CLAUDE.md`, `sync.sh` behavior); verify the diff before staging.
- **Commit 1's grep-validation gate is non-skippable.** If residual references to `docs/architecture/contracts/` remain in live files after the sweep, fix them before committing. A Commit 1 that leaves stragglers forces a follow-up commit and complicates rollback.
- **No content rewrites** of the moved files beyond path self-references. Truth model, shim policy, contract matrix prose stays verbatim. The milestone is structural; any substantive prose change belongs elsewhere.
- **No new epics or milestones** spawned from this milestone. If further structural work surfaces during execution, capture it as a new entry in `work/gaps.md`.

## Design Notes

- All deliberated decisions and rejected alternatives are in [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md). Do not re-litigate; cite.
- The five-commit decomposition is deliberate: (1) physical surgery + mechanical sweep, (2) articulation, (3) config, (4) E-21 semantic adjustments, (5) research renumbering. Each represents a distinct kind of change. Do not bundle across boundaries.
- The decision-log entries D-2026-04-24-031 (reorg ratified) and D-2026-04-24-032 (`specsPath` omission rationale) are appended to `work/decisions.md` as part of Commit 2 alongside the rule-text articulation — they are *operational* records complementing ADR-0003's *reasoning* record.
- `work/proposals/` is not an established artifact class in Liminara. The working proposal `work/proposals/docs-layout-reorg.md` that seeded this epic was untracked throughout its lifetime and was cleared from the working tree once its content was absorbed into ADR-0003, this milestone's spec, and the tracking doc. No git deletion is part of M-DOCS-02. If a future contribution wants to use the "proposal" shape for multi-decision deliberation, it will need a first-class definition at that time (deferred to `work/gaps.md` if raised).
- Commit 5's PDF treatment (move to `docs/research/literature/` without prefix) was decided in ADR-0003 alternatives review: the `NN_` convention applies to author-sequenced *thinking* docs; PDFs are reference material, not thinking, so they live in `research/` without participating in the convention.

## Contract matrix changes

None — this milestone does not add, modify, or retire contract surface rows in the contract matrix. The rule text around contract matrix discipline is updated (path pointer), and E-21 planning prose is semantically adjusted, but no existing row's live-source paths change and no new contract surface is introduced.

## Surfaces touched

- **Moved:** `docs/architecture/contracts/{00_TRUTH_MODEL,01_CONTRACT_MATRIX,02_SHIM_POLICY}.md`, `docs/research/*.pdf`.
- **Created:** `docs/governance/{truth-model,shim-policy,README}.md`, `docs/architecture/indexes/contract-matrix.md`, `docs/research/literature/` (implicit via PDF moves), `docs/research/NN_*.md` (implicit via renames).
- **Removed:** `docs/architecture/contracts/`. (The working proposal `work/proposals/docs-layout-reorg.md` was cleared at M-DOCS-01 close-out; it was never committed and does not exist at M-DOCS-02 start.)
- **Edited (rule text):** `.ai-repo/rules/liminara.md`.
- **Edited (config):** `.ai-repo/config/artifact-layout.json`.
- **Edited (mechanical sweep):** `README.md`, `CLAUDE.md` (Project-Specific Rules — Current Work preserved), `docs/architecture/{01_CORE,02_PLAN,08_EXECUTION_TRUTH_PLAN}.md`, `work/gaps.md`, `work/decisions.md` (new entries only), `work/epics/E-21-pack-contribution-contract/{epic,E-21a-contract-design,E-21b-runtime-pack-infrastructure,E-21c-pack-dx,E-21d-radar-extraction-and-migration}.md`.
- **Regenerated (not manually edited):** `.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`, and the `CLAUDE.md` Project-Specific Rules section (via `sync.sh` in Commit 2).

## Out of Scope

- Framework-side changes (M-DOCS-01 territory).
- Creation of CUE schemas, fixtures, or the schema-evolution policy document (E-21 deliverables).
- Content rewrites of moved files beyond path self-references.
- Sweep of frozen surfaces (`work/done/`, `work/agent-history/`, prior `work/decisions.md` entries). Hard constraint.
- Bulk-renaming `NN_UPPERCASE.md` files in `docs/architecture/` (convention retained).
- Rename or normalization of PDF filenames in `docs/research/literature/`.
- Establishing `work/proposals/` as a first-class artifact class.
- Reviewing or modifying the non-E-21 semantic content of moved files' cross-referenced docs (e.g., if `docs/architecture/02_PLAN.md` mentions the truth model in a way that could be clearer, that's a separate improvement).

## Dependencies

- **M-DOCS-01** complete (framework PR merged, `.ai` submodule bumped in Liminara, adapters regenerated).
- [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md) in `proposed` or `accepted` status (either is sufficient to execute; `accepted` flip is part of epic wrap).
- Clean working tree on a milestone branch off the epic branch, per Liminara's git-workflow rules.
- `gh` CLI available for any framework-side interactions (but no framework-side changes in this milestone — M-DOCS-01 already merged).

## References

- [ADR-0003 — Adopt bind-me/inform-me doc-tree taxonomy](../../../docs/decisions/0003-doc-tree-taxonomy.md) — full taxonomy, alternatives, consequences.
- [E-22 epic spec](epic.md) — parent epic, sequencing, success criteria.
- [M-DOCS-01 spec](M-DOCS-01-framework-prep.md) — prerequisite milestone.
- `D-2026-04-22-028` in `work/decisions.md` — frozen-surface policy precedent.
- `D-2026-04-23-030` in `work/decisions.md` — reaffirmation of frozen-surface policy.
- `.ai/CLAUDE.md` — framework-side conventions (adapter preservation, sync.sh behavior).
- `work/milestones/tracking/E-22-docs-foundation/M-DOCS-02-tracking.md` — in-flight deliberation log + per-commit progress.
