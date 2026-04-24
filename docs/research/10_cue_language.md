# CUE Language — Constraint Unification for Configuration and Validation

**Date:** 2026-03-22
**Context:** Surfaced via HN discussion on the dag-map repo. Investigated for relevance to Liminara's core runtime, pack system, and LodeTime.
**Source:** https://cuelang.org/

---

## What CUE is

CUE (Configure, Unify, Execute) is an open-source data validation language and inference engine created by Marcel van Lohuizen, who spent 15 years working on Google's internal configuration language (GCL). CUE was designed to fix the problems GCL caused at scale.

The theoretical foundation is **graph unification of typed feature structures**, borrowed from computational linguistics. Two properties make it fundamentally different from every other configuration language:

**1. Types are values.** In most languages, types (`int`, `string`) and values (`42`, `"hello"`) live in separate universes. In CUE they are the same kind of thing, placed in a single hierarchy. `int` is a value just as much as `42` is — it just represents a larger (less specific) set. There is no separate schema language, no separate type system, no separate validation layer. They are all the same mechanism.

**2. All values are ordered in a lattice.** Every CUE value — from the most abstract type down to the most concrete data point — is placed in a single partially ordered set (a lattice). A lattice guarantees that for any two elements, there exists a unique greatest lower bound (meet) and least upper bound (join). Merging any two CUE values is always unambiguous and order-independent.

### Key operations

- **Meet (`&`)** — greatest lower bound. Combining constraints. `int & >0 & <100` yields "positive integers under 100."
- **Join (`|`)** — least upper bound. Alternatives. `"dev" | "staging" | "prod"` is an enum. `*8080 | int` is a default.
- **Bottom (`_|_`)** — contradiction. `true & false` yields bottom. The constraints are incompatible. This is how CUE reports errors — structurally, at the exact path where constraints conflict.

### The properties that fall out of the lattice

- **Order independence.** Combining CUE values in any sequence produces the same result. No file ordering, no override precedence, no "last writer wins." Mathematical guarantee, not convention.
- **Commutativity, associativity, idempotency.** These follow from lattice algebra.
- **Subsumption = backwards compatibility.** Struct A subsumes struct B if B satisfies all of A's constraints. This is exactly API compatibility checking.

### How it differs from alternatives

| Language | Model | CUE's advantage |
|----------|-------|-----------------|
| JSON / YAML | Pure data, no validation | CUE subsumes JSON and adds constraints, types, defaults |
| JSON Schema / OpenAPI | Schema-only, no cross-field constraints | CUE validates cross-field relations (`port > min_port`) |
| HCL (Terraform) | Human-friendly but tool-dependent validation | CUE validates independently of any tool |
| Jsonnet / GCL | Inheritance-based (pull), order-dependent | CUE is constraint-based (push), order-independent |
| Dhall | Typed functional, but types ≠ values | CUE unifies types and values in one hierarchy |

CUE deliberately restricts Turing-completeness. No general recursion, no unbounded iteration. Configuration should be declarative and machine-analyzable. Heavy computation belongs elsewhere. This is a lesson learned from GCL at Google, where blending computation and configuration at scale made systems opaque.

---

## Lattices vs DAGs — the relationship

Both are drawn as directed acyclic graphs, which causes confusion. They are different things.

**A DAG** is a shape: nodes, directed edges, no cycles. Pure structure. Says nothing about what the nodes mean. Liminara's execution plans are DAGs — "do this, then that, fan out here, converge there." dag-map visualizes these as metro maps.

**A lattice** is an algebraic structure that can be drawn as a DAG (its Hasse diagram), but has additional guarantees: every pair of elements must have exactly one meet (greatest lower bound) and exactly one join (least upper bound). A general DAG doesn't guarantee this.

```
Lattice:                    DAG (not a lattice):

      ⊤                        A   B
     / \                       / \ / \
    A   B                     C   D   E
     \ /
      ⊥
```

In the lattice, A & B = ⊥ and A | B = ⊤ — unambiguous. In the DAG, C and E have no unique meet; the algebraic operations are undefined.

**Every lattice can be drawn as a DAG. Most DAGs are not lattices.**

The key distinction for Liminara:

- **Liminara's DAG is a recipe.** Steps with dependencies. It says what to *do* and in what *order*.
- **CUE's lattice is a funnel.** You start wide (top = "any value") and pour in constraints. Each narrows the funnel. You end with a concrete value, or the constraints contradict (bottom = error). It says what's *valid*, not what to *do*.

One models execution. The other models progressive refinement of valid states. Both acyclic, both directed, fundamentally different purposes.

---

## Where CUE could add value to Liminara

### 1. Pack manifests — static composition checking

A Pack declares ops, artifact types, and decision schemas via Elixir callbacks. A CUE manifest could sit alongside:

```cue
pack: "radar"
version: "0.2.0"

ops: {
    fetch_sources: {
        in:  ["source_list"]
        out: ["raw_content"]
        determinism: "side_effecting"
    }
    summarize: {
        in:  ["raw_content"]
        out: ["summary"]
        determinism: "recordable"
    }
}
```

When composing packs, CUE unification can verify at plan time — before any Elixir runs — that Pack A's output types satisfy Pack B's input constraints. Incompatibilities surface as `_|_` at specific paths with clear error messages.

**Value:** static, language-independent pack compatibility checking. Particularly useful as the pack ecosystem grows beyond single-author packs.

### 2. Run configuration with layered constraints

A run is configured from multiple sources: pack defaults → user profile → per-run overrides → environment. Today this needs an explicit merge-precedence model. With CUE, these are files that unify. No precedence — constraints compose. Conflicts are structural errors, not silent overrides.

```cue
// pack-defaults.cue
timeout: int | *30
retries: >=0 & <=5 | *3

// security-policy.cue (organization-wide)
timeout: <=60            // no runaway ops
retries: <=3             // bounded retry cost

// run-override.cue (user request)
timeout: 45
retries: 2
```

Unification yields `{timeout: 45, retries: 2}`. If the user had requested `timeout: 120`, the meet with `<=60` yields `_|_` — "security policy limits timeout to 60, got 120."

**Value:** multi-source configuration that composes safely without "which file wins?" ambiguity. Particularly relevant for multi-tenant or multi-team deployments.

### 3. Decision space constraints

For recordable ops, the space of valid decisions could be a CUE value:

```cue
#ClassifyDecision: {
    category:   "positive" | "negative" | "neutral"
    confidence: >=0.0 & <=1.0
    if confidence < 0.7 {
        rationale: string  // required when uncertain
    }
}
```

A recorded decision is a concrete CUE value. Replay validation = checking that stored decisions still satisfy updated constraints (lattice subsumption). If a policy change narrows the valid decision space, CUE can identify which historical decisions would no longer be valid — useful for audit and compliance.

**Value:** machine-checkable decision schemas that compose with policy constraints. Directly relevant to EU AI Act Article 12 requirements for documenting decision-making.

### 4. dag-map — validated DAG definitions

dag-map currently takes JSON-shaped DAG definitions. CUE could define the schema:

```cue
#Node: {
    id:    string
    label: string
    cls:   "pure" | "pinned_env" | "recordable" | "side_effecting" | "gate"
}

#DAG: {
    nodes: [...#Node]
    edges: [...[string, string]]
}
```

Contributors get validation for free — typos in node classes or dangling edge references caught at definition time, not render time. Low-stakes application, good way to learn CUE on a small surface.

### 5. Cross-pack compatibility

When multiple packs compose in a single run, CUE could verify:

- Artifact schema compatibility (output of op A subsumes expected input of op B)
- Configuration compatibility (both packs' config schemas have compatible defaults)
- Policy compatibility (security/resource constraints from both packs have a non-bottom meet)

All without running any code. Pure static analysis on the lattice.

---

## Where CUE fits LodeTime specifically

This is where the deepest resonance is. LodeTime's IR2 pass (Findings) checks architecture rules against codebase state. CUE is almost purpose-built for this.

### Architecture rules as a constraint lattice

```cue
// architecture-rules.cue
boundaries: {
    core: {
        may_import: ["core"]
    }
    web: {
        may_import: ["core", "web", "observation"]
    }
    observation: {
        may_import: ["core", "observation"]
    }
}
```

The IR0 snapshot (actual codebase state) is a CUE value. The architecture rules are constraints. Unifying them = checking compliance. Every violation is `_|_` at a specific path — which rule, which file, why.

### Multi-stakeholder policy composition

Different teams define constraints independently:

- **Security team:** no privileged ports, TLS required, no secrets in config
- **Platform team:** container memory limits, approved base images
- **Compliance team:** logging required for all external calls, PII fields annotated

Each is a CUE file. Unifying them yields the combined policy. If two teams' constraints contradict, `_|_` identifies the conflict before any code is checked — not after a deployment fails.

### Recursive provenance over constraints

LodeTime's premise: "the tool that tracks provenance should have provenance over itself." CUE adds another layer: **constraints are themselves values** — content-addressable, diffable, composable. When a rule changes, the change is a lattice operation (the constraint moved up or down in specificity). You can ask "what became more permissive in this policy update?" and get a structural answer, not a textual diff.

### IR2 implementation path

The IR2 pass could work as:

1. **IR0 → CUE value:** Export workspace snapshot as CUE (module boundaries, dependency lists, config files)
2. **Rules as CUE constraints:** Architecture rules, naming conventions, boundary policies
3. **Unify:** `cue eval snapshot.cue rules.cue` — violations are `_|_` at specific paths
4. **Findings artifact:** Structured violations with rule ID, file path, and constraint that failed

This gives LodeTime's architecture checking a formal foundation — violations are not pattern-match heuristics but lattice-theoretic proofs of constraint incompatibility.

---

## Where CUE should NOT be applied

### Not for execution semantics

CUE is deliberately not Turing-complete. It cannot express "run op A, then op B." Liminara's scheduler, DAG execution, event sourcing — none of this is CUE's domain. CUE validates and constrains; Elixir/OTP executes.

### Not as a replacement for Elixir's type system

CUE operates on data (JSON-like values). Elixir ops are functions with behavior. CUE can validate the *contracts* between ops (input/output schemas) but not the ops themselves.

### Not yet — complexity budget

CUE adds a dependency and a concept every contributor must understand. The places where it earns its weight are where **multiple sources of constraints must compose safely** — pack composition, multi-stakeholder policy, layered configuration. If Liminara stays single-pack for a while, the practical value is limited.

The honest assessment: CUE is most valuable when the problem is "N parties define constraints independently, and I need to know if they're all simultaneously satisfiable." Liminara doesn't have that problem yet. LodeTime will.

---

## Relationship to adjacent technologies

CUE connects to several systems already tracked in [ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md):

| Existing concept | CUE connection |
|------------------|----------------|
| **Nix** — total input-addressing for reproducible builds | CUE validates the *configuration* that feeds into builds. Nix ensures same inputs → same output. CUE ensures the inputs are valid before Nix sees them. Complementary, not competing. |
| **Category theory** — ops as morphisms, types as objects | CUE's lattice is a specific algebraic structure (bounded lattice with meet and join). The type lattice is the semantic counterpart to the DAG's structural composition. |
| **Petri nets / process mining** — formal execution models | CUE doesn't model execution. But CUE constraints could define valid Petri net configurations (legal markings, transition guards). Validation of the model, not the execution. |
| **Bazel** — CAS + action cache | Bazel uses Starlark for build rules. CUE could validate build configurations and cross-repository dependency constraints. Same architectural layer as Liminara's pack manifests. |
| **Content addressing** — identify by content | CUE values are content-addressable by nature (deterministic serialization → stable hash). A set of CUE constraints has a content address. Policy changes are diffable at the constraint level. |

---

## Open questions

1. **Elixir ↔ CUE bridge:** How to invoke CUE validation from Elixir? Options: CUE CLI via Port, CUE Go library via NIF/Port, or a CUE-to-JSON-Schema compiler that feeds Elixir's existing JSON validation. The last option avoids a runtime dependency on CUE.
2. **Adoption path:** Start with dag-map (JavaScript, low stakes, small surface) or with pack manifests (Elixir, higher stakes, more value)?
3. **CUE vs JSON Schema:** For simple artifact schemas, JSON Schema may be sufficient and already has Elixir tooling. CUE's advantage only kicks in when constraints compose across sources. Where is the crossover?
4. **CUE modules and versioning:** CUE has a module system. Could pack constraint definitions be CUE modules, versioned and published independently of the Elixir code?

---

*See also:*
- *[ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) — broader technology landscape*
- *[LodeTime Dev Pack](../domain_packs/10_LodeTime_Dev_Pack.md) — IR pipeline where CUE fits most naturally*
- *[01_CORE.md](../architecture/01_CORE.md) — five core concepts and determinism classes*
- *[The Logic of CUE](https://cuelang.org/docs/concept/the-logic-of-cue/) — official conceptual documentation*
