#!/usr/bin/env bash
# sync.sh — Idempotent sync of framework + repo-specific files into .github/ (for Copilot).
#
# Copilot requires agents/skills to be physically in .github/.
# This script generates stubs for framework agents/skills (.ai/) and overlays
# repo-specific overrides (.ai-repo/) on top, then prunes stale entries.
#
# Usage:  bash .ai/sync.sh
#
# Safe to run repeatedly. Only overwrites files that changed.
# Removes .github/ entries that no longer have a source in .ai/ or .ai-repo/.
#
# Run after:
#   - Updating the .ai submodule (new framework agents/skills)
#   - Adding or editing a repo-specific agent in .ai-repo/agents/
#   - Adding or editing a repo-specific skill in .ai-repo/skills/
#   - Adding or editing a repo-specific rule  in .ai-repo/rules/

set -euo pipefail

REPO_DIR=".ai-repo"
CHANGED=0
SKIPPED=0
REMOVED=0

# --- Helpers ---
sync_file() {
    local src="$1" dest="$2" label="$3"
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    cp "$src" "$dest"
    echo "  ✓ $label"
    CHANGED=$((CHANGED + 1))
}

# Write content to a file only if it changed. Uses printf to avoid trailing newline issues.
write_if_changed() {
    local dest="$1" label="$2" content="$3"
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$dest" ]] && diff -q <(printf '%s' "$content") "$dest" >/dev/null 2>&1; then
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    printf '%s' "$content" > "$dest"
    echo "  ✓ $label"
    CHANGED=$((CHANGED + 1))
}

# Remove .github/ files that have no corresponding source in .ai-repo/.
prune_stale() {
    local dest_dir="$1" src_dir="$2" pattern="$3" label="$4"
    [[ -d "$dest_dir" ]] || return
    for dest in "$dest_dir"/$pattern; do
        [[ -f "$dest" ]] || continue
        local name
        name=$(basename "$dest")
        if [[ ! -f "$src_dir/$name" ]]; then
            rm "$dest"
            echo "  ✗ removed stale $label: $name"
            REMOVED=$((REMOVED + 1))
        fi
    done
}

# --- Path rewriting ---
# The .ai/ submodule is the framework source; .github/ is the composed output.
# When generating instruction files and inlining agent bodies, rewrite paths so
# the AI reads the composed versions (which include repo-specific overrides)
# instead of the raw framework source files.
#
# .ai/agents/X.md      → .github/agents/X.agent.md
# .ai/skills/X.md      → .github/skills/X/SKILL.md
# .ai/rules.md         → unchanged (no composed equivalent)
# .ai/paths.md         → unchanged (no composed equivalent)
# .ai/templates/       → unchanged (no composed equivalent)
rewrite_paths() {
    local text="$1"
    # Rewrite .ai/agents/NAME.md → .github/agents/NAME.agent.md
    text=$(echo "$text" | sed -E 's|\.ai/agents/([a-z_-]+)\.md|\.github/agents/\1.agent.md|g')
    # Rewrite .ai/skills/NAME.md → .github/skills/NAME/SKILL.md
    text=$(echo "$text" | sed -E 's|\.ai/skills/([a-z_-]+)\.md|\.github/skills/\1/SKILL.md|g')
    # Rewrite generic directory references
    text=$(echo "$text" | sed 's|\.ai/agents/|\.github/agents/|g')
    text=$(echo "$text" | sed 's|\.ai/skills/|\.github/skills/|g')
    echo "$text"
}

# --- Agents ---
# 1. Generate inlined agents from framework sources (.ai/agents/*.md → .github/agents/*.agent.md)
# 2. Overlay repo-specific agents (.ai-repo/agents/*.agent.md) on top — these override.
# 3. Prune .github/agents/ entries that exist in neither source.

AI_DIR=".ai"
EXPECTED_AGENTS=()  # track which agents should exist

# --- Agent frontmatter (handoffs, tools, agents) ---
# Returns extra YAML frontmatter lines for each agent.
# These define the handoff chain and coordinator capabilities.
get_agent_frontmatter() {
    local agent_name="$1"
    case "$agent_name" in
        coordinator)
            cat <<'FMEOF'
tools: [vscode/extensions, vscode/getProjectSetupInfo, vscode/installExtension, vscode/newWorkspace, vscode/openSimpleBrowser, vscode/runCommand, vscode/askQuestions, vscode/vscodeAPI, execute/getTerminalOutput, execute/awaitTerminal, execute/killTerminal, execute/runTask, execute/createAndRunTask, execute/runTests, execute/runNotebookCell, execute/testFailure, execute/runInTerminal, read/terminalSelection, read/terminalLastCommand, read/getTaskOutput, read/getNotebookSummary, read/problems, read/readFile, read/readNotebookCellOutput, agent/runSubagent, edit/createDirectory, edit/createFile, edit/createJupyterNotebook, edit/editFiles, edit/editNotebook, search/changes, search/codebase, search/fileSearch, search/listDirectory, search/searchResults, search/textSearch, search/usages, search/searchSubagent, web/fetch, web/githubRepo, todo, memory]
agents: ['planner', 'builder', 'reviewer', 'deployer']
handoffs:
  - label: Plan & Research
    agent: planner
    prompt: "Plan and research the task described above."
    send: false
  - label: Start Implementation
    agent: builder
    prompt: "Implement the work described above."
    send: false
  - label: Review Changes
    agent: reviewer
    prompt: "Review the changes described above."
    send: false
  - label: Deploy / Release
    agent: deployer
    prompt: "Release the work described above."
    send: false
FMEOF
            ;;
        planner)
            cat <<'FMEOF'
handoffs:
  - label: Start Implementation
    agent: builder
    prompt: "Implement the plan described above."
    send: false
  - label: Back to Coordinator
    agent: coordinator
    prompt: ""
    send: false
FMEOF
            ;;
        builder)
            cat <<'FMEOF'
handoffs:
  - label: Review Changes
    agent: reviewer
    prompt: "Review the implementation above."
    send: false
  - label: Back to Coordinator
    agent: coordinator
    prompt: ""
    send: false
FMEOF
            ;;
        reviewer)
            cat <<'FMEOF'
handoffs:
  - label: Fix Issues
    agent: builder
    prompt: "Fix the issues identified in the review above."
    send: false
  - label: Ship It
    agent: deployer
    prompt: "Release the reviewed changes."
    send: false
  - label: Back to Coordinator
    agent: coordinator
    prompt: ""
    send: false
FMEOF
            ;;
        deployer)
            cat <<'FMEOF'
handoffs:
  - label: Back to Coordinator
    agent: coordinator
    prompt: ""
    send: false
FMEOF
            ;;
    esac
}

# Framework agents — generate inlined agent files
for f in "$AI_DIR"/agents/*.md; do
    [[ -f "$f" ]] || continue
    agent_name=$(basename "$f" .md)
    dest=".github/agents/${agent_name}.agent.md"
    EXPECTED_AGENTS+=("${agent_name}.agent.md")

    # Skip if a repo-specific override exists (it will be copied next)
    if [[ -f "$REPO_DIR/agents/${agent_name}.agent.md" ]]; then
        continue
    fi

    # Extract description from the agent file (first non-empty, non-heading line)
    agent_desc=$(grep -m1 -vE '^(#|$)' "$f" | sed 's/^[*_]*//;s/[*_]*$//' | head -c 200)
    if [[ -z "$agent_desc" ]]; then
        agent_desc="AI-assisted development agent: ${agent_name}"
    fi

    # Read the full agent content and rewrite .ai/ paths to composed .github/ paths
    agent_body=$(rewrite_paths "$(cat "$f")")

    # Get extra frontmatter (handoffs, tools, agents) for this agent
    extra_fm=$(get_agent_frontmatter "$agent_name")

    # Build frontmatter block
    fm_block="---
description: \"${agent_desc}\""
    if [[ -n "$extra_fm" ]]; then
        fm_block+="
${extra_fm}"
    fi
    fm_block+="
---"

    # Generate an inlined agent file with Copilot frontmatter
    stub="${fm_block}
<!-- AUTO-GENERATED from .ai/agents/${agent_name}.md by sync.sh — do not edit manually -->

${agent_body}

---

**Also read before starting work:**
- \`.ai/rules.md\` — non-negotiable guardrails
- \`.ai/paths.md\` — artifact locations
- Relevant skill files from \`.github/skills/\` as referenced above
- Project-specific rules from \`.ai-repo/rules/\` (if they exist)"

    # Only write if content changed
    write_if_changed "$dest" "agent: ${agent_name}.agent.md" "$stub"
done

# Repo-specific agents — override framework stubs
if [[ -d "$REPO_DIR/agents" ]]; then
    for f in "$REPO_DIR"/agents/*.agent.md; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        EXPECTED_AGENTS+=("$name")
        sync_file "$f" ".github/agents/$name" "agent (override): $name"
    done
fi

# Prune agents that aren't in either source
if [[ -d ".github/agents" ]]; then
    for dest in .github/agents/*.agent.md; do
        [[ -f "$dest" ]] || continue
        name=$(basename "$dest")
        found=false
        for expected in "${EXPECTED_AGENTS[@]}"; do
            if [[ "$expected" == "$name" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            rm "$dest"
            echo "  ✗ removed stale agent: $name"
            REMOVED=$((REMOVED + 1))
        fi
    done
fi

# --- Skills ---
# 1. Copy framework skills (.ai/skills/*.md → .github/skills/<name>/SKILL.md)
# 2. Overlay repo-specific skills (.ai-repo/skills/) on top — these override.
# 3. Prune .github/skills/ directories that exist in neither source.

EXPECTED_SKILLS=()  # track which skill directories should exist

# Framework skills
for f in "$AI_DIR"/skills/*.md; do
    [[ -f "$f" ]] || continue
    skill_name=$(basename "$f" .md)
    EXPECTED_SKILLS+=("$skill_name")

    # Skip if a repo-specific override exists (flat file)
    if [[ -f "$REPO_DIR/skills/${skill_name}.md" ]]; then
        continue
    fi
    # Skip if a repo-specific override exists (directory)
    if [[ -f "$REPO_DIR/skills/${skill_name}/SKILL.md" ]]; then
        continue
    fi

    sync_file "$f" ".github/skills/$skill_name/SKILL.md" "skill: $skill_name"
done

# Repo-specific skills — override framework or add new
if [[ -d "$REPO_DIR/skills" ]]; then
    # Flat files: skill-name.md
    for f in "$REPO_DIR"/skills/*.md; do
        [[ -f "$f" ]] || continue
        skill_name=$(basename "$f" .md)
        EXPECTED_SKILLS+=("$skill_name")
        sync_file "$f" ".github/skills/$skill_name/SKILL.md" "skill (override): $skill_name"
    done
    # Directory-based: skill-name/SKILL.md
    for f in "$REPO_DIR"/skills/*/SKILL.md; do
        [[ -f "$f" ]] || continue
        skill_name=$(basename "$(dirname "$f")")
        EXPECTED_SKILLS+=("$skill_name")
        sync_file "$f" ".github/skills/$skill_name/SKILL.md" "skill (override): $skill_name"
    done
fi

# Prune skill directories that aren't in either source
if [[ -d ".github/skills" ]]; then
    for dest_dir in .github/skills/*/; do
        [[ -d "$dest_dir" ]] || continue
        skill_name=$(basename "$dest_dir")
        found=false
        for expected in "${EXPECTED_SKILLS[@]}"; do
            if [[ "$expected" == "$skill_name" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            rm -rf "$dest_dir"
            echo "  ✗ removed stale skill: $skill_name/"
            REMOVED=$((REMOVED + 1))
        fi
    done
fi

# --- Rules & Platform Entry Points ---
# Generate the platform instruction files with framework pointers +
# appended repo-specific rules from .ai-repo/rules/*.md (if any).

# Collect repo-specific rules content (if any)
REPO_RULES=""
if [[ -d "$REPO_DIR/rules" ]]; then
    shopt -s nullglob
    for f in "$REPO_DIR"/rules/*.md; do
        # Skip README and files with no meaningful content
        [[ "$(basename "$f")" == "README.md" ]] && continue
        # Skip files where every line is blank, a comment (#), or an HTML tag (<)
        if grep -qE '^[^#<[:space:]]' "$f" 2>/dev/null; then
            REPO_RULES+="
$(cat "$f")
"
        fi
    done
    shopt -u nullglob
fi

# Collect dynamic lists for instructions
FRAMEWORK_AGENTS=$(ls -1 "$AI_DIR"/agents/*.md 2>/dev/null | xargs -I{} basename {} .md | paste -sd', ')
FRAMEWORK_SKILLS=$(ls -1 "$AI_DIR"/skills/*.md 2>/dev/null | xargs -I{} basename {} .md | paste -sd', ')
REPO_SKILL_NAMES=""
if [[ -d "$REPO_DIR/skills" ]]; then
    shopt -s nullglob
    repo_skills=()
    for f in "$REPO_DIR"/skills/*.md; do repo_skills+=("$(basename "$f" .md)"); done
    for f in "$REPO_DIR"/skills/*/SKILL.md; do repo_skills+=("$(basename "$(dirname "$f")")"); done
    shopt -u nullglob
    REPO_SKILL_NAMES=$(printf '%s,' "${repo_skills[@]}" | sed 's/,$//')
fi

# --- .github/copilot-instructions.md ---
copilot_content="# Copilot Instructions
<!-- AUTO-GENERATED by .ai/sync.sh — do not edit manually -->

## AI Framework

This project uses the AI-Assisted Development Framework v2.

You work directly in **Agent mode** with full tool access. Use the routing table below to identify the right workflow, then follow the corresponding agent's instructions and skill.

For specific personas with tool restrictions, the user may switch to a named agent: @planner, @builder, @reviewer, @deployer. Otherwise, you operate as the default agent with all tools available.

**Before starting any task**, read these files for context:
- \`.ai/rules.md\` — Non-negotiable guardrails
- \`.ai/paths.md\` — Where artifacts live

## Session Start — Load Memory

Before doing anything else, read these files if they exist:
1. \`work/decisions.md\` — shared decision log (active decisions the team has made)
2. \`work/agent-history/\` — accumulated learnings from past sessions (read the file matching the current role)

Use this context to avoid re-discovering things or contradicting prior decisions.

## Subagent Delegation

For **research-heavy or analysis tasks**, use subagents to keep your context clean:
- **Planning/research:** Spawn a subagent (optionally with \`agentName: \"planner\"\`) to analyze the codebase, research options, or draft a plan. Review the summary it returns before proceeding.
- **Code review:** Spawn a subagent (optionally with \`agentName: \"reviewer\"\`) to review changes. It runs in isolated context with read-only tools and returns findings.

Do **not** use subagents for building/implementation — that workflow is interactive and requires back-and-forth with the user.

## FIRST — Identify the Workflow

**Before writing any code or making any changes**, determine which workflow this task needs.
Use the routing table below or the user's explicit request to pick the approach.

## Agent Instructions

Each agent below has a dedicated instruction file. Read it for role-specific constraints and workflow.

### @planner — Planning, specs, architecture, research
**Activate when:** user says plan, design, scope, epic, architecture, brainstorm, research, spec, break down
**Steps:**
1. Read \`.github/agents/planner.agent.md\` — adopt the planner role and constraints
2. Read the relevant skill: \`.github/skills/plan-epic/SKILL.md\`, \`.github/skills/plan-milestones/SKILL.md\`, \`.github/skills/draft-spec/SKILL.md\`, or \`.github/skills/architect/SKILL.md\`
3. Follow the skill's step-by-step workflow

### @builder — Implementation, TDD, fixes
**Activate when:** user says build, implement, code, start, add feature, fix, patch, bug, chore, tweak, hotfix
**Steps:**
1. Read \`.github/agents/builder.agent.md\` — adopt the builder role and constraints
2. Read the relevant skill: \`.github/skills/start-milestone/SKILL.md\`, \`.github/skills/tdd-cycle/SKILL.md\`, or \`.github/skills/patch/SKILL.md\`
3. Follow the skill's step-by-step workflow

### @reviewer — Code review, milestone wrap-up
**Activate when:** user says review, check, validate, wrap, finish, complete milestone
**Steps:**
1. Read \`.github/agents/reviewer.agent.md\` — adopt the reviewer role and constraints
2. Read the relevant skill: \`.github/skills/review-code/SKILL.md\` or \`.github/skills/wrap-milestone/SKILL.md\`
3. Follow the skill's step-by-step workflow

### @deployer — Releases, deployments, infrastructure
**Activate when:** user says release, deploy, tag, publish
**Steps:**
1. Read \`.github/agents/deployer.agent.md\` — adopt the deployer role and constraints
2. Read the relevant skill: \`.github/skills/release/SKILL.md\`
3. Follow the skill's step-by-step workflow

**Available skills:** ${FRAMEWORK_SKILLS}"

if [[ -n "$REPO_SKILL_NAMES" ]]; then
    copilot_content+="
**Project-specific skills:** ${REPO_SKILL_NAMES} (see \`.ai-repo/skills/\`)"
fi

copilot_content+="
**Templates:** epic-spec, milestone-spec, tracking-doc (see \`.ai/templates/\`)
## Intent Routing

When the user describes a task, route to the right agent and skill based on intent:

| User intent | Workflow | Skill | Mode | Subagent? |
|-------------|---------|-------|------|----------|
| Plan, design, scope, epic, architecture, brainstorm, research | @planner | plan-epic, plan-milestones, architect | Epic or Standard | Yes — good candidate for subagent research |
| Write a spec, draft spec, break down | @planner | draft-spec | Standard | Yes |
| Build, implement, code, start milestone, add feature | @builder | start-milestone, tdd-cycle | Standard | No — interactive, work directly |
| Fix, patch, bug, chore, tweak, hotfix, one-off | @builder | patch | Quick | No — interactive |
| Review, check, validate, look over | @reviewer | review-code | Standard | Yes — good candidate for subagent review |
| Wrap, finish, complete milestone | @reviewer | wrap-milestone | Standard | Partial — analysis as subagent, then present |
| Release, deploy, tag, publish | @deployer | release | Standard | No — needs explicit human gates |

After identifying the workflow, read the corresponding agent instruction file and follow the skill's steps.

## Workflow Modes

Not every task needs the full ceremony. Match the mode to the task:

| Mode | When | What happens |
|------|------|-------------|
| **Quick** | One-off fixes, typos, config changes, single-file edits, issue-linked patches | Use \`patch\` skill. No spec, no tracking doc. Branch → fix → commit → PR. |
| **Standard** | Milestone-scoped work with acceptance criteria | Full workflow: spec → branch → TDD → tracking doc → review → merge. |
| **Epic** | Multi-milestone features, new systems, large initiatives | Plan epic → break into milestones → Standard mode for each → wrap epic → release. |

**Mode detection hints:**
- **Quick:** user mentions a bug, issue number, single file, \"fix\", \"patch\", \"update\", \"typo\", \"bump\"
- **Standard:** user references a milestone, says \"implement\", \"add feature\", \"build\", or has a spec
- **Epic:** user says \"plan\", \"design\", \"new system\", mentions multiple components or phases

When unsure, ask: \"This looks like a [Quick/Standard/Epic] task. Should I proceed that way?\"
## Context Refresh

When the user says **\"refresh context\"** or **\"refresh\"**:
1. Re-read \`.ai/rules.md\` and \`.ai/paths.md\`
2. Re-read the active agent file if one is invoked (e.g. \`.github/agents/builder.agent.md\`)
3. Check \`work/epics/\` and \`ROADMAP.md\` for current work state
4. Summarize: current branch, submodule state, active epic/milestone, pending changes

This re-grounds context during long sessions or after framework updates (e.g. \`sync.sh\`, submodule branch switch).
## Key Rules

- Never commit without explicit human approval
- TDD by default: write tests first
- Artifacts gate work, not ceremonies
- Follow Conventional Commits format"

if [[ -n "$REPO_RULES" ]]; then
    copilot_content+="

## Project-Specific Rules
${REPO_RULES}"
fi

write_if_changed ".github/copilot-instructions.md" ".github/copilot-instructions.md" "$copilot_content"

# --- .claude/rules/ai-framework.md ---
claude_content="# AI Framework v2
<!-- AUTO-GENERATED by .ai/sync.sh — do not edit manually -->

Read and follow:
1. \`.ai/rules.md\` — Non-negotiable guardrails
2. \`.ai/paths.md\` — Where artifacts live

Work directly with the default agent. Use the routing table below to identify the right workflow.
For specific personas with tool restrictions, switch to a named agent: planner, builder, reviewer, deployer.

For research-heavy or analysis tasks, use subagents to keep context clean:
- **Planning/research:** Spawn a subagent to analyze the codebase or draft a plan.
- **Code review:** Spawn a subagent to review changes in isolated context.
- Do NOT use subagents for building — that workflow is interactive.

## FIRST — Identify the Workflow

**Before writing any code or making any changes**, determine which workflow this task needs.
Use the routing table below or the user's explicit request to pick the approach.

## Agent Instructions

Each agent below has a dedicated instruction file. Read it for role-specific constraints and workflow.

### planner — Planning, specs, architecture, research
**Activate when:** user says plan, design, scope, epic, architecture, brainstorm, research, spec, break down
**Steps:**
1. Read \`.github/agents/planner.agent.md\` — adopt the planner role and constraints
2. Read the relevant skill: \`.github/skills/plan-epic/SKILL.md\`, \`.github/skills/plan-milestones/SKILL.md\`, \`.github/skills/draft-spec/SKILL.md\`, or \`.github/skills/architect/SKILL.md\`
3. Follow the skill's step-by-step workflow

### builder — Implementation, TDD, fixes
**Activate when:** user says build, implement, code, start, add feature, fix, patch, bug, chore, tweak, hotfix
**Steps:**
1. Read \`.github/agents/builder.agent.md\` — adopt the builder role and constraints
2. Read the relevant skill: \`.github/skills/start-milestone/SKILL.md\`, \`.github/skills/tdd-cycle/SKILL.md\`, or \`.github/skills/patch/SKILL.md\`
3. Follow the skill's step-by-step workflow

### reviewer — Code review, milestone wrap-up
**Activate when:** user says review, check, validate, wrap, finish, complete milestone
**Steps:**
1. Read \`.github/agents/reviewer.agent.md\` — adopt the reviewer role and constraints
2. Read the relevant skill: \`.github/skills/review-code/SKILL.md\` or \`.github/skills/wrap-milestone/SKILL.md\`
3. Follow the skill's step-by-step workflow

### deployer — Releases, deployments, infrastructure
**Activate when:** user says release, deploy, tag, publish
**Steps:**
1. Read \`.github/agents/deployer.agent.md\` — adopt the deployer role and constraints
2. Read the relevant skill: \`.github/skills/release/SKILL.md\`
3. Follow the skill's step-by-step workflow

Agents are defined in \`.github/agents/\`. Skills are in \`.github/skills/\`.
Templates are in \`.ai/templates/\`.

Project-specific extensions are in \`.ai-repo/\`:
- \`.ai-repo/agents/\` — project-specific agent overrides
- \`.ai-repo/skills/\` — project-specific skills
- \`.ai-repo/rules/\`  — project-specific rules (read these too)

## Intent Routing

Route tasks to the right agent based on intent:

| User intent | Workflow | Skill | Mode | Subagent? |
|-------------|---------|-------|------|----------|
| Plan, design, scope, epic, architecture, brainstorm | planner | plan-epic, plan-milestones, architect | Epic/Standard | Yes — research |
| Write a spec, draft spec | planner | draft-spec | Standard | Yes |
| Build, implement, code, start milestone | builder | start-milestone, tdd-cycle | Standard | No — interactive |
| Fix, patch, bug, chore, tweak, hotfix | builder | patch | Quick | No — interactive |
| Review, check, validate | reviewer | review-code | Standard | Yes — review |
| Wrap, finish, complete milestone | reviewer | wrap-milestone | Standard | Partial |
| Release, deploy, tag, publish | deployer | release | Standard | No — human gates |

After identifying the workflow, read the corresponding agent instruction file and follow the skill's steps.

## Workflow Modes

| Mode | When | What happens |
|------|------|-------------|
| **Quick** | One-off fixes, typos, config changes, issue-linked patches | Use patch skill. No spec, no tracking doc. |
| **Standard** | Milestone-scoped work with acceptance criteria | Spec → TDD → tracking doc → review → merge. |
| **Epic** | Multi-milestone features, new systems | Plan → milestones → Standard for each → release. |

Key rules:
- Never commit without explicit human approval
- TDD by default: write tests first
- Artifacts gate work, not agent handoffs
- Follow Conventional Commits format"

if [[ -n "$REPO_RULES" ]]; then
    claude_content+="

## Project-Specific Rules
${REPO_RULES}"
fi

write_if_changed ".claude/rules/ai-framework.md" ".claude/rules/ai-framework.md" "$claude_content"

# --- CLAUDE.md (repo root) ---
# Claude Code loads CLAUDE.md automatically. Inline the critical rules here
# so they are followed without requiring additional file reads.

claude_md_content="# CLAUDE.md
<!-- AUTO-GENERATED by .ai/sync.sh — do not edit manually -->

This project uses the AI Framework v2 at \`.ai/\`. Follow its agents, skills, and rules.

## Hard Rules

### Commits — NEVER without explicit human approval
- \"continue\", \"ok\", \"looks good\" do **NOT** count as approval
- Wait for: \"commit\", \"push it\", \"go ahead and commit\", \"merge it\"
- Before committing: stage changes, show diff summary, propose message, **STOP and wait**
- Before pushing: **STOP and ask**
- Conventional Commits format: \`feat:\`, \`fix:\`, \`chore:\`, \`docs:\`, \`test:\`, \`refactor:\`

### Agent Workflow — ALWAYS identify the agent first
Before writing any code, determine which agent handles this task:

| Intent | Agent | Read first |
|--------|-------|------------|
| build, implement, code, start, fix, patch | **builder** | \`.ai/agents/builder.md\` + relevant skill |
| plan, design, scope, epic, architecture | **planner** | \`.ai/agents/planner.md\` + relevant skill |
| review, check, validate, wrap, finish | **reviewer** | \`.ai/agents/reviewer.md\` + relevant skill |
| release, deploy, tag, publish | **deployer** | \`.ai/agents/deployer.md\` + relevant skill |

Read the agent file. Adopt its role and constraints. Follow its skill workflow.

### TDD — Write tests first
- **Logic, API, data code:** strict TDD — red → green → refactor
- **UI components/layout:** build first, then add smoke tests to verify
- **Scaffold milestones:** tests can come at end as verification
- No exceptions for logic code unless the user explicitly waives it

### Branches
- Epic work: \`epic/<slug>\` integration branch from \`main\`
- Milestone work: \`milestone/<id>\` branch from epic branch
- Do NOT commit milestone work directly to \`main\`

### Tracking Artifacts
- Tracking doc: \`work/milestones/tracking/<id>-tracking.md\` — update after each AC
- Decisions: \`work/decisions.md\` — log architectural/technical decisions made
- Gaps: \`work/gaps.md\` — log discovered issues deferred for later
- Agent learnings: \`work/agent-history/<agent>.md\` — append patterns and pitfalls

### Code Quality
- Tests must be deterministic (no network calls, no time-dependent)
- Build must be green before declaring done
- Prefer minimal changes — don't refactor unrelated code

### Security
- Never paste secrets, tokens, or credentials into prompts, docs, or logs
- New dependencies require human approval

## Enforcement Levels

| Level | Rule | What happens if skipped |
|-------|------|------------------------|
| **Hard gate** | Commit approval, push approval | Work is lost or pushed without review |
| **Hard gate** | Branch workflow | Milestone work lands on wrong branch |
| **Hard gate** | Update CLAUDE.md current work | Next conversation starts with stale context |
| **Required** | TDD (for logic code) | Bugs ship without test coverage |
| **Required** | Tracking doc updates | Progress is invisible |
| **Required** | decisions.md, gaps.md | Knowledge is lost between sessions |
| **Required** | agent-history append | Same mistakes repeated |

## Framework Reference

| Path | Purpose |
|------|---------|
| \`.ai/rules.md\` | Full rules (this is a summary) |
| \`.ai/paths.md\` | Where artifacts live |
| \`.ai/agents/\` | Agent definitions |
| \`.ai/skills/\` | Skill workflows |
| \`.ai/templates/\` | Document templates |
| \`.ai-repo/\` | Project-specific extensions |"

if [[ -n "$REPO_RULES" ]]; then
    claude_md_content+="

## Project-Specific Rules
${REPO_RULES}"
fi

# Preserve the "Current Work" section if it already exists in CLAUDE.md.
# This section is managed by start-milestone/wrap-milestone skills, not by sync.
current_work_default="## Current Work
<!-- Updated by start-milestone and wrap-milestone skills. Do not edit in sync.sh. -->

No active milestone. Run \`start-milestone\` to begin work."

if [[ -f "CLAUDE.md" ]] && grep -q '^## Current Work' CLAUDE.md; then
    existing_current_work=$(awk '/^## Current Work/{found=1} found{print}' CLAUDE.md)
    claude_md_content+="

${existing_current_work}"
else
    claude_md_content+="

${current_work_default}"
fi

write_if_changed "CLAUDE.md" "CLAUDE.md" "$claude_md_content"

# --- Cleanup: .claude/ stale content ---
# Claude reads agents from .github/agents/, skills from .github/skills/.
# Only .claude/rules/ai-framework.md should exist. Everything else is stale.

for stale_dir in .claude/agents .claude/skills; do
    if [[ -d "$stale_dir" ]]; then
        count=$(find "$stale_dir" -type f | wc -l)
        rm -rf "$stale_dir"
        label=$(basename "$stale_dir")
        echo "  ✗ removed .claude/$label/ ($count stale file(s))"
        REMOVED=$((REMOVED + count))
    fi
done

# Prune .claude/rules/ entries not generated by sync
if [[ -d ".claude/rules" ]]; then
    shopt -s nullglob
    for f in .claude/rules/*.md; do
        name=$(basename "$f")
        if [[ "$name" != "ai-framework.md" ]]; then
            rm "$f"
            echo "  ✗ removed stale .claude/rules/$name"
            REMOVED=$((REMOVED + 1))
        fi
    done
    shopt -u nullglob
fi

# --- Summary ---
echo ""
TOTAL=$((CHANGED + REMOVED))
if [[ $TOTAL -gt 0 ]]; then
    echo "Synced $CHANGED file(s), removed $REMOVED stale file(s) ($SKIPPED unchanged)."
else
    echo "Everything up to date ($SKIPPED file(s) checked)."
fi
