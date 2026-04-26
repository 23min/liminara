generated_at: 2026-04-26T14:39:15Z
source_sha: 13dd4512c60b7a8dc0e03efc89bc042ee39fb196
docs_tree_hash: 728c0a92a319f91a446ee22b0b8439191a29702b7227b45d8ef3df805b898ed1
generator: doc-lint full

# Docs Index

_Bootstrap entry — first ever doc-lint full pass on 2026-04-26. Each entry below carries minimal-but-correct metadata (path, sha, purpose extracted from H1, sections from ## headers); richer fields (`covers`, `references`, `authoritative_for`) populate over time via `doc-garden verify` passes. `tier` and `last_verified` default to `—` per the bootstrap rule._

## docs/analysis/01_First_Analysis.md
sha: 524024ce877a984c4531ab3f51f52f4a4ed5e68c
purpose: First Analysis: Honest Review of the Liminara Core Runtime
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Executive Summary — —
  - 1. A2UI: Good Choice, but Understand the Maturity — —
  - 2. The Specs Are AI-Generated (and It Shows) — —
  - 3. Scope Analysis: Why This Could Die — —
  - 4. Build vs Buy: The Case Against Building — —
  - 5. Core Design Issues (Assuming You Build) — —
  - 6. What the Specs Get Right — —
  - 6.8 Validation strategy: omvärldsbevakning first, with a house spike — —
  - 7. Hardening Recommendations — —
  - 8. The One-Page Version (What To Actually Do) — —
  - Appendix: Document-by-document notes — —

## docs/analysis/02_Fresh_Analysis.md
sha: e8bbdc106a69ee36ed282c983ddfa6d5d25393b6
purpose: Fresh Analysis: What is Liminara, Really?
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Elevator Pitch You Haven't Found Yet — —
  - 2. Landscape (March 2026) — —
  - 3. Viability Assessment — —
  - 4. MVP on Hetzner — —
  - 5. Lessons from Apache Burr and Prefect ControlFlow — —
  - 6. Conclusions — —

## docs/analysis/03_EU_AI_Act_and_Funding.md
sha: 2d84d636d3dde5ccb284c12f4cdd59425be936b8
purpose: EU AI Act: Compliance Opportunity and Funding Paths
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Regulatory Tailwind — —
  - 2. Article 12: The Article That Justifies Liminara — —
  - 3. Funding Paths — —
  - 4. The Pitch — —
  - 5. Action Items — —

## docs/analysis/04_HashiCorp_Parallels.md
sha: aeea11cde541fe46397427db31459d909eb7b433
purpose: HashiCorp Parallels and the Scope of Liminara
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Context — —
  - HashiCorp: What They Built — —
  - Architectural Parallels: Terraform and Liminara — —
  - Where Liminara Goes Beyond Terraform — —
  - Lessons From HashiCorp's Journey — —
  - Liminara Is Not Just "Knowledge Work" — —

## docs/analysis/05_Why_Replay.md
sha: fb3c0ab46cbcdf9df7425c508bb2fa442aa906e3
purpose: Why Replay: The Case for Recorded Decisions and Re-execution
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The Naive Objection — —
  - 1. Selective Re-execution (The Build System Property) — —
  - 2. Branching Decisions (Exploration as a Tree, Not a Line) — —
  - 3. Auditable Provenance (The Compliance Property) — —
  - 4. Deterministic Production (Discovery to Hardened Pipeline) — —
  - 5. Efficient What-If Analysis — —
  - 6. Regression Detection — —
  - 7. Collaboration and Handoff — —
  - Summary — —
  - The Core Argument — —

## docs/analysis/06_FlowTime_and_Liminara.md
sha: 1eff1c9be6c9cefee797a38404de09f0b37e15c6
purpose: FlowTime and Liminara: How They Relate
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What FlowTime Is — —
  - The Relationship Isn't Simple — —
  - Model 1: FlowTime as an Op (Node in the DAG) — —
  - Model 2: FlowTime's Model-Building Process as a Liminara Pipeline — —
  - Model 3: Shared Philosophical DNA, Complementary Domains — —
  - The Concrete Architecture — —
  - Where FlowTime's Core Vision Fits — —
  - Process Mining: The Natural Feeder — —
  - The Combination Is Stronger Than Either Alone — —

## docs/analysis/07_Compliance_Layer.md
sha: 9b0fbc5d84138240f4eb4fc8d3772096c302df0f
purpose: Liminara Compliance Layer
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What Article 12 Actually Requires — —
  - 2. The Compliance Layer Architecture — —
  - 3. The Python Decorator Interface (Model A in Detail) — —
  - 4. Hash Chain — Tamper-Evidence — —
  - 5. The Article 12 Compliance Report — —
  - 6. Testing the Compliance Layer — —
  - 7. What the Compliance Layer Is Not — —
  - 8. Relationship to the Full Runtime — —

## docs/analysis/08_Article_12_Summary.md
sha: db1e143e197a302b831597f57bccd8158ccae3d7
purpose: EU AI Act — Article 12: What It Actually Says and Means
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The Short Version — —
  - The Exact Text — —
  - What It Means in Practice — —
  - Who Does Article 12 Apply To? — —
  - Common Misconceptions — —
  - What Compliance Actually Looks Like — —
  - How Liminara Satisfies Article 12 — —
  - Related Articles Worth Knowing — —

## docs/analysis/09_Compliance_Demo_Tool.md
sha: 759385d99a207000040d2820c6fada27eedc1f43
purpose: Python SDK — Design and Rationale
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Why This Was Built First — —
  - What the Demo Tool Proves — —
  - Repository Structure — —
  - The Python SDK Design — —
  - Example 1: Raw Python + Anthropic SDK — —
  - Example 2: LangChain RAG Pipeline — —
  - The CLI — —
  - Docker: Run Without Setup — —
  - Relationship to the Elixir Runtime — —
  - Development Sequence — —
  - What This Enables — —

## docs/analysis/10_Synthesis.md
sha: dba718a6e6ab4098f3a0a226c76d056d608288b4
purpose: Liminara: Strategic Synthesis
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What Liminara Is — The Final Definition — —
  - 2. DAG as the Execution Model — Settled — —
  - 3. Platform Emergence Model — Settled — —
  - 4. Licensing — Decided — —
  - 5. EU AI Act Positioning — Settled — —
  - 6. Radar Architecture — Clarified — —
  - 7. FlowTime Relationship — Defined — —
  - 8. What Is Cut — Definitive List — —
  - 9. Development Sequence — Revised — —
  - 10. Open Questions — —

## docs/analysis/11_Data_Model_Spec.md
sha: 7658ec815c99829f0c25bbe68878efad91c00f67
purpose: Liminara: Phase 0 Data Model Specification
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Purpose — —
  - Hash Algorithm — —
  - Canonical Serialization — —
  - Artifact Storage — —
  - Event Log — —
  - Run Seal — —
  - Decision Records — —
  - Event Types — —
  - Directory Layout — —
  - What Is NOT Defined Here — —
  - Implementation Checklist — —

## docs/analysis/12_Regulatory_Landscape.md
sha: e06defc65268219955a9bf3324a84959c2993d98
purpose: EU Regulatory Landscape: The Provenance Opportunity
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The "Tell Us" to "Prove It" Shift — —
  - 2. Regulations Mapped to Liminara — —
  - 3. Master Enforcement Timeline — —
  - 4. Enterprise Compliance Landscape — —
  - 5. Gap Analysis: What's Missing — —
  - 6. Market Context — —
  - 7. Implications for Liminara — —
  - References — —

## docs/analysis/13_Compliance_Positioning.md
sha: 4eab8b740ee7daa59a6a3d6b257401ce1b0a8cef
purpose: Liminara: Compliance Positioning Strategy
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Thesis — —
  - 2. The Layer Model — Settled — —
  - 3. Three Integration Models — —
  - 4. Which Regulation to Lead With — Decided — —
  - 5. The Compliance Pack Family — —
  - 6. Swedish Market Focus — —
  - 7. Defensibility — —
  - 8. Honest Risks — —
  - 9. Relationship to Existing Roadmap — —
  - 10. What's Needed — —

## docs/analysis/14_VSME_Pack_Plan.md
sha: d0348f8c754e0efa350f5b8aaaf960dc554cf6aa
purpose: VSME Compliance Pack — Design Plan
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Overview — —
  - DAG Structure (~25 nodes) — —
  - Ops by Determinism Class — —
  - Key Demo Scenarios — —
  - What We Need to Build — —
  - Sequencing — —
  - Market Context — —

## docs/analysis/15_Radar_Pack_Plan.md
sha: dc241c198703ebe57abe8e84a27f223df08d3f33
purpose: Radar Pack — Design Plan
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Overview — —
  - Architecture: Elixir + Python — —
  - DAG Structure — —
  - Deduplication Strategy — —
  - Serendipity: How Discovery Works — —
  - Delivery — —
  - Cost Management — —
  - Deployment (for long-running use) — —
  - What We Build (in order) — —
  - Configuration — —
  - Why Radar Before House Compiler — —

## docs/analysis/16_Orchestration_Positioning.md
sha: 8f9581a82ffc48aac65a358fea67b3fb26e6bb94
purpose: Orchestration Landscape Positioning
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Landscape — —
  - 2. Liminara Is Not a Workflow Orchestrator — —
  - 3. The "Tack It On" Question — —
  - 4. Where Liminara Competes and Where It Doesn't — —
  - 5. The "Any Pack" Ambition — —
  - 6. What to Steal From Each System — —
  - 7. The Competitive Moat — —
  - 8. Positioning Statement — —

## docs/architecture/01_CORE.md
sha: fe56402c5a82a30155e84a03e62a79b6e808a0c8
purpose: The Liminara Core
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What is Liminara? — —
  - The mental model — —
  - Five concepts — —
  - The plan: a DAG you can read — —
  - The scheduler: ten lines — —
  - How it maps to OTP — —
  - Caching: Bazel's gift — —
  - Observation: the Excel quality — —
  - Replay: discovery vs re-execution — —
  - How the domain packs map — —
  - What's actually hard — —
  - What's deferred — —
  - Build sequence — —
  - The dependency test — —
  - The elegance test — —

## docs/architecture/02_PLAN.md
sha: cf43559ba52825f3042379994fa9f55c5497ccb2
purpose: Architecture Source Map
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Current sources of truth — —
  - Resolution rules — —
  - Update protocol — —

## docs/architecture/08_EXECUTION_TRUTH_PLAN.md
sha: ca2183bf8b274dbdf9ad7fb889b0bf2be2da0004
purpose: Execution Truth Plan
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Purpose — —
  - Why This Must Happen Now — —
  - Existing Commitments This Plan Pulls Together — —
  - Placement In The Roadmap — —
  - Rule For M-RAD-04 While It Is In Flight — —
  - Architectural Principles — —
  - Target Contract — —
  - Workstreams — —
  - Proposed Milestones — —
  - Concrete Design Rules — —
  - What This Plan Is Not — —
  - Recommendation — —

## docs/architecture/indexes/contract-matrix.md
sha: afd8ff2a0441e675a128ecebe1c3420c6b5cf507
purpose: Contract Matrix
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - (no top-level sections)

## docs/architecture/proposals/lifecycle-fsm-engine.md
sha: 4e33353245cb3eedb4d71ac84700659371fc76f9
purpose: ## RFC: Per-entity FSMs + LLM/engine boundary — a lifecycle architecture for wf-graph-based workflow
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - RFC: Per-entity FSMs + LLM/engine boundary — a lifecycle architecture for wf-graph-based workflow — —

## docs/brainstorm/00_README.md
sha: 1d67356010cdccd3b2b98f0bb994a8b2885a2ed9
purpose: Agent Runtime Specs (Index)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Structure — —
  - Reading order (recommended) — —

## docs/brainstorm/01_Architecture_Requirements_Brief.md
sha: cb2dbc9ab3ada6474a8adc8b287e349b8c185b5f
purpose: Agent Runtime Architecture & Requirements Brief
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Problem statement — —
  - 2. Terms and concepts — —
  - 3. Design principles — —
  - 4. High-level architecture — —
  - 5. Domain pack model — —
  - 6. Determinism, replay, and side effects — —
  - 7. A2UI requirements — —
  - 8. Mapping the three domain packs onto the runtime — —
  - 9. Key challenges and risks — —
  - 10. Requirements — —
  - 11. Data model sketches (illustrative) — —
  - 12. Suggested incremental roadmap — —
  - 13. Open questions — —
  - 14. Appendix: Agent types (taxonomy) — —

## docs/brainstorm/02_Umbrella.md
sha: 414b5c4597f5450be8460394d60744f124a8c44e
purpose: Umbrella: Multi-Pack Agent Runtime (Vision, Fit, and Project Approach)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What we are building — —
  - 2. The domain packs we discussed — —
  - 3. Three ways to sort the packs (useful for planning) — —
  - 4. How the core accommodates all packs (without compromise) — —
  - 5. Does anything like this already exist? — —
  - 6. Why an Elixir/OTP control plane is (and isn’t) smart — —
  - 7. Project approach (how to keep it solo-dev feasible) — —
  - Appendix: Competitive and research links — —

## docs/brainstorm/03_Core_Runtime.md
sha: 978e7bd0bba53e48500f73e2c6513926303fcaba
purpose: Core Runtime Substrate Specification (Elixir/OTP control plane)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 0. Summary — —
  - 1. Goals and non-goals — —
  - 2. Core concepts — —
  - 3. Execution semantics — —
  - 4. Determinism and replay — —
  - 5. The runtime kernel: components — —
  - 6. Executor model (control plane vs compute plane) — —
  - 7. Multi-tenancy and workspaces — —
  - 8. Context management (LLM) — —
  - 9. Observability and debugging — —
  - 10. Data model (illustrative) — —
  - 11. Core risks (objective) — —
  - 12. Incremental roadmap (recommended) — —
  - Appendix: References used by this spec — —

## docs/decisions/0001-failure-recovery-strategy.md
sha: 1dd4256cc2803657a9a250735439e2dc53e8edd9
purpose: ADR-0001: Failure Recovery via Cache-Based Re-run, Not Automatic Retry
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Context — —
  - Decision — —
  - Alternatives considered — —
  - Consequences — —

## docs/decisions/0002-visual-execution-states.md
sha: c880617d7fd5cc352b09c3577e9e94966cc2e7a3
purpose: ADR-0002: Visual Execution States in the Observation Layer
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Status — —
  - Context — —
  - Problem — —
  - Proposed visual states — —
  - Implementation approach — —
  - Decision — —
  - References — —

## docs/decisions/0003-doc-tree-taxonomy.md
sha: 254baa66cf9c79c8c5165f94bcec1b5a9e8a8332
purpose: ADR-0003: Adopt bind-me/inform-me doc-tree taxonomy
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Context — —
  - Decision — —
  - Alternatives considered — —
  - Consequences — —
  - Validation — —

## docs/domain_packs/01_Radar.md
sha: 020f1c8aa83e9444cf862cad2f09918a067a62c9
purpose: Domain Pack: Radar / Omvärldsbevakning
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/02_House_Compiler.md
sha: f608099f93f5ec5f020c89f6a4d46d09e15a0b2f
purpose: Domain Pack: House Compiler Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/03_Software_Factory.md
sha: 588730f4263d03ba90236d43c4a20a06b5d6106b
purpose: Domain Pack: Software Factory Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/04_FlowTime_Integration.md
sha: 1dbb34747cc3e3cc891cce4f329727c2b25d4cd8
purpose: Domain Pack: FlowTime Integration Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/05_Process_Mining.md
sha: d6133019c2c8b42932e48cfd513eee321ac962a2
purpose: Domain Pack: Process Mining Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/06_Agent_Fleets.md
sha: 12a6c2d2a840a3a173b7a4b54963b60b0fb8e6d9
purpose: Domain Pack: Agent Fleet Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/07_Population_Simulation.md
sha: 292dd3aa201ce5188e72d881a7bc6cfd56dc8d69
purpose: Domain Pack: Population Simulation Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. Variable injection — the "God's Eye View" — —
  - 9. Forked runs and dual-environment testing — —
  - 10. The hallucination convergence problem — and Liminara's structural answer — —
  - 11. MVP plan (incremental, testable) — —
  - 12. Should / shouldn't — —
  - 13. Risks and mitigations — —
  - Appendix: Related work and reference implementations — —

## docs/domain_packs/08_Behavior_DSL.md
sha: 5065d3e1d16e24a11686c8d8d932e1ecc589320f
purpose: Domain Pack: Behavior DSL Pack (LLM-authored programs as data)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/09_Evolutionary_Factory.md
sha: 61aaa92465627e48ea9e057cf84379d9d1520b9f
purpose: Domain Pack: Evolutionary Software Factory Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —
  - Appendix: Agentic Algorithm Engineering (AAE) — Adjacent Pattern — —

## docs/domain_packs/10_LodeTime_Dev_Pack.md
sha: 647b58dbf268d81523a64bda9ef2be4800627887
purpose: Domain Pack: LodeTime Dev Process Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/11_Toy_Report_Compiler.md
sha: 51d14efc12918642bdd24ea636430e8c5eb7e1ed
purpose: Domain Pack: Report & Diagram Compiler (Toy Pack / Substrate Validation)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/12_Toy_Ruleset_Lab.md
sha: 0212802c2724adfff406257ac75196f86f093855
purpose: Domain Pack: Ruleset Lab (Toy Pack / Policy & Rules)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/domain_packs/13_Toy_GA_Sandbox.md
sha: 289532c014e935f38c281ef821294c0f5fbb4a35
purpose: Domain Pack: GA Sandbox (Toy Pack / Optimization Harness)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Purpose and value — —
  - 2. Pack interfaces — —
  - 3. IR pipeline — —
  - 4. Op catalog (core-executed contract) — —
  - 5. Decision records and replay — —
  - 6. A2UI / observability — —
  - 7. Executor and tool requirements — —
  - 8. MVP plan (incremental, testable) — —
  - 9. Should / shouldn’t — —
  - 10. Risks and mitigations — —
  - Appendix: Related work and competitive tech — —

## docs/governance/README.md
sha: 007fe65c713aaac357b8dda36f72622a28b1c005
purpose: Governance
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Instruments — —
  - Moved from `docs/architecture/contracts/` — —

## docs/governance/shim-policy.md
sha: f3a3de4da5adeaff7408d19d68f7e5a8ffe222e3
purpose: Compatibility Shim Policy
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Allowed exception — —
  - Required records — —
  - Forbidden shims — —
  - Review question — —

## docs/governance/truth-model.md
sha: 9a2933f2c2c0e46427a20903c98c7162dea7409a
purpose: Documentation Truth Model
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Truth classes — —
  - Resolution order — —
  - Folder rules — —
  - Frontmatter schema — —
  - Completion vs quality — —
  - Change discipline — —

## docs/guides/devcontainer_operations.md
sha: b51861e2afe35d76a45044595b56b97d82f4bcf2
purpose: Devcontainer Operations Guide
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Purpose — —
  - Current Setup — —
  - Development Persistence Model — —
  - What We Found In This Container — —
  - Safe Mental Model — —
  - Safe To Clean — —
  - Not Safe To Treat As Disposable — —
  - Rebuild Workflow — —
  - Disk Management — —
  - .dockerignore — —
  - Operational Rules — —
  - Current Gaps — —
  - Related Sources — —

## docs/guides/elixir_tooling.md
sha: 256c31280c066fa5ac5001a10436ba35fb8fa0e3
purpose: Elixir Tooling Reference (2026)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Code quality stack — —
  - AI development aids — —
  - Language server: Expert LSP — —
  - Elixir MCP SDKs (for building MCP servers in Elixir) — —

## docs/guides/pack_design_and_development.md
sha: 43e45f3dff51757a0dfa7708218781a0e5913b5d
purpose: Pack Design and Development Guide
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Purpose — —
  - What a pack is — —
  - Runtime vs Pack Ownership — —
  - Pack Design Process — —
  - Persistent Data Rules — —
  - Reference Data — —
  - Python Environment Ownership — —
  - Op Design Inside a Pack — —
  - Plan Design Rules — —
  - Config Rules — —
  - Pack Testing Strategy — —
  - When To Add a Runtime Feature Instead of Pack Logic — —
  - Minimum Checklist For A New Pack — —
  - Current Gaps This Guide Does Not Pretend To Solve — —
  - Related Sources — —

## docs/guides/python_tooling.md
sha: 0408f32077dd4c75892ecef745d981d11eca65c0
purpose: Python Tooling Reference (2026)
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Code quality stack — —
  - Project setup template — —
  - AI development aids — —
  - What we don't use (and why) — —

## docs/history/architecture/02_PLAN.md
sha: 2cc2e7d4c980379c9c4fd7c2347c02bfa3844e64
purpose: Liminara: Build Plan
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Snapshot phase: Phase 4 — —
  - Build sequence — —
  - Recognized architectural patterns — —
  - Deferral triggers — —
  - Python SDK as data model validation — —

## docs/history/architecture/03_PHASE3_REFERENCE.md
sha: d02888c3650639e67f96320caae856c0b041f748
purpose: Liminara: Phase 3 Reference Architecture
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What exists — —
  - How to run it — —
  - Supervision tree — —
  - Module map — —
  - Data flow: a run from start to finish — —
  - The five concepts — —
  - Event types and hash chain — —
  - Run lifecycle and node states — —
  - Two execution paths — —
  - Crash recovery — —
  - Event broadcasting — —
  - Gate mechanism — —
  - Cache semantics — —
  - Filesystem layout — —
  - Dependencies — —
  - Test suite structure — —
  - What this enables (Phase 4+) — —

## docs/history/architecture/04_OBSERVATION_DESIGN_NOTES.md
sha: 706c34f526e1e67b5f9f26e43b14219963a5b9ca
purpose: Observation Layer: Design Notes
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. Show the grid, not the logic — —
  - 2. Behaviors vs Events as distinct subscription abstractions — —
  - Non-goals — —

## docs/history/architecture/05_RADAR_CEP_NOTES.md
sha: 87d44c89d5f161feb0becdfb1e1c097b62537875
purpose: Radar Pack: CEP Framing and Two-Layer Design
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The insight — —
  - Layer 1: Continuous collection (CEP-style) — —
  - Layer 2: Triggered analysis (LLM-heavy) — —
  - Scoping recommendation — —
  - Source — —

## docs/history/architecture/06_VISUALIZATION_DESIGN.md
sha: 4ad736fa8229138e797f5afd29da77bc4d8a0b7b
purpose: Visualization Design Spec
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Visual identity — —
  - Layout system — —
  - Scale strategy — —
  - Dynamic DAGs (discovery mode) — —
  - Animation model — —
  - Node rendering (the inline preview) — —
  - Technology stack — —
  - Pack-specific considerations — —
  - Research references — —

## docs/history/architecture/07_TIDEPOOL_VISION.md
sha: 979ee9f0cb02257b9eae03f955fcd03559fcbcd0
purpose: Visualization Visions for Liminara
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The four visions — —
  - The question — —
  - How nature solves this — —
  - What must be perceivable — —
  - The Tidepool Score — —
  - At scale — —
  - Dynamic DAGs (discovery mode) — —
  - The key insight — —
  - Interactive prototype — —
  - References — —

## docs/history/architecture/viz/circuit/VISION_CIRCUIT.md
sha: 5bd12f3ed4e2c177100c3eea7cdf5bea6a6460a7
purpose: Vision D: The Circuit + Marginalia
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The two layers — —
  - The metaphor — —
  - The full board with marginalia — —
  - The component bloom — —
  - Gates as unpopulated footprints — —
  - At scale — —
  - What the PCB + marginalia combination adds — —
  - The manuscript connection — —
  - Hybrid possibilities — —
  - Strengths and limitations — —
  - Interactive prototype — —
  - References — —

## docs/history/architecture/viz/score/VISION_SCORE.md
sha: ba505ba376e9812fdace3d2b8c78152b5d0f6695
purpose: Vision B: The Score
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The metaphor — —
  - The mapping — —
  - The full score — —
  - The rest: gates as silence — —
  - At scale — —
  - What makes this distinctive — —
  - Strengths and limitations — —
  - Interactive prototype — —

## docs/history/architecture/viz/terrain/VISION_TERRAIN.md
sha: c8654806bcccfeacd8df110fe1ed8cf027dc5bf1
purpose: Vision C: The Terrain
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The metaphor — —
  - The isometric view — —
  - The contour map (top-down) — —
  - Natural vocabulary — —
  - Replay as erosion — —
  - Strengths and limitations — —
  - The cross-section view (not shown) — —
  - Interactive prototype — —

## docs/index.md
sha: (uncommitted)
purpose: Docs Index
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - docs/analysis/01_First_Analysis.md — —
  - docs/analysis/02_Fresh_Analysis.md — —
  - docs/analysis/03_EU_AI_Act_and_Funding.md — —
  - docs/analysis/04_HashiCorp_Parallels.md — —
  - docs/analysis/05_Why_Replay.md — —
  - docs/analysis/06_FlowTime_and_Liminara.md — —
  - docs/analysis/07_Compliance_Layer.md — —
  - docs/analysis/08_Article_12_Summary.md — —
  - docs/analysis/09_Compliance_Demo_Tool.md — —
  - docs/analysis/10_Synthesis.md — —
  - docs/analysis/11_Data_Model_Spec.md — —
  - docs/analysis/12_Regulatory_Landscape.md — —
  - docs/analysis/13_Compliance_Positioning.md — —
  - docs/analysis/14_VSME_Pack_Plan.md — —
  - docs/analysis/15_Radar_Pack_Plan.md — —
  - docs/analysis/16_Orchestration_Positioning.md — —
  - docs/architecture/01_CORE.md — —
  - docs/architecture/02_PLAN.md — —
  - docs/architecture/08_EXECUTION_TRUTH_PLAN.md — —
  - docs/architecture/indexes/contract-matrix.md — —

## docs/liminara.md
sha: 5c5464e03a9744320f62bdc25b6de6b53b75c78e
purpose: Liminara: Comprehensive Reference
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Table of Contents — —
  - Companion Guides — —
  - 1. What Liminara Is — —
  - 2. The Core Insight — —
  - 3. The Mental Model — —
  - 4. Five Concepts — —
  - 5. The Execution Model — —
  - 6. Determinism Classes — —
  - 7. Replay and Why It Matters — —
  - 8. Architecture — —
  - 9. Data Model — —
  - 10. Domain Packs — —
  - 11. Competitive Landscape — —
  - 12. Intellectual Ancestors — —
  - 13. EU AI Act and Compliance — —
  - 14. Build Plan — —
  - 15. Licensing and Business Model — —
  - 16. Funding Paths — —
  - 17. What's Deferred — —
  - 18. Recognized Architectural Patterns — —

## docs/public/compliance/battery-passport.md
sha: 373b5bd6bf09fdb98a9aa03ed9ed1a6ae943e173
purpose: Battery Passport — Carbon Footprint as Competitive Advantage
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/compliance/cbam.md
sha: bd19ef86953afd74f8deb3797e3575f8aa95aca3
purpose: CBAM — Embedded Emissions Verification
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/compliance/dpp.md
sha: e819b9a8506ce23653bf2c248f66b91ca03cfa8f
purpose: Digital Product Passport — Supply Chain Provenance
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What you can ask afterward — —
  - Why this is hard without provenance — —

## docs/public/compliance/eudr.md
sha: 4f4a3c07b47aff5222f4e3feae72f9b99ac24cde
purpose: EUDR — Deforestation-Free Commodity Traceability
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/compliance/vsme.md
sha: fd17dbd68de97b4ca211db1c43989fd670a93ba2
purpose: VSME — Sustainability Reporting for SMEs
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/flowtime.md
sha: b6e2cfacb1c5d9e52299d693e83a9eb95513587f
purpose: FlowTime Integration — System Flow Modeling and What-If Analysis
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - Three integration models — —
  - The pipeline — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/house-compiler.md
sha: b01c66dd429e4232ddcb33aee24f1f60d76c8ca3
purpose: House Compiler — Parametric Timber Frame Manufacturing
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - What happens when the customer asks about 35° — —
  - Reference data and regulatory updates — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/lodetime.md
sha: f9a16e4c086464d203ca5580579ea9d070445ee6
purpose: LodeTime — DevOps as a Provenance Chain
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - The recursive property — —
  - The post-mortem, traced — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/process-mining.md
sha: 7bf978dccc486e2f1decdd0346c5462b00c04f37
purpose: Process Mining — Pipeline Self-Analysis and Discovery
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The pipeline — —
  - The unexpected reclassification pattern — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/radar.md
sha: 1dbcd7c1db444df905cbd1ded968cb97aadd2ad4
purpose: Radar — Research Intelligence
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - Two layers, not one — —
  - What makes Radar more than a feed reader — —
  - A concrete week — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/foundations/software-factory.md
sha: 0339f77837116afa88051fa1691278aab58eaa54
purpose: Software Factory — Agentic Coding with Provenance
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - The session, step by step — —
  - Tracing a decision — —
  - Replay with a different model — —
  - What you can ask afterward — —
  - Before and after — —

## docs/public/horizons/agent-fleets.md
sha: 2cfa090b883fee186e2d093b55ffc4d62cf84d50
purpose: Agent Fleets — Continuously Operating Agent Infrastructure
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The idea — —
  - How it maps — —
  - What makes this more than "run many pipelines" — —
  - What this exercises as a Liminara validation — —

## docs/public/horizons/behavior-dsl.md
sha: 79b00a9c83468b7ef838c1e9a5ec2540812ab598
purpose: Behavior DSL — Regulations as Versioned Artifacts
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - What makes this interesting as a Liminara validation — —

## docs/public/horizons/evolutionary-factory.md
sha: 0c19fe57c1a90415693a9e77a88345748766e67f
purpose: Evolutionary Factory — Supply Chain Optimization Through Composition
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - What makes this interesting as a Liminara validation — —

## docs/public/horizons/population-sim.md
sha: 92c7c54bf73991b97fa683c93a65e684f5de6f64
purpose: Population Sim — Evolutionary House Design
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The scenario — —
  - What makes this interesting as a Liminara validation — —

## docs/public/proliminal-liminara-work-entry.md
sha: 2dedd22ac943017f937d2f16b996d881d5d9aecf
purpose: Liminara — Work Entry for proliminal.net
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Liminara — —

## docs/public/proliminal-provenance-page.md
sha: 47ef4d7e4c690189566d1be1ce2ae8f076747d08
purpose: Position Paper: proliminal.net/provenance
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The shift — —
  - The gap — —
  - An architectural approach — —
  - What this looks like in practice — —
  - Liminara — —
  - Where I'm looking for help — —
  - References — —
  - Implementation notes — —

## docs/public/site-restructure.md
sha: 8677b60749ca3d2d09181154d9a0c0878d97068a
purpose: Proliminal.net — Site Restructure Prompt
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - New navigation — —
  - Lab — the new section — —
  - Services — absorbing Approach — —
  - About — absorbing VOODOO — —
  - Work — past projects and track record — —
  - Visual/UX notes — —
  - Summary of navigation flow — —

## docs/research/01_adjacent_technologies.md
sha: cabe6868e95c2176c4aa0bc92b3baf19c907f211
purpose: Adjacent Technologies and Intellectual Ancestors
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Memex and Its Lineage — —
  - 2. Petri Nets and Process Mining — —
  - 3. Spaces — —
  - 4. Content Addressing — The Intellectual Family — —
  - 5. Hash Chains, Merkle Trees, and Tamper-Evidence — —
  - 6. Formal Models Illuminating Liminara — —
  - 7. Rich Hickey's Relevant Ideas — —
  - 8. Vector Databases in the Radar Pipeline — —
  - 9. CUE — Lattice-Based Configuration and Constraint Unification — —
  - 10. Reactor — Saga Orchestration for Elixir — —
  - 11. Camunda — BPMN Process Orchestration — —
  - 12. Luna / Enso — Visual Data-Flow Programming — —
  - 13. Technology Synthesis — The Pattern — —

## docs/research/02_a2ui_finding.md
sha: 8bc3a09aac80a78daa7ddcbfc25033a164a2ef55
purpose: A2UI Assessment: Real Protocol, Good Fit, Early Stage
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Summary — —
  - What it does — —
  - Why it fits Liminara — —
  - Maturity risk — —
  - Recommendation — —

## docs/research/03_artifact_store_design.md
sha: c1a1574d0cae79c43605c6118bd0db116b2d8ce5
purpose: Artifact Store Design: Lessons from Existing Systems
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Existing Systems with Content-Addressed Artifacts — —
  - Engineering Decisions — —
  - Storage Cost Projections — —
  - Practical Implementation Path — —

## docs/research/04_build_vs_buy.md
sha: e09d3d6cb8162ee9d2763095ba887f25048ca1a9
purpose: Build vs Buy: Temporal, Dagster, Flyte, and the Custom Path
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The Question — —
  - Temporal — —
  - Dagster — —
  - Flyte — —
  - Prefect — —
  - What to steal from each — —
  - Bottom line — —

## docs/research/05_house_compiler_context.md
sha: 925a7042ebed35742393557a84992f1cff0e569e
purpose: House Compiler Context: From ChatGPT Design Conversation
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The Problem Statement — —
  - Why It Fits as a Domain Pack (Not a Separate System) — —
  - The Pipeline Architecture (IR Stages) — —
  - The Agent Topology — —
  - The Design Genome (GA Optimization) — —
  - Swedish Regulatory Knowledge Base — —
  - The Two Hardest Problems — —
  - The Coupled Constraint Problem (Convergence) — —
  - The NC File Ecosystem — —
  - Strategic Insight: Platform vs. Product Tension (Resolved) — —
  - Key Insight: The "Agent" Abstraction — —
  - What This Conversation Validates in the Core Spec — —
  - What This Conversation Reveals as Missing from the Core Spec — —

## docs/research/06_project_origins.md
sha: 6a7f57e183a61f7afde4b8a855cb88f5ce5814f2
purpose: Project Origins: How Liminara Evolved
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The evolution — —
  - Key ChatGPT recommendations adopted in the specs — —
  - Key tension: platform vs product — —

## docs/research/07_flowtime_liminara_convergence.md
sha: 7f6c9058d15f9afd0482e913c6849b44ffba9ca5
purpose: FlowTime and Liminara: Convergence Analysis
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What Has Changed Since the Last Analysis — —
  - 2. Two Systems, One Pattern — —
  - 3. How Liminara Can Help FlowTime — —
  - 4. How FlowTime Can Help Liminara — —
  - 5. The Practical Integration Path — —
  - 6. The Consulting Toolkit Vision — —
  - 7. The Graph-of-Graphs Insight — —
  - 8. The Bigger Picture: Flow Literacy as a Universal Lens — —
  - 9. Differences from Previous Analysis — —
  - 10. Open Questions — —

## docs/research/08_graph_execution_patterns.md
sha: 02730930b6f462b664041d0fc099e98f40c7cab2
purpose: Graph Execution Patterns: Supply Chains, Smart Contracts, and Liminara
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. The Pattern — —
  - 2. A Taxonomy of Graph Execution Systems — —
  - 3. Ethereum Smart Contracts: Deeper Than the Analogy — —
  - 4. Supply Chains as Computation — —
  - 5. Transparency and Verification — —
  - 6. Ricardian Contracts and Computational Agreements — —
  - 7. Visualization: A Shared Problem Space — —
  - 8. What This Means for Liminara — —
  - 9. Open Questions — —

## docs/research/09_supply_chain.md
sha: dd057257d6bed7b84a5be80a46178935af23f1c5
purpose: Our Emergency
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - We have to change the world "back" so that it... — —
  - Transparent Input & Output — —
  - Supply chain  — —
  - Value Chain — —
  - Value — —

## docs/research/10_cue_language.md
sha: 846a12e8ab285e6013af3fe496e411ca589deae1
purpose: CUE Language — Constraint Unification for Configuration and Validation
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What CUE is — —
  - Lattices vs DAGs — the relationship — —
  - Where CUE could add value to Liminara — —
  - Where CUE fits LodeTime specifically — —
  - Where CUE should NOT be applied — —
  - Relationship to adjacent technologies — —
  - Open questions — —

## docs/research/11_zvec.md
sha: 9df567a541ea9533cc9ca635da291e01710cee21
purpose: zvec — Embedded Vector Database
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What it is — —
  - Key capabilities — —
  - Elixir integration — —
  - Comparison to alternatives — —
  - How zvec maps to Liminara — —
  - Build complexity — —
  - Recommendation — —

## docs/research/12_a2ui_assessment.md
sha: 3d9b463a87a4df080a7bfa078791fc485003d363
purpose: A2UI Assessment — Post M-OBS-05b
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Does ex_a2ui work as expected? — —
  - Is the A2UI protocol suitable for Liminara's observation needs? — —
  - What would it take to make this production-ready? — —
  - Recommendation — —

## docs/research/13_agent_frameworks_landscape.md
sha: ea85d9903037a342e31afbff21af3d9b7ebf4785
purpose: Agent Frameworks Landscape: LangGraph and Cloudflare Agents
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What the Article Is Saying — —
  - How This Maps to Liminara — —
  - Comparison Table — —
  - Verdict — —

## docs/research/14_alternative_computation_models.md
sha: aff834aad7cec6ecf521a0f100ba3f5f09d8394b
purpose: Beyond the DAG: Alternative Computation Models
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Why Look Beyond DAGs? — —
  - Blackboard Systems — The Strongest Alternative — —
  - Tuple Spaces — The Coordination Insight — —
  - Rule Engines — Data-Driven Control Flow — —
  - Petri Nets — More Expressive Than DAGs — —
  - Stigmergy — Indirect Coordination — —
  - Chemical Abstract Machine / Gamma — Computation as Reactions — —
  - Constraint Solvers / Declarative Models — —
  - Assessment — —

## docs/research/15_dataflow_systems_and_liminara.md
sha: d6a73b895cdded1b0ad0259275b33cda40bb2f44
purpose: Dataflow Systems, Procedural Audio, and Liminara
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - The Procedural Audio Thesis — —
  - Seven Structural Parallels to Liminara — —
  - Three Borrowable Concepts — —
  - The Deeper Connection: Process vs. Data — —
  - Could Procedural Audio Be a Liminara Domain Pack? — —
  - Statistical Distributions Farnell Uses (Reference) — —
  - Key Quotes — —
  - How DSP Actually Works (and Why It's Not Choppy) — —
  - Can the BEAM Do Audio DSP? — —
  - Joe Armstrong, Erlang, and Music — —
  - Convergence: Three Independent Paths to the Same Architecture — —
  - The Broader Landscape: Visual Dataflow Systems — —
  - Seven Gaps: Where These Systems Expose Liminara's Limitations — —
  - Reference: Agentic Algorithm Engineering (AAE) — —

## docs/research/16_mirofish_population_simulation.md
sha: 2660728a1b1ad56862da88fdfacc22264ebd68f4
purpose: MiroFish and the Population Simulation Pack
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - What the Article Is Saying — —
  - Liminara's Population Simulation Pack — What Already Exists — —
  - Where MiroFish Goes Further Than the Current Spec — —
  - The Most Important Insight: Liminara Solves MiroFish's #1 Unsolved Problem — —
  - Simulation/Live Duality Becomes Very Concrete Here — —
  - Variable Injection as a Gate — —
  - OASIS as the External Executor — —
  - Dual-Environment Testing in Liminara Terms — —
  - Priority Reassessment — —
  - What Liminara Would Uniquely Offer Over MiroFish — —
  - Additions to the Pack Spec — —
  - Verdict — —

## docs/research/17_flyte_architecture.md
sha: fad0da6a2167c69a059e78618727202d2c436213
purpose: Flyte: Architecture Deep Dive
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What Flyte Is — —
  - 2. Core Concepts — —
  - 3. Architecture — —
  - 4. Type System — —
  - 5. Caching (DataCatalog) — —
  - 6. Reproducibility Model — —
  - 7. Execution Model and Fault Tolerance — —
  - 8. Plugin / Executor Model — —
  - 9. Cost Model — —
  - 10. Who Uses Flyte — —
  - 11. Could Decision Recording Be Tacked Onto Flyte? — —
  - 12. What Liminara Should Steal From Flyte — —

## docs/research/18_scale_and_distribution_strategy.md
sha: 114b8cc7299ef105b9ff2aa86f0f7a23e4fbcef6
purpose: Scale and Distribution Strategy
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - 1. What "Scale" Means for Different Packs — —
  - 2. Three Planes, Three Scale Stories — —
  - 3. The Executor Abstraction: Liminara's Key Architectural Decision — —
  - 4. Compute Backend Options — —
  - 5. OTP Distribution: When and How — —
  - 6. The Executor Roadmap — —
  - 7. Scale Strategy Summary — —

## docs/schemas/README.md
sha: 9891e12da7ef716556ee93fe1fa30cd29e94c3f7
purpose: `docs/schemas/` — CUE schemas + co-located fixtures
covers: —
references: —
authoritative_for: —
tier: —
last_verified: —
sections:
  - Layout — —
  - Local validation — —
  - Pre-commit enforcement — —
  - Topic discovery is automatic — —
  - Status (as of M-PACK-A-01 wrap) — —

## Reverse indexes

### by_topic
_(empty — populated as docs declare `authoritative_for:` topics)_

### by_symbol
_(empty — populated as docs declare `references:` symbols)_
