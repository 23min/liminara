# HashiCorp Parallels and the Scope of Liminara

## Context

This document emerged from analyzing HashiCorp's architecture (especially Terraform) against Liminara's core design, and a subsequent discussion about whether "Make for knowledge work" constrains Liminara's identity.

## HashiCorp: What They Built

HashiCorp was founded in 2012 by Mitchell Hashimoto and Armon Dadgar. They built a suite of infrastructure tools — Vagrant, Packer, Terraform, Consul, Vault, Nomad, Boundary, Waypoint — each solving one layer of the infrastructure lifecycle. IPO'd in 2021 at ~$14B valuation, acquired by IBM in 2025 for $6.4B. Mitchell departed in December 2023 and now works on Ghostty (a terminal emulator in Zig) under a nonprofit structure.

### The Tao of HashiCorp (Their Design Philosophy)

1. **Workflows, Not Technologies** — focus on the end goal, not the underlying tech.
2. **Simple, Modular, Composable** — Unix philosophy. Eight products, each doing one thing well.
3. **Immutability** — don't mutate in place. Destroy and recreate from known-good state.
4. **Codification** — everything as code: infrastructure, policy, security. Turn tribal knowledge into executable, reviewable artifacts.
5. **Pragmatism** — principles are aspirations, not dogma.

## Architectural Parallels: Terraform and Liminara

| Pattern | Terraform | Liminara |
|---------|-----------|----------|
| **DAG of operations** | Resource graph — nodes are resources, edges are dependencies | Plan — nodes are Ops, edges are artifact flow |
| **Immutable artifacts** | Packer images are content-addressed, immutable blobs | Artifacts are immutable, content-addressed blobs |
| **Plan then apply** | `terraform plan` (dry-run) then `terraform apply` (execute) | Discovery run (build DAG) then Replay (deterministic execution) |
| **State as source of truth** | State file records what exists | Event log IS the run — all state derived from events |
| **Pluggable providers** | Providers are separate binaries, protocol-separated from core | Packs provide op definitions, plan functions — protocol-separated from core |
| **Declarative over imperative** | Describe desired end-state, engine figures out how | Describe the DAG of ops, scheduler figures out execution order |
| **Caching via content-addressing** | If nothing changed, nothing happens (idempotent) | `cache_key = hash(op, version, input_hashes)` — determinism-aware memoization |
| **Determinism classes** | Not explicit, but providers have implicit determinism | Explicit: pure, pinned_env, recordable, side_effecting |

## Where Liminara Goes Beyond Terraform

1. **Decisions as first-class citizens.** Terraform has no concept of "recorded nondeterminism." When a Terraform provider makes a choice (e.g., AWS assigns an IP), it's captured in state but not treated as a replayable decision. Liminara's Decision concept — recording LLM responses, human approvals, random seeds — is what makes "discovery then replay" possible.

2. **Event sourcing as the core model.** Terraform's state file is a snapshot — it can get corrupted, go stale, conflict. Liminara's event log is append-only and is the canonical source. You can rebuild any state from the log. Architecturally superior for auditability and replay.

3. **Heterogeneous agents.** Terraform providers are all API clients. Liminara's Ops can be LLMs, geometry kernels, rule engines, human gates, optimizers — "the runtime doesn't care what's inside, it cares about the contract." The provider model generalized beyond infrastructure.

## Lessons From HashiCorp's Journey

**What validates Liminara's approach:**
- Starting with a walking skeleton and hardening as patterns emerge is exactly what HashiCorp did.
- The "one tool per concern, composable" philosophy worked brilliantly. Liminara's Pack model follows the same instinct.
- Terraform proved that DAG-based, state-tracked, cacheable execution works at massive scale worth billions.

**What to watch for:**
- Terraform's state file became its Achilles' heel (locking, drift, corruption). Liminara's event-sourced approach is better in theory, but event logs will face similar operational challenges at scale (compaction, corruption, migration).
- The BSL license change destroyed HashiCorp's community trust overnight. License decisions are existential if Liminara grows an open-source community.
- HashiCorp's "compose our tools together" story was always harder than the marketing suggested. Integration tax is real. Liminara's five-concept model being in one runtime avoids this.

## Liminara Is Not Just "Knowledge Work"

The tagline "Make for knowledge work" is a useful market positioning, but it constrains the actual scope of the architecture. The five core concepts are completely domain-agnostic:

- **Artifact**: immutable, content-addressed blob. Could be a PDF, a 3D mesh, a compiled binary, a sensor reading, a genome sequence.
- **Op**: typed function, artifacts in → artifacts out, with a determinism class. Just a function with metadata about its purity.
- **Decision**: recorded nondeterministic choice. Applies to any process with genuine choice — human, algorithmic, stochastic.
- **Run**: append-only event log + plan (DAG). Event sourcing + dependency graph. Domain-agnostic by construction.
- **Pack**: plugin system providing ops and plan functions.

### What Liminara Actually Is

A **general-purpose supervised computation runtime with recorded nondeterminism.** Or: **Make for processes with choices.**

Where Make assumes deterministic operations (compile this file → same output every time), Liminara extends the build system model to operations that involve genuine nondeterminism, by recording the choices that resolve that nondeterminism.

### Examples Beyond Knowledge Work

**Manufacturing/engineering**: CNC machining workflow. Ops: CAD import → toolpath generation → simulation → material optimization → G-code output. Decisions: tool selection, cut strategy, tolerance trade-offs. Artifacts: toolpaths, simulation results, G-code files.

**Biotech**: Drug candidate screening pipeline. Ops: molecular docking → ADMET prediction → toxicity screening → lead optimization. Decisions: which candidates to advance, which assays to run.

**Finance**: Portfolio construction. Ops: universe screening → factor analysis → optimization → risk decomposition → compliance check. Decisions: factor weights, constraint relaxation, rebalancing triggers.

**Game development**: Procedural content generation. Ops: terrain generation → biome placement → settlement layout → quest graph generation → balancing pass. Decisions: seed selection, aesthetic choices, difficulty curves.

**The house compiler**: Already in the roadmap. Geometry kernels, rule engines, optimizers, human approval gates producing floor plans and structural calculations. Not knowledge work. Fits perfectly.

**Software factory**: Meta-circular — Liminara building software, possibly including itself.

### Why Lead With Knowledge Work Anyway

Knowledge work is the right *validation domain* even though it's not the right *definition*:

1. **High ratio of nondeterministic ops.** LLM calls, human judgment, web scraping — exercises the Decision concept immediately.
2. **Market timing.** Everyone is trying to orchestrate LLM workflows; existing tools do it badly.
3. **Low barrier to entry.** Text and JSON artifacts, no specialized compute engines needed to start.
4. **The house compiler proves generality early.** Having it as the second real pack demonstrates the architecture isn't limited to text pipelines.

### The Nix Parallel

Liminara is closer to what Nix does for software builds than what LangChain does for LLM orchestration. Nix's insight: if you record every input (including the environment), builds become reproducible. Liminara's insight: if you record every *decision*, processes with genuine nondeterminism become reproducible too. Nix controls determinism by controlling inputs. Liminara controls determinism by recording choices. That's a more general mechanism because it handles irreducible nondeterminism (human judgment, stochastic algorithms, external API responses) that Nix's approach can't capture.

### The Bottom Line

"Knowledge work" is the beachhead market. The house compiler is the proof of generality. The software factory is the meta-circular flex. But the architecture is domain-agnostic, and the tagline should not constrain what Liminara can become.

The HashiCorp parallel reinforces this: Terraform's architecture (DAG, state, plan/apply, providers) is completely generic — it could manage anything with a CRUD API. But they launched it for cloud infrastructure because that's where the pain was sharpest. The architecture was always bigger than the first use case. Liminara's is too.
