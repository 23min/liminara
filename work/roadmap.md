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

## Phase 5: Radar — Not started

*Epics not yet drafted.*

## Phase 6: Oban + Postgres — Not started

*Epics not yet drafted.*

## Phase 7: House Compiler — Not started

*Epics not yet drafted.*
