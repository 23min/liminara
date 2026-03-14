# Domain Pack: Software Factory Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `software_factory`

---

## 1. Purpose and value

A pack for LLM-assisted and agentic software development: planning, code changes, tests, reviews, and publishing (PRs/commits/releases) with strict gating and provenance.

It’s a high-risk/high-reward pack that will heavily pressure security, tool boundaries, and multi-tenancy.

### Fit with the core runtime

Matches core concepts: repo snapshot artifacts, deterministic build/test ops, nondet LLM planning decisions, side-effect gates for writes and PRs.

### Non-goals

- Compete head-on with commercial IDE copilots as a UI product in v0.
- Run untrusted code in the control plane VM.

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

### Task Spec (`IR0`)

User intent, constraints, and success criteria; includes budget.

**Artifact(s):**
- `sf.task_spec.v1`

### Workspace Snapshot (`IR1`)

Repo snapshot + dependency lockfiles + toolchain manifest.

**Artifact(s):**
- `sf.repo_snapshot.v1`
- `sf.toolchain_manifest.v1`

### Plan / Patch Set (`IR2`)

Proposed change plan + diffs (possibly multi-commit).

**Artifact(s):**
- `sf.plan.v1`
- `sf.patchset.v1`

### Verification Results (`IR3`)

Test results, lint/format output, build logs, security scans.

**Artifact(s):**
- `sf.test_report.v1`
- `sf.build_log.v1`

### Publish Artifacts (`IR4`)

PR, commits, release notes, and receipts.

**Artifact(s):**
- `sf.pr_spec.v1`
- `sf.delivery_receipt.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`sf.snapshot_repo`** — *Deterministic w/ pinned env*, *side-effect*
  - Fetch repo to immutable snapshot artifact.
  - Inputs: `sf.repo_ref.v1`
  - Outputs: `sf.repo_snapshot.v1`
- **`sf.plan_changes`** — *Nondeterministic but recordable*, *no side-effects*
  - LLM planning; record outputs (plan + tool calls).
  - Inputs: `sf.task_spec.v1`, `sf.repo_snapshot.v1`
  - Outputs: `sf.plan.v1`
- **`sf.apply_patch`** — *Pure deterministic*, *no side-effects*
  - Apply diffs to workspace; produce patchset artifact.
  - Inputs: `sf.plan.v1`, `sf.repo_snapshot.v1`
  - Outputs: `sf.patchset.v1`
- **`sf.run_tests`** — *Deterministic w/ pinned env*, *no side-effects*
  - Run tests/build in sandbox; record logs as artifacts.
  - Inputs: `sf.patchset.v1`, `sf.toolchain_manifest.v1`
  - Outputs: `sf.test_report.v1`, `sf.build_log.v1`
- **`sf.open_pr`** — *Side-effecting*, *side-effect*
  - Open PR / push branch. Always gated + idempotent.
  - Inputs: `sf.pr_spec.v1`
  - Outputs: `sf.delivery_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **LLM plan and edits**: Plan, file selection, diffs, command suggestions.
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay + audit; also safety review for tool calls.
- **Human approval for write actions**: Approve patch apply / PR publish.
  - Stored as: `decision.gate_approval.v1`
  - Used for: Prevent unsafe side effects.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Workspace browser (read-only by default).
- Patchset/diff review UI (approve/reject hunks).
- Test log viewer and failing-test navigator.
- PR publishing gate (with idempotency preview).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- Sandboxed workspace executor (container/VM) for running commands and tools.
- Optional remote build/test workers.
- LLM executor with strict tool allowlists.

---

## 8. MVP plan (incremental, testable)

- Read-only analysis mode (no writes): plan + explain changes.
- Then gated patch apply to workspace snapshot → patchset.
- Then run tests and render a report.
- Only later: PR creation and multi-agent 'swarm'.

---

## 9. Should / shouldn’t

### Should

- Default to read-only tools; require explicit gate for writes and command execution.
- Record every tool call and result as artifacts/events.
- Enforce strict repo/workspace sandboxing per tenant.

### Shouldn’t

- Don’t give the LLM direct shell access without policy enforcement.
- Don’t treat the Git remote as the source of truth for run artifacts; keep your own artifact store.

---

## 10. Risks and mitigations

- **Risk:** Prompt injection via repo content
  - **Why it matters:** Malicious code/comments can manipulate agent behavior.
  - **Mitigation:** Treat repo text as data; separate 'read' from 'act'; require human approval for actions; tool allowlist.
- **Risk:** Credential leakage
  - **Why it matters:** Agents may inadvertently log tokens or include them in prompts.
  - **Mitigation:** Secret redaction; never include secrets in context; use scoped tokens; audit.
- **Risk:** Non-deterministic builds
  - **Why it matters:** Flaky tests make replay useless.
  - **Mitigation:** Pin toolchains; quarantine flaky tests; record run environment; verify replay mode.

---

## Appendix: Related work and competitive tech

- [Claude Code docs](https://code.claude.com/docs/en/overview) — Agentic coding tool.
- [GitHub Copilot coding agent](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent) — Hosted PR-based coding agent.
- [Cursor Agents](https://cursor.com/learn/agents) — Agentic IDE workflow.
- [Aider](https://github.com/Aider-AI/aider) — Terminal-based AI pair programmer.
- [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) — Multi-agent framework.
- [Model Context Protocol (MCP)](https://github.com/modelcontextprotocol/modelcontextprotocol) — Tool/context integration protocol.
