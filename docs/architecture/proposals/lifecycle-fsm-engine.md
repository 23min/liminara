## RFC: Per-entity FSMs + LLM/engine boundary — a lifecycle architecture for wf-graph-based workflow

> **Filed upstream as [`23min/ai-workflow#77`](https://github.com/23min/ai-workflow/issues/77) on 2026-04-25.** This local copy is Liminara's design-history record. The upstream issue is the canonical discussion venue; updates to the RFC's content land there first, with this file kept in sync at significant revisions.
>
> **Origin:** drafted on Liminara during a long-running design conversation that surfaced repeated friction with the framework's lifecycle skills (multiple sub-epics in E-21 with no native graph kind; ad-hoc "parked" vocabulary; per-skill flow duplication). Filing upstream because the architecture is framework-relevant, not Liminara-specific.

### Status

Draft / discussion. Filed as RFC because the design touches multiple skills and the wf-graph CLI; consensus on the architecture should precede implementation. Companion to and supersedes the wiring scope of [#68](https://github.com/23min/ai-workflow/issues/68).

### Summary

The framework's five lifecycle skills (`plan-epic`, `plan-milestones`, `start-milestone`, `wrap-milestone`, `wrap-epic`) are five Markdown files with overlapping flow shapes, edit frontmatter directly, and don't route through `wf-graph`. Issue #68 proposes wiring them to `workflow-graph mutate`. This RFC argues that the wiring fix alone leaves a deeper architectural gap: there is no state-machine model in the framework, no shared concept of "lifecycle event," no support for concurrent multi-entity flows, and no clear LLM/engine boundary. The result is recurring drift, ad-hoc vocabulary ("parked"), per-skill duplication, and consumer pain on non-trivial topologies (e.g., sub-epics in this consumer's case — see [the on-wire mistake on Liminara 2026-04-25](#references)).

This RFC proposes:

1. **Per-entity FSMs** as a first-class wf-graph concept, one FSM-type per node-kind.
2. **A clear LLM/engine boundary**: LLM owns content, intent, and dialogue; engine owns structure, atomicity, and FSM correctness; the patch YAML is the contract between them.
3. **Lifecycle skills become thin transition wrappers** — one event-type per wrapper, all routed through a uniform `wf-graph transition` interface.
4. **Ergonomic verbs** (`wf-graph promote`, `wf-graph wrap`, `wf-graph pause`, etc.) so consumers can author transitions without hand-writing patch YAML.

The design dissolves the multi-active-epic awkwardness, gives "parked" / "blocked" / "cancelled" actual meaning, makes sub-epic-style nesting expressible without ad-hoc rules, and reduces the lifecycle skills from five overlapping flows to one transition engine plus N event-type wrappers.

### Background

#### Today's shape

The framework provides:

- A graph engine (`wf-graph`) with kinds `epic`, `milestone`, `adr`, `decision`, `gap`, edges (`parent`, `depends_on`, `supersedes`, etc.), and atomic mutation via patch YAML.
- A `workflow-graph` skill orchestrating the graph in four modes (bootstrap / triage / query / mutate).
- A `workflow-audit` skill for periodic drift detection.
- Five lifecycle skills (`plan-epic`, `plan-milestones`, `start-milestone`, `wrap-milestone`, `wrap-epic`) that handle status transitions on epic / milestone specs.

`workflow-graph.md` §31 already states the aspiration:

> all epic/milestone lifecycle skills should invoke `workflow-graph mutate` for status transitions once wf-graph is adopted, rather than editing frontmatter directly.

This is the wire #68 proposes to solder.

#### What #68 alone doesn't fix

#68's scope is *"each lifecycle skill, instead of editing frontmatter directly, composes a patch and routes through `workflow-graph mutate`."* Useful — gets atomicity and propose-time impact preview. But the wiring change does not address:

- **No FSM concept.** The framework has no notion of *"valid transitions for kind X."* Each skill encodes its own transition (`start-milestone` knows `draft → active`; `wrap-milestone` knows `active → complete`; etc.) implicitly in prose. There is no machine-checkable transition rule.
- **Five overlapping flows.** Each lifecycle skill is a Markdown file with similar-but-not-identical structure. Maintenance burden is N×, drift is inevitable.
- **No multi-entity concurrency story.** "Active focus" assumes one epic / one milestone in flight. Real consumers run concurrent epics, pause some, block others.
- **No sub-epic support.** Consumers (this one explicitly) carry ad-hoc vocabulary like "parked sub-epic" that has no representation in the framework.
- **Patch authoring complexity.** Even a *skill* composing a patch has to know that orphan-detection uses `parent` edges (not the `Node.ParentID` YAML field), pick the right status string, etc. (See [#68 comment](https://github.com/23min/ai-workflow/issues/68#issuecomment-4319779349) for the friction encountered today.) Five skills each authoring patches duplicate this discovery.

### Design

#### Layer 1 — Per-entity FSMs

Each node-kind has its own state machine. Concurrent entities operate independently.

**Epic FSM:**

```
proposed → planning → active → complete
                       ⇅
                    paused (intentional inactivity)
                       ↓
                    blocked (graph-tracked dependency unsatisfied)
                       ↓
                    cancelled (terminal)
```

**Milestone FSM:**

```
draft → active → complete
          ⇅
       blocked
          ↓
       cancelled (terminal)
```

**ADR FSM:**

```
proposed → accepted → superseded → deprecated
```

(Other kinds — `gap`, `decision` — get their own FSMs at smaller scale.)

Each FSM definition specifies:

- The set of states.
- The allowed transitions between them.
- Per-transition **guards** (e.g., `milestone.draft → active` requires *all `depends_on` blockers in terminal state*).
- Per-transition **effects** (graph mutation; spec frontmatter updates; — but see [Open Question Q-2](#open-questions) on whether structural side effects like branch operations live in the engine or in the LLM-side wrapper).

There is no global FSM for "the project." There are N concurrent per-entity FSMs that interact only through the graph.

#### Layer 2 — The LLM/engine boundary

The framework already has both an LLM (Claude / Copilot) and an engine (`wf-graph`). The architecture's success depends on dividing labor cleanly.

| | **LLM** | **`wf-graph` engine** |
|---|---|---|
| Reads | Markdown bodies, intent, conversation, CLAUDE.md | Frontmatter fields, edges, FSM definitions |
| Knows | What things *mean*, whether a spec is well-formed, what the user wants | What's *structurally allowed* now, what would happen if X transitioned |
| Authors | Markdown content, patch YAML, commit messages, human-readable summaries | Nothing it doesn't have to |
| Decides | What to do, when to propose a transition | Whether a proposed transition is *legal* given the FSM + graph |
| Guarantees | Nothing on its own (interpretive, stochastic) | Atomicity, FSM correctness, propagation |

**The patch YAML is the contract.** The LLM composes it (informed by content + intent); the engine validates and applies. This boundary keeps the LLM's interpretive flexibility and the engine's deterministic safety.

#### Layer 3 — Lifecycle skills as thin transition wrappers

Replace the five Markdown files with one transition pattern, instantiated per event-type:

```
/wf-start <id>     — milestone:draft → active   |  epic:planning → active
/wf-wrap <id>      — milestone:active → complete |  epic:active → complete
/wf-pause <id>     — epic:active → paused
/wf-resume <id>    — epic:paused → active
/wf-cancel <id>    — *:* → cancelled
/wf-plan <id>      — epic:proposed → planning
```

Each is a one-liner that:

1. Calls into the FSM engine with `(node-id, target-state)`.
2. Lets the engine validate guards.
3. Lets the engine compute effects + impact preview.
4. Shows the human a translated summary.
5. On approval, applies atomically.
6. Performs post-transition LLM-side work (CLAUDE.md update, tracking doc scaffold, summary).
7. Stages commit; human approves.

The lifecycle skill's content is essentially: *"invoke this transition on this node; here's the human-readable framing for this event-type."* All FSM logic lives in the engine.

#### Layer 4 — Ergonomic verbs in the CLI

The patch YAML is expressive but verbose. For the common lifecycle events, expose ergonomic verbs that synthesize patches internally:

```
wf-graph promote <id> --to <state>           # primitive: validates FSM transition + applies
wf-graph add-milestone <id> --epic <id> ...  # primitive: add_node + parent edge atomically
wf-graph block <id> --reason "..."           # active → blocked
wf-graph unblock <id>                        # blocked → active (when blockers resolved)
wf-graph cancel <id> --reason "..."          # any → cancelled
wf-graph wrap <id>                           # active → complete (with cascade preview)
```

These verbs route through the same propose-then-apply path as patch YAML, but skill code becomes one line.

### Walked scenarios

#### S1: `start-milestone` with satisfied blockers

User: *"start M-PACK-A-01."*

1. **LLM (intent):** resolves "M-PACK-A-01" to a node-id; recognizes the start event-type.
2. **LLM (context):** reads the milestone spec, CLAUDE.md *Current Work*.
3. **Engine (query):** `wf-graph query M-PACK-A-01 --transitions`. Returns: `current_state: draft, allowed_targets: [active, cancelled]`.
4. **Engine (query):** `wf-graph query M-PACK-A-01 --blocked-by`. Returns: `[E-19 (status: complete)]`. Blockers in terminal state — guard satisfied.
5. **LLM (compose):** invokes `wf-graph promote M-PACK-A-01 --to active --dry-run`.
6. **Engine (preview):** validates; returns delta JSON: `would_succeed: true; effects: [graph mutation, frontmatter status flip]; propagation: [no downstream auto-transitions].`
7. **LLM (relay):** *"This transition flips M-PACK-A-01 to active and updates `work/graph.yaml` + spec frontmatter atomically. The follow-up post-effect (cutting `milestone/M-PACK-A-01` branch from `epic/E-21-pack-contribution-contract`) is LLM-side. Apply?"*
8. **Human:** approves.
9. **Engine (apply):** `wf-graph promote M-PACK-A-01 --to active` writes graph.yaml + frontmatter atomically.
10. **LLM (post-effects):** cuts the milestone branch; scaffolds the tracking doc; updates CLAUDE.md *Current Work*; stages commit.
11. **Human:** approves commit; LLM commits.

#### S2: `start-milestone` with unsatisfied blockers

User: *"start M-PACK-A-02b."*

1. **LLM (intent + context):** as S1.
2. **Engine (query):** `wf-graph query M-PACK-A-02b --blocked-by`. Returns: `[M-PACK-A-02a (status: draft)]`.
3. **Engine (transition validation):** `wf-graph promote M-PACK-A-02b --to active --dry-run`. Returns: `would_succeed: false; reason: "blocker M-PACK-A-02a is not in terminal state"`.
4. **LLM (relay):** *"M-PACK-A-02b can't start yet — its blocker M-PACK-A-02a is in `draft`, not a terminal state. Either start M-PACK-A-02a first, or override the dependency, or pick a different milestone."*
5. **No transition occurs.** Engine refuses; LLM presents the human-readable reason.

This scenario shows how guards prevent invalid lifecycle moves *before* any spec is touched. Today, a skill could write `status: active` to frontmatter regardless of blockers — drift in slow motion. The FSM engine catches it deterministically.

#### S3: `wrap-epic` with cascading propagation

User: *"wrap E-19."*

1. **Engine (query + dry-run):** validate transition `E-19: active → complete`. Compute propagation: which downstream entities are unblocked?
2. **Engine (preview):** `propagation: { unblocked: [M-PACK-A-01, ...] }`.
3. **LLM (relay):** *"Wrapping E-19 unblocks the following downstream items: M-PACK-A-01 (in draft, will become eligible to start). Apply?"*
4. **Human:** approves.
5. **Engine (apply):** atomic flip; downstream `blocked` entities (if any) auto-transition to `active` (or to whatever their pre-block state was).
6. **LLM (post-effects):** merges `epic/E-19-...` into main; archives the epic folder; updates CLAUDE.md.

This scenario shows propagation: one transition cascades cleanly through dependents because the graph + FSM rules know how. Today, "this wrap unblocks E-21" is invisible to the operator.

#### S4: pause-then-resume

User: *"pause E-21."* (Real reason: stakeholder reprioritization, want to ship E-12 first.)

1. **Engine (transition):** `E-21: active → paused`. No automatic effects on dependents (they don't care about pause/resume; only about terminal-state transitions).
2. **LLM (post-effects):** updates CLAUDE.md; notes the pause reason in `decisions.md`.
3. Later: User: *"resume E-21."*
4. **Engine (transition):** `E-21: paused → active`. Re-evaluates dependents: any that auto-blocked because of the pause come back. (Depends on whether `paused` is treated as terminal-for-dependents — open design question.)

This scenario shows how `pause` is a real state with semantics, not a CLAUDE.md word.

#### S5: concurrent multi-epic flow

State: E-21 is `paused`, E-12 is `active`.

`wf-graph report --status` shows both, each with its own progress. There is no global "active focus." The lifecycle skills operate on whichever node-id you pass; the graph keeps state for all in-flight FSMs simultaneously.

This is the case current framework can't model cleanly. The proposed architecture handles it natively because there is no global FSM — only per-entity FSMs that operate independently.

#### S6: sub-epic transition (consumer-specific)

This consumer (Liminara) has split E-21 into four sub-epics (E-21a/b/c/d). Today the framework has no `sub_epic` kind, so sub-epics are filename conventions and ad-hoc CLAUDE.md vocabulary.

Two ways to support this in the proposed architecture:

**(a) `kind: sub_epic` as a first-class node-kind** with its own FSM (probably identical to milestone's). Parent edge points to a `kind: epic`. Children edges point to milestones.

**(b) Recursive nesting via `kind: epic` + `parent` edges.** An epic can be the parent of another epic; the parent epic's FSM doesn't transition to `complete` until all child epics are complete.

Either way, the lifecycle skills (`/wf-start`, `/wf-wrap`, etc.) work uniformly on whichever node-id you pass; nesting is a graph concern, not a skill concern.

This dissolves the [Liminara-specific working rules](https://github.com/23min/ai-workflow/issues/) that currently exist as ad-hoc CLAUDE.md content.

### Open questions

The following are real, unresolved choices the design will have to answer before implementation. Each has options + tradeoffs; recommendations are starting points, not commitments.

**Q-1: Where do FSM definitions live?**

- **Option A:** Hardcoded in Go (`wf-graph` CLI). Single source of truth; consumers can't customize.
- **Option B:** YAML files (`framework/fsms/<kind>.yaml`). Consumers can override per-kind.
- **Option C:** Plugin system — Go core, with optional YAML overlays per consumer.

*Lean: A initially (forces convergence on a canonical FSM per kind), with B as a future extension if real-consumer divergence justifies it.*

**Q-2: Where does the post-transition effects boundary fall?**

- **Option A: Engine-driven effects.** Branch ops, frontmatter writes, ROADMAP regen all atomic with graph mutation. Engine has to know git, file paths, project conventions.
- **Option B: LLM-driven post-effects.** Engine handles only graph + frontmatter; LLM-side skill handles branch ops + scaffolding + CLAUDE.md after engine confirms apply.

*Lean: B with explicit transactional intent. Engine is a *kernel* — graph + frontmatter atomically. Post-work has clear failure-recovery semantics: detectable mid-flight, idempotently re-runnable.*

**Q-3: How are auto-transitions triggered?**

When E-19 → complete, dependents (M-PACK-A-01) become unblocked. Does the engine auto-transition `M-PACK-A-01: blocked → active`?

- **Option A:** Yes, automatic. One transition cascades.
- **Option B:** No — the engine reports propagation, but each dependent's transition is human-initiated.

*Lean: B. Propagation as visibility, not as automation. Humans decide when work starts; automation only enforces "you can't start yet" (guards), not "you must start now."*

**Q-4: How is sub-epic / nesting modeled?**

See [S6](#s6-sub-epic-transition-consumer-specific). Recommend recursive `kind: epic` + parent edges; flag for community input.

**Q-5: How do we handle "FSM definitions need to evolve"?**

Adding states / transitions to existing FSMs is a breaking change for consumers with state already in the new-state space. Versioning strategy needed.

**Q-6: What about non-lifecycle entities (decisions, gaps, ADRs)?**

The proposal sketches FSMs for them too, but their lifecycle is much lighter. Should they be in scope here, or punted to a follow-up RFC?

*Lean: in scope, even if implementation phases land separately. A unified FSM model means all kinds get the same treatment.*

### Migration path

The architecture can land incrementally without breaking existing consumer repos.

**Phase 1 — Engine groundwork.**

- Land FSM definitions in `wf-graph` (Go).
- Add ergonomic verbs (`wf-graph promote`, `wf-graph wrap`, etc.) — pure additions, no behavior change.
- Add the `--transitions` flag to `query`.
- Existing skills continue to edit frontmatter directly. No consumer-visible change yet.

**Phase 2 — Wire skills (#68 territory).**

- Each of the five lifecycle skills updated to invoke ergonomic verbs instead of editing frontmatter directly.
- Backward-compatible: skills' contracts to humans are identical (`/wf-start-milestone <id>` still works the same way), but underneath they go through propose-then-apply.

**Phase 3 — Consolidate skills.**

- Replace the five lifecycle Markdown files with one transition-wrapper template + per-event-type instantiations. Reduces maintenance burden.
- Add new event types (pause, resume, cancel, block) that today don't have skills.

**Phase 4 — Concurrency + sub-epic native support.**

- Remove "active focus" assumption from CLAUDE.md template; replace with multi-entity status display.
- Land `kind: epic` recursive nesting (or `kind: sub_epic`, per Q-4 resolution).

Each phase is independently shippable and adds value before the next phase lands.

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| LLM-side post-effects partial-failure (e.g., branch cut but tracking doc not scaffolded) | Medium — divergence between graph and disk | Idempotent post-effect runner; post-effect status recorded in graph as `transitioning` until confirmed; manual recovery skill (`/wf-finalize <id>`) for stuck states |
| FSM definitions diverge between framework and consumer overlays (if Q-1 = C) | Medium — cross-repo confusion | Strict precedence rules (consumer overrides framework only for opt-in-listed kinds); validation on adoption |
| Atomic-boundary subtle bugs (e.g., flock race, partial frontmatter write) | High — on the path that matters most | Property-based tests in `tests/test-sync.sh`; explicit failure-mode catalog |
| The architecture requires more upfront work than current consumers want | Medium — adoption lag | Phased migration (above); each phase ships value independently |
| Scope creep — "while we're at it, let's redesign everything" | Medium — RFC stalls | Punt out-of-scope items to follow-up RFCs; keep this one focused on lifecycle + FSMs + LLM/engine boundary |

### Acceptance criteria

For the architecture to be considered *implemented and usable*:

- [ ] Each FSM has a canonical definition in the engine.
- [ ] `wf-graph promote / wrap / pause / resume / cancel` ergonomic verbs implemented and tested.
- [ ] Each lifecycle skill (`plan-epic`, `plan-milestones`, `start-milestone`, `wrap-milestone`, `wrap-epic`) invokes a verb instead of editing frontmatter directly.
- [ ] `wf-graph query <id> --transitions` returns the allowed targets for the current state.
- [ ] Sandbox tests demonstrate: S1 (happy-path start), S2 (blocked-start refused), S3 (wrap-with-cascade), S4 (pause/resume), S5 (concurrent multi-epic), S6 (sub-epic if Q-4 is resolved in scope).
- [ ] `workflow-graph.md` and `wrap-epic.md` updated to describe the FSM-driven flow.
- [ ] Migration guide for consumer repos.
- [ ] All ACs from #68 satisfied as a subset.

### References

- [#68](https://github.com/23min/ai-workflow/issues/68) — wiring fix (subset of this RFC's scope).
- [`workflow-graph.md`](https://github.com/23min/ai-workflow/blob/main/skills/workflow-graph.md) — current graph orchestration skill.
- [`wf-graph-design.md`](https://github.com/23min/ai-workflow/blob/main/docs/wf-graph-design.md) — graph engine design.
- Adjacent prior art: compiler IRs (parser/IR boundary mirrors LLM/engine boundary); ORM + query planner (interpretive code authors structured queries; planner enforces validity); agent state graphs in LangGraph et al. (FSM-driven agents, but for runtime task orchestration, not project artifact lifecycle).

### Process notes

- The RFC was drafted on Liminara (a consumer repo) after a long-running design conversation surfaced repeated friction points. Filing here on `ai-workflow` because the architecture is upstream-relevant, not Liminara-specific.
- Happy to break this into smaller RFCs if maintainers prefer one issue per layer (FSMs / boundary / verbs / skill consolidation).
- Open to disagreement on every named "lean" — none of them are commitments. The walked scenarios are the design's pressure-test surface; if a maintainer's preferred shape passes the same scenarios, that shape is fine.
