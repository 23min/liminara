# RFC: Dynamic pipelining via content-routed contract dispatch

## Status

Draft / proposal. Filed during M-CONTRACT-02 (foundational contracts) authoring on 2026-05-02 to elaborate the design direction recorded in `work/decisions.md` D-2026-05-02-039 and tracked under `work/gaps.md` *Dynamic pipelining shape — content-routed dispatch via contract matching*. **No implementation work is proposed for the current epic (E-24).** The decision points marked in §8 are the things M-CONTRACT-04 will commit to when it scopes `ADR-DYNAMIC-PIPELINE-01` (or a scope-extension of `ADR-MULTIPLAN-01`, whichever the milestone picks). The schema-room obligations on M-CONTRACT-02 are listed in §7.

This RFC is a sibling to `docs/architecture/proposals/pipeline-scoped-run-context.md`, filed the same day for the same purpose: pressure-test the foundational five contracts (manifest, plan, op-spec, replay, wire) before they accidentally close design space. The two proposals address orthogonal axes — pipeline-scoped is about *where ops execute*; this is about *how ops are wired together when wiring depends on data*. They co-exist; §9 verifies they don't conflict.

## Summary

Liminara's deterministic-replay discipline is well-served by the *static* DAG model `ADR-PLAN-01` v1.0.0 ships. Every node and every edge is named at plan-build time; the realized execution is the declared graph. This shape is exactly right for Radar today and for every compiler-shaped pack on the roadmap. It is **not** sufficient for a pack whose realized DAG depends on data — admin-pack v2's §9 plan example uses `enabled: input.use_llm` to gate an `llm_escalation` node by a runtime input; future packs (Software Factory, House Compiler with conditional structural-check branches, Process Mining with adaptive cleanup paths, Population Simulation with branching scenarios) will all want the same capability.

The Q&A round on `ADR-PLAN-01` Q8 ratified two paired decisions:

1. PLAN-01 v1.0.0 ships strict static-DAG-only. No `enabled:`, no conditional skip flags, no candidate-consumers binding shape, no contract-routing semantics in v1.0.0. Admin-pack §9's shape isn't admitted until a v1.x evolution path lands.
2. The future direction for dynamic pipelining is **content-based contract routing with dead-letter fallback**, designed at M-CONTRACT-04. Each consumer's input contract declares which artifacts it accepts; the runtime introspects an output and routes it to the matching consumer. Control flow *is* data flow — one surface, not two. Dead-letter falls out as the catch-all "nothing matched" path.

This RFC elaborates that direction. It walks the design space the Q&A surfaced; restates *why* contract routing is structurally cleaner than predicate-flag conditionals; works through the four hard cases (single-consumer routing, multi-input composition, slot collections, cascading dead-letter starvation); maps out the design forces (replay discipline, Petri-net deadlock theory, sum-type pattern matching, BPMN content-based routing) that the eventual ADR will lean on; elaborates the 12-item bill of materials D-039 enumerated; and pins down what M-CONTRACT-02 must keep open versus what it can leave for M-CONTRACT-04.

The recommendation is in §11. In one sentence: *PLAN-01 v1.0.0 keeps its `#InputBinding` union open to additive expansion; OPSPEC-01's `#Contracts` block keeps its `{[string]: _}` open to value-pattern constraints; the rest waits for M-CONTRACT-04 with the bill of materials below as its inheriting brief.*

---

## Background — the gap

### What PLAN-01 v1.0.0 admits

`docs/schemas/plan/schema.cue` defines a `#Plan` as a list of `#Node`s; each input is an `#InputBinding`, a discriminated union of exactly two shapes:

```cue
#InputBinding: #LiteralBinding | #RefBinding

#LiteralBinding: close({ type: "literal", value: _ })
#RefBinding:     close({ type: "ref", ref: string & !="", key?: string & !="" })
```

`#LiteralBinding` carries a JSON-encodable value hard-coded at plan-build time; `#RefBinding` names another node's output (optionally a specific output key). Every binding is named statically; every edge in the DAG is decidable from the plan document alone, before any node runs. For Radar's plan — five linear nodes — this is all the schema needs.

### What admin-pack §9 wants

`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md` §9 sketches a per-period bookkeeping plan with thirteen nodes. One isn't plain static:

```elixir
|> Plan.add_node("llm_escalation", LlmMatchEscalate, %{
     inputs: %{ambiguous: {:ref, "apply_thresholds", :ambiguous}},
     enabled: input.use_llm
   })
```

If the period's input config has `use_llm: true`, the LLM-escalation node participates; otherwise it doesn't. Downstream nodes (`review_gate`, `reconcile`) consume `llm_escalation`'s output via `{:ref, "llm_escalation", ...}` bindings; if the node didn't run, those rows are absent. The §9 prose says "skip" — but skip-with-what-downstream-fate is unspecified.

### Why this is a capability gap, not a syntax gap

The first shape that springs to mind is admitting `enabled:` in the `#Node` schema — a one-field addition with a predicate language over plan inputs and prior outputs. But the gap isn't notation; it's *what runtime semantics that notation commits the runtime to*. Predicate-flag conditionals open (at least) these questions: what's the predicate language and its evaluator (CEL? JSONPath? custom DSL? each with its own footguns); when is the predicate evaluated (plan-build-time-only is a thin convenience, runtime-with-prior-outputs is a new evaluation surface); what happens to downstream consumers when a node is skipped (cascade? fail? default?); and how does replay stay deterministic.

The Q&A surfaced these and named the structurally cleaner alternative — encode the conditional in the **contract surface itself**, not as a predicate language layered over the DAG. §3 walks the argument; §4 works the shapes; §5 maps the design forces.

### The two flavors of dynamism

- **Flavor 1 — plan-time dynamism.** The predicate references plan-time inputs only. Equivalent to "the plan author chose not to emit this node at all." A thin convenience; the same effect is achievable by having `Pack.plan/1` build different plans for different inputs.
- **Flavor 2 — runtime dynamism.** The predicate references prior-node outputs. Resolved at execution time, based on data values that don't exist until then. Genuinely dynamic: the plan document alone does not determine which nodes run.

Flavor 2 is the interesting case. It is also *deterministic dynamic pipelining*: same content-addressed inputs → same routing decision → same realized DAG subset → same outputs. The DAG becomes "the static envelope of possible execution; the realized subset is data-determined." This proposal targets Flavor 2; Flavor 1 is trivially subsumed.

---

## §3 — Predicate-flags vs. contract-routing

This is the load-bearing argument of the proposal. Both shapes can encode admin-pack §9's `use_llm` case. They differ in how many surfaces the runtime has to reason about, and in how the design behaves under pressure from new requirements.

### The predicate-flag shape

Add an optional `enabled` field to `#Node`:

```yaml
- node_id: llm_escalation
  op: llm_match_escalate
  inputs:
    ambiguous: { type: ref, ref: apply_thresholds, key: ambiguous }
  enabled:                    # NEW: predicate over inputs + prior outputs
    expr: "$config.use_llm == true"
```

The runtime evaluates `enabled` at schedule time; if false, the node is marked skipped. This is the shape nearly every workflow runtime ships (Airflow's `branch_task`, Prefect's `case`, Dagster's branching, Flyte's conditional). The question is what it costs.

### Costs of the predicate-flag shape

- **Two surfaces, not one.** Plan authoring becomes "name your inputs (via ref-bindings) *and* write predicates (in a parallel language) over those and other inputs." Two evaluation surfaces; two failure modes; two debug stories. A pack author asking "why didn't this node run?" must look at both the binding graph and the predicate.
- **Predicate-language design is its own headache.** CEL, JSONPath, or custom DSL — each comes with type coercion, error propagation, sandboxing, performance, and replay-version-pinning concerns. Another contract surface under M-CONTRACT-04's ownership.
- **The failure mode is silent skip.** A node ran or it didn't; if it didn't, the downstream consumer's slot is empty and the cascade rule is implicit ("input missing → you skip too"). Cascade becomes per-runtime convention, not first-class semantics. Audit answers "did this run?" but not "where did this go?"
- **Conditionals don't compose.** Two predicates that depend on each other's outputs don't form a coherent dependency graph; static-DAG invariant breaks without a clear replacement.

### The contract-routing shape

Encode the conditional in the **input contract** of each candidate consumer. Each consumer declares "I accept artifacts matching this value-pattern." The runtime, holding an output, picks the consumer whose contract matches.

```yaml
ops:
  - identity:
      name: llm_match_escalate
      version: 1.0.0
    contracts:
      inputs:
        ambiguous:
          # The contract describes the artifact's structural and
          # value shape. Routing is "find a consumer whose input
          # contract matches the produced artifact."
          schema:
            kind: ambiguity_set
            config:
              use_llm: true               # value-pattern constraint
        ...

  - identity:
      name: rule_only_match_escalate     # alternative consumer for use_llm: false
      version: 1.0.0
    contracts:
      inputs:
        ambiguous:
          schema:
            kind: ambiguity_set
            config:
              use_llm: false
```

Plan-side, the binding declares "any matching consumer," not a specific node:

```yaml
- node_id: apply_thresholds
  op: apply_auto_threshold
  outputs: [ambiguous]
  routes_to:                        # NEW: candidate consumers, not a fixed ref
    ambiguous:
      candidates: [llm_match_escalate, rule_only_match_escalate]
      # Or omitted entirely — the runtime can derive candidates from
      # which ops in the plan declare a matching input contract.
```

At runtime, `apply_thresholds` produces an `ambiguous` artifact. The runtime reads its bytes; introspects `config.use_llm`; matches it against each candidate consumer's input contract; routes to whichever one claims the value.

Both candidates are present in the plan. Both will run *iff* the data routes to them. Whichever didn't get the artifact terminates as *not-fired* — a defined terminal state (§5.3).

### Why contract-routing is structurally cleaner

- **One surface, not two.** The consumer's input contract describes what it consumes; the matcher is a pure function over artifact bytes; the plan binds outputs to "any matching consumer." No parallel predicate language. "Why didn't this node run?" gets one answer: *the artifact's bytes didn't match its input contract.*
- **The discipline already exists in the contract layer.** OPSPEC-01's `#Contracts` block declares input/output shapes (today loose, `{[string]: _}`); extending it to admit value-pattern constraints is an additive grammar bump, not a new evaluation surface. The runtime needs a contract-validator at op-invocation time anyway; the matcher is the same function asking a slightly stronger question.
- **Failure mode is principled, not silent.** "Nothing matched" is a defined routing outcome — the artifact lands at a dead-letter consumer (pack-author-registered or runtime-default). Operators see exactly which artifacts couldn't route and why.
- **Coverage analysis is load-time-decidable.** Because consumers' contracts are declared (not predicate expressions evaluated at runtime), PackLoader can statically enumerate "for every artifact shape an upstream might produce, which consumer claims it?" If every shape has at least one consumer (or the dead-letter), coverage is proven and starvation is impossible. With predicate- flags this is undecidable in the general case. §5.2 develops it.
- **Pattern names back the design up.** BPMN content-based routing routes by inspecting message content; predicate dispatch (Cecil, Object-Oriented Common Lisp) selects methods by input predicates; sum-type pattern matching (ML, Haskell, OCaml, Erlang) dispatches on discriminators. Liminara's contract routing inherits this lineage. §5.3, §5.4 work the analogies.

### The §9 worked recasting

`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md` §9 becomes:

```yaml
ops:
  - identity: { name: llm_match_escalate, version: 1.0.0 }
    contracts:
      inputs:
        ambiguous: { schema: { kind: ambiguity_set, config: { use_llm: true } } }
      outputs:
        still_ambiguous: { kind: ambiguity_set, route: llm }

  - identity: { name: rule_only_passthrough, version: 1.0.0 }
    contracts:
      inputs:
        ambiguous: { schema: { kind: ambiguity_set, config: { use_llm: false } } }
      outputs:
        still_ambiguous: { kind: ambiguity_set, route: rules }
```

Both ops are in the pack and in the plan as candidate consumers of `apply_thresholds`'s `ambiguous` output. The period config carries `use_llm: true|false` into the produced `ambiguous` artifact; the runtime routes to whichever op's contract claims the value. Downstream (`review_gate`, `reconcile`) declares its `still_ambiguous` inputs as either singular (whoever produced it) or collection.

No predicate language. No `enabled:` flag. No silent skip. *Control flow is data flow.*

---

## §4 — The shape (worked examples for the four hard cases)

This section works four cases the eventual ADR has to handle. Each case introduces one additional design pressure and shows the proposed shape's response.

### Case 1 — Single-input single-consumer with data-determined routing

One upstream output, several candidate consumers, runtime routes by content match.

```yaml
plan:
  schema_version: 1
  nodes:
    - node_id: classify_document
      op: classify_document
      inputs:
        document: { type: ref, ref: intake_scan, key: documents }
      outputs: [classified]

    - node_id: extract_invoice
      op: extract_invoice           # contract: accepts classified, document_kind == "invoice"
    - node_id: extract_receipt
      op: extract_receipt           # contract: accepts classified, document_kind == "receipt"
    - node_id: extract_statement
      op: extract_statement         # contract: accepts classified, document_kind == "statement"

  routes:
    # Optional: derivable from input-contract matching; declared here
    # for plan-readability.
    - from: classify_document.classified
      to: [extract_invoice, extract_receipt, extract_statement]
      via: contract_match
```

`classify_document` emits one `classified` artifact per document; each artifact's bytes carry a `document_kind` field. The runtime matches each candidate's input contract, routes to the matching extractor. Three documents (invoice/receipt/statement) → three extractors fire (one each). A fourth document with `document_kind: "unknown"` → no match; lands at dead-letter (case 4).

Replay: each routing decision is a pure function of artifact bytes plus contract definitions. No `Decision` record needed; the matcher is not a nondeterministic choice. An `artifact_routed` audit event is recorded for operator UI clarity (§6.10).

### Case 2 — Multi-input composition (palette + structure)

A House-Compiler-shaped consumer needs *two* artifacts of different kinds from separate upstream nodes. Each input slot has its own contract.

```yaml
plan:
  nodes:
    - node_id: derive_palette
      op: derive_palette
      outputs: [palette]                # contract: kind=palette

    - node_id: derive_structure
      op: derive_structure
      outputs: [structure]              # contract: kind=structure

    - node_id: compose_design
      op: compose_design
      # Op contract:
      #   inputs:
      #     palette:   { schema: { kind: palette } }
      #     structure: { schema: { kind: structure } }
      # Both slots are singular (function-call model).
```

`compose_design` declares two slots, each with its own contract. No explicit ref-bindings needed; the runtime matches each output to its contract-matching slot.

This subsumes today's static `{:ref, node_id, key}` bindings — in the static case, every slot has exactly one matching producer; the routing is unambiguous; the realized DAG is exactly the static one.

The interesting bit: a future plan adding a second palette-deriving node doesn't require manual rewiring; the runtime routes either palette to `compose_design`'s palette slot. Disambiguation when multiple candidates match singularly: see §9.5.

### Case 3 — Slot multiplicity (collection: merge candidates)

A consumer needs *all* matching outputs — "merge clusters from any producer that emitted a cluster artifact." Slot declared as collection, not singular.

```yaml
ops:
  - identity: { name: cluster_lexical, version: 1.0.0 }
    contracts: { outputs: { clusters: { kind: cluster_set, source: lexical } } }

  - identity: { name: cluster_semantic, version: 1.0.0 }
    contracts: { outputs: { clusters: { kind: cluster_set, source: semantic } } }

  - identity: { name: cluster_temporal, version: 1.0.0 }
    contracts: { outputs: { clusters: { kind: cluster_set, source: temporal } } }

  - identity: { name: merge_cluster_candidates, version: 1.0.0 }
    contracts:
      inputs:
        all_clusters:
          schema: { kind: cluster_set }
          multiplicity: collection             # NEW
          closing_condition: producers_terminal
```

`merge_cluster_candidates` accepts every matching artifact. The closing condition fires when every named candidate producer reaches a terminal state (`fired`, `dead-lettered`, or `skipped`). Other reasonable closing conditions:

- `count: 3` — fire on first three matches; ignore later (rare, streaming-shaped).
- `producers_terminal` — static-DAG-friendly; the recommended default.
- `bounded_window: ...` — rejected in v1; time-windowing conflicts with replay. May be revisited if a sound deterministic version emerges.

Collection ordering must be deterministic on replay. §9.7 develops the options; the eventual ADR picks one.

### Case 4 — Cascading dead-letter starvation

The hard case: a producer's output dead-letters (no consumer's contract claimed it), and a downstream consumer was expecting that output as a required input.

```yaml
ops:
  - identity: { name: classify_document, version: 1.0.0 }
    contracts:
      outputs:
        classified: { schema: ... }   # document_kind ∈ {invoice, receipt, statement, ...}

  - identity: { name: extract_invoice, version: 1.0.0 }
    contracts:
      inputs:
        document: { schema: { kind: classified, document_kind: invoice }, optionality: required }

  - identity: { name: build_audit_pack, version: 1.0.0 }
    contracts:
      inputs:
        invoices:
          schema: { kind: extracted_invoice }
          multiplicity: collection
          closing_condition: producers_terminal
          optionality: required        # cascade behavior on starvation

  - identity: { name: dead_letter_unclassified, version: 1.0.0 }
    contracts:
      inputs:
        document: { schema: { kind: classified } }   # catch-all (least-specific)
```

Scenario: a document with `document_kind: unknown`. None of the extractors match; dead-letter does (catch-all). The artifact lands there. What happens to `build_audit_pack`? Its `invoices` slot's producer candidates include `extract_invoice`. `extract_invoice` didn't fire for this document. If *all* upstream documents are `unknown`, `extract_invoice` reaches a terminal "not-fired-for-any- input" state. The collection slot's closing condition (`producers_terminal`) fires; the collection is empty.

Slot optionality decides:

- `required` → consumer cascades to dead-letter (or another defined terminal, per §6.7).
- `optional-with-default` → consumer fires with the pack-declared default (e.g. empty list).
- `optional-with-skip` → consumer cascades to skip transitively.

Cascade table:

| Upstream state              | Slot optionality        | Consumer fate         |
|-----------------------------|-------------------------|-----------------------|
| Producers fired, slot empty | required                | cascade dead-letter   |
| Producers fired, slot empty | optional-with-default   | fire with default     |
| Producers fired, slot empty | optional-with-skip      | cascade skip          |
| Producer dead-lettered      | required                | cascade dead-letter   |
| Producer dead-lettered      | optional-with-default   | fire with default     |
| Producer dead-lettered      | optional-with-skip      | cascade skip          |
| Producer skipped            | required                | cascade dead-letter   |
| Producer skipped            | optional-with-default   | fire with default     |
| Producer skipped            | optional-with-skip      | cascade skip          |

Every (state, optionality) cell has a defined outcome. PackLoader proves this at load time (§5.2). At runtime, the cascade is deterministic on event order.

The critical property: **starvation is impossible**. Every node terminates in `fired`, `dead-lettered`, or `skipped` — no `expected-to-fire-but-stuck`. This is the load-bearing invariant the design buys.

---

## §5 — Design forces

Four forces shape the design and bind it to a specific direction. Each is not just a constraint but an opinion about *what kind of* runtime Liminara is.

### §5.1 — Replay discipline as design force

Liminara's deterministic-replay invariant forbids wall-clock timeouts. Every other dataflow runtime's escape hatches for starvation — "wait T seconds, then give up", "retry with backoff", "race a fallback with timeout" — are structurally unavailable. Time is not a deterministic function of inputs; replay would diverge whenever a timed wait fired differently.

This is a feature, not a hardship. Time-based starvation handling is *fragile* — it makes runtime behavior depend on scheduler decisions, machine load, network jitter, and operator luck. Production incidents in time-driven dataflow runtimes are overwhelmingly "the timeout fired in the wrong place" or "the fallback raced with the primary and won when it shouldn't have."

Forbidding time-based escape hatches forces the design to a stronger shape: every starvation case must be resolved by the *structure* of the pipeline, not by a runtime decision under load. Coverage analysis becomes a design obligation, not a nice-to-have. The discipline lineage: event-sourced systems (Kafka Streams, Akka Persistence, Datomic) hit the same wall when they want deterministic event-stream processing — and answer the same way. Liminara inherits the discipline.

### §5.2 — Petri-net deadlock theory

`docs/research/14_alternative_computation_models.md` §"Petri Nets — More Expressive Than DAGs" observes that Liminara's scheduler already resembles a Petri net execution engine: "find ready nodes" is "find enabled transitions." With contract routing:

- **Tokens** are artifacts (immutable in Liminara; anonymous-and- consumable in classical Petri nets).
- **Places** are slot-states: each consumer's input slot accumulates tokens until ready to fire.
- **Transitions** are op invocations: fire when input slots fill per the closing condition.

Petri-net theory has spent four decades on "given this dataflow graph, can it deadlock?" — answered by reachability analysis: enumerate possible token states, prove every reachable state has a successor or is a defined terminal. Generalized reachability across the full Petri-net model is **decidable** (Mayr 1981; simplified Leroux & Schmitz 2019) but **Ackermann-complete** in worst-case complexity (Czerwiński et al. 2019, Leroux 2021) — non-elementary; no fixed tower of exponentials bounds it. The *structured subset* Liminara's plans live in is tractable: every plan is acyclic per `Liminara.Plan.validate/1`, every slot has a finite candidate producer set, every producer terminates in a finite number of artifact emissions. The reachable-state space is finite and walkable, and the proof reduces to polynomial cost in nodes × contract partitions (§6.9). The cliff between "structured polynomial" and "general Ackermann-hard" is what §5.5's grammar-decidability spectrum has to police: pick a grammar slice the proof can discharge cheaply.

PackLoader's load-time coverage proof is a Petri-net-style reachability analysis specialized to this structured subset:

1. **Build the candidate-routing graph.** For each producer output, enumerate consumers whose contracts could structurally match.
2. **Walk the cascade table.** For each consumer, verify every (state, optionality) cell (§4.4) has a defined outcome.
3. **No orphan values.** For each value-pattern partition of an output's contract, verify some consumer's input contract claims it (or the dead-letter does).
4. **Walk transitively.** If consumer A cascades to dead-letter on slot starvation, verify A's downstream consumers handle A's not-firing per their own optionality rules.

If all four pass, **starvation is impossible at runtime**. Every artifact has a defined consumer; every consumer has a defined fate for every upstream state. *Load-time proof replaces runtime fallback.*

The cost: contract-grammar value-pattern checking has to be load-decidable. A pattern like "the artifact's `score` is greater than the output of an LLM call" is not load-decidable — the LLM decision exists only at runtime. Such patterns must be expressed differently (e.g. record the LLM's classification as a separate artifact and route on its discrete value). The grammar restricts to load-decidable patterns by construction. §5.5 develops the decidability constraint.

### §5.3 — Sum-type pattern matching as inherited toolkit

ML-family languages have a 50-year tradition of this exact pattern with sum types (discriminated unions) and pattern-matched function clauses:

```ocaml
type document =
  | Invoice of invoice_record
  | Receipt of receipt_record
  | Statement of statement_record
  | Unknown of raw_payload

let extract = function
  | Invoice r   -> extract_invoice r
  | Receipt r   -> extract_receipt r
  | Statement r -> extract_statement r
  | Unknown p   -> dead_letter p
```

The `document` type is the union; the clauses are candidate consumers; pattern matching is the routing. ML-family compilers prove **exhaustiveness** statically — forget a constructor, the compiler complains. The Petri-net coverage proof is the same property in a different vocabulary.

The benefit isn't intellectual pedigree. It's that 50 years of language design has shaped the grammar to support exhaustiveness checking *efficiently*. Patterns decidable in ML pattern matching are decidable in Liminara's coverage analysis; patterns that aren't (predicates over unbounded data) aren't admitted in either tradition. Borrowing the shape borrows the analyzability.

### §5.4 — BPMN content-based routing as precedent

BPMN's content-based gateway is the standard pattern for "based on the document, send it to the right reviewer." Mature; widely implemented. Not *deterministic* by default — most BPMN engines admit time-based fallbacks ("no match within T seconds → default") and store-and-forward semantics that depend on engine state. Liminara's variant adds two restrictions:

1. **No time-based fallbacks.** Routing is a pure function of bytes.
2. **Load-time coverage proof.** The pack proves every input reaches a defined consumer; dead-letter is a *defined* consumer with explicit contract, not an "unhandled goes here" sink.

With those, Liminara gets BPMN's expressiveness plus deterministic replay plus structural deadlock-freedom — properties BPMN doesn't have natively.

### §5.5 — Why decidability constraints matter

Contract grammar choices live on a decidability spectrum:

- **Most decidable** — tagged discriminated unions (`kind: invoice | receipt | statement`). Equality on finite enum. Trivially decidable, trivially exhaustivable.
- **Decidable** — refinement types over base types (`score: int &
  >=0`). First-order; standard reasoning.
- **Decidable with care** — JSON-Schema-like predicates (`pattern: "^foo"`, `enum: [...]`). Decidable per-shape but may not be *exhaustivable* (proving every possible string is claimed requires pattern-complementation reasoning).
- **Undecidable in general** — arbitrary Turing-complete predicates. Rejected by construction.

D-039 leaves the grammar open (item 1: refinement / JSON-Schema / tagged discriminator / CUE) — these span the first three categories. The eventual ADR picks a slice the coverage proof can discharge. Tagged discriminators are the safest starting point; refinements over base types extend it; arbitrary JSON-Schema is the limit before undecidability bites. §6.1 develops the trade-offs.

---

## §6 — Bill of materials (12 items, elaborated)

D-039's 10-item BoM plus the gap entry's two additional items (failure-mode taxonomy split, cross-pack routing) — twelve items the M-CONTRACT-04 ADR has to design. Each item is presented as a standalone design question with the trade-offs the eventual ADR's Q&A will work through.

### §6.1 — Contract grammar extension

OPSPEC-01's `#Contracts` block today is `{[string]: _}` — input/output names map to *any* descriptor. Sufficient for v1.0.0 (shape is per-pack and not policed by schema), insufficient for value-pattern matching. Grammar options:

- **Tagged discriminators.** A finite enum on a known field (`kind: invoice | receipt | statement`). Matcher is equality on the discriminator. Coverage proof is enumeration. Familiar to anyone who's used Rust enums or Haskell ADTs.
- **Refinement types.** Constraints over base types (`score: int &
  >=0`). Matcher is a small predicate evaluator. Coverage proof
  decidable for linear-arithmetic refinements; trickier for string-pattern refinements.
- **JSON-Schema-like predicates.** Schemas with `enum`, `pattern`, `properties`. Matcher is a JSON-Schema validator. Coverage proof harder — pattern-complementation reasoning may not always be decidable.
- **CUE-style constraints embedded in contract definitions.** The language Liminara already uses for the contract surface itself. Lattice-based; decidable; supports refinement and discrimination uniformly. Most powerful, most expensive (CUE evaluation has its own performance and tooling profile).
- **Hybrid: discriminator + refinement per branch.** Primary discriminator picks the variant; per-variant refinements narrow within. The FP-language convention (Rust enums with field types, Haskell ADTs).

The eventual ADR weighs "strong-but-decidable" (discriminators + refinements) vs. "expressive-but-may-bite-back" (full JSON-Schema or CUE). No pre-commit here.

### §6.2 — Runtime contract matcher

A pure function `match(artifact_bytes, contract) -> bool`. Smaller than CEL/JSONPath; bigger than equality-on-discriminators (unless §6.1 picks discriminators-only). Determinism on replay is trivial — pure function of bytes. The matcher's *implementation* must be pinned across runtime versions (a corner-case-changing bump would diverge replay), so it's part of the wire contract ADR-EVOLUTION-01 (M-CONTRACT-04) governs.

Open question: matcher in Elixir (one per runtime version) or as a declarative grammar that compiles to per-language matchers (one per pack-implementation language)? The first is simpler; the second supports cross-language pack ecosystems (Python, TypeScript hosts).

### §6.3 — Candidate-consumers plan shape

How does the plan say "any matching consumer"?

- **Implicit derivation.** Plan declares producers and consumers; PackLoader builds the candidate-routing graph from contracts. No new plan field; routing graph is implicit. Fewer plan fields, but invisible to plan readers.
- **Explicit `routes_to` block per producer.** Plan declares candidates per output. Visible and reviewable, but redundant with contract-derived routing and mismatch-prone if not regenerated when contracts change.
- **Hybrid.** PackLoader derives; plan author optionally pins a subset for documentation or constraint-tightening. Flexible, more surface area.

Today's `#RefBinding` covers the static case unambiguously. The extension admits one of the three additively. ADR weighs visibility vs. avoid-redundant-fields.

### §6.4 — Dead-letter as catch-all consumer

A *real* consumer with an op, a contract claiming what's left, and an output (the dead-letter artifact, for audit). Pack authors register one explicitly or PackLoader provides a default.

Routing rule: prefer specific over catch-all. Dead-letter's value- pattern is the union complement of all other consumers'; the runtime matches specific first and falls through to dead-letter only if nothing claims. This requires a partial-order on contracts (specificity) — trivial for tagged discriminators (anything with a discriminator beats the wildcard), harder for refinement types (specificity becomes "implication"). §6.1's grammar choice determines how hard this is.

A pack can register multiple dead-letter consumers (different ops for different unhandled shapes), one, or none (default kicks in). Default behavior: log to event store, emit `dead_letter` artifact carrying the original payload, halt downstream cascade per slot optionality.

### §6.5 — Slot multiplicity (singular vs. collection)

Each input slot declares:

- **Singular.** One matching artifact fills the slot. Two matches → ambiguity (§9.5); zero matches → slot-optionality cascade (§6.6). The function-call model.
- **Collection.** All matching artifacts fill the slot. Runtime accumulates and fires the consumer when the closing condition triggers (§4.3). The stream-join model.

The eventual ADR may support only singular in v1 and add collection later — singular is the more-static-DAG-friendly choice (v1.0.0 invariant generalized to value-routing). Collection is needed for "merge candidates" patterns (§4.3); rare enough in v1.x to potentially defer.

### §6.6 — Slot optionality

Each input slot declares:

- **`required`.** Empty slot → consumer cascades to dead-letter.
- **`optional-with-default`.** Empty slot → consumer fires with a pack-author-declared default. Default is part of the op contract, not a runtime fallback decision.
- **`optional-with-skip`.** Empty slot → consumer cascades to skip (transitively).

Default is `required`, matching the function-call mental model.

The ADR could also admit a per-slot **fallback consumer** ("if my upstream produces nothing, run this op instead") — likely sugar over the above (define an alternate consumer with a different contract; route to it when the original starves). Defer to ADR-author judgment.

### §6.7 — Cascade rules

§4.4's cascade table is the spec. The eventual ADR commits to:

- The full table (every (upstream-state, slot-optionality) cell has a defined outcome).
- Event-emission semantics: cascade-skip emits `node_skipped`; cascade-dead-letter emits `node_dead_lettered`; fire-with-default emits normal `node_completed` with the default as output.
- Transitive-cascade order: a node's state finalizes only after all its *required* upstream slots reach terminal states.

The cascade must be deterministic. Discipline: process events in event-log order; on upstream terminal events, re-evaluate dependent consumers; tie-break by node-id when multiple consumers become eligible simultaneously.

### §6.8 — Reachability tracking at runtime

Per-node state machine:

- `expected-to-fire` — not yet evaluated (or not added to the realized DAG, in dynamic-pipelining language).
- `fired` — ran, emitted outputs, terminated normally.
- `dead-lettered` — could not run; output (if any) is the dead-letter artifact.
- `skipped` — could not run; output is empty.

Transitions are driven by upstream events; state lives in the event log plus the Run.Server's scheduler. Replay walks the log and reaches the same final states.

### §6.9 — Load-time coverage proof

The load-bearing payoff. PackLoader runs the §5.2 reachability analysis at pack-load time; three sub-obligations:

1. **No orphan outputs.** Every routable artifact shape is claimed by some consumer's input contract (or the dead-letter). Fail pack-load otherwise.
2. **No unfulfillable required slots.** For every consumer with a required slot, prove the slot can be filled given the producer-candidate set's terminal states. The cascade-table walk.
3. **No transitive-skip orphans.** If A's only producer skips and A's slot is `optional-with-skip` (so A skips), and A is B's only producer with B's slot `required` — B can never fire. Catch the transitive case.

If all three discharge, **starvation is impossible at runtime**. The runtime inherits the property without further work.

Cost is in the loader. The eventual ADR specs the algorithm and complexity bound. For the structured subset (acyclic, finite producer-sets, decidable contract grammar), the algorithm is polynomial in nodes × contract-shape partitions.

### §6.10 — Decision-record interaction

A routing decision is **not** a `Decision` in Liminara's nondeterministic-choice sense — it's a pure function of artifact bytes. But routing can *depend on* a recorded `Decision` (an LLM classifier outputs a label; downstream routes on the label). Routing is deterministic *given the recorded decision*; replay injects the decision and routing falls out.

ADR design choices:

- **Dispatch produces an audit event.** `artifact_routed` records (producer-node, output-key, artifact-hash, matched-consumer). Not required for replay (re-derivable), but required for operator-debug "where did this artifact go?"
- **Audit event lands in the run's event log** alongside `node_started`, `node_completed`, `decision_recorded`.
- **Audit payload is the matched-consumer node-id**, not the matcher result (which contract claimed it) — the latter is recoverable from artifact + contract definition. Smaller events, same content.

### §6.11 — Failure-mode taxonomy split

Two distinct failures, often conflated:

- **Structural mismatch.** An output's *shape* doesn't match any consumer's input shape — a real contract violation. PackLoader catches at load time (a type error). At runtime, structural mismatch is a runtime-invariant violation (terminate run with hard error). Not user-facing.
- **Value-no-match.** Output's shape is right, but its *value* doesn't match any consumer's value-pattern. A `classified` artifact carrying `document_kind: unknown` — structurally fine, no consumer claims `unknown`. Routine routing decision; lands at dead-letter; operator inspects (could be pack-design bug or real-world surprise).

The eventual ADR's UI / event taxonomy distinguishes the two. Conflating them produces operator confusion ("bug or expected?").

### §6.12 — Cross-pack op references and routing

PLAN-01 v1.0.0 is single-pack-only — node `op:` resolves against the *same pack's* manifest. Cross-pack routing is a future question:

- **Inter-pack pipelines.** Pack A's output routes to Pack B's consumer. Useful when packs compose (Radar's clusters into a downstream report-builder pack).
- **Pack-marketplace shapes.** Third-party packs subscribe to a shape; PackLoader builds the cross-pack candidate graph.
- **Versioning across packs.** Pack A v1.2 emits a contract Pack B v0.9 doesn't claim; Pack B v1.0 claims it. Cross-pack version-skew matrix that single-pack doesn't have.

Substantial design space; **explicitly deferred** to its own future pass. M-CONTRACT-04 may scope single-pack contract routing and leave cross-pack for later. The gap entry tracks for visibility.

---

## §7 — Sequencing recommendation

### §7.1 — What M-CONTRACT-02 must NOT preclude (and is already on track)

This section verifies that PLAN-01 v1.0.0 and OPSPEC-01 v1.0.0 keep the necessary doors open additively. As of 2026-05-02 the schemas are already shaped this way.

- **`#InputBinding: #LiteralBinding | #RefBinding`** is an open disjunction. Adding a third shape (`#ContractRoutedBinding`) at v1.x is syntactically additive — existing fixtures stay valid.
- **`#Plan` and `#Node`** are `close({...})` records but admit *new optional top-level fields* additively (e.g. `routes?: #RoutingTable`); existing fixtures stay valid.
- **`#Contracts.inputs / outputs: {[string]: _}`** is a loose map. Tightening to admit a richer grammar at v1.x is additive — the current `_` already admits anything, and the eventual ADR *narrows* by adding validation, not by removing schema flexibility.
- **Manifest `schema_version` discipline** (integer-major, required, top-level) inherits unchanged to plan and op-spec topics.
- **Replay-protocol and wire-protocol schemas** are not on this proposal's path. Routing audit events (§6.10) land in the event log, governed by separate (M-CONTRACT-03+) ADRs.

**M-CONTRACT-02 has no homework from this RFC.** The schemas are shaped to admit the M-CONTRACT-04 extension additively. The remaining sequencing question is what M-CONTRACT-04 commits to.

### §7.2 — What M-CONTRACT-04 must design

The eventual ADR (provisionally `ADR-DYNAMIC-PIPELINE-01`, or a scope-extension of `ADR-MULTIPLAN-01`; M-CONTRACT-04 picks one when it scopes) inherits the BoM in §6 verbatim. The ADR's Q&A walks through:

- Grammar choice (§6.1) — pick a slice on the decidability spectrum.
- Plan-shape choice (§6.3) — implicit / explicit / hybrid.
- Default cascade rules (§6.7) and their event semantics.
- The proof algorithm (§6.9) and its complexity bound.
- Failure-mode taxonomy split (§6.11) and its UI surface.

§8 below restates these as decision points the ADR's Q&A round will adjudicate.

### §7.3 — What later milestones inherit

- **M-RUNTIME-01..M-RUNTIME-04 (E-25 PackLoader):** the reachability-analysis implementation lives here. PackLoader's load-time coverage proof is a load-bearing piece of the proposal; the proof algorithm spec'd in `ADR-DYNAMIC-PIPELINE-01` is implemented in the loader. Add to one of M-RUNTIME-XX's scope when M-CONTRACT-04 lands; the natural pairing is M-RUNTIME-02 (loaded pack validation) or its successor.

- **E-22 admin-pack:** the binding pressure-test consumer. If E-22 lands before M-CONTRACT-04, admin-pack must defer conditional usage (rewrite §9's plan as static-DAG-only with `Pack.plan/1` emitting different plans for different inputs) or push the v1.x evolution path itself (drive the M-CONTRACT-04 design as part of E-22's milestone scope). The current sequencing has E-22 after M-CONTRACT-04, which avoids the conflict.

- **Future packs (Software Factory with conditional execution branches, House Compiler with conditional structural-check branches, Process Mining with adaptive cleanup paths, Population Simulation with branching scenarios):** unblocked once M-CONTRACT-04 + M-RUNTIME-XX coverage-proof land. None of these packs exist today; the proposal's value is in not closing their design space prematurely.

### §7.4 — Sequencing summary

| Stage                              | When                | What                                                                     |
|------------------------------------|---------------------|--------------------------------------------------------------------------|
| RFC filed                          | 2026-05-02          | This document                                                            |
| Decision-direction record (D-039)  | 2026-05-02          | `work/decisions.md` D-2026-05-02-039                                     |
| Gap entry                          | 2026-05-02          | `work/gaps.md` *Dynamic pipelining shape — content-routed dispatch*    |
| M-CONTRACT-02 schema-room verify   | This milestone      | §7.1 audit confirms additive expansion path — no schema changes needed |
| Hold                               | Through M-CONTRACT-03 | No further work on this axis                                          |
| `ADR-DYNAMIC-PIPELINE-01` design   | M-CONTRACT-04       | Q&A walks the §6 BoM; ADR ratifies grammar + cascade + proof algorithm |
| PackLoader coverage-proof impl     | M-RUNTIME-XX (E-25) | Load-time reachability analysis implementation                          |
| Admin-pack §9 conditional usage    | E-22 (post-M-CONTRACT-04) | Admin-pack uses contract-routing shape; §9 recasted              |
| Future-pack adoption               | Per-pack            | Software Factory / House Compiler / Process Mining / Pop Sim use it   |
| Cross-pack routing                 | Future ADR          | Deferred to its own pass (§6.12)                                       |

---

## §8 — Decision points for M-CONTRACT-04 (numbered)

Each is a self-contained Q&A surface for the eventual ADR. The proposal narrows but does not commit. Items are restated terse.

1. **Contract grammar extension shape.** Refinement types? JSON-Schema-like predicates? Tagged discriminators? CUE-style constraints? Hybrid? §6.1 walks the decidability trade-offs.
2. **Runtime matcher language.** Pure function on bytes; what's its surface? Implemented in Elixir or as a declarative grammar that compiles per-language? §6.2.
3. **Candidate-consumers plan shape.** Implicit derivation, explicit `routes_to` block, or hybrid? §6.3.
4. **Dead-letter registration model.** Pack-author-registered, runtime-provided default, or hybrid (default if not registered)? §6.4. Specificity ordering is a sub-question.
5. **Slot multiplicity declaration.** Per-slot field on input contract (`multiplicity: singular | collection`); v1 supports one or both; closing-condition shape for collections. §4.3, §6.5.
6. **Slot optionality declaration.** Per-slot field (`optionality: required | optional-with-default | optional-with-skip`); default is `required`. §6.6.
7. **Cascade rules table.** Every (upstream-state, slot-optionality) cell has a defined outcome. §4.4 sketches the table; the ADR commits to it. §6.7.
8. **Per-node state-machine ordering.** State transitions are driven by upstream events; tie-break rule for simultaneous-eligible consumers; cascade-event emission semantics. §6.7, §6.8.
9. **Reachability-analysis algorithm.** PackLoader's load-time proof walks the candidate-routing graph plus the cascade table. Complexity bound; algorithm spec; what gets rejected. §6.9.
10. **Decision-record-vs-routing interaction.** Routing decisions are not `Decision`s in the nondeterministic sense, but routing can depend on recorded `Decision`s. Audit-event design (`artifact_routed`?). §6.10.
11. **Failure-mode taxonomy split.** Structural-mismatch (type error, runtime-invariant-violation) vs. value-no-match (routine dead-letter). Distinct event types, distinct operator surfaces. §6.11.
12. **Cross-pack routing.** Single-pack v1; cross-pack deferred to its own future pass. §6.12.

---

## §9 — Open questions / risks

The proposal does not resolve these; each is flagged for the eventual ADR.

### §9.1 — Coverage analysis cost vs. plan size

Petri-net reachability is decidable across the full model but **Ackermann-complete** in worst-case complexity (Czerwiński et al. 2019, Leroux 2021) — non-elementary, far worse than PSPACE. Liminara's structured subset (acyclic, finite producer-sets, decidable grammar) is tractable, but "tractable" ≠ "fast." Complexity is at least O(N × K) for N nodes × K contract partitions; higher depending on grammar (§6.1). The eventual ADR should bound worst-case and report typical-case timings on representative packs. Mitigation: PackLoader caches the proof per-pack-version; reload only when manifest or plan changes. The grammar-decidability spectrum (§5.5) is the load-bearing discipline that keeps the proof in the polynomial subset rather than letting it slide toward the general Ackermann-complete case.

### §9.2 — Non-decidable value patterns

The grammar (§6.1) excludes Turing-complete predicates by construction. The boundary is fuzzy: does a regex with backreferences count? (Decidable but expensive.) Refinement over arbitrary integers? (Decidable for linear arithmetic, undecidable for some nonlinear.) Recommendation: start with **tagged discriminators + base-type refinements** (linear arithmetic, string equality, enum membership); exclude unbounded-precision arithmetic, backreference regex, and user-supplied predicate functions. Conservative slice; expand later if a real pack needs more.

### §9.3 — Interaction with the pipeline-scoped run-context proposal

Sibling RFC `pipeline-scoped-run-context.md` proposes a `run_context` plan-level primitive hosting a stateful workspace across a pipeline's ops. Likely answer: contract-routing and run-context are **orthogonal**. Run-context governs *where* ops execute; contract routing governs *which* op gets a given artifact. An op's executor (`in_context`, `inline`, `port`, ...) is decoupled from its routing role. The matcher's "pure function on artifact bytes" invariant holds because it operates on declared artifacts, not workspace state. In-context ops participating in routing declare their content- addressed artifact contracts; workspace-mutation side-effects don't participate in the routing layer. Each future ADR should cross-reference the other to verify.

### §9.4 — Orphan outputs without explicit dead-letter

If a pack ships a contract with an uncovered value-partition AND no registered dead-letter:

- **Reject at load.** Most conservative; forces the author to confront.
- **Auto-route to default dead-letter** with a warning. Most permissive.
- **Configurable strictness** via manifest (`coverage_mode: strict | warn | permissive`; default `strict`).

Lean: `strict` by default. Liminara's discipline is "reject wrong work at the earliest checkpoint." Weak lean; both alternatives are defensible.

### §9.5 — Disambiguation when multiple consumers match a singular slot

Two candidates' contracts both claim the artifact:

- **Reject at load** with "specialize or register a tie-break."
- **First-wins by defined order** (manifest-declaration or node-id lexicographic). Risks silent surprise on pack-edit.
- **Reject at runtime** (structural-mismatch hard error per §6.11).

Lean: **reject at load** — static-DAG discipline says ambiguity is a pack design error caught early. Specificity ordering (§6.4) may subsume this for grammars admitting partial-order on contracts.

### §9.6 — Performance at runtime

Naive matching is O(N × K) for N candidates × K bytes. Most pipelines have small N (< 10 per output) and small K (metadata, not payload); unlikely to be a problem. For pack-marketplace shapes with hundreds of candidates per output, mitigation is discriminator-keyed indexing (O(1) dispatch on the discriminator); fall back to per-candidate scan for non-discriminator grammars. The grammar choice determines the indexing strategy.

### §9.7 — Replay determinism for collection ordering

Collection slots accumulate matches; replay must reproduce the order. Options:

- **Content-hash order.** Pure function of bytes; trivially replayable.
- **Producer-node-id order.** Deterministic given the plan; matches operator intuition; doesn't handle multi-emit per producer cleanly.
- **Event-log arrival order.** Deterministic on replay (replay walks the same log); fragile under live re-execution.

Lean: **producer-node-id order, then event-log order within a producer**. Operator-intuitive; pure function of plan + event log.

### §9.8 — Schema-evolution interactions

PLAN-01's `schema_version` is per-cohort. ADR-EVOLUTION-01 (M-CONTRACT-04, same milestone) governs whether dynamic-pipelining additions are an *additive* v1.x bump (supported alongside v1.0.0) or a *successor* v2.0.0 bump (replaces v1.x). Lean: *additive* — preserves v1.0.0 plans, avoids re-validating Radar's existing `pack.yaml` shim.

---

## §10 — References

**Repository**

- Decision-direction record: `work/decisions.md` D-2026-05-02-039
- Gap entry: `work/gaps.md` *Dynamic pipelining shape — content-routed dispatch via contract matching*
- ADR-PLAN-01 (static-DAG-only ratification): `docs/decisions/0008-pack-plan.md`
- ADR-OPSPEC-01 (contract-grammar source): `docs/decisions/0004-op-execution-spec.md`
- ADR-MANIFEST-01 (`schema_version` evolution discipline): `docs/decisions/0007-pack-manifest.md`
- ADR-REPLAY-01: `docs/decisions/0006-replay-protocol.md`
- ADR-WIRE-01: `docs/decisions/0005-port-wire-protocol.md`
- Plan schema: `docs/schemas/plan/schema.cue`
- Op-execution-spec schema: `docs/schemas/op-execution-spec/schema.cue`
- Architecture overview: `docs/architecture/01_CORE.md` (esp. `:464-471` executor taxonomy, `:478-494` determinism classes)
- Sibling proposal: `docs/architecture/proposals/pipeline-scoped-run-context.md`
- Companion in spirit: `docs/architecture/proposals/lifecycle-fsm-engine.md`

**Admin-pack**

- `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md` §9 *The Plan — DAG construction* — `enabled: input.use_llm` on the `llm_escalation` node; per-period vs. per-item discussion motivating collection multiplicity (§6.5).

**Research notes**

- `docs/research/14_alternative_computation_models.md` *Petri Nets — More Expressive Than DAGs* §139–153 — supports §5.2.
- `docs/research/14_alternative_computation_models.md` *Blackboard Systems* — content-driven consumer selection precedent (though discovery-mode, not contract-routing).
- `docs/research/15_dataflow_systems_and_liminara.md` — comparable- runtime landscape (Beam, Dask, Prefect, Airflow).
- `docs/research/17_flyte_architecture.md` §250–259 *What Liminara Should Steal From Flyte* — Flyte 2.0's dynamic workflows compared.

**External (background — common-knowledge claims; verify citations before publication)**

- BPMN 2.0 *exclusive data-based gateway* — canonical content-routing primitive; Liminara extends with deterministic replay + load-time coverage proof.
- Petri-net reachability analysis — decidable across the full model (Mayr 1981; simplified Leroux & Schmitz 2019, *J. ACM* 66(6)); Ackermann-complete in worst-case complexity (Czerwiński, Lasota, Lazić, Leroux, Mazowiecki 2019; Leroux 2021). Tractable for structured subsets — Murata 1989 (*Petri Nets: Properties, Analysis and Applications*) is the standard survey but predates the modern complexity bounds.
- Sum-type pattern matching exhaustiveness — ML / Haskell / OCaml / Rust 50-year tradition; same property as the Petri-net coverage proof in a different vocabulary.

---

## §11 — Recommendation

1. **In M-CONTRACT-02 (now):** §7.1's verification has confirmed the schemas already keep the additive-expansion path open. **No schema changes required.** Land this RFC; the decision-direction record (D-039) and the gap entry already exist.

2. **Through M-CONTRACT-03:** hold. No work on this axis. The replay-protocol and wire-protocol bundles are independent.

3. **At M-CONTRACT-04:** scope `ADR-DYNAMIC-PIPELINE-01` (or a scope-extension of `ADR-MULTIPLAN-01` — milestone scoping picks one) using §6's BoM as the inheriting brief. Q&A walks §8's 12 decision points; ADR ratifies the grammar slice + cascade table + proof algorithm.

4. **At M-RUNTIME-XX (E-25 PackLoader):** implement the load-time coverage proof per the M-CONTRACT-04 ADR's spec. Coverage proof is load-bearing — without it the design's "starvation is impossible at runtime" property doesn't hold.

5. **At E-22 admin-pack:** consume the contract-routing shape; recast §9's plan to use it. Until M-CONTRACT-04 lands, admin-pack either defers conditional usage or pushes the v1.x evolution path itself.

The cost of M-CONTRACT-02 schema-room is zero (the schemas already admit additive expansion). The cost of M-CONTRACT-04 deferral is a real but bounded design debt — the BoM in §6 makes the debt explicit and the gap entry tracks it for visibility. The proposal's value is in making the deferral *informed*: M-CONTRACT-04 inherits a 12-item checklist, four worked examples, four design forces, and a clear north star, rather than re-discovering the design space from scratch.
