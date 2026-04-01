# Roadmap: Closing the Gap with Squad

**Date:** 2026-02-26 (updated 2026-03-03)
**Context:** Prioritized improvements for ai-workflow v2, inspired by [Squad's](https://github.com/bradygaster/squad) architecture. Each item includes effort, impact, and whether it conflicts with ai-workflow's core philosophy (human-gated, multi-platform, zero-dependency).

---

## Priority 1: Persistent Memory

**What:** Add a `decisions.md` file (shared) and per-agent `history.md` files that agents read at session start and append to at session end.

**Why this is #1:** Every other improvement becomes more effective when agents remember prior context. Today, each session starts cold — the AI re-discovers project conventions, past mistakes, and architectural choices every time. This is the single highest-waste pattern in the current framework.

**What Squad does:** Each agent has `history.md` (project-specific learnings). The team shares `decisions.md` (cross-cutting choices). The coordinator loads relevant history on every spawn. Squad also prunes when context grows too large (~80K → 33K tokens in v0.4.0).

**What we'd do:**
- Add `work/decisions.md` — shared decision log, append-only, structured entries
- Add `work/agent-history/<agent>.md` — per-agent learnings (planner, builder, reviewer, deployer)
- Add a "Session Start" preamble to each agent: "Read `work/decisions.md` and `work/agent-history/<agent>.md` before starting"
- Add a "Session End" step to each skill: "Append any new decisions or learnings to the relevant file"
- Add a pruning guideline: when a history file exceeds ~200 lines, summarize and archive older entries

**Effort:** Low — markdown files + agent instruction updates. No tooling changes.
**Impact:** High — compounds value over time. Agents get smarter with use.
**Philosophy conflict:** None. Memory is passive (files on disk). Human still gates all commits.

---

## Priority 2: Coordinator / Intent Router

**What:** Add a coordinator agent (or a routing preamble in `copilot-instructions.md`) that matches user intent to the right agent + skill without requiring the user to type `@builder` or `@planner`.

**Why this is #2:** This is ai-workflow's biggest architectural gap vs Squad. Currently, routing depends entirely on the host platform's agent picker, which works inconsistently. Users shouldn't need to know the framework's internal structure to use it.

**What Squad does:** A 1,147-line coordinator prompt reads the team roster, evaluates the request, selects a Response Mode (Direct / Lightweight / Standard / Full), and spawns the right agent. The user just describes the task.

**What we'd do (two options):**

*Option A — Lightweight routing table (recommended):*
- Add a routing section to `copilot-instructions.md` and `.claude/rules/ai-framework.md`:
  ```
  ## Routing
  | User says something like... | Route to | Skill |
  |---|---|---|
  | "plan", "design", "scope", "epic", "architecture" | planner | plan-epic or architect |
  | "build", "implement", "code", "start milestone" | builder | start-milestone, tdd-cycle |
  | "review", "check", "validate", "wrap" | reviewer | review-code, wrap-milestone |
  | "release", "deploy", "tag", "publish" | deployer | release |
  | "fix", "patch", "chore", "bug" | builder | patch |
  ```
- Update `setup.sh` and `sync.sh` to generate this table from agent metadata

*Option B — Coordinator agent:*
- Add `agents/coordinator.md` (~100-200 lines) that reads the request, picks the agent, and delegates
- Register it as the default agent in `.github/agents/coordinator.agent.md`
- Risk: adds complexity and an extra LLM round-trip before real work starts

**Effort:** Option A is low (table in generated instructions). Option B is medium (new agent + testing).
**Impact:** High — removes the biggest usability friction.
**Philosophy conflict:** None. Routing is about convenience, not autonomy. Human still gates commits.

> **Status note (2026-03-03):** The new [GUIDE.md](../GUIDE.md) explicitly documents this limitation: *"GitHub Copilot does not automatically route between agents or invoke skills. You must explicitly select an agent."* The entire guide is structured around manual agent switching at phase boundaries — a functional workaround, but exactly the friction this priority aims to eliminate.

---

## Priority 3: Response Mode Awareness

**What:** Not every request needs the full epic → milestone → tracking doc ceremony. Add explicit workflow modes so the framework doesn't over-process simple tasks.

**Why this is #3:** The `patch` skill was a good start (v2 addition), but the framework still defaults to heavyweight ceremony. A user saying "fix the typo in the README" shouldn't trigger milestone planning. This friction discourages adoption.

**What Squad does:** Four response modes:
- **Direct** — Coordinator answers immediately, no agent spawn
- **Lightweight** — Single agent, minimal overhead
- **Standard** — Single agent with full context
- **Full** — Multiple agents, parallel fan-out, reviewer pass

**What we'd do:**
- Define three workflow modes in the routing table:
  - **Quick** — Single-file fixes, typos, config changes → `patch` skill, no spec needed
  - **Standard** — Milestone-scoped work → existing workflow (spec → build → review)
  - **Epic** — Multi-milestone features → full planning ceremony
- Add mode detection heuristics to the routing preamble:
  - Quick: "fix", "typo", "update", "bump", single file mentioned, issue reference
  - Standard: "implement", "add feature", milestone reference
  - Epic: "plan", "design", "new system", multiple components
- Update agent instructions to respect the mode — builder in Quick mode skips tracking doc creation

**Effort:** Low-medium — routing table updates + minor agent instruction edits.
**Impact:** High — makes the framework usable for the 80% of tasks that are small.
**Philosophy conflict:** None. Human gate still applies regardless of mode.

> **Status note (2026-03-03):** The new [GUIDE.md](../GUIDE.md) validates this pattern in practice — Scenario 1 (single bug fix via `patch` skill) vs Scenario 2 (full epic ceremony) are distinct workflows. The two modes exist implicitly; this priority would make detection and routing automatic rather than manual.

---

## ~~Priority 4: Coordinator Agent / Charter-Style Descriptions~~ — DROPPED

> **Status (2026-03-03):** Dropped. Instead of building a prescriptive coordinator agent, we added per-agent delegation blocks directly into the generated instructions (copilot-instructions.md and claude rules). Each agent has its own section with activation keywords, exact file paths to read, and step-by-step instructions. This achieves ~90% of the coordinator's routing benefit without adding a prescriptive orchestration layer that would conflict with the framework's "artifacts gate work, not ceremonies" philosophy.
>
> A full Squad-style coordinator puts everything in one 1,147-line system prompt — effective but rigid and single-platform. Our approach keeps routing inline while preserving flexibility for different project types.

---

## Priority 5: Decision Lifecycle Management

**What:** Structure how decisions are recorded, referenced, and archived — not just appended to a flat file.

**Why this is #5:** This builds on Priority 1 (memory). Once agents start recording decisions, the file grows unboundedly. Squad learned this the hard way (80K → 33K token prune in v0.4.0). Better to design the lifecycle upfront.

**What Squad does:** Decisions have states (active → archived). The coordinator prunes stale decisions. Archived decisions remain searchable but don't consume context budget.

**What we'd do:**
- Structure `work/decisions.md` with YAML-like entries:
  ```markdown
  ## D-2026-02-26-001: Use xUnit over NUnit
  **Status:** active
  **Context:** Needed a test framework for .NET 9 project
  **Decision:** xUnit — better async support, community preference
  **Consequences:** All test projects use xUnit. Fixture pattern follows xUnit conventions.
  ```
- Add archival rules: decisions older than 90 days with no recent references → move to `work/decisions-archive.md`
- Add a "Prune decisions" step to the `wrap-milestone` skill — after wrapping, review active decisions for staleness
- Cap: if `decisions.md` exceeds ~150 entries or ~300 lines, trigger a pruning pass

**Effort:** Low — template + skill instruction updates.
**Impact:** Medium — prevents context bloat as memory accumulates.
**Philosophy conflict:** None.

---

## Priority 6: Framework Self-Testing — ✅ Substantially Complete

**What:** Add a test suite that validates `setup.sh`, `sync.sh`, and the generated output.

**Why this is #6:** The framework has zero tests. Squad has 118+. For a framework that mandates TDD for its users, having no tests for itself is a credibility gap.

**What we'd do:**
- Add `tests/` directory with bash test scripts (using `bats` or plain `assert` functions)
- Test cases:
  - `setup.sh` generates all expected files in `.github/`, `.claude/`, `.codex/`
  - `sync.sh` is idempotent (running twice produces same output)
  - `sync.sh` prunes stale agents/skills correctly
  - Generated `.agent.md` files have valid YAML frontmatter
  - Adding a skill to `.ai-repo/skills/` gets picked up by sync
  - Adding a rule to `.ai-repo/rules/` appears in generated instructions
- Run tests in CI (if/when CI exists) or manually via `bash .ai/tests/run.sh`

**Effort:** Medium — writing tests + possibly adopting `bats`.
**Impact:** Medium — catches regressions, builds credibility, practices what we preach.
**Philosophy conflict:** None. Strengthens the framework's own TDD credibility.

> **Status (2026-03-03): Substantially complete.** `tests/test-sync.sh` (397 lines, 10 scenarios) now covers:
> - ✅ Blank-slate generation (all expected files created)
> - ✅ Idempotency (second run changes nothing)
> - ✅ Override layering (repo-specific files win over framework stubs)
> - ✅ Pruning stale entries
> - ✅ Stale `.claude/` cleanup
> - ✅ Rules content appended to platform files
> - ✅ Directory-based repo skills
> - ✅ Source removal triggers pruning
> - ✅ Mixed override + prune in one run
> - ✅ No `.ai-repo/` scenario
>
> Additionally, `setup.sh` was refactored to delegate sync work to `sync.sh` (194 lines, down from ~343).
>
> **Remaining gaps:** YAML frontmatter validation, `setup.sh`-specific tests (Codex output, `.ai-repo/` scaffold, `work/` dirs), CI integration.

---

## Priority 7: GitHub Actions for Issue Triage

**What:** Add optional GitHub Actions workflows that auto-label and auto-assign issues based on keywords, similar to Squad's triage system.

**Why this is #7:** Lower priority because ai-workflow is hosted on Azure DevOps (not GitHub), but the concept translates to Azure Pipelines too. For GitHub-hosted consumers of the framework, this would be immediately useful.

**What Squad does:** Three workflows (~600 lines total):
- `squad-triage.yml` — parses issue text, keyword-matches against agent roles, applies `squad:{agent}` label
- `squad-issue-assign.yml` — when labeled, posts acknowledgment and assigns
- `sync-squad-labels.yml` — creates labels from team roster

**What we'd do:**
- Add `templates/workflows/` with optional GitHub Actions:
  - `triage.yml` — keyword-match issues against agent roles, apply labels (`agent:planner`, `agent:builder`, etc.)
  - `assign.yml` — auto-assign based on label
- Make these opt-in: `setup.sh` copies them only if a flag is set or a config file exists
- For Azure DevOps: document equivalent pipeline YAML (or provide templates)

**Effort:** Medium — workflow authoring + testing across platforms.
**Impact:** Medium — useful for GitHub users, less relevant for Azure DevOps.
**Philosophy conflict:** Minor — auto-assignment is a convenience, not autonomous action. Human still reviews.

---

## Priority 8: Inter-Agent Communication (Drop-Box Pattern)

**What:** Allow agents to leave structured notes for other agents via a shared file, enabling async handoffs without the user manually relaying context.

**Why this is #8:** Nice-to-have. The current workflow already uses tracking docs and specs for handoffs, which serves a similar purpose. But a dedicated channel would be cleaner.

**What Squad does:** Agents write to a shared drop-box (markdown file). Other agents check it at spawn. The coordinator manages the flow.

**What we'd do:**
- Add `work/handoff.md` — structured handoff notes
- When builder finishes a milestone, append: "Ready for review. Key changes: X, Y, Z. Watch for: A."
- When reviewer starts, read `handoff.md` for context from the builder
- Clear entries after they're consumed

**Effort:** Low — markdown file + agent instruction updates.
**Impact:** Low-medium — smoother handoffs, but current workflow already works.
**Philosophy conflict:** None.

---

## Priority 9: CLI Wrapper

**What:** A simple bash script (`ai`) that wraps common operations: `ai plan`, `ai build`, `ai review`, `ai release`, `ai sync`.

**Why this is #9:** Convenience, not capability. Everything the CLI would do can already be done by talking to agents directly. But it lowers the barrier to entry and looks more professional.

**What Squad does:** Full Node.js CLI (1,654 lines) with install, upgrade, watch, export/import, plugin management.

**What we'd do:**
- Add `scripts/ai` (bash, ~100-200 lines):
  ```bash
  ai plan "notification system"    → opens Copilot/Claude with planner context
  ai build m-cfdf-04               → opens with builder + milestone context
  ai sync                          → runs sync.sh
  ai setup                         → runs setup.sh
  ai status                        → shows active milestones, tracking doc status
  ```
- Keep it bash-only (zero dependencies, consistent with framework philosophy)
- The `ai status` command alone would be valuable — quick view of what's in progress

**Effort:** Medium — script authoring + cross-platform testing (bash on Windows via Git Bash/WSL).
**Impact:** Low-medium — convenience and polish.
**Philosophy conflict:** None.

---

## What We Should NOT Do

Some Squad features are intentionally excluded because they conflict with ai-workflow's core philosophy:

1. **Unattended work / watchdog** — Squad's Ralph agent monitors and processes work without human presence. This directly conflicts with our hard commit gate. We want humans in the loop, not catching up after the fact.

2. **Agent personality / casting** — Squad names agents after film characters (Keyser, Ripley, etc.) for engagement. This is clever but orthogonal to our goals. Our agents are roles, not personas.

3. **Parallel fan-out** — Squad spawns multiple agents simultaneously. This requires platform-specific `task` tool support and creates merge conflicts. Our sequential, human-gated workflow is intentionally single-threaded.

4. **Plugin marketplace** — Squad has a plugin system for third-party extensions. Our `.ai-repo/` convention serves the same need more simply. A marketplace implies a community we don't have.

---

## Implementation Sequence

```
Phase 1 (next iteration):
  P1: Persistent memory (decisions.md + agent history)
  P2: Routing table in generated instructions
  P3: Response mode awareness (quick/standard/epic)

Phase 2 (following iteration):
  P4: Charter-style agent descriptions
  P5: Decision lifecycle management
  P6: Framework self-testing          ← substantially complete (2026-03-03)

Phase 3 (when needed):
  P7: GitHub Actions templates
  P8: Inter-agent drop-box
  P9: CLI wrapper
```

Phase 1 items are low effort and high impact — they can all land in a single milestone. Phase 2 builds on Phase 1 (P6 is already mostly done). Phase 3 is opportunistic.

---

*This roadmap is informed by the [Squad comparison analysis](squad-comparison.md) and deep source code analysis of Squad's coordinator, workflows, and CLI.*
