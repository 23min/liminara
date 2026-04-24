---
id: E-12-op-sandbox
phase: 5
status: planning
depends_on: E-20-execution-truth
---

# E-12: Op Sandbox & Provenance

## Goal

Harden the `:port` executor so that Python ops run in a kernel-enforced sandbox with no access to the host filesystem, no inherited environment variables, and no ability to affect other ops. Record the sandbox configuration in run events so that artifact provenance includes the isolation context under which each op executed.

## Context

The `:port` executor (E-10) spawns Python ops via `uv run python` through Erlang Ports. Each op is a separate OS process communicating via `{packet, 4}` JSON over stdio. This is already better than most Python orchestrators (Dagster, Prefect, Temporal all run tasks in the same process), but three isolation gaps remain:

1. **Env var leakage.** The spawned process inherits all environment variables from the BEAM. Discovered during M-RAD-03: `VIRTUAL_ENV` from an unrelated Python project leaked into every op, causing `uv` warnings. Any shell variable — `PYTHONPATH`, `LD_LIBRARY_PATH`, secrets from CI — leaks into every op.

2. **Filesystem access.** An op has full read/write access to the host filesystem. A buggy or malicious op can overwrite other ops' source code (`runtime/python/src/ops/`), corrupt the shared venv (`site-packages/`), or write to any path the user can access.

3. **No provenance.** When replaying a run, there's no record of what isolation was active when an artifact was produced. Two runs of the same plan — one sandboxed, one not — look identical in the event log.

Nobody in the Python orchestration world does lightweight sandboxing without containers. They either trust the process (Dagster, Prefect) or use full containers (Airflow K8s, Excel Python, Snowflake UDFs). Containers add 500ms+ startup overhead, making them impractical for Liminara's spawn-per-call model where ops can be 5-line functions.

Research (D-2026-04-02-011) identified a layered approach using Linux kernel security primitives that provides kernel-enforced isolation at ~4ms overhead — negligible compared to Python startup (~60ms) and actual op execution.

Sequencing note: this epic implements against the canonical `execution_spec/0` isolation contract designed in M-TRUTH-01 and migrated into live runtime paths by M-TRUTH-02. Partial-enforcement degradation must reuse the warning contract from E-19 rather than inventing a sandbox-local status model. It must not introduce a standalone `sandbox_capabilities/0` callback or any other local op-shape escape hatch.

## Scope

### In Scope

- Clean environment whitelist in the Port executor (no inherited env vars)
- Python audit hooks in the op runner (intercept filesystem/network/subprocess at Python level)
- Landlock LSM integration (kernel-enforced filesystem + network restriction per-process)
- Capability declarations in the `execution_spec/0` isolation section (`env_vars`, `network`, `bootstrap_read_paths`, `runtime_read_paths`, `runtime_write_paths`)
- Sandbox configuration recorded in run events (provenance)
- Graceful degradation surfaced through canonical warnings plus sandbox metadata (devcontainer gets audit hooks + clean env; production Linux gets full Landlock)
- Documentation of the isolation model

### Out of Scope

- Container-based isolation (E-17 — `:container` executor)
- Per-op dependency isolation (separate venvs — addressed if needed by E-17)
- GPU/resource limits (E-17)
- seccomp-BPF syscall filtering (layer 4 — can be added later as hardening)
- bubblewrap/namespace isolation (layer 5 — requires user namespaces, not always available)
- Rewriting existing Python ops as Elixir `:inline` ops (separate optimization, not a security concern)

## Constraints

- Must work inside Docker/devcontainer (Landlock works on overlay/tmpfs, not on fakeowner mounts — audit hooks cover the gap)
- Must work on Linux 5.13+ (Landlock ABI v1+). Kernel 6.12 available in current devcontainer (ABI v6).
- Zero new Elixir dependencies (Landlock and audit hooks are applied from Python side)
- Must use the `isolation` section of M-TRUTH-01's execution spec; no standalone sandbox callback
- Must surface partial enforcement through the canonical warning/degraded-success contract; no sandbox-local degraded flag or logs-only contract
- Must not break existing ops or tests
- Overhead budget: ≤10ms per op invocation (measured: ~4ms for layers 1-3)
- Audit hooks and Landlock are both irreversible per-process — an op cannot undo them

## Success Criteria

- [ ] No env vars leak from the host into Python ops (only explicitly whitelisted vars like `PATH`, `HOME`, and op-specific vars like `ANTHROPIC_API_KEY`)
- [ ] Python ops cannot write to paths outside their declared `runtime_write_paths`
- [ ] Bootstrap import access is limited to declared `bootstrap_read_paths`, and runtime file access is limited to declared `runtime_read_paths` / `runtime_write_paths` with no undeclared access to other ops' working dirs or mutable shared state
- [ ] `mix radar.run` works identically with sandbox enabled (all ops pass)
- [ ] Run events include sandbox metadata in canonical isolation vocabulary: active layers plus `env_vars`, `network`, `bootstrap_read_paths`, `runtime_read_paths`, and `runtime_write_paths`
- [ ] Partial enforcement in devcontainer surfaces as warning-bearing success plus sandbox metadata, not as logs-only state
- [ ] Full mode on production Linux (Landlock + audit hooks + clean env) is the default
- [ ] Existing tests pass without modification
- [ ] Overhead ≤10ms per op (benchmark before/after)

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Landlock doesn't work on fakeowner mounts (Docker Desktop) | Med | Audit hooks provide Python-level enforcement in devcontainer. Surface partial enforcement through canonical warnings plus sandbox metadata. Production uses ext4/xfs where Landlock works fully. |
| Audit hooks bypassable via ctypes/raw syscalls | Low | Landlock catches these at kernel level. Audit hooks are defense-in-depth, not the primary boundary. |
| Ops that legitimately need network (fetch_rss, fetch_web, summarize) | High | Capability declarations use `network: :tcp_outbound`. Ops without that declaration get network blocked. |
| Ops that need to write files (dedup writes to LanceDB) | High | Capability declarations use `runtime_write_paths: [lancedb_path]`. Sandbox restricts writes to declared paths only. |
| model2vec downloads model on first run (~59MB) | Med | First-run model download happens outside the sandbox (during setup/init), or `runtime_write_paths` includes the model cache dir. |
| Performance regression from sandbox setup | Low | Measured ~4ms. Python startup is ~60ms, op execution is 100ms-30s. Negligible. |

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-ISO-01 | Executor isolation | Clean env whitelist, audit hooks in op runner, Landlock integration, capability enforcement from `execution_spec/0.isolation`, and canonical warning-bearing degraded mode for partial enforcement | M-TRUTH-02, M-WARN-01 | not started |
| M-ISO-02 | Provenance & documentation | Sandbox config in run events, observation UI indicators, isolation model docs, benchmark report | M-ISO-01 | not started |

## Technical Design

### Layer 1: Clean Environment (Erlang side)

Modify `Executor.Port.execute_port/5` to build a whitelist env from the op's `execution_spec().isolation` section instead of inheriting:

```elixir
defp sandbox_env(isolation_spec) do
  base = [
    {~c"PATH", System.get_env("PATH") |> to_charlist()},
    {~c"HOME", System.get_env("HOME") |> to_charlist()},
    {~c"PYTHONDONTWRITEBYTECODE", ~c"1"},
    {~c"VIRTUAL_ENV", false},
    {~c"PYTHONPATH", false},
    {~c"LD_PRELOAD", false},
  ]

  # Add op-specific env vars from the canonical isolation spec
  op_env = Enum.map(isolation_spec.env_vars || [], fn var ->
    case System.get_env(var) do
      nil -> {to_charlist(var), false}
      val -> {to_charlist(var), to_charlist(val)}
    end
  end)

  # Explicitly unset all other known-dangerous vars
  dangerous = ~w(PYTHONPATH LD_PRELOAD LD_LIBRARY_PATH VIRTUAL_ENV
                  CONDA_PREFIX CONDA_DEFAULT_ENV)
  unset = Enum.map(dangerous, &{to_charlist(&1), false})

  base ++ op_env ++ unset
end
```

### Layer 2: Python Audit Hooks (Python side)

Added to `liminara_op_runner.py` before any op code runs:

```python
import sys

def _sandbox_audit_hook(event, args):
    if event == "open" and args[1] not in ("r", "rb"):
        path = args[0]
    if not _is_allowed_runtime_write(path):
            raise PermissionError(f"Sandbox: write to {path} blocked")
    if event in ("subprocess.Popen", "os.system"):
        raise PermissionError(f"Sandbox: {event} blocked")

sys.addaudithook(_sandbox_audit_hook)  # Irreversible
```

### Layer 3: Landlock (Python side)

Applied after audit hooks, before op import:

```python
import ctypes
import ctypes.util

def apply_landlock(bootstrap_read_paths, runtime_read_paths, runtime_write_paths):
    """Apply Landlock filesystem restrictions. Irreversible."""
    libc = ctypes.CDLL(ctypes.util.find_library("c"))
  # ... (create ruleset, add rules for bootstrap/runtime paths, enforce)
    # Once enforced, process cannot access any path not in the ruleset
```

### Capability Declarations Via `execution_spec/0`

Capability declarations belong in the canonical `execution_spec/0` isolation section, not in a standalone callback.

Illustrative direction:

```elixir
def execution_spec do
  %Liminara.ExecutionSpec{
    isolation: %{
      env_vars: ["ANTHROPIC_API_KEY"],
      network: :tcp_outbound,
      bootstrap_read_paths: [:op_code, :runtime_deps],
      runtime_read_paths: [],
      runtime_write_paths: []
    }
  }
end
```

Example for existing ops:

| Op | network | runtime_write_paths | env_vars |
|----|---------|---------------------|----------|
| fetch_rss | `:tcp_outbound` | [] | [] |
| fetch_web | `:tcp_outbound` | [] | [] |
| normalize | `:none` | [] | [] |
| embed | `:none` | [model_cache] | [] |
| dedup | `:none` | [lancedb_path] | [] |
| llm_dedup | `:tcp_outbound` | [] | [ANTHROPIC_API_KEY] |
| cluster | `:none` | [] | [] |
| rank | `:none` | [] | [] |
| summarize | `:tcp_outbound` | [] | [ANTHROPIC_API_KEY] |

### Provenance in Run Events

Each `node_completed` event gains a `sandbox` field:

```json
{
  "event_type": "node_completed",
  "node_id": "cluster",
  "sandbox": {
    "layers": ["clean_env", "audit_hooks", "landlock"],
    "landlock_abi": 6,
    "env_vars": [],
    "network": "none",
    "bootstrap_read_paths": ["op_code", "runtime_deps"],
    "runtime_read_paths": [],
    "runtime_write_paths": []
  }
}
```

When replaying, the replay engine can verify the sandbox config matches.

If the runtime has to fall back to partial enforcement, that condition should surface through canonical warnings rather than a sandbox-local boolean or logs-only state.

## References

- Decision D-2026-04-02-011: Layered sandbox, not containers
- Decision D-2026-04-01-005: Raw Erlang Ports for Python execution
- `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
- `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`
- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Port executor: `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
- Op runner: `runtime/python/src/liminara_op_runner.py`
- Op behaviour: `runtime/apps/liminara_core/lib/liminara/op.ex`
- Executor dispatcher: `runtime/apps/liminara_core/lib/liminara/executor.ex`
- Landlock docs: https://docs.kernel.org/userspace-api/landlock.html
- Python audit hooks (PEP 578): https://peps.python.org/pep-0578/
