---
id: M-OBS-05-a2ui-renderer
epic: E-09-observation-layer
status: draft
---

# M-OBS-05: A2UI Experimental Renderer

## Goal

Integrate ex_a2ui as an experimental second renderer that consumes the same Observation.Server state as LiveView. This validates the renderer-agnostic architecture and eats our own dogfood on the A2UI protocol. The A2UI renderer targets mobile-friendly status monitoring — a lightweight way to check on a running plan from a phone without the full LiveView dashboard.

This milestone is explicitly experimental. ex_a2ui is alpha software and the A2UI spec is at v0.8. We accept that the protocol may change and that we may need to iterate on ex_a2ui itself.

## Acceptance criteria

- [ ] ex_a2ui added as a dependency in the umbrella
- [ ] A2UI WebSocket endpoint available at `/a2ui/ws` (or similar path, served by Bandit via ex_a2ui)
- [ ] A2UI provider GenServer subscribes to Observation.Server PubSub updates
- [ ] Maps run events to A2UI components: run status card, node progress list, gate interaction form
- [ ] An A2UI client (browser or test client) can connect and receive streaming component updates
- [ ] Run status view: shows run_id, status, progress (N/M nodes complete), elapsed time
- [ ] Node progress: list of nodes with status indicators (icons or text: pending/running/done/failed/waiting)
- [ ] Gate interaction: when a gate is waiting, renders an interactive component (approve/reject buttons) that resolves the gate
- [ ] Provider handles multiple concurrent client connections
- [ ] Provider handles client disconnect gracefully (no crash, no leaked state)

## Tests

### A2UI message format tests
- Verify provider emits valid A2UI JSON component descriptions
- Verify component updates are valid JSONL (one JSON object per line, or valid A2UI streaming format)
- Verify run status component contains required fields (run_id, status, progress)
- Verify node list component contains one entry per node with correct state

### WebSocket connectivity tests
- Connect a test WebSocket client to the A2UI endpoint, verify handshake succeeds
- Verify client receives initial state on connection
- Verify client receives updates as run events occur
- Disconnect client, verify server-side cleanup (no leaked processes)
- Connect two clients to the same run, verify both receive updates

### Gate interaction tests
- When a gate is waiting, verify A2UI renders an interactive component
- Send a gate resolution via the A2UI interaction protocol, verify the gate resolves in the Run.Server
- Verify the resolved gate state propagates to all connected clients

### Integration tests
- Start a ToyPack run, connect an A2UI client, verify the client receives events from start to completion
- Compare Observation.Server state with A2UI component content — verify they are consistent

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- DAG visualization via A2UI (A2UI is component-based, not graphics-based — DAG drawing stays in LiveView)
- A2UI client implementation (we test with raw WebSocket clients; a proper A2UI renderer app is a separate project)
- Polished A2UI component design (functional proof-of-concept)
- A2UI catalog negotiation (use a fixed component set for now)
- Authentication on the A2UI endpoint

## Spec reference

- `docs/research/a2ui_finding.md`
- `docs/architecture/01_CORE.md §Observation`
- ex_a2ui: `https://github.com/23min/ex_a2ui`

## Related ADRs

- none yet

## Notes

This milestone may require changes to ex_a2ui itself. If the library doesn't support a needed feature, we can either:
1. Implement a workaround in the provider
2. Contribute the feature to ex_a2ui (since it's our repo)
3. Descope the affected acceptance criterion

The goal is to validate the dual-renderer architecture and learn from real A2UI usage, not to ship a polished A2UI product.
