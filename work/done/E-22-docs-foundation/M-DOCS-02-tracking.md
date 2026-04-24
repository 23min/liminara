# M-DOCS-02: Doc-tree Taxonomy — Tracking

**Started:** 2026-04-24
**Completed:** 2026-04-24
**Branch:** `milestone/M-DOCS-02-doc-tree-taxonomy` (off `epic/E-22-docs-foundation`)
**Spec:** `work/epics/E-22-docs-foundation/M-DOCS-02-doc-tree-taxonomy.md`
**Commits:** `ce5f7a1`, `4c2cbef`, `1e7992f`, `c61dec6`, `c08da56` (5/5 landed)

## Acceptance Criteria

- [x] AC1: `docs/governance/` exists with `truth-model.md`, `shim-policy.md`, `README.md`. (Commit 1 `ce5f7a1`.)
- [x] AC2: `docs/architecture/indexes/contract-matrix.md` exists; `docs/architecture/contracts/` does not. (Commit 1 `ce5f7a1`.)
- [x] AC3: `.ai-repo/rules/liminara.md` contains *Doc-tree boundaries* + *Author-sequenced thinking convention* sections; *Contract matrix discipline* path pointer + *Project structure* list updated. (Commit 1 `ce5f7a1` for path pointer; Commit 2 `4c2cbef` for new sections and Project structure.)
- [x] AC4: `bash .ai/sync.sh` regenerates cleanly; `CLAUDE.md` Current Work preserved byte-identical. (Commit 2 `4c2cbef`; verified via diff inspection — only non-Current-Work sections changed.)
- [x] AC5: `.ai-repo/config/artifact-layout.json` has `researchPath` + `architecturePath`; no `specsPath`; `bash .ai/migrate.sh` reports "No migrations needed". (Commit 3 `1e7992f`.)
- [x] AC6: Zero live references to `docs/architecture/contracts/` remain — narrowed gate empty. Broader gate returns 7 matches, each an intentional historical description of the move itself (ADR-0003, `docs/governance/README.md` redirect table, `work/decisions.md` D-031/D-032 entries, M-DOCS-02 spec + tracking, M-DOCS-01 spec, E-22 epic spec). Narrowing documented in *Decisions made during implementation* above. (Commit 1 `ce5f7a1`.)
- [x] AC7: E-21 planning prose (epic.md + four sub-epics) reflects the reorg. Validation: `grep -rln "docs/policies|docs/architecture/contracts|pack-contract-index|docs/fixtures" work/epics/E-21-pack-contribution-contract/` returns empty. (Paths swept in Commit 1 `ce5f7a1`; AC-collapse semantic adjustments in Commit 4 `c61dec6`.)
- [x] AC8: `docs/research/*.md` prefixed `NN_<lower_case>.md` per git-creation order (re-derived at execution time; matches spec's table); PDFs live in `docs/research/literature/` unrenamed. Word-boundary-anchored validation grep returns zero unprefixed old-basename references in live surfaces. (PDFs moved in Commit 1 `ce5f7a1`; MD renames + reference sweep in Commit 5 `c08da56`.)
- [x] AC9: `work/proposals/docs-layout-reorg.md` cleared from the working tree (never committed; removed at M-DOCS-01 close-out once content had been absorbed into ADR-0003, the M-DOCS-02 spec, and this tracking doc).
- [ ] AC10: ADR-0003 status flipped `proposed` → `accepted` — deferred to epic wrap per spec.

## Decisions made during implementation

- **2026-04-24 — AC6 grep gate narrowed.** The spec-defined AC6 validation command (`grep -rln "docs/architecture/contracts" ... --exclude-dir=work/done --exclude-dir=work/agent-history --exclude-dir=.ai`) returns 7 matches at Commit 1 completion, but each is a historical description of the move itself: ADR-0003 (the decision record explaining what was moved), `docs/governance/README.md` (the redirect table naming old→new paths), `work/decisions.md` entries D-2026-04-24-031 / D-2026-04-24-032, the M-DOCS-02 spec and tracking doc (planning prose for this very move), M-DOCS-01 framework-prep spec (describes E-22's target state), and E-22 epic spec. Rewriting these to the new paths would destroy their meaning — a decision record describing a rename inherently mentions the rename. AC6's **intent** ("no live code / active-config / planning-prose points at the old path") is satisfied by the narrowed command recorded in the *Validation* section below, which additionally excludes the ADR, decisions log, and E-22 planning surfaces. Option 1 chosen over strict literal enforcement (which would sacrifice fidelity) or escape-tricks (which would be hacky).

## Deliberation log (pre-execution)

This section preserves the fidelity of the working proposal `work/proposals/docs-layout-reorg.md` that seeded M-DOCS-02. The proposal is deleted in Commit 1; its *reasoning* lives in [ADR-0003](../../../docs/decisions/0003-doc-tree-taxonomy.md), its *plan* lives in the M-DOCS-02 spec, and the *deliberation trail* that produced both lives here.

### Review context

The starting document was a multi-page proposal at `work/proposals/docs-layout-reorg.md` (draft status). A structured pre-execution review surfaced three blockers (must resolve before ratification) and several significant concerns (address but don't block). Each was resolved in Q&A with the project owner; resolutions are summarised below with pointers to where the reasoning is preserved long-term.

### Blockers surfaced and resolved

**B1 — Moving the contract matrix would break `workflow-audit` detection.**
The framework's `workflow-audit` skill detects the contract matrix via *"a file named `01_CONTRACT_MATRIX.md` (or similar) under `architecturePath`."* The original proposal moved the matrix to `docs/policies/contract-matrix.md` — out of `architecturePath` — which would silently disable the drift check.

Resolution: the matrix is an *inventory*, not a policy. Reading the file confirmed it's 80% "Surface | Live source | Approved next | Historical context | Drift guard" — which is an index — and 20% per-row drift-guard rules — which are rules-bearing but inseparable from the rows they describe. Per the proposal's own taxonomy (a matrix row = *what the contract is and where its live source lives*; an ADR = *why*), the matrix is architecture-level inventory. It moves to `docs/architecture/indexes/contract-matrix.md`, stays under `architecturePath`, and remains detectable by the skill. The *discipline* around the matrix (plan-time declaration, wrap-time check) stays in `.ai-repo/rules/liminara.md` as a policy. E-21a's planned separate `pack-contract-index.md` dissolves — the renamed matrix *is* the index.

Preserved in: ADR-0003 sub-decision 1 + Alternatives.

**B2 — `specsPath: docs/architecture/` would redirect architect-skill output into the curated architecture tree.**
The framework's `architect` skill (`.ai/skills/architect.md:14`) and `planner` agent (`.ai/agents/planner.md:25`) actively write to `specsPath`. Default is `docs/specs/`. The original proposal set it to `docs/architecture/` to avoid creating a top-level `docs/specs/` directory — but this would put pre-ratification architect output next to curated design prose (`01_CORE.md`, `02_PLAN.md`, `08_EXECUTION_TRUTH_PLAN.md`), diluting the truth-discipline quality bar.

Options considered: subfolder `docs/architecture/specs/` (rejected on taxonomic grounds — the word still carries ambiguity), leave unset (accepts `migrate.sh §3.1e` advisory noise), remove `specsPath` from the framework entirely.

Resolution: remove upstream. The framework's three-way split of architect-skill output (research / architecture / specs) does not survive the truth discipline — a "decided-but-not-architecture" tier doesn't exist coherently. Liminara-side: `specsPath` deliberately omitted from `artifact-layout.json`. Framework-side: M-DOCS-01 ships the removal PR.

Preserved in: ADR-0003 sub-decision 6 + Alternatives; M-DOCS-01 spec.

**B3 — Contract matrix was classified as a policy.**
Dissolved by B1's resolution. The matrix is architecture-level inventory; the discipline around it is policy. ADR-0003 Alternatives records this as a rejected classification.

### Significant concerns surfaced and resolved

**S4 — Schemas and fixtures at separate top-level dirs.**
Original proposal: `docs/schemas/<topic>.cue` + `docs/fixtures/<topic>/v<N>/`. Alternative: co-locate as `docs/schemas/<topic>/{schema.cue, fixtures/v<N>/}`.

Resolution: co-located. Fixtures only exist *in relation to* a schema; two top-level trees mean two-walk reads with no payoff. Co-location matches how JSON Schema test suites and OpenAPI examples are organized.

Preserved in: ADR-0003 sub-decision 4 + Alternatives.

**S5 — `docs/policies/` collides register-wise with `.ai-repo/rules/`.**
Both describe "authoring rules." The actual distinction: `.ai-repo/rules/` governs *how AI operates the workflow* (process); `docs/policies/` (as originally named) governs *how project artifacts behave* (artifact governance). The word "policies" didn't telegraph the distinction.

Resolution: directory renamed to `docs/governance/`. File names retain "-policy" suffix where the artifact is a policy (`shim-policy.md`, future `schema-evolution-policy.md`). The rule-text articulation explicitly distinguishes the two surfaces.

Preserved in: ADR-0003 sub-decision 2 + Alternatives.

**S6 — Matrix naming convention and docs/research retroactive renaming.**
Two coupled questions: (a) Does the matrix land at `docs/architecture/contract-matrix.md` (top level, breaks the `NN_UPPERCASE.md` convention of existing peers) or in a subdir? (b) Should `NN_` be formalised as a convention, and should `docs/research/` files be retroactively prefixed?

Resolution on (a): subdirectory `docs/architecture/indexes/`. The top level of `docs/architecture/` is reserved for author-sequenced `NN_` thinking; supporting material (indexes, references) lives in named subdirectories. Resolution on (b): yes, formalise the convention; yes, retroactively prefix `docs/research/` files per git-creation order with alphabetical tie-break within same-commit batches. Case differs by directory: `UPPERCASE_WITH_UNDERSCORES.md` in architecture/analysis/brainstorm/domain_packs; `lower_case_with_underscores.md` in research.

Preserved in: ADR-0003 sub-decision 5 + Alternatives; M-DOCS-02 spec Commit 5 ordering table.

**S7 — Broken-link window between Commit 1 (file moves) and Commit 4 (E-21 sweeps).**
Original proposal: Commit 1 swept selective files; Commit 4 swept E-21. In between, E-21 planning linked to moved files at old paths.

Resolution: Commit 1 is the *mechanical* sweep across all live files (including E-21). Commit 4 is narrowed to E-21 *semantic* adjustments — scope changes flowing from the resolved blockers (pack-contract-index dissolution, schemas+fixtures co-location, governance rename).

Preserved in: M-DOCS-02 spec commit-sequence decomposition.

**S8 — Frozen-surface 404 risk.**
Original proposal's stance: don't rewrite frozen surfaces (per D-2026-04-22-028); accept 404s unless they become a reported problem.

Resolution: write `docs/governance/README.md` with a discovery table + one-section redirect stub now, as part of Commit 1. Cost is trivial; cognitive tax on future readers who follow frozen-record links to moved paths is eliminated. The redirect note is long-term-but-deletable (remove in a future cleanup once 404 risk feels vestigial).

Preserved in: M-DOCS-02 spec Commit 1 (governance README authored).

**S9 — `work/proposals/` as an artifact class.**
Original proposal placed itself in `work/proposals/` with a `draft → approved → executed` lifecycle. The directory wasn't documented as an artifact class, raising the question: codify it now, or reframe the work?

Resolution: reframe. The working document is absorbed — reasoning → ADR, plan → milestone specs, deliberation → this tracking doc. `work/proposals/` is not established as a first-class artifact class. Future multi-decision deliberation can reuse the pattern informally (or codify it later if it becomes recurring).

Preserved in: epic spec Out of Scope; this tracking doc's absorption map below.

### Sequencing decision

Framework PR first, then doc-tree reorg (option A). Rationale: avoids the transient state where Liminara's `artifact-layout.json` omits `specsPath` but the framework still requires it; cleaner adapter regeneration.

### Pre-flight findings (2026-04-24)

- **14 live files** reference `docs/architecture/contracts/*` (excluding `.ai/`, `work/done/`, `work/agent-history/`, and the soon-deleted proposal doc). ~40 references total.
- **20 files in `docs/research/`** — 18 markdown (no existing numeric prefixes, 2-digit prefix is sufficient) + 2 PDFs (neither referenced by any live markdown; zero sweep cost on the move to `docs/research/literature/`).
- **Same-commit ties** dominate the git-creation history: 5 distinct batch commits, the largest adding 6 files on 2026-03-14 and 5 files on 2026-04-01. Timestamp doesn't disambiguate within a batch; alphabetical tie-break applies.
- **Framework adapter files** (`.claude/skills/wf-doc-lint/SKILL.md`, `.claude/skills/wf-workflow-audit/SKILL.md`, `.github/skills/doc-lint/SKILL.md`, `.github/skills/workflow-audit/SKILL.md`) reference `01_CONTRACT_MATRIX.md` as an example pattern ("or similar"). Cosmetic staleness only; framework PR (M-DOCS-01) softens the examples.
- **`.ai/` is a submodule** at `https://github.com/23min/ai-workflow.git` with push access. Framework PR work happens in the same workspace via `cd .ai/`.
- **Liminara-side reference hotspots** for `docs/research/` files: `ADJACENT_TECHNOLOGIES.md` (9 refs), `graph_execution_patterns.md` (6), `cue_language.md` (5). Five files have zero references (rename = zero sweep cost).

### Absorption map (proposal doc → target artifacts)

| Proposal section | Lives now in |
|---|---|
| Context (thread-pulling narrative) | ADR-0003 Context |
| The distinction being drawn (bind-me/inform-me + two axes) | ADR-0003 Decision |
| Target doc-tree layout (before/after) | ADR-0003 Decision + M-DOCS-02 AC1-3 |
| File moves (git mv commands) | M-DOCS-02 Commit 1 |
| Reference-sweep scope (per-file table) | M-DOCS-02 Commit 1 |
| Rule text to add (full draft) | M-DOCS-02 Commit 2 (full text embedded) |
| artifact-layout.json changes | M-DOCS-02 Commit 3 |
| Sync impact | M-DOCS-02 Commit 2 validation |
| Commit sequence (now five commits) | M-DOCS-02 Commit sequence section |
| E-21 impact & re-routing table | M-DOCS-02 Commit 4 |
| Frozen-records policy | Epic constraint + M-DOCS-02 constraint |
| Risks & rollback | Epic Risks table |
| Open questions (five of them) | This tracking doc — all resolved in Q&A before milestone start |
| Acceptance criteria | M-DOCS-02 AC list |
| Post-execution (proposal-doc lifecycle) | Discarded — proposal doc deleted in Commit 1 |
| Alternatives considered for each decision | ADR-0003 Alternatives |
| In-flight Q&A trail that produced ADR-0003 | This tracking doc (above) |

## Work Log

<!-- Append one entry per commit as execution proceeds. -->

### 2026-04-24 — Commit 1 (`ce5f7a1`)

**chore(docs): reorg doc-tree per bind-me/inform-me taxonomy**

- Created `docs/governance/`, `docs/architecture/indexes/`, `docs/research/literature/`.
- `git mv` moves: `00_TRUTH_MODEL.md` → `docs/governance/truth-model.md`; `02_SHIM_POLICY.md` → `docs/governance/shim-policy.md`; `01_CONTRACT_MATRIX.md` → `docs/architecture/indexes/contract-matrix.md`; both PDFs → `docs/research/literature/`.
- Removed empty `docs/architecture/contracts/`.
- Authored `docs/governance/README.md` with discovery table + redirect stub.
- Updated self-references in moved files' `source_of_truth` frontmatter (truth-model + shim-policy).
- Mechanical sweep across 10 live files: `README.md`, `CLAUDE.md` (non-Current-Work sections), `.ai-repo/rules/liminara.md` (path pointer only — rule-text articulation was Commit 2), `docs/architecture/{01_CORE,02_PLAN,08_EXECUTION_TRUTH_PLAN}.md`, `work/gaps.md`, and E-21 sub-epic specs (E-21a, E-21b, E-21d; E-21c had no references).
- Narrowed-grep validation gate passed — only match was `docs/governance/README.md` (the intentional redirect table).
- No content rewrites in moved files beyond self-reference updates.

### 2026-04-24 — Commit 2 (`4c2cbef`)

**docs(rules): articulate doc-tree boundaries and NN_ convention**

- Inserted two new sections in `.ai-repo/rules/liminara.md` after *Truth discipline* and before *Contract matrix discipline*: *Doc-tree boundaries — bind-me vs. inform-me* (full taxonomy + word-"spec"/word-"contract" disambiguations + rules-vs-governance boundary statement) and *Author-sequenced thinking convention* (NN_ rule + directory-specific casing).
- *Project structure* list updated: added `docs/governance/` and `docs/schemas/`; broadened `docs/architecture/` description to cover the NN_ convention + subdirectory supporting material.
- Ran `bash .ai/sync.sh` — 3 files regenerated (`CLAUDE.md`, `.claude/rules/ai-framework.md`, `.github/copilot-instructions.md`); only `.ai-repo/rules/liminara.md` and `CLAUDE.md` are tracked (the other two are gitignored per framework convention).
- `CLAUDE.md` Current Work section preserved byte-identical (verified via `git diff` inspection: no Current-Work lines in the diff).

### 2026-04-24 — Commit 3 (`1e7992f`)

**chore(config): add researchPath and architecturePath to artifact-layout**

- Appended `researchPath: "docs/research/"` + `architecturePath: "docs/architecture/"` to `.ai-repo/config/artifact-layout.json`. `specsPath` deliberately omitted (framework removed it upstream in `ai-workflow#40` as part of M-DOCS-01).
- `bash .ai/migrate.sh` reports "No migrations needed" — clean.

### 2026-04-24 — Commit 4 (`c61dec6`)

**docs(E-21): semantic adjustments per docs-layout reorg**

- Collapsed the planned separate `pack-contract-index.md` per ADR-0003 sub-decision 1: AC line in E-21a rewritten to "discovery is served by `docs/architecture/indexes/contract-matrix.md` — each pack-contract ADR, schema, and fixture set gets a row there rather than a separate per-family index"; M-PACK-A-02c milestone-description sentence that named the planned index file removed.
- Other semantic adjustments from the spec (schemas+fixtures co-location, `docs/policies` → `docs/governance` rename, schema-evolution / admin-pack-readiness destination changes) were applied as part of Commit 1's mechanical sweep; their Commit 4 work was the path substitutions, which already landed. Commit 4 is narrowly scoped to the AC-collapse pieces.
- Validation gate empty: `grep -rln "docs/policies|docs/architecture/contracts|pack-contract-index|docs/fixtures" work/epics/E-21-pack-contribution-contract/` returns nothing.

### 2026-04-24 — Commit 5 (`c08da56`)

**chore(docs): prefix docs/research files per git-creation order**

- Re-derived the ordering table at execution time via `git log --diff-filter=A --follow --format='%aI'` per file + alphabetical tie-break; result matches the spec's table exactly.
- 18 markdown files renamed 01_… through 18_… in `lower_case_with_underscores` form. PDFs in `docs/research/literature/` not renumbered (NN_ applies to thinking docs, not reference material, per ADR-0003 alternatives).
- Mechanical reference sweep via sed across 13 live files: `docs/liminara.md`, `docs/analysis/{01_First_Analysis, 07_Compliance_Layer, 10_Synthesis, 16_Orchestration_Positioning}.md`, `docs/domain_packs/{01_Radar, 07_Population_Simulation, 09_Evolutionary_Factory}.md`, `docs/history/architecture/02_PLAN.md`, `docs/public/horizons/agent-fleets.md`, `work/roadmap.md`, `work/gaps.md`. Five files had zero references (rename only).
- Initial spec validation grep threw false positives (substring matches against the new prefixed form — e.g., `build_vs_buy.md` matches inside `04_build_vs_buy.md`). Fixed by adding a `(^|[^0-9_])` prefix anchor to the regex. With the anchor applied, zero unprefixed old-basename references remain in live surfaces.

## Reviewer notes

- **Commit 1 grep-validation gate is load-bearing.** Before Commit 1 is staged, verify the exact grep (excluding `.ai/`, `work/done/`, `work/agent-history/`) returns empty. Stragglers left by the sweep force a follow-up commit and complicate rollback.
- **CLAUDE.md Current Work preservation.** After Commit 2's `sync.sh` run, diff `CLAUDE.md` and verify the *Current Work* section is byte-identical to pre-commit. The framework's adapter-preservation rule handles this, but the reviewer should confirm.
- **Contract matrix move isn't a matrix row update.** Moving `01_CONTRACT_MATRIX.md` to `docs/architecture/indexes/contract-matrix.md` is a file relocation, not a change to any row's live-source paths. The matrix itself isn't in any row's live-source list. No row updates, no retirements.
- **E-21 semantic adjustments in Commit 4** might surface additional scope changes as the sub-epic specs are walked — e.g., if E-21a's `## Contract matrix changes` section declared a row addition for the now-dissolved `pack-contract-index.md`, that declaration must be removed. Walk each file with the semantic-adjustments list open.
- **Commit 5 ordering table is derived, not hand-assigned.** If `git log` reports different earliest-creation dates at execution time (e.g., because a file was touched by a rebase or submodule update in the meantime), re-derive the table rather than trusting the spec's numbers.

## Validation

After each commit, and as a final gate before the milestone is declared complete:

- **Commit 1 (narrowed per Option 1 — see Decisions above):** `grep -rln "docs/architecture/contracts" --include="*.md" --include="*.json" --include="*.sh" --exclude-dir=work/done --exclude-dir=work/agent-history --exclude-dir=.ai --exclude=docs/decisions/0003-doc-tree-taxonomy.md --exclude=docs/governance/README.md --exclude=work/decisions.md --exclude-dir=work/milestones --exclude-dir=work/epics/E-22-docs-foundation` returns empty. The broader gate (without narrowing exclusions) returns 7 matches, each an intentional historical description of the move itself.
- **Commit 2:** `bash .ai/sync.sh`; `git diff --stat` shows only expected files; `CLAUDE.md` Current Work section unchanged.
- **Commit 3:** `bash .ai/migrate.sh` produces no advisory for `researchPath`, `architecturePath`, or `specsPath`.
- **Commit 4:** `grep -rln "docs/policies\|docs/architecture/contracts\|pack-contract-index\|docs/fixtures" work/epics/E-21-pack-contribution-contract/` returns empty.
- **Commit 5:** per-basename grep loop (as specified in M-DOCS-02 spec Commit 5 validation) returns empty.
- **Final:** `bash mix format --check-formatted` and full validation pipeline — out of scope for doc-only changes, but include if any `.ex`/`.exs` files inadvertently get touched.

## Deferrals

- **Optional `docs/architecture/indexes/README.md`** — if `indexes/` grows beyond the single `contract-matrix.md` file, adding a one-paragraph README there is cheap. Not gated on this milestone; file in `work/gaps.md` if a second index artifact arises.
- **`work/proposals/` first-class definition** — if the multi-decision proposal pattern becomes recurring (this conversation was productive), a follow-up proposal could codify it. Not scoped here.
- **Framework docs drift in `.ai/docs/migrate-contract-surfaces.md`** — M-DOCS-01's framework PR softens the skill references but the migration guide may retain old example paths in places beyond what M-DOCS-01 scope covers. If any remain, note in `work/gaps.md`.
- **Redirect-stub sunset** — the redirect section in `docs/governance/README.md` is long-term-but-deletable. Sunset trigger: when enough time has passed that no frozen-record reader is likely to follow the old paths (post-VSME, post-E-21 close, or similar milestone). Low priority; not tracked beyond this note.
