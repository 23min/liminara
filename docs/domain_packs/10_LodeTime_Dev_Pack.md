# Domain Pack: LodeTime Dev Process Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `lodetime.dev_pack`

---

## 1. Purpose and value

Domain pack that treats a codebase + its surrounding signals (CI, issues, PRs, architecture rules) as a **flowing system** and produces actionable dev-process and architecture insights.

Goal: something you can use daily as a consultant tool and later package via “domain packs” concept.

### Fit with the core runtime

Maps well to IR passes: snapshot repo → index/graph → analyses → reports/alerts; can also run as a fleet (scheduled checks).

### Non-goals

- Replace full IDEs or Sourcegraph.
- Implement a full build system.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is “agentic”). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Workspace Snapshot (`IR0`)

Repo snapshot, config, and input references (commits, PR refs).

**Artifact(s):**
- `dev.repo_snapshot.v1`

### Indexes & Graphs (`IR1`)

File index, symbol index, dependency graph, test map.

**Artifact(s):**
- `dev.code_index.v1`
- `dev.dep_graph.v1`

### Findings (`IR2`)

Rule findings (architecture, layering, dependencies), smells, hotspots.

**Artifact(s):**
- `dev.findings.v1`

### Recommendations (`IR3`)

Suggested actions (refactors, backlog items, PR drafts) with evidence links.

**Artifact(s):**
- `dev.recommendations.v1`

### Deliverables (`IR4`)

Dashboards/reports/PR comments. Side-effect gated.

**Artifact(s):**
- `dev.report_md.v1`
- `dev.pr_comment.v1`
- `dev.delivery_receipt.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`dev.snapshot_repo`** — *Deterministic w/ pinned env*, *side-effect*
  - Clone/fetch repo refs into snapshot artifact.
  - Inputs: `dev.repo_ref.v1`
  - Outputs: `dev.repo_snapshot.v1`
- **`dev.build_index`** — *Deterministic w/ pinned env*, *no side-effects*
  - Build symbol/dep/test indexes via external tooling.
  - Inputs: `dev.repo_snapshot.v1`
  - Outputs: `dev.code_index.v1`, `dev.dep_graph.v1`
- **`dev.analyze`** — *Pure deterministic*, *no side-effects*
  - Run analyses/rules; produce findings.
  - Inputs: `dev.dep_graph.v1`
  - Outputs: `dev.findings.v1`
- **`dev.recommend`** — *Nondeterministic but recordable*, *no side-effects*
  - LLM-assisted recommendation generation; record outputs.
  - Inputs: `dev.findings.v1`
  - Outputs: `dev.recommendations.v1`
- **`dev.publish`** — *Side-effecting*, *side-effect*
  - Post to PR/issue/wiki/slack. Gated.
  - Inputs: `dev.report_md.v1`
  - Outputs: `dev.delivery_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **LLM recommendation output**: Natural-language recommendations and proposed diffs (if any).
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay/diff and safety review.
- **Human acceptance of change**: Approve a PR comment or apply a patch.
  - Stored as: `decision.gate_approval.v1`
  - Used for: Side-effect gating.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Dependency graph explorer + rule violations overlay.
- Hotspot/time-series view (if integrating VCS history).
- Patch/diff review (if proposing code changes).
- Run diff and 'why changed' panel.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Repo tooling executor (ripgrep, tree-sitter, language servers, linters) in containerized workspace.
- Optional LLM executor for summarization/recommendations.

---

## 8. MVP plan (incremental, testable)

- Repo snapshot + file index + dependency graph for one language stack.
- A small set of architecture rules (layering, forbidden deps).
- Generate a report with evidence links.
- Schedule as a daily/weekly fleet deployment.

---

## 9. Should / shouldn’t

### Should

- Keep raw repo content out of LLM context by default; prefer derived findings + targeted snippets.
- Make all write actions gated and idempotent.

### Shouldn’t

- Don’t run arbitrary shell commands without policy allowlisting and sandboxing.

---

## 10. Risks and mitigations

- **Risk:** Tooling sprawl per language
  - **Why it matters:** Supporting many languages becomes a platform tax.
  - **Mitigation:** Start with one stack; define a tool abstraction; allow packs to bring their own analyzers.
- **Risk:** Security of repo credentials
  - **Why it matters:** Repo access tokens are high-value.
  - **Mitigation:** Secret isolation; least privilege; no secrets in prompts; audit logs.

---

## Appendix: Related work and competitive tech

- [LodeTime repo](https://github.com/23min/lodetime) — User project.
- [Semgrep](https://semgrep.dev/) — Static analysis.
- [GitHub CodeQL](https://codeql.github.com/) — Code scanning.
- [Sourcegraph](https://sourcegraph.com/) — Code search and intelligence.
- [OpenRewrite](https://docs.openrewrite.org/) — Automated refactoring.
