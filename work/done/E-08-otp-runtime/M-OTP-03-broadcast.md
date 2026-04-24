---
id: M-OTP-03-broadcast
epic: E-08-otp-runtime
status: complete
---

# M-OTP-03: Event Broadcasting

## Goal

Add `:pg` (process groups) based event broadcasting to the Run.Server. Every event the Run.Server records is broadcast to all subscribers of that run. This is the mechanism the observation layer (Phase 4) will consume — building it now ensures the contract is stable before any UI code exists.

## Acceptance criteria

- [ ] `:pg` scope `:liminara` is started as part of the application supervision tree
- [ ] Each run has a process group: `{:run, run_id}`
- [ ] `Liminara.Run.subscribe(run_id)` — calling process joins the run's `:pg` group
- [ ] `Liminara.Run.unsubscribe(run_id)` — calling process leaves the group
- [ ] Every event the Run.Server records is broadcast: `send(subscriber, {:run_event, run_id, event})`
- [ ] Broadcast is fire-and-forget (non-blocking for the Run.Server)
- [ ] Multiple subscribers on the same run each receive all events
- [ ] Subscriber that crashes doesn't affect the Run.Server or other subscribers
- [ ] Late-joining subscriber receives events from the point of subscription onward (no backfill)
- [ ] Events are broadcast in the same order they are recorded
- [ ] Run completion/failure events are broadcast (subscriber knows when the run ends)

## Tests

### Subscription API
- `subscribe/1` adds the calling process to the run's `:pg` group
- `unsubscribe/1` removes the calling process from the group
- Subscribing to a non-existent run succeeds (group is created lazily)

### Event delivery
- Subscriber receives `{:run_event, run_id, event}` for each event in a running run
- Subscriber receives `run_started` as the first event (if subscribed before the run starts)
- Subscriber receives `run_completed` or `run_failed` as the final event
- Events arrive in order: `run_started` before `node_started` before `node_completed` before `run_completed`

### Multiple subscribers
- Two subscribers both receive all events from the same run
- Subscribing and unsubscribing mid-run: unsubscribed process stops receiving events
- Subscriber to run A does not receive events from run B

### Subscriber resilience
- Subscriber process crashes during a run → Run.Server continues without error
- Subscriber with a full message queue doesn't block the Run.Server (send is non-blocking)

### Integration with Run.Server
- A full run (start → ops → complete) delivers all events to a subscriber
- Event payloads match what's written to the event store (same data)
- Replay run also broadcasts events to subscribers

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Design notes

### Implementation

The broadcast function is minimal:

```elixir
defp broadcast(run_id, event) do
  :pg.get_members(:liminara, {:run, run_id})
  |> Enum.each(&send(&1, {:run_event, run_id, event}))
end
```

This is called inside `record_event/3` in the Run.Server, after the event is written to the event store. The `:pg` module is built into OTP — zero external dependencies.

### `:pg` scope startup

Add `{:pg, :liminara}` (or `%{name: :liminara}`) as a child in the supervision tree, before the Run.DynamicSupervisor. This creates the named `:pg` scope that all runs share.

### Why not Phoenix.PubSub or Registry dispatch?

- `:pg` is built into OTP, zero deps
- It handles subscriber crashes gracefully (dead processes are automatically removed from groups)
- It's the mechanism described in `01_CORE.md`
- Phoenix.PubSub would work but adds an unnecessary dependency

## Out of scope

- Backfill for late-joining subscribers (they read the event log)
- Filtered subscriptions (subscribe to specific event types)
- Observation UI (Phase 4)

## Spec reference

- `docs/architecture/01_CORE.md` § "Observation: the Excel quality"
- Erlang `:pg` docs: https://www.erlang.org/doc/man/pg
