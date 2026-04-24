# Agent Fleets — Continuously Operating Agent Infrastructure

**Can provenance infrastructure scale to hundreds of long-lived agents that come and go, react to events, checkpoint their state, and produce durable outputs?**

Far horizon | Fleet deployment, stimulus-response, checkpointing, agent lifecycle

---

## The idea

Not a workflow with five agents. An **operating layer for agents** — long-lived, continuously running groups that react to stimuli (timers, webhooks, inboxes, sensor events), process them in episodes, checkpoint their state as durable artifacts, and resume on demand. Agents are deployed, upgraded, scaled, and retired. The fleet persists even as individual agents come and go.

Think IoT, but for intelligent agents. A fleet of 200 monitoring agents, each watching a different data source, each with its own checkpoint state, each producing artifacts when something interesting happens. Some are always active. Some wake on a timer. Some respond to external events. The BEAM — built at Ericsson for managing millions of concurrent telecom connections — is architecturally native to this pattern.

---

## How it maps

```
Fleet Deployment Spec ──→ stimulus arrives ──→ dispatch ──→ load checkpoint ──→ handle ──→ perform action
(fleet.deployment.v1)    (fleet.stimulus.v1)    (pure)       (pure)           (recordable)  (side-effecting)
                                                  │                              │              │
                                                  │  route to correct            │  agent       │  external
                                                  │  agent by type               │  logic/LLM   │  effects
                                                  │  + deployment                │  DECISION     │  gated
                                                  │                              │  RECORDED     │
                                                  │                              ▼              │
                                                  │                     new checkpoint ─────────┘
                                                  │                     (fleet.checkpoint.v1)
                                                  │                     durable, resumable
                                                  │
                                            ┌─────┴──────┐
                                            │ Episode run │  ← one stimulus = one DAG run
                                            │ append-only │    with full provenance
                                            │ event log   │
                                            └────────────┘
```

Each stimulus produces an **episode** — a complete Liminara run with its own event log, decision records, and artifacts. The checkpoint artifact from one episode becomes input to the next. The agent's history is the chain of episode runs, each independently replayable.

---

## What makes this more than "run many pipelines"

**Deployment as configuration.** A fleet spec defines agent types, tool allowlists, schedules, budgets, and checkpoint policies — all as versioned artifacts. Redeploy = new spec version, cache keys change, agents reconfigure automatically.

**Stimulus routing.** Incoming events are dispatched to the correct agent(s) by a pure routing op. Timer ticks, webhooks, inbox messages, sensor readings — the fleet handles heterogeneous event sources.

**Checkpointing as artifacts.** Agent state is not in memory — it's a content-addressed artifact. Kill an agent, restart it tomorrow, it resumes from its last checkpoint. Like Ethereum smart contracts: state on disk, computation only on activation. This is the "activatable run" pattern from `docs/research/08_graph_execution_patterns.md`, applied at scale.

**Idempotent stimuli.** Every stimulus has a deduplication key. Process the same event twice? The second time is a no-op. Essential for reliability when agents number in the hundreds.

**Budget and policy.** Per-agent budgets, tool allowlists, secret scoping. The fleet controls what agents can do, not just what they compute. An agent exceeding its budget is paused, not crashed.

---

## What this exercises as a Liminara validation

This is where Liminara's Erlang/OTP heritage pays off most directly. The BEAM was designed for exactly this: millions of lightweight processes, supervised, isolated, fault-tolerant, hot-upgradable. What was built for telecom switches becomes infrastructure for agent fleets.

- The "activatable run" pattern at scale — hundreds of runs that start, checkpoint, stop, restart
- OTP supervision under real load — the BEAM managing hundreds of concurrent agent processes with independent failure domains
- Artifact accumulation over time — thousands of episode checkpoints and outputs, content-addressed, garbage-collectable by policy
- The boundary between runtime (scheduling, checkpointing, routing) and agent logic (LLM decisions, tool use)
- Fleet-level observation — seeing the health and behavior of the collective, not just individual agents

---

*Far-horizon exploration. The fleet pattern is architecturally supported by the existing runtime (episode runs, checkpoints as artifacts, activatable runs via event sourcing). The fleet-specific ops (dispatch, checkpoint management, policy enforcement) are the new work.*
