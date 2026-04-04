# Agent Frameworks Landscape: LangGraph and Cloudflare Agents

**Date:** 2026-03-22
**Source:** ["LangGraph vs Cloudflare Agents: Queues, Scheduling, and Durable Execution"](https://www.agentnative.dev/blog/langgraph-vs-cloudflare-agents-queues-scheduling-and-durable-execution), Agent Native, February 6, 2026
**Context:** Research gathered to orient Liminara relative to the emerging agent framework space. Not a list of things to build — a positioning analysis.

---

## What the Article Is Saying

The piece is a practical comparison of two systems attacking the same three-part problem: **queue it, schedule it, survive a crash**. It calls this the "later + reliably + resume" trio.

**LangGraph** is a Python orchestration framework. You express agent logic as a directed graph of nodes. If you add a "checkpointer", it saves graph state at the boundary of each "super-step" to a thread. That's its durability model: crash mid-step → resume from the start of that step. The checkpoint history also gives you time-travel debugging, human-in-the-loop, and replay. LangGraph's replay means: *re-run from a saved snapshot*.

**Cloudflare Agents** are a runtime primitive built on Durable Objects. Each agent is a globally unique, single-threaded, stateful micro-server — like an actor, of which you can have millions. They survive restarts because their state is durable storage. They can be "woken up" via alarms. For longer background work, you pair them with **Cloudflare Workflows** — which add step-level durability with retries and `waitForEvent` for human approval gates.

The article compares them on three axes:

**Queueing.** Cloudflare has a built-in `queue()` that persists tasks to SQLite and processes them sequentially (FIFO). No built-in retries or priority. For a decoupled queue, you use Cloudflare Queues (a separate product). LangGraph doesn't prescribe a queue — you run graphs wherever you like (workers, Celery, Kubernetes jobs). Via its server layer it offers background runs with polling or webhook completion.

**Scheduling.** Cloudflare's `schedule()` supports delays, fixed dates, and cron; `scheduleEvery()` adds fixed-interval recurrence. LangGraph's server layer supports cron jobs running an assistant on a schedule. Both are solved infrastructure, not novel architecture.

**Durable execution.** LangGraph checkpoints at node boundaries; a crash means resuming from the start of the failed node. Cloudflare Agents persist state via Durable Objects; Workflows add step-level retries and can `waitForEvent`. The article frames LangGraph's checkpoint history as a "superpower" for time-travel debugging and introspection.

The article's conclusion: use Cloudflare when the product magic is the *experience* (realtime, edge, stateful UX). Use LangGraph when the product magic is the *orchestration logic* (branching, inspection, replay, HITL).

---

## How This Maps to Liminara

### Where Liminara is solving the same problem — and going further

**Durable execution** is the central concern of both systems. LangGraph checkpoints at node boundaries. Cloudflare persists agent state in SQLite-backed Durable Objects. Liminara's answer is **event sourcing from an append-only, hash-chained JSONL log** — and it is fundamentally more principled than either.

LangGraph saves *the current state*. Liminara saves *every event that ever happened*. This means:
- Crash recovery is rebuilding state from the log (implemented in Phase 3)
- The history of how you got there is preserved — you have an audit trail, not just a snapshot
- The durability mechanism is the same one that enables compliance, replay, and caching — it's one mechanism with multiple consequences, not several bolted-together mechanisms

This maps directly to the "activatable runs" pattern captured in the archived `docs/history/architecture/02_PLAN.md`:

> *"Event arrives → Start Run.Server, rebuild state from event log → Dispatch newly ready nodes → If nothing to dispatch, stop the GenServer → Event log persists on disk. Run state is safe."*

This is exactly what Cloudflare alarms do for Durable Objects — wake up, do some work, sleep again — but Liminara's version is semantically richer because the event log contains the full causal history of the run, not just current state.

**Human approval gates** appear in both systems as a recognized first-class use case. Cloudflare Workflows use `waitForEvent`. LangGraph uses checkpoint-based interrupts. Liminara has gates — ops that return `{:gate, prompt}` and pause the run. The article validates this is the right primitive. The "Enhanced gate API" (webhooks, timeouts, delegation) is correctly deferred in the build plan; the basic mechanism is already sound.

**Debuggability.** The article specifically calls out LangGraph's checkpoint history as exceptional for time-travel debugging. Liminara's event log + content-addressed artifacts provide more than LangGraph here. You don't just have snapshots — you have every intermediate artifact, its hash, what op produced it, and what decisions were made. The Excel analogy in `01_CORE.md` is the right framing: every value visible, every formula traceable, every dependency inspectable.

---

### Where Liminara is solving a different and harder problem

This is the most important distinction. Both LangGraph and Cloudflare Agents solve **fault tolerance**: if something crashes, pick up where you left off. That is valuable. But Liminara solves **reproducibility of nondeterminism** — a fundamentally different problem.

LangGraph's "replay" means: re-run from a checkpoint snapshot. If an LLM call returns something different on the second run, LangGraph doesn't care — it just re-executes. There is no concept of a **decision record**.

Liminara's replay means: inject the stored decisions from the first run so every nondeterministic choice produces the same output. The LLM response was recorded. The human approval was recorded. The GA selection was recorded. On replay, these are fed back in — the run becomes deterministic.

Neither LangGraph nor Cloudflare has this. Neither system could produce an EU AI Act Article 12 compliance report, verify tamper-evidence, or prove that a run executed exactly as recorded. Liminara can — not because compliance tooling was bolted on, but because decision recording is the core architecture.

A related gap: **content-addressed artifacts with determinism classes**. Liminara's cache key is `hash(op, version, input_hashes, env_hash?)` and ops are formally classified as `pure / pinned_env / recordable / side_effecting`. This is build system semantics — the same rigor as Nix or Bazel — applied to AI pipelines. Neither LangGraph nor Cloudflare comes close to this. They have "retries" and "idempotency warnings". Liminara has a formal model.

Both systems acknowledge idempotency as important but treat it as a user responsibility: "guard your side effects." Liminara's determinism classes make this explicit and structural. `side_effecting` ops are explicitly marked, their outputs are recorded as decisions, and caching behavior is formally defined per class. This is a meaningful differentiator worth naming in public documentation.

---

### What Liminara is not doing — and doesn't need to

The Cloudflare Agents value proposition is largely about **per-user, realtime, edge-native** stateful experiences — chat interfaces, collaborative agents, live progress feeds. Liminara is not building that and shouldn't. It's a different product category entirely. Liminara's observation layer (Phase 4) gives you live visibility into a run, but that's for the operator/developer — not a user-facing product.

Liminara is also not (yet) doing scheduling as a first-class primitive — that's correctly deferred to Oban in Phase 6. The article validates that scheduling is mostly solved infrastructure (cron, alarms, job queues) and doesn't require novel architecture. Oban is the right choice.

---

### Strategic observations

**LangGraph integration is already the right idea.** Phase 1 of the build plan includes `LiminaraCallbackHandler` for LangChain. The article implicitly positions LangGraph as a popular framework with limited intrinsic auditability. A Liminara adapter for LangGraph — recording decisions from LangGraph runs into Liminara's event log and artifact store — would be a compelling story: "LangGraph for orchestration logic, Liminara for provenance and replay."

**The "build system for AI" framing holds up very well against this landscape.** The article's taxonomy (queue / schedule / durable execution) is about operational reliability. Liminara's framing (artifact / op / decision / run / pack) is about *epistemic* correctness — knowing what happened and why. These are orthogonal, and the article unintentionally demonstrates the gap: both LangGraph and Cloudflare can survive a crash, but neither can tell you, months later, exactly which LLM response led to which output.

**The "activatable runs" architecture is well-timed.** The article shows this pattern is a recognized need — Cloudflare alarms, LangGraph crons. Liminara's version via Oban in Phase 6 will be more powerful because Oban activates a GenServer that rebuilds from a full event history, not just triggers a function with current state.

---

## Comparison Table

| | LangGraph | Cloudflare Agents | Liminara |
|---|---|---|---|
| **Core model** | Graph + checkpoints | Durable Object actors | Event-sourced DAG |
| **Fault tolerance** | Resume from last checkpoint | Durable Object state persists | Rebuild from event log |
| **Replay semantics** | Re-run from snapshot | N/A (stateful, not replay-oriented) | Inject stored decisions → deterministic |
| **Decision recording** | No | No | Yes (first-class) |
| **Content-addressed artifacts** | No | No | Yes (core primitive) |
| **Determinism classes** | No | No | Yes (formal) |
| **Compliance-grade auditability** | No | No | Yes (by design) |
| **Scheduling** | Via server layer / external | Built-in (alarms, cron) | Deferred to Oban (Phase 6) |
| **Human gates** | Checkpoint-based interrupts | `waitForEvent` in Workflows | Gates (op returns `{:gate, prompt}`) |
| **Target use case** | Orchestration logic, HITL | Realtime UX, edge, per-user agents | Reproducible nondeterministic computation |

---

## Verdict

The article is not describing competition — it is describing adjacent terrain. LangGraph and Cloudflare Agents solve reliability. Liminara solves reproducibility and auditability. The intersection is fault tolerance and human gates, where Liminara is already well-positioned. The divergence is in decision recording and content-addressed artifact graphs, where Liminara is doing something neither system can touch.

---

*See also:*
- *[02_Fresh_Analysis.md](../analysis/02_Fresh_Analysis.md) — landscape and competitive analysis*
- *[05_Why_Replay.md](../analysis/05_Why_Replay.md) — the case for recorded decisions*
- *[ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) — intellectual ancestors and formal models*
