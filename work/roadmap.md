# Roadmap

## Phase 0: Data Model — Complete

- [x] E-01 Data Model Spec

## Phase 1: Python SDK / Data Model Validation — Complete

- [x] E-02 Python SDK (data model validation + demo artifact)
- [x] E-03 LangChain Integration

## Phase 2: Elixir Walking Skeleton — Complete

- [x] E-04 Elixir Project Scaffolding + Golden Fixtures
- [x] E-05 Storage Layer (Artifact Store + Event Store + Decision Store)
- [x] E-06 Execution Engine (Plan + Op + Run.Server + Cache)
- [x] E-07 Integration and Replay (end-to-end, Pack behaviour, interop)

## Phase 3: OTP Runtime Layer — Complete

- [x] E-08 OTP Runtime (supervision tree, Run.Server GenServer, :pg broadcasting, crash recovery, property-based stress testing, toy pack)

## Phase 4: Observation Layer — Complete

- [x] E-09 Observation Layer (Observation.Server, Phoenix LiveView UI, DAG visualization, inspectors, A2UI experimental renderer)
  - [x] M-OBS-01 Observation Server — renderer-agnostic event projection
  - [x] M-OBS-02 Phoenix scaffolding + runs dashboard
  - [x] M-OBS-03 SVG DAG visualization with real-time updates
  - [x] M-OBS-04a Node inspector + artifact viewer + dashboard layout
  - [x] M-OBS-04b Event timeline + decision viewer
  - [x] M-OBS-05a Gate demo + LiveView gate interaction
  - [x] M-OBS-05b A2UI exploration + integration

## Phase 5: Radar — Planning

- [x] E-10 Port Executor (prerequisite — `:port` executor for Python ops via Erlang Ports)
  - [x] M-PORT-01 Port protocol + executor + Python runner
  - [x] M-PORT-02 Integration test (all determinism classes)
- [ ] E-11 Radar Pack (daily intelligence briefing pipeline)
  - [ ] M-RAD-01 Pack + source config + fetch (~47 sources)
  - [ ] M-RAD-02 Extract + embed + dedup (embedding provider TBD)
  - [ ] M-RAD-03 Cluster + rank + render (Haiku summaries)
  - [ ] M-RAD-04 Web UI + scheduler (LiveView + GenServer)
  - [ ] M-RAD-05 Serendipity exploration (Tavily, enhancement)

## Phase 6: Oban + Postgres — Not started

*Epics not yet drafted.*

## Phase 7: House Compiler — Not started

*Epics not yet drafted.*
