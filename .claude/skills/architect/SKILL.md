---
name: architect
description: "Brainstorming, architecture, and research skill. Used by the planner agent for ideation, technical design, and research documentation."
---
<!-- AUTO-GENERATED from source by sync.sh — do not edit manually -->

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