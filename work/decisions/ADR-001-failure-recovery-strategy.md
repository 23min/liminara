---
id: ADR-001
date: 2026-03-19
status: accepted
---

# ADR-001: Failure Recovery via Cache-Based Re-run, Not Automatic Retry

## Context

When a node in a DAG fails (op raises, network timeout, API error), the runtime needs a recovery strategy. The architecture doc (`01_CORE.md`) mentions error policies (retry, skip, fail) as a future capability, and the Run.Server pseudocode references `apply_error_policy/2`. After building the OTP runtime layer (Phase 3), we needed to decide: should the Run.Server automatically retry failed nodes, or should recovery happen through a new run that leverages the cache?

The question has different answers depending on the op's determinism class:

- **Pure/pinned_env ops** (e.g., HTTP fetch, parse, transform): safe to retry — idempotent, no side effects.
- **Recordable ops** (e.g., LLM call, GA selection): retrying may be desirable but produces a different decision each time. Should the retry decision replace the failed one?
- **Side-effecting ops** (e.g., send email, write to external DB): retrying is dangerous — may cause duplicates.

## Decision

**Fail fast within a run. Recover by starting a new run with the same plan — the cache handles the rest.**

When a node fails:

1. The node is marked `:failed` immediately. No automatic retry.
2. The Run.Server continues dispatching nodes that don't depend on the failed node.
3. The run finishes as `:partial` (some completed, some failed, none blocked) or `:failed` (failures block downstream nodes).
4. Each run has a complete, unambiguous event log.

To recover:

1. Start a new run with the same plan and inputs.
2. Pure/pinned_env ops that completed in the previous run are cache hits — instant, no re-execution.
3. The failed op re-executes (with potentially different conditions — the transient error may have resolved).
4. Downstream ops re-execute only if their inputs changed.

This is the build-system model: `make` doesn't retry a failed compilation — you fix the issue and run `make` again. Cached targets are skipped. Only what needs to rebuild, rebuilds.

**Automatic retry is deferred**, not rejected. When it's added, it will be:

- Configured per-node, not globally: `error_policy: :retry, max_retries: 3, backoff: :exponential`
- Limited to pure/pinned_env ops by default (safe to retry)
- Recordable ops: retry only with explicit opt-in (the decision record captures the successful attempt)
- Side-effecting ops: never auto-retry (too dangerous)
- Retries are invisible in the event log until final resolution (only the last attempt's outcome is recorded as the node's terminal event, with a retry count in the payload)

## Alternatives considered

- **Automatic retry with exponential backoff** — The obvious first instinct. Rejected for now because: (a) it's unsafe for side-effecting ops without per-op configuration, (b) the cache already provides "retry from the point of failure" semantics at the run level, (c) Oban (Phase 6) will handle job-level retry with battle-tested backoff, dead letter queues, and uniqueness, making op-level retry less urgent. Will be added as per-node policy when a real pack needs it.

- **Resume a failed run in place** — Instead of starting a new run, modify the existing run's state (reset failed nodes to pending, re-dispatch). Rejected because: (a) it breaks the "run = immutable event log" invariant — you'd be appending retry events to a log that already has a `run_failed` terminal event, (b) the Run.Server has already exited, so resuming means rebuilding state anyway, (c) a new run with cache is operationally equivalent and preserves clean audit trails. Each attempt is a separate, complete record.

- **Skip failed nodes and continue** — Mark the failed node as skipped and let downstream nodes execute with missing inputs. Rejected because: this produces corrupt or incomplete outputs. If the fetch op fails, the normalize op gets no input. Better to fail explicitly than produce garbage silently. (Exception: a pack could declare a node as optional via metadata, but this is future work.)

- **Checkpoint and resume** — Persist Run.Server state to disk periodically so a crashed server can resume exactly where it stopped. Partially built: the state rebuild from event log (M-OTP-04) already does this for Run.Server crashes. But this addresses server crashes, not op failures. For op failures, the question is whether to retry the op, not whether to resume the server.

## Consequences

**What becomes easier:**

- The Run.Server is simple — no retry state machine, no backoff timers, no "which attempt is this" tracking.
- Every run has a clean, linear event log with exactly one terminal event per node.
- Audit and debugging are straightforward — each attempt is a separate run you can compare.
- The cache makes re-runs cheap. For a 10-node plan where node 7 failed, the re-run cache-hits on nodes 1–6 and only re-executes 7–10.

**What becomes harder:**

- Transient failures require external re-triggering. For cron-scheduled packs (Radar), the next schedule handles this naturally. For interactive use, the caller must detect failure and re-run.
- No "single run" story for a sequence of attempts. If it takes 3 tries to get node 7 to succeed, that's 3 separate runs in the system. (Mitigated: you can trace them by plan_hash — all 3 runs share the same plan.)
- Oban integration becomes more important earlier than it otherwise would be, since job-level retry is the primary mechanism for automated recovery.

**What we accept:**

- Manual re-triggering for interactive failures until Oban is added (Phase 6).
- Multiple run records for what is conceptually "one attempt" with retries.
- The architecture doc's `apply_error_policy` remains a placeholder until a real pack (likely Radar's fetch ops) demonstrates the need for per-node retry.

**Trigger to revisit:**

- When Radar's fetch ops fail transiently in production and manual re-triggering is too frequent.
- When a pack author requests per-node retry configuration.
- When the observation layer needs to show "attempt 2 of 3" in the UI.
