---
id: M-EE-01-plan
epic: E-06-execution-engine
status: done
---

# M-EE-01: Plan Data Structure

## Goal

Implement `Liminara.Plan` — the DAG data structure that represents a computation plan. A plan is a graph of nodes, where each node names an op and declares its inputs as either literal values or references to other nodes' outputs. The plan module provides DAG validation, topological ordering, and ready-node detection.

## Acceptance criteria

### Module: `Liminara.Plan`

- [x] `Plan.new()` → creates an empty plan
- [x] `Plan.add_node(plan, node_id, op_module, inputs)` → adds a node, returns updated plan
- [x] `Plan.ready_nodes(plan, completed)` → returns node_ids whose inputs are all resolved
- [x] `Plan.all_complete?(plan, completed)` → true when all nodes are in the completed set
- [x] `Plan.nodes(plan)` → returns all node definitions
- [x] `Plan.get_node(plan, node_id)` → returns a single node definition

### Input types

- [x] `{:literal, value}` — a static value, always available
- [x] `{:ref, node_id}` — the output of another node, available when that node completes
- [x] Inputs are a map of `%{input_name => {:literal, value} | {:ref, node_id}}`

### Ready-node detection

- [x] A node is ready when all its `:ref` inputs point to completed nodes (literals are always resolved)
- [x] `ready_nodes/2` returns only nodes not yet in the completed set
- [x] Linear plan (A → B → C): initially only A is ready; after A completes, B is ready; etc.
- [x] Fan-out plan (A → B, A → C): after A completes, both B and C are ready
- [x] Fan-in plan (A → C, B → C): C is ready only when both A and B complete

### Validation

- [x] `Plan.validate(plan)` → `:ok` or `{:error, reason}`
- [x] Rejects duplicate node IDs
- [x] Rejects dangling refs (ref to a node_id that doesn't exist in the plan)
- [x] Rejects cycles (A → B → A)
- [x] Empty plan is valid

### Plan hash

- [x] `Plan.hash(plan)` → `"sha256:{hex}"` — deterministic hash of the plan structure
- [x] Same plan always produces the same hash (canonical serialization)

## Tests

### `test/liminara/plan_test.exs`

**Construction:**
- `new/0` creates an empty plan
- `add_node/4` adds nodes, returned plan has them
- Multiple nodes can be added
- Node with literal inputs
- Node with ref inputs
- Node with mixed literal + ref inputs

**Ready nodes:**
- Empty plan has no ready nodes
- Single node with no inputs (or only literals) is immediately ready
- Linear chain: A → B → C — test ready at each step
- Fan-out: A → B, A → C — B and C ready after A
- Fan-in: A → C, B → C — C ready only after both A and B
- Already-completed nodes are not returned as ready

**Validation:**
- Valid linear plan passes
- Valid fan-out plan passes
- Empty plan passes
- Duplicate node_id rejected
- Dangling ref rejected (ref to nonexistent node)
- Cycle rejected (A refs B, B refs A)
- Self-referencing node rejected

**Plan hash:**
- Same plan produces same hash
- Different plans produce different hashes
- Hash is in `sha256:{hex}` format

## TDD sequence

1. **Test agent** reads this spec, writes `plan_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Plan` until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## Out of scope

- Discovery mode (dynamic DAG expansion at runtime)
- Plan serialization to/from disk (not needed until E-07)
- Execution — Plan is a pure data structure, Run.Server handles execution (M-EE-03)

## Spec reference

- `docs/architecture/01_CORE.md` § The plan
- `docs/architecture/02_PLAN.md` § Phase 2
