# Observation Layer: Design Notes

Notes from analysis of prior art (Nummesh concept, FRP, Reactive Demand Programming / Sirea / Awelon Blue). These should inform M-OBS-03 (DAG visualization) and M-OBS-04 (inspectors) design decisions.

---

## 1. Show the grid, not the logic

Spreadsheets succeed because users see **values**, not control flow. The observation UI should default to showing the **current state of computed values** — artifact contents inline in each node — rather than foregrounding the execution machinery (status badges, arrows, workflow diagrams).

Concretely:
- Each DAG node's primary display should be its **output value** (or a preview), not its Op type or implementation.
- Status (running/completed/failed) is secondary — conveyed by color/border, not as the main content.
- The user's mental model should be "a grid of results that fills in as computation proceeds," not "a workflow engine advancing through steps."
- This is what the plan already calls "the Excel quality." This note makes the design principle explicit.

**Source:** Nummesh notes — "In spreadsheets, each cell pulls in values and computes. There are no imperative instructions. Control constructs are replaced by functional constructs." RDP tagline: "stateless logic on a stateful grid."

---

## 2. Behaviors vs Events as distinct subscription abstractions

FRP distinguishes two abstractions:
- **Behaviors**: time-varying values — "what is the current state?" (continuous)
- **Events**: discrete occurrences — "what just happened?" (stream)

The Observation.Server already maintains both: the view model (behavior) and the event stream. The renderers should consume them as **explicitly separate things**:

- **DAG visualization + Node inspector** → subscribe to the **view model** (behavior). They show current state. When a node completes, the UI shows its new value — it doesn't need to know about the event that caused the transition.
- **Event timeline** → subscribes to the **event stream**. It shows history. Each event is a discrete occurrence.

This distinction should be visible in the PubSub topic design or the Observation.Server API:
```
# Behavior (current state snapshot + diffs)
Observation.Server.get_state(run_id)       # snapshot
PubSub topic: "observation:#{run_id}:state" # diffs

# Events (discrete stream)
Observation.Server.get_events(run_id)      # history
PubSub topic: "observation:#{run_id}:events" # new events
```

This keeps the renderers clean: the DAG view never parses events, the timeline never reconstructs state.

**Source:** FRP literature (Elliott & Hudak 1997). "A behavior is a function of time; an event source is a list of time/value pairs."

---

## Non-goals

These principles do NOT mean:
- Building a visual programming environment (the DAG is read-only observation)
- Eliminating the DAG graph layout (it's valuable for showing structure/dependencies)
- Real-time streaming in the FRP sense (LiveView server-push is sufficient)

The goal is to bias the UI toward **values and results** over **process and plumbing**.
