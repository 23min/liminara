# Fresh Analysis: What is Liminara, Really?

**Date:** 2026-03-14 (updated)
**Reviewer:** Claude (fresh-eyes review)
**Scope:** Landscape analysis, viability assessment, MVP strategy, lessons from Burr, ControlFlow, and Crosser

---

## 1. The Elevator Pitch You Haven't Found Yet

"Make for knowledge work" and "Make with a tape recorder" are good analogies for engineers, but they undersell the actual insight.

**Liminara is a provenance engine for nondeterministic computation.**

The world is building AI pipelines everywhere — but nobody can answer "why did this pipeline produce this output last Tuesday?" Everyone can replay a database migration. Nobody can replay an LLM-driven workflow. Temporal records *execution history* but treats nondeterminism as a nuisance. LangGraph has checkpoint replay but no content-addressed artifact lineage. Dagster has asset lineage but no decision recording.

The core insight — that nondeterminism isn't chaos, it's just **decisions you haven't recorded yet** — is the actual differentiator. The four-class determinism system (pure / pinned_env / recordable / side_effecting) is the most elegant part of this design. It doesn't exist anywhere else as a first-class architectural concept.

---

## 2. Landscape (March 2026)

### 2.1 The Market Is Validated

The orchestration/durable-execution space has exploded:

| Company | Valuation / Revenue | Signal |
|---------|-------------------|--------|
| **Temporal** | $5B (Series D, $300M) | Durable execution is a proven category. 380% YoY revenue growth, 20M+ monthly installs. |
| **n8n** | $2.5B ($180M Series C) | $40M ARR, 10x revenue growth in 2025. 75% of customers use AI features. |
| **Dagster** | $49M raised | Software-defined assets = closest philosophical match to Liminara's artifact-first model. |
| **Prefect** | $43.6M raised, $13.1M rev | ControlFlow (now archived → Marvin 3.0) was the closest "AI workflow orchestration" product. |
| **Restate** | $7M seed (2024) | "Durable async/await" — lightweight durable execution in Rust. |
| **Crosser** | Acquired by AVEVA (Schneider Electric) Dec 2025, est. SEK 500M-1B (~$45-90M) | Hybrid streaming/edge analytics. .NET 8 runtime. 800+ integrations. Swedish origin. |
| **AWS** | Lambda Durable Functions (re:Invent 2025) | Hyperscalers are entering the space. |

**Key trend:** The market is bifurcating into **data pipeline orchestration** (Airflow, Dagster, Prefect, Kestra) and **durable execution engines** (Temporal, Restate, Inngest, Hatchet). Liminara sits at the intersection but with a unique "recorded decisions" layer that none of these tools treat as first-class.

### 2.5 The Four Lanes — and the Gap Between Them

The orchestration space has fractured into four distinct lanes. Every one of them treats nondeterminism as someone else's problem:

| Lane | Players | What they do | What they don't do |
|------|---------|-------------|-------------------|
| **Streaming/Integration** | Crosser, n8n, Kafka, Flink | Move data continuously between systems | No artifacts, no provenance, no replay |
| **Data Pipeline** | Dagster, Prefect, Airflow | Schedule batch jobs, asset lineage | No decision recording, no nondeterminism handling |
| **Durable Execution** | Temporal, Restate, Inngest | Make code survive crashes | No content-addressing, no determinism classes |
| **Agent Frameworks** | LangGraph, CrewAI, Burr, Google ADK | Wire up LLM calls | No immutable artifacts, no true replay |

Liminara's unique position is the combination of three things nobody has put together:

1. **Content-addressed artifacts** (like Git/Nix) — "have I computed this exact thing before?"
2. **Decision records** (like a lab notebook) — "what did the LLM say, what did the human approve?"
3. **Determinism classes** (like a type system for side effects) — "is this op safe to cache? safe to replay?"

Crosser doesn't need any of this because factory sensor data is deterministic. Temporal doesn't need it because their typical workflow is "charge a credit card" not "ask an LLM to summarize." But the moment you have **knowledge work** — LLM calls, human judgments, evolutionary search, creative synthesis — you need all three.

### 2.6 Crosser: A Closer Look at What "Orchestration" Means in Industry

Crosser (founded 2016, Sweden, acquired by AVEVA Dec 2025) is instructive not as a competitor but as a **contrast case** that reveals what Liminara is *not*.

**Architecture:** Clean control plane / data plane separation. The Control Center (SaaS) manages flow definitions and monitoring. The Crosser Node (.NET 8, runs in Docker or as Windows service, 500MB RAM) executes flows locally — even offline. 100K+ msg/sec per node. Built-in HTTP server and MQTT broker.

**What a "flow" is:** A pipeline of typed modules — input (OPC UA, Modbus, MQTT, webhooks), transform (filter, aggregate, map, validate), output (databases, Kafka, cloud). 100+ built-in modules. Messages flow continuously. Custom modules in C#, Python, JavaScript.

**AI story:** Edge ML inference (TensorFlow, PyTorch, scikit-learn). Anomaly detection on streaming sensor data. No LLM integration, no prompt management, no generative AI orchestration.

**What Crosser proves:** Industrial companies will pay for orchestration (~$1.4M revenue, 20 people, acquired for $45-90M). The control plane / data plane split works. Visual flow design (their Flow Studio) is table stakes for adoption. But Crosser's world is deterministic — sensors produce numbers, you filter and route them. No decisions to record, no nondeterminism to tame.

**What Liminara learns from Crosser:**
1. **Visual flow design matters.** Every successful orchestration tool has one. Liminara's observation layer is read-only. Eventually you need a way to *design* DAGs visually, not just observe them.
2. **The "800 connectors" game exists but don't play it.** Crosser wins on breadth of integrations. Liminara wins on depth of provenance. Different games.
3. **Edge/hybrid deployment is valuable.** The BEAM's distribution capabilities (literally built for telecom at Ericsson) could be a differentiator for running nodes at the edge, coordinated from the cloud.

### 2.2 Decision Recording Is Emerging as a Recognized Need

Several recent projects and papers converge on the same problem Liminara addresses:

- **AgentRR** (arXiv:2505.17716, 2025) — Academic framework introducing record-and-replay for AI agent frameworks. Records interaction traces and internal decision processes.
- **R-LAM** (arXiv:2601.09749, 2026) — "Reproducibility-Constrained Large Action Models for Scientific Workflow Automation." Introduces structured action schemas, deterministic execution policies, and explicit provenance tracking.
- **Sakura Sky's "Missing Primitives for Trustworthy AI" blog series** — Part 8 on Deterministic Replay describes almost exactly Liminara's architecture: record mode vs replay mode, append-only traces, seven categories of captured data.
- **LangGraph Time Travel** — Checkpoint-based state replay for debugging nondeterministic LLM agents. Can rewind, modify logic, and replay.
- **Apache Burr** — State machine + replay for decision-making apps. Closest open-source project, but lacks content-addressed storage and decision recording.
- **Prefect ControlFlow** — Orchestrated multi-agent LLM workflows with structured outputs. Archived August 2025. See detailed analysis in Section 5.

**Nobody has built the full picture.** Content-addressed artifacts + decision records + DAG execution + determinism classes as a unified system does not exist.

### 2.3 Related Academic Research

- **"Reproducibility in Machine-Learning-Based Research"** (AI Magazine, 2025) — Five pillars: code versioning, data access, data versioning, experiment logging, pipeline creation.
- **"From Data to Decision"** (arXiv:2506.16051, 2025) — Six structured artifacts: Dataset, Feature, Workflow, Execution, Asset, Controlled Vocabulary.
- **"The (R)evolution of Scientific Workflows in the Agentic AI Era"** (arXiv:2509.09915, 2025) — Argues for evolving workflow tools into platforms supporting intelligent, multi-agent orchestration with provenance-aware decision-making.
- **"Audit Trails for Accountability in Large Language Models"** (arXiv:2601.20727, 2026) — Structured audit trail requirements for LLM-based systems.

### 2.4 The Elixir/OTP Bet

Contrarian but defensible. The BEAM's supervision trees, lightweight processes, and fault tolerance are uniquely suited for orchestration. The ecosystem has the building blocks (Oban Pro for job DAG execution, Commanded for event sourcing patterns, Broadway for data pipelines). The risk is smaller community and fewer LLM integrations, mitigated by the `:port` and `:container` executor model.

---

## 3. Viability Assessment

### 3.1 Is a Single Core Runtime Viable?

**Yes**, with two conditions:

1. **The BEAM is control plane only.** Heavy compute goes to Ports/NIFs/containers. The core dispatches, collects, and records. This is already in the design.
2. **Pipeline mode is the primary mode.** Discovery mode (dynamically expanding DAGs) works but is an order of magnitude more complex. Ship pipeline mode first.

The scheduler loop is genuinely simple — 10 lines of "find ready nodes, dispatch, collect, repeat." OTP supervision gives crash recovery for free. ETS + filesystem gives zero-dependency storage. This is one of the rare cases where building custom is defensible.

**The risk isn't the runtime. The risk is scope creep.**

### 3.2 Are Domain Packs Viable?

The Pack abstraction is sound. Five callbacks is the right surface area. The acid test is whether different domains reduce to the same primitives:

| Pack | Viability | Assessment |
|------|-----------|------------|
| **Radar** | High | Pipeline mode, clear product value, exercises LLM decisions, caching, scheduling. First product. |
| **Report Compiler** | High | Toy pack, perfect test fixture. Exercises every core concept in miniature. |
| **House Compiler** | Medium | IR pipeline maps literally, but needs Rust NIFs, binary artifacts, regulatory data. |
| **Software Factory** | Low (for now) | Discovery mode is genuinely harder. Competing with Claude Code, Cursor, Copilot agents. |
| **Everything else** | Cut | Agent Fleets, Population Sim, Evolutionary Factory — research projects, not products. |

**Prove the abstraction with Radar + Report Compiler. The house compiler is a later act once the runtime is solid.**

### 3.3 Is This Worth Building?

**In favor:**
- The gap is real — the specific combination doesn't exist
- The market is proven ($5B+ in durable execution)
- The timing is right — AI workflows exploding, regulation coming (EU AI Act, audit trails)
- Elixir/OTP is the right tool for orchestration

**Against:**
- Solo developer building what Temporal has 200+ engineers on
- Smaller Elixir ecosystem
- The "platform trap" — 2 years of infrastructure, no product
- Agent framework space moving fast (LangGraph, CrewAI, Google ADK iterate weekly)

**Verdict: Build it, but build a product first and extract the platform second.**

Don't build "Liminara the platform" and put Radar on top. Build "Radar the product" — a hosted intelligence briefing service — and extract the core runtime as it proves itself. The Report Compiler is the test fixture, not the product. Radar is the product.

---

## 4. MVP on Hetzner

### 4.1 Architecture

Single Hetzner VPS (CX31 or CX41, ~10-20 EUR/month):

```
Hetzner VPS (Ubuntu + Elixir)
├── Postgres (for Oban scheduling + optional metadata)
├── Liminara Core
│   ├── Artifact.Store (ETS + filesystem /var/lib/liminara/artifacts/)
│   ├── Event.Store (append-only files /var/lib/liminara/events/)
│   ├── Run.Server (GenServer per run)
│   └── Oban (scheduled jobs)
├── Radar Pack
│   ├── Ops: fetch, normalize, dedup, summarize, deliver
│   └── Schedule: every 6 hours
└── Web UI
    ├── Phoenix LiveView (lightweight, real-time)
    └── Pages: runs list, run detail (DAG view), artifact inspector, briefing viewer
```

### 4.2 Why Phoenix LiveView Instead of ex_a2ui (for MVP)

LiveView gives you a complete web app with real-time updates, authentication, and server-rendered HTML in one dependency. A2UI is the right long-term choice for the observation protocol, but for an MVP, LiveView is faster to build and more mature. Add A2UI as an additional rendering target later.

### 4.3 What the MVP Does

1. Configure sources (RSS feeds, websites, HN) via web form
2. Every 6 hours, Oban triggers a Radar run
3. Pipeline: fetch → normalize → dedup (against previous run) → LLM rank+summarize → produce briefing
4. See the briefing in the web UI, with full provenance (which sources contributed, what the LLM decided, cached vs fresh)
5. Replay any run, see decision diffs between runs, inspect any artifact

### 4.4 What This Proves

- The core runtime works (DAG execution, artifact store, event log)
- Decision recording works (LLM summarization is reproducible)
- Caching works (unchanged sources skip re-processing)
- The Pack abstraction works (Radar is self-contained)
- It's a product someone would actually use (you!)

### 4.5 Timeline (Realistic, Solo Dev)

- Weeks 1-2: `mix new liminara` — Artifact.Store, Event.Store, Plan, Run.Server, Op behaviour
- Weeks 3-4: Report Compiler toy pack (proves the core)
- Weeks 5-7: Radar pack with real HTTP fetching + LLM integration
- Weeks 8-9: Phoenix LiveView UI (runs list, DAG view, briefing viewer)
- Week 10: Oban scheduling + deploy to Hetzner
- Weeks 11-12: Polish, replay feature, cache visualization

**3 months to a working, hosted, daily-use product.**

---

## 5. Lessons from Apache Burr and Prefect ControlFlow

### 5.1 Apache Burr — Deep Technical Comparison

Burr (entered Apache Incubator May 2025, ~1.4K stars, used by Coinbase, TaskHuman) models applications as **state machines** (graphs with cycles), not DAGs. The fundamental unit is the **action** — a function that reads/writes an immutable `State` object.

```python
app = (
    ApplicationBuilder()
    .with_actions(action1=action1, action2=action2)
    .with_transitions(("action1", "action2", when(...)), ("action2", "action1"))
    .with_state(chat_history=[])
    .with_entrypoint("action1")
    .build()
)
```

#### Key Architectural Differences

| Aspect | Liminara | Burr |
|--------|----------|------|
| **Graph model** | Data-flow DAG (artifacts on edges) | Control-flow state machine (shared state) |
| **Core abstraction** | Artifact (immutable, content-addressed) | State (immutable updates, single object) |
| **Nondeterminism** | First-class (4 classes, Decision records) | Invisible (framework-agnostic) |
| **Persistence** | Event sourcing (append-only log) | State checkpointing (snapshots) |
| **Replay** | Deterministic (inject stored decisions) | Fork from checkpoint (re-execute, may differ) |
| **Caching** | Content-addressed (hash of op + input hashes) | Manual / not built-in |
| **Cycles** | No (DAG; use fixed-point wrapper) | Yes (state machine with loops) |

**Critical insight:** Burr saves **state snapshots** (the full State at each step). Liminara saves **events** (append-only log from which state is derived). Event sourcing gives time-travel and "what happened between minute 3 and minute 7" for free; checkpoint-based persistence gives simpler random-access.

**Burr cannot replay deterministically.** It has no concept of recording nondeterministic choices. You can fork from a checkpoint, but re-execution of LLM calls produces different results.

#### What to Adopt from Burr

1. **Lifecycle hook protocol.** Burr's `PreRunStepHook` / `PostRunStepHook` pattern is a clean extensibility model. Liminara should define an explicit hook API beyond just `:pg` event broadcast — lower the barrier for integrations (telemetry, cost tracking, custom logging).

2. **Fork-from-checkpoint as an explicit API.** Burr's `fork_from_sequence_id` lets you snapshot mid-execution and branch. Liminara's event sourcing supports this naturally, but it should be an explicit API: `Run.fork(run_id, after_node: :normalize)`.

3. **Multiple execution granularities.** Burr offers `step()`, `iterate()`, `run()`, and `stream_result()`. Liminara should offer similar: single-step for debugging, full execution for production, streaming for the observation UI.

4. **Enforce input/output declarations at runtime.** Burr's `reads`/`writes` declarations on actions create a clean contract. Liminara already has `inputs` and `outputs` on Op — make sure these are enforced (reject an op that produces an undeclared output).

### 5.2 Prefect ControlFlow — Post-Mortem Analysis

ControlFlow was archived in August 2025 and merged into Marvin 3.0 (using Pydantic AI). Three core concepts:

- **Task**: Discrete work unit with `result_type` (Pydantic model) for structured output validation
- **Agent**: LLM-powered entity with custom instructions and tools
- **Flow**: Container orchestrating tasks and agents with shared context

```python
@cf.flow
def research_workflow():
    topic = cf.Task("Get research topic", interactive=True)
    proposal = cf.run("Generate proposal",
                      result_type=ResearchProposal,
                      depends_on=[topic])
    return proposal
```

#### Why It Was Archived (Cautionary Lessons)

1. **Tight Prefect coupling** — users who wanted agentic DX were forced to take Prefect as a dependency
2. **No deployment strategy** — no built-in way to deploy to production
3. **Orchestration freezing** — flows with >2 tasks could freeze due to tool-use failures
4. **Naming collision** — ControlFlow's "flow"/"task" collided with Prefect's own concepts
5. **No explicit DAG control** — abstracted too heavily toward LLM-driven agentic flows

#### What to Adopt from ControlFlow

1. **Schema validation on artifact types.** ControlFlow's Pydantic `result_type` with custom validators is a strong pattern. Liminara's artifacts have a `type` field but no validation. Consider: ops declare output schemas, runtime validates before storing. Catches bugs early, makes the DAG self-documenting.

2. **Human gate DX shorthand.** ControlFlow's `interactive=True` is a clean API. Liminara's gate concept is more powerful (it's a recorded decision), but the DX of marking a task as interactive is worth emulating.

3. **Multi-agent collaboration strategies** (for pack layer, not core). ControlFlow 0.9 had round-robin, moderated, delegation patterns. Useful for the Software Factory pack.

4. **The cautionary tale: don't couple the core to optional dependencies.** ControlFlow died partly because of tight coupling. Liminara's "zero external dependencies for core" principle is vindicated. Keep the core pure BEAM. Keep ex_a2ui and Oban optional.

### 5.3 Comparative Summary

| Capability | Liminara | Burr | ControlFlow |
|-----------|----------|------|-------------|
| Decision recording | First-class | None | None |
| Deterministic replay | Yes (inject decisions) | No (fork only) | No |
| Content-addressed artifacts | Yes | No | No |
| Determinism classes | 4 classes, automatic caching | None | None |
| Event sourcing | Yes (append-only log) | No (checkpoints) | No (Prefect tracking) |
| OTP supervision | Yes (crash recovery for free) | No (Python) | No (Python) |
| Schema validation on outputs | Gap (should add) | No | Yes (Pydantic) |
| Lifecycle hooks | Via `:pg` broadcast | Yes (rich API) | Via Prefect |
| Fork-from-checkpoint | Possible but not API | Yes (explicit) | No |
| Cycles in graph | No (DAG) | Yes (state machine) | No |

**Liminara's unique combination is genuinely novel.** Neither Burr nor ControlFlow can replay a run deterministically. The gap is real.

---

## 6. Conclusions

### 6.1 What This Is

Liminara is a **provenance engine for nondeterministic computation** — a system that makes AI-driven workflows reproducible, auditable, and debuggable by treating nondeterminism as recorded decisions rather than uncontrolled chaos.

The five-concept model (Artifact, Op, Decision, Run, Pack) is clean and sufficient. The scheduler is simple. The event sourcing approach is proven. The Elixir/OTP fit is genuine.

### 6.2 What to Build

1. **Build Radar as a product**, not Liminara as a platform
2. **Extract the core** as the runtime proves itself against Radar and Report Compiler
3. **Ship to Hetzner** within 3 months — a daily-use intelligence briefing service
4. **Add schema validation** on artifact types (lesson from ControlFlow)
5. **Add lifecycle hooks and fork API** (lesson from Burr)
6. **Keep the core zero-dependency** (lesson from ControlFlow's death)

### 6.3 What Not to Build

- Discovery mode (v2, after pipeline mode is proven)
- More than 3 packs (Radar, Report Compiler, eventually House Compiler)
- Multi-tenancy, distributed execution, Wasm
- A "platform" before you have a product

### 6.4 The One Thing That Makes This Worth It

Decision recording. If you build nothing else that's novel, build the decision recording and deterministic replay. That's the part nobody else has. That's the part the academics are writing papers about. That's the part that will matter when AI audit trails become mandatory.

---

*This analysis supersedes 01_First_Analysis.md (2026-03-02) with updated landscape data and deeper technical comparisons.*
