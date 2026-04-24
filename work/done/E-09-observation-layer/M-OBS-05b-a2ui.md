---
id: M-OBS-05b-a2ui
epic: E-09-observation-layer
status: complete
---

# M-OBS-05b: A2UI Exploration + Integration

## Goal

Bring in ex_a2ui as a git submodule, analyze what works and what doesn't, and build an A2UI provider that consumes the same Observation.Server state as LiveView. Validate the dual-renderer architecture by serving run status, node progress, and gate interaction over the A2UI protocol via WebSocket.

This is explicitly experimental. ex_a2ui is at v0.6.0 (232 tests, targeting A2UI spec v0.9). The A2UI spec has evolved — v0.9 is the current closed version (flat component format, "Prompt First" philosophy), v0.10 is in active draft adding `actionResponse` for sync round-trips. The goal is to learn whether A2UI is viable for Liminara's observation surface, not to ship a polished product.

## Prerequisites

- M-OBS-05a (gate demo + LiveView gate interaction) — provides the interactive demo run we test against

## Architecture decisions

- **ex_a2ui as git submodule** — allows us to make fixes directly if needed, since we own the repo
- **A2UI provider implements `A2UI.SurfaceProvider` behaviour** — `init/1`, `surface/1`, `handle_action/2`, `handle_info/2`
- **A2UI.Supervisor** started alongside Phoenix — serves WebSocket + SSE endpoints via Bandit (no Phoenix dependency)
- **Component mapping** (v0.9 flat format): run status → Card, node list → List with StatusIndicator items, gate → Form with buttons
- **Data binding** via `A2UI.BoundValue` — data model updates push node state changes without rebuilding full component tree

## Acceptance criteria

### ex_a2ui integration
- [x] ex_a2ui added as a git submodule and dependency in the umbrella
- [x] ex_a2ui compiles and its existing tests pass
- [x] Analysis document written: what ex_a2ui provides, what's missing, what needs fixing

### A2UI provider
- [x] `Liminara.Observation.A2UIProvider` GenServer exists
- [x] Subscribes to Observation.Server PubSub updates for a given run
- [x] Maps ViewModel state to A2UI component descriptions (JSON)
- [x] Run status component: run_id, status, progress (N/M nodes complete), elapsed time
- [x] Node progress component: list of nodes with status indicators
- [x] Gate component: when a gate is waiting, renders approve/reject interactive component

### WebSocket endpoint
- [x] A2UI WebSocket endpoint available at a configurable path (e.g., `/a2ui/ws`)
- [x] Client connects, receives initial state as A2UI components
- [x] Client receives streaming updates as run events occur
- [x] Multiple concurrent clients supported
- [x] Client disconnect handled gracefully (no crash, no leaked state)

### Gate interaction via A2UI
- [x] When a gate is waiting, A2UI client receives an interactive gate component
- [x] Client sends gate approval via A2UI interaction protocol
- [x] Gate resolves in Run.Server, all clients receive updated state
- [x] Full roundtrip: A2UI client connects → sees gate waiting → approves → run completes

### Mobile validation
- [x] A2UI endpoint is accessible from a mobile browser (WebSocket connection works)
- [x] Run status is readable on a small screen (A2UI components are mobile-friendly by design)

## Tests

### A2UI message format tests
- Provider emits valid A2UI JSON component descriptions
- Run status component contains required fields (run_id, status, progress)
- Node list component contains one entry per node with correct state
- Gate component contains prompt text and interaction affordances

### WebSocket connectivity tests
- Connect a test WebSocket client to the A2UI endpoint, verify handshake succeeds
- Client receives initial state on connection
- Client receives updates as run events occur
- Disconnect client, verify server-side cleanup
- Connect two clients to the same run, verify both receive updates

### Gate interaction tests
- Gate waiting → A2UI renders interactive component
- Send gate resolution via A2UI interaction protocol → gate resolves in Run.Server
- Resolution propagates to all connected clients

### Integration tests
- Start demo run (from M-OBS-05a), connect A2UI client, verify events from start to gate pause
- Resolve gate via A2UI, verify run completes and client receives completion

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- DAG visualization via A2UI (A2UI is component-based, not graphics-based)
- A2UI client app implementation (test with raw WebSocket clients)
- Polished A2UI component design (functional proof-of-concept)
- A2UI catalog negotiation (fixed component set)
- Authentication on the A2UI endpoint
- Performance optimization

## Findings to document

After completing this milestone, write a brief assessment:
- Does ex_a2ui work as expected? What needed fixing?
- Is the A2UI protocol suitable for Liminara's observation needs?
- What would it take to make this production-ready?
- Recommendation: continue investing, defer, or drop A2UI

## Spec reference

- `docs/research/a2ui_finding.md` (note: references v0.8, ex_a2ui is now v0.9)
- `docs/architecture/01_CORE.md §Observation`
- ex_a2ui v0.6.0: `https://github.com/23min/ex_a2ui` (232 tests, A2UI spec v0.9)
- A2UI spec v0.9: `https://github.com/google/A2UI/blob/main/specification/0.9/`
- A2UI spec v0.10 (draft): `https://github.com/google/A2UI/blob/main/specification/0.10/`

## Related ADRs

- none yet
