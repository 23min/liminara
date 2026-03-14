# Why Replay: The Case for Recorded Decisions and Re-execution

## The Naive Objection

"I ran a pipeline. I have the output. Why would I ever run it again?"

If Liminara only re-ran the same thing identically, replay would be pointless overhead. But replay isn't about repetition — it's the mechanism that turns a process into a navigable structure instead of a one-shot event.

## 1. Selective Re-execution (The Build System Property)

Consider a radar pack:

```
fetch_sources → filter → analyze_each → synthesize → format → deliver
```

50 sources analyzed by an LLM — $2 and 10 minutes. You realize the synthesis prompt was wrong (summarizing instead of comparing).

- **Without replay**: re-run everything. 50 LLM calls you already paid for. Waste.
- **With replay**: fetch, filter, and analyze ops haven't changed. Cache hit. Skip them all. Only the synthesis op (changed prompt = changed op version = cache miss) and downstream re-execute.

This is exactly what `make` does: if `foo.c` didn't change, don't recompile it. But extended to operations with recorded nondeterminism. **Incremental recomputation over nondeterministic processes.**

## 2. Branching Decisions (Exploration as a Tree, Not a Line)

House compiler example:

```
site_constraints → generate_layouts → select_layout → detail_rooms → structural_calc → output
```

At `select_layout`, the system chooses layout B from five candidates. Everything downstream computed from that choice. Buyer asks: "What if we'd gone with option D?"

- **Without replay**: start over. Re-run layout generation (30 minutes of geometry computation). Get the same five options. Pick D. Re-run everything downstream.
- **With replay**: fork the run at the decision point. Inject decision D where decision B was. Everything upstream is cached. Only downstream ops re-execute.

**Linear processes become decision trees you can navigate after the fact.** Recorded decisions are the branch points. This is genuinely novel — build systems don't do this (no decisions to vary), workflow engines don't do this (decisions aren't first-class replayable entities).

## 3. Auditable Provenance (The Compliance Property)

For any artifact, answer: **What produced this? From what inputs? With what decisions? By which version of which op?**

The event log gives a complete causal chain from final output back to initial inputs. Every decision recorded. Every intermediate artifact content-addressed and retrievable.

Example: a radar report from three months ago said "competitor X is entering market Y." Where did that come from? Trace it: the synthesis op produced that claim → from these three analysis artifacts → produced by analyzing these three source articles → fetched on this date → the LLM made this specific inference (recorded decision) from this specific passage.

Not replay as "run it again." Replay as **forensic reconstruction.**

Directly supports EU AI Act Article 12 logging requirements, but the value extends far beyond compliance.

## 4. Deterministic Production (Discovery to Hardened Pipeline)

Many processes start as exploration and need to become reliable production:

- **Week 1 (Discovery)**: building a new pipeline. Trying different source lists, prompts, strategies. Each run makes decisions. Iterate.
- **Week 4 (Stabilization)**: found a configuration that works. Every decision has been made and recorded.
- **Week 5+ (Production)**: replay with stored decisions. The run is deterministic — same inputs, same decisions, same outputs. No expensive calls for pinned decisions. Schedule it, monitor it, guarantee behavior.

Without replay, the transition from experiment to production requires rewriting as a different system. **With replay, it's the same system — you stop making new decisions and start injecting recorded ones.**

## 5. Efficient What-If Analysis

Combine branching (#2) with selective re-execution (#1): **cheap what-if analysis over expensive processes.**

House compiler: a full run took 2 hours and $15 in compute. The buyer explores:

- "What if we used a different roof type?" → fork at roof decision, re-run structural + downstream
- "What if we added a bathroom?" → fork at room layout decision, re-run from there
- "What if we used cheaper materials?" → fork at materials decision, re-run cost + structural

Each what-if re-uses everything upstream of the changed decision. Cost: minutes and cents, not hours and dollars.

**The buyer explores a design space interactively because replay makes it incremental.** Applies equally to knowledge work: "re-analyze but focus on regulatory risk instead of competitive risk" — fork at the analysis prompt decision, re-use all fetching and filtering.

## 6. Regression Detection

Upgrade an LLM from GPT-4 to GPT-4.5. Does the pipeline still work?

Replay the last 10 runs with the new model. Compare outputs. The decisions will differ (different model = different responses), but the DAG structure, inputs, and all deterministic ops stay the same. **The variable is isolated. Outputs can be diffed structurally.**

Without recorded decisions: re-run everything, try to figure out what changed and why. With replay: know exactly which decisions changed, trace their downstream effects.

## 7. Collaboration and Handoff

A colleague built a radar pipeline. You want to understand what it does. The event log tells you — not as documentation that might be stale, but as the actual record of execution. Every op, every decision, every artifact.

Better: replay it, override one decision, see what happens. "I think the filtering is too aggressive — let me loosen it and see how the output changes." Not reading documentation. **Interacting with a recorded process.**

## Summary

| Capability | Without Replay | With Replay |
|-----------|---------------|------------|
| Change one step in a pipeline | Re-run everything | Re-run only what changed |
| Explore alternative choices | Start over | Fork at the decision point |
| Audit how an output was produced | Hope you logged enough | Complete causal reconstruction |
| Move from experiment to production | Rewrite as a different system | Pin decisions, same system |
| Test a model upgrade | Re-run and eyeball it | Controlled comparison, isolated variable |
| Explore a design space | N full runs at full cost | N partial runs at marginal cost |
| Understand someone else's pipeline | Read (possibly stale) docs | Navigate the actual execution record |

## The Core Argument

The event log isn't a debug log — it's the process itself, reified as data, explorable after the fact.

The output of a pipeline is one path through a decision tree. Replay lets you explore other paths without paying full cost for each one. That's why it matters even when you "already have the report."
