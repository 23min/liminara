---
description: Brainstorming, architecture, and research skill. Used by the planner agent for ideation, technical design, and research documentation.
name: architect
when_to_use: |
  - When the user requests brainstorming, architecture, design, or research work
  - When planning new features or evaluating technical approaches
  - When documenting research findings or architectural decisions
responsibilities:
  - Facilitate brainstorming and ideation sessions
  - Propose and evaluate architectural patterns and trade-offs
  - Document research findings in docs/research
  - Write or update architecture docs in docs/architecture
  - Draft technical specs in docs/specs (if needed)
  - Summarize alternatives, risks, and recommendations
output:
  - Markdown documentation (architecture, research, or specs)
  - Decision records or trade-off analyses
  - Clear, actionable recommendations for next steps
invoked_by:
  - planner agent (automatically when brainstorming, architecture, or research is requested)
---

# Skill: Architect

This skill enables the planner agent to:
- Lead brainstorming and ideation sessions
- Propose and evaluate technical architectures
- Document research and design work
- Produce actionable, well-structured outputs for the team

## File Placement
- Research: docs/research/
- Architecture: docs/architecture/
- Specs: docs/specs/

## Example Triggers
- "Let's brainstorm approaches for X"
- "Can you design an architecture for Y?"
- "Research the best way to do Z"
- "Write an ADR for this decision"
- "Document the trade-offs between A and B"

## Best Practices
- Always cite sources or rationale for recommendations
- Use diagrams or tables where helpful
- Keep outputs concise, actionable, and easy to find

## Record Learnings

After completing research or architecture work:
- Append key decisions to `work/decisions.md` (use the standard decision format)
- Append research insights or architectural patterns to `work/agent-history/planner.md`
- Note: only record things worth remembering across sessions — not every detail
