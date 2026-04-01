# Roadmap

Status of planned improvements. Details and rationale in [docs/squad-inspired-roadmap.md](docs/squad-inspired-roadmap.md).

| ID | Item | Status | Branch | Notes |
|----|------|--------|--------|-------|
| P1 | Persistent memory (decisions.md + agent history) | done | main | Agents read/write memory files across sessions |
| P2 | Intent routing table | done | main | Keyword → agent+skill mapping in generated instructions |
| P3 | Response mode awareness (quick/standard/epic) | done | main | Auto-detect task complexity, skip ceremony for small fixes |
| P4 | Coordinator agent + handoffs | experimental | experiment/phase-2 | Native subagent delegation + handoff buttons between workflow phases |
| P5 | Decision lifecycle management | planned | — | Structured decisions with active/archived states + pruning |
| P6 | Framework self-testing | done (partial) | main | `tests/test-sync.sh` — 10 scenarios, 397 lines |
| P7 | GitHub Actions for issue triage | planned | — | Optional workflows for auto-labeling + auto-assign |
| P8 | Inter-agent drop-box | planned | — | Structured handoff notes between agents |
| P9 | CLI wrapper | planned | — | `ai plan`, `ai build`, `ai sync`, `ai status` |
