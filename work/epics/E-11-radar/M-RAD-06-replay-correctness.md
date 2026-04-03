---
id: M-RAD-06-replay-correctness
epic: E-11-radar
status: in-progress
depends_on: M-RAD-03-cluster-rank-render
---

# M-RAD-06: Replay Correctness

## Goal

Fix the multi-decision replay contract so that recordable ops producing multiple decisions per node (like `radar_summarize`) can be replayed exactly, and harden port executor environment isolation. After this milestone, `Liminara.replay/4` produces identical outputs to the discovery run for the full Radar pipeline.

## Context

M-RAD-03 delivered a working forward-execution pipeline, but deferred replay correctness. The review and gap analysis (2026-04-02) identified two critical issues:

1. **Decision.Store overwrites**: It stores one file per `node_id`. When `radar_summarize` produces N decisions (one per cluster), each `Store.put` overwrites the previous. Only the last decision survives on disk. Replay loads one decision and injects a single `"result"` output — data loss.

2. **Executor.Port env leakage**: Python ops inherit the host's full environment. `VIRTUAL_ENV` and other vars leak into op execution, violating reproducibility. D-019 designates this as a Layer 1 correctness fix (~20 lines).

A third issue — rank determinism (`datetime.now()` in a `:pure` op) — was already fixed in M-RAD-03 by passing `reference_time` as an explicit plan input. This milestone validates that fix via the end-to-end replay test.

## Acceptance Criteria

1. **Decision.Store supports multi-decision nodes**
   - `Store.put/3` stores a list of decisions per `node_id` (not one file overwriting another)
   - `Store.get/3` returns `{:ok, [decision, ...]}` — always a list (single-decision ops return a one-element list)
   - `Store.verify/3` validates integrity of all decisions in the list
   - Backward compatible: existing single-decision files load as a one-element list
   - Hash integrity preserved — each decision's `decision_hash` is independently verifiable

2. **Run.Server replay restores multi-decision outputs**
   - `handle_replay_inject/2` loads the full decision list for a node
   - Reconstructs the op's output map from the decision list (not just `"result"` from one decision)
   - Replayed output artifacts are byte-identical to discovery output artifacts
   - Events emitted during replay match discovery events (same decision hashes, same count)

3. **End-to-end Radar replay test**
   - Test creates a discovery run using the Radar pack with test fixtures (no network, no API keys)
   - Test replays the run using `Liminara.replay/4`
   - Asserts: all output artifact hashes match between discovery and replay
   - Asserts: decision count per node matches
   - Asserts: no LLM calls made during replay (summarize uses recorded decisions)
   - This test exercises: cluster → rank → summarize → compose → render

4. **Executor.Port env whitelist**
   - Port opens with an explicit env whitelist: baseline `PATH`, `HOME`, `LANG`, `TERM`, `USER`, `SHELL`, `LC_ALL`, and `LC_CTYPE`, plus op-declared vars
   - `VIRTUAL_ENV`, `CONDA_PREFIX`, `PYTHONPATH`, and other Python env vars from the host are excluded
   - Existing tests continue to pass (env whitelist doesn't break `uv run`)
   - Whitelist is defined as a module attribute (easy to audit and extend)

## Tests

### Decision.Store tests (Elixir — ExUnit)
- Store 3 decisions for same node_id → get returns list of 3
- Store 1 decision → get returns list of 1
- Verify passes for valid multi-decision node
- Verify detects tampered decision in a multi-decision list
- Load legacy single-decision file → returns one-element list (backward compat)

### Run.Server replay tests (Elixir — ExUnit)
- Multi-decision recordable op: discovery produces N decisions, replay restores all N
- Single-decision recordable op: existing behavior unchanged
- Replay output artifacts are hash-identical to discovery
- Use the existing `ReplayGapPack` characterization test as the basis

### Radar replay integration test (Elixir — ExUnit)
- Full Radar pipeline with fixture data (mock sources, no API key → placeholder summaries)
- Discovery run → replay run → assert identical output hashes
- Tag as `@tag :integration` (may be slow)

### Executor.Port env tests (Elixir — ExUnit)
- Python op that prints `os.environ` → verify `VIRTUAL_ENV` not present
- Python op still has `PATH` and `HOME`
- Existing port executor tests pass unchanged

## Technical Notes

### Decision.Store storage format

Current: `{runs_root}/{run_id}/decisions/{node_id}.json` — single JSON object.

Proposed: same path, but the file contains a JSON array of decision objects. Migration: on `get`, if the file contains a JSON object (not array), wrap it in a list. This gives backward compatibility with zero migration.

### Run.Server replay output reconstruction

The current `handle_replay_inject` extracts `decision["output"]["response"]` and stores it as `%{"result" => output_value}`. This is too rigid.

The fix: the op's output map must be reconstructable from the decision list. For `radar_summarize`, the decisions contain per-cluster summaries; the output is `%{"summaries" => json_list, "decisions" => json_list}`. The reconstruction logic needs to match what the op originally returned.

Options:
- Store the full output map alongside the decisions (simplest, slightly redundant)
- Convention: recordable ops include enough in their decision records to reconstruct outputs
- Store outputs as artifacts (already happens) and re-read them during replay

The simplest approach: store the original output map in the decision file alongside the decision list. Replay reads the stored outputs directly instead of reconstructing from decisions.

### Env whitelist approach

```elixir
@env_whitelist ~w(PATH HOME LANG TERM USER SHELL LC_ALL LC_CTYPE)c

defp clean_env(extra_env_names \\ []) do
   extra_charlists = Enum.map(extra_env_names, &String.to_charlist/1)
   allowed = MapSet.new(@env_whitelist ++ extra_charlists)

  System.get_env()
  |> Enum.flat_map(fn {k, _v} ->
    if MapSet.member?(allowed, String.to_charlist(k)),
      do: [],
      else: [{String.to_charlist(k), false}]
  end)
end
```

This unsets everything not in the whitelist rather than trying to enumerate what to remove.

## Out of Scope

- Replay of plans from stored `plan.json` (currently rebuilds a fresh plan — acceptable for now)
- Threading real runtime `run_id` through plan execution (plan uses plan-time ID)
- Historical centroid computation (cross-run feature, not a correctness fix)
- Sandbox Layers 2-3 (audit hooks, Landlock — E-12 scope per D-019)
- Warnings/degraded outcomes (E-19)

## Dependencies

- M-RAD-03 (forward execution pipeline — done)
- Existing `ReplayGapPack` characterization test and fixtures
