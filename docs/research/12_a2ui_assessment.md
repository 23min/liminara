# A2UI Assessment — Post M-OBS-05b

**Date:** 2026-04-01
**ex_a2ui version:** 0.6.0 (A2UI spec v0.9)

## Does ex_a2ui work as expected?

Yes, with minor additions:

- **SurfaceProvider behaviour** works well. The init/surface/handle_action/handle_info contract is clean and composable.
- **Builder pipe API** is the right abstraction for constructing component trees. Direct struct manipulation is too verbose.
- **WebSocket transport** is solid. Bandit + WebSock handles connections, reconnects, and concurrent clients correctly.
- **Debug renderer** (built-in HTML page) is surprisingly useful for development — renders Cards, Buttons, Lists with working click actions.

**What needed fixing/adding:**
- Added `A2UI.Supervisor.running?/0` for test assertions
- Added explicit `{:plug, "~> 1.14"}` dep (was implicit via bandit)
- Extracted WebSocket test client from `A2UI.Socket` to `A2UI.TestClient` to avoid `:gun` compile warnings in non-test builds
- These are small, clean changes — no fundamental issues with the library.

## Is the A2UI protocol suitable for Liminara's observation needs?

**For status display and gate interaction: yes.** The component model (Card, Text, Button, List, Row) maps naturally to run status, node lists, and gate approval forms. Data binding via PubSub → surface push works for real-time updates.

**Limitations encountered:**
- **No DAG visualization** — A2UI is component-based, not graphics-based. The metro-map DAG can't be rendered via A2UI components. This is fine — A2UI is complementary to LiveView, not a replacement.
- **No incremental updates** — every state change rebuilds the full surface. For 10 nodes this is fine; for 100+ nodes, data model updates (updateDataModel) with bound values would be needed.
- **Reconnection** — the debug renderer loses query params on WebSocket reconnect, causing "missing_run_id" errors for stale connections. This is a renderer issue, not a protocol issue.

## What would it take to make this production-ready?

1. **Proper renderer** — replace the debug renderer with a Lit or React component that renders Liminara-specific components (run status card, node progress list, gate form). The debug renderer is fine for dev but too generic for users.
2. **Data model binding** — use `updateDataModel` for incremental node status changes instead of rebuilding the full component tree on every event.
3. **Multi-surface** — one surface per run, managed by a surface registry. Currently each WebSocket connection creates its own surface.
4. **Authentication** — the A2UI endpoint has no auth. Add token-based auth before exposing outside localhost.
5. **Error handling** — surface provider errors should produce user-visible error components, not WebSocket disconnects.

## Recommendation

**Continue investing.** A2UI works well for the observation use case. The dual-renderer architecture (LiveView for desktop, A2UI for mobile/lightweight clients) is validated. Next steps:

- Build a minimal Lit renderer for Liminara's A2UI surface (run status, node list, gate interaction)
- Add A2UI observation to the Radar pack (Phase 5) as a secondary UI
- Investigate v0.10 `actionResponse` for synchronous gate approval feedback
