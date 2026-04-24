# A2UI Assessment: Real Protocol, Good Fit, Early Stage

**Date:** 2026-03-02 (corrected)
**Status:** A2UI is a real Google project. Initial analysis incorrectly flagged it as fictional.

---

## Summary

A2UI (Agent-to-UI) is a **real open-source project from Google**, available at:
- Website: [a2ui.org](https://a2ui.org/)
- GitHub: [github.com/google/A2UI](https://github.com/google/A2UI) (11k+ stars, Apache 2.0, actively maintained)
- Specification: v0.8 (Public Preview), v0.9 in draft

## What it does

A2UI enables AI agents to generate interactive UIs by sending declarative JSON component descriptions that clients render using native widgets. Key properties:

- **Declarative, not executable** — agents send component descriptions, preventing code injection
- **LLM-optimized** — flat JSON structure with IDs instead of nesting, designed for reliable transformer generation
- **Framework-agnostic** — single agent response renders across React, Angular, Flutter, native mobile
- **Progressive rendering** — UIs stream via JSONL over SSE, building incrementally
- **Catalog negotiation** — server and client agree on available components per surface

## Why it fits Liminara

A2UI maps directly to Liminara's observation surface needs:

| Liminara Need | A2UI Solution |
|---|---|
| Run progress display | Progressive rendering of DAG status components |
| Artifact inspection | Declarative viewers rendered from artifact metadata |
| Human-in-the-loop gates | Interactive components (buttons, forms) for approvals |
| Pack-specific views | Custom catalog entries per domain pack |
| Multi-client support | Framework-agnostic rendering |

## Maturity risk

A2UI is at **v0.8 Public Preview**. From the docs: "The specification and implementations are functional but are still evolving."

This means:
- The protocol may change between v0.8 and v1.0
- Not all component types may be stable
- Client implementations may lag behind the spec
- Community tooling is still forming

## Recommendation

Use A2UI, but protect against spec churn:

1. **Build an internal event model** (run events, gate events, artifact events) as the source of truth
2. **Treat A2UI rendering as a consumer** of these events, not the primary data model
3. **Use Phoenix Channels** as the transport layer for streaming A2UI messages to clients
4. **Keep the rendering layer swappable** — if A2UI breaks or stalls, you can replace it with custom LiveView rendering without touching the event model

The clean separation is: events (yours) -> rendering (A2UI) -> transport (Phoenix Channels/SSE).
