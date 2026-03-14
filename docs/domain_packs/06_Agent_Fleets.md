# Domain Pack: Agent Fleet Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `agent_fleets`

---

## 1. Purpose and value

Support long-lived, continuously operating groups of agents (“fleets”) that react to stimuli (timers, events, inboxes) and produce durable outputs.

This pack codifies fleet semantics on top of the core: deployments, stimuli, episodes, checkpoints, and observability.

### Fit with the core runtime

Fleets are implemented as repeated **episode runs** with checkpoint artifacts; the core remains a DAG runner plus scheduler.

### Non-goals

- Make the BEAM the compute substrate for heavy tasks.
- Run forever without checkpointing; fleet must be resumable from artifacts.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is “agentic”). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Fleet Deployment Spec (`IR0`)

Fleet config: agent types, tools allowlists, schedules, budget, and checkpoint policy.

**Artifact(s):**
- `fleet.deployment.v1`

### Stimulus Envelope (`IR1`)

Incoming event/tick message with idempotency key.

**Artifact(s):**
- `fleet.stimulus.v1`

### Episode Checkpoint (`IR2`)

Durable agent state snapshot after handling stimulus.

**Artifact(s):**
- `fleet.checkpoint.v1`

### Episode Outputs (`IR3`)

Artifacts produced by the episode (reports, actions, deliveries).

**Artifact(s):**
- `fleet.outputs.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`fleet.dispatch`** — *Pure deterministic*, *no side-effects*
  - Route stimulus to correct deployment/agent(s) and create an episode run.
  - Inputs: `fleet.stimulus.v1`
  - Outputs: `run.manifest.v1`
- **`fleet.load_checkpoint`** — *Pure deterministic*, *no side-effects*
  - Load last checkpoint artifact for the deployment/agent.
  - Inputs: `fleet.deployment.v1`
  - Outputs: `fleet.checkpoint.v1`
- **`fleet.handle_stimulus`** — *Nondeterministic but recordable*, *no side-effects*
  - Agent logic/LLM tools; produce outputs and next checkpoint.
  - Inputs: `fleet.stimulus.v1`, `fleet.checkpoint.v1`
  - Outputs: `fleet.outputs.v1`, `fleet.checkpoint.v1`
- **`fleet.perform_action`** — *Side-effecting*, *side-effect*
  - Execute external side effects (post message, write file) with gating and idempotency.
  - Inputs: `fleet.outputs.v1`
  - Outputs: `fleet.action_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Tool use decisions**: Tool call plans + arguments; record all results.
  - Stored as: `decision.llm_tool_trace.v1`
  - Used for: Replay + incident review.
- **Human-in-the-loop interrupts**: Approve or modify agent state mid-episode.
  - Stored as: `decision.gate_approval.v1`
  - Used for: Safety and correctness.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Fleet dashboard (health, backlog, budgets).
- Per-agent timeline (stimuli handled, decisions, outputs).
- Interrupt/approval UI to resume episodes.

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- LLM executor; tool executors (web, repo, email, etc).
- Scheduler/timer service for stimuli creation.

---

## 8. MVP plan (incremental, testable)

- Define FleetDeployment + Stimulus + Episode run mapping.
- Implement checkpoint artifact and resume.
- Add interrupts and a simple A2UI fleet dashboard.

---

## 9. Should / shouldn’t

### Should

- Make every stimulus idempotent and deduplicated by key.
- Checkpoint after every episode; avoid long-running uncheckpointed behavior.

### Shouldn’t

- Don’t keep fleet state only in memory.
- Don’t allow tool calls that require secrets unless explicitly authorized for the deployment.

---

## 10. Risks and mitigations

- **Risk:** Run explosion
  - **Why it matters:** Fleets create many runs over time.
  - **Mitigation:** Retention/compaction; aggregate dashboards; sampling.
- **Risk:** Unbounded tool access
  - **Why it matters:** Agents can become an attack surface.
  - **Mitigation:** Policy engine, allowlists, secret scoping, auditing.

---

## Appendix: Related work and competitive tech

- [Temporal Workflows](https://docs.temporal.io/workflows) — Durable execution model for long-running workflows.
- [LangGraph overview](https://docs.langchain.com/oss/javascript/langgraph/overview) — Agent workflows with durable execution + HITL.
- [Prefect schedules](https://docs.prefect.io/v3/how-to-guides/deployments/manage-schedules) — Deployment/schedule concepts.
- [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/) — Lightweight agent framework.
