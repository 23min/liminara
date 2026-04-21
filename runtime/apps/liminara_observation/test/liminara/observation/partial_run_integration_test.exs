defmodule Liminara.Observation.PartialRunIntegrationTest do
  @moduledoc """
  M-WARN-04 merged_bug_001 regression: verify that a `:partial` run
  (one node completes with warnings, a parallel branch fails) is
  correctly projected as `degraded: true` and `run_status: :partial`
  across the runtime → observation → ViewModel pipeline.

  Before the fix, `Run.Server.finish_run/2` emitted the same
  `"run_failed"` event type for both `:failed` and `:partial` terminal
  statuses. `Observation.ViewModel.apply_typed(_, "run_failed", ...)`
  set `run_status: :failed` and `degraded: derive_degraded(:failed, n)`
  which always returns `false`. The CLI surface (via `Run.Result.degraded`)
  correctly reported `degraded: true`, but every observation/web consumer
  collapsed the partial to `:failed` and dropped the degraded signal.

  The fix introduces a new `"run_partial"` terminal event type — one
  event type per `Run.Result.status`. Every consumer that switches on
  event type grows a matching `run_partial` clause. The payload
  shape is identical to `run_completed` / `run_failed`; only the
  event_type discriminator changes.
  """

  use ExUnit.Case, async: false

  alias Liminara.Observation.Server
  alias Liminara.{Plan, Run}

  # ── Helpers ────────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
  end

  defp await_observation(obs_pid, condition_fn, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_observation(obs_pid, condition_fn, deadline)
  end

  defp do_await_observation(obs_pid, condition_fn, deadline) do
    state = Server.get_state(obs_pid)

    if condition_fn.(state) do
      state
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk(
          "await_observation timed out. Last state: #{inspect(state, pretty: true, limit: 5)}"
        )
      else
        Process.sleep(20)
        do_await_observation(obs_pid, condition_fn, deadline)
      end
    end
  end

  # A fan-out plan: root feeds two independent branches.
  # - "warn" emits a warning and completes
  # - "fail" always fails
  # Because neither branch depends on the other, the run enters the
  # "stuck with any_failed and any_completed and no pending" state in
  # `maybe_complete_stuck/1`, which yields `:partial`.
  defp partial_plan do
    Plan.new()
    |> Plan.add_node("root", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
      "text" => {:ref, "root", "result"}
    })
    |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:ref, "root", "result"}})
  end

  # ── End-to-end :partial-with-warnings projection ─────────────────

  describe "merged_bug_001: :partial-with-warnings reaches ViewModel as degraded" do
    test "partial run: Result, ViewModel, and terminal event all agree on degraded: true" do
      run_id = unique_run_id("partial-degraded")
      plan = partial_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)

      # 1. Run.Result carries the canonical degraded: true signal
      # (this works today via Result.derive_degraded/2).
      assert result.status == :partial
      assert result.warning_count >= 1
      assert "warn" in result.degraded_nodes
      assert result.degraded == true

      # 2. ViewModel projection agrees.
      state = await_observation(obs_pid, fn s -> s.run_status == :partial end)

      assert state.run_status == :partial
      assert state.warning_count == result.warning_count
      assert state.degraded_nodes == Enum.sort(result.degraded_nodes)
      assert state.degraded == true

      # Per-node projection for the warning-emitting node is populated.
      assert state.nodes["warn"].status == :completed
      assert state.nodes["warn"].degraded == true
      assert length(state.nodes["warn"].warnings) == 1

      # Failing node is marked :failed.
      assert state.nodes["fail"].status == :failed

      GenServer.stop(obs_pid)
    end

    test "partial run emits a run_partial terminal event (not run_failed)" do
      run_id = unique_run_id("partial-event-type")
      plan = partial_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 5_000)

      # Give the terminal event time to reach the observer.
      _ = await_observation(obs_pid, fn s -> s.run_status == :partial end)

      events = Server.get_events(obs_pid)
      terminal = List.last(events)

      terminal_type =
        Map.get(terminal, :event_type) || Map.get(terminal, "event_type")

      assert terminal_type == "run_partial",
             "Expected terminal event_type 'run_partial' for a :partial run, got #{inspect(terminal_type)}"

      GenServer.stop(obs_pid)
    end

    test "partial with zero warnings: ViewModel reports run_status :partial and degraded: false" do
      # Edge case: a partial run where the successful branch emitted
      # no warnings. The run is still :partial (one branch failed), but
      # it is not degraded (no warnings to be degraded by).
      run_id = unique_run_id("partial-no-warn")

      plan =
        Plan.new()
        |> Plan.add_node("root", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
        |> Plan.add_node("ok", Liminara.TestOps.Reverse, %{"text" => {:ref, "root", "result"}})
        |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:ref, "root", "result"}})

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)

      assert result.status == :partial
      assert result.warning_count == 0
      assert result.degraded == false

      state = await_observation(obs_pid, fn s -> s.run_status == :partial end)

      assert state.run_status == :partial
      assert state.warning_count == 0
      assert state.degraded == false

      GenServer.stop(obs_pid)
    end
  end

  describe "merged_bug_001: replay of :partial-with-warnings preserves degraded" do
    test "rebuilt ViewModel from persisted events projects degraded: true" do
      run_id = unique_run_id("partial-replay")
      plan = partial_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)
      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 5_000)

      live_state = await_observation(obs_pid, fn s -> s.run_status == :partial end)
      GenServer.stop(obs_pid)

      # Start a fresh observer after completion — forces a rebuild
      # from the persisted event log (JSON round-trip).
      Process.sleep(50)
      {:ok, obs_pid2} = Server.start_link(run_id: run_id, plan: plan)
      replay_state = await_observation(obs_pid2, fn s -> s.run_status == :partial end)

      assert replay_state.run_status == :partial
      assert replay_state.warning_count == live_state.warning_count
      assert replay_state.degraded_nodes == live_state.degraded_nodes
      assert replay_state.degraded == true

      # And the terminal event in the rebuilt log is still "run_partial".
      events = Server.get_events(obs_pid2)
      terminal = List.last(events)

      terminal_type =
        Map.get(terminal, :event_type) || Map.get(terminal, "event_type")

      assert terminal_type == "run_partial"

      GenServer.stop(obs_pid2)
    end

    test "result_from_event_log recognises run_partial and returns :partial" do
      # Regression guard for `Run.Server.result_from_event_log/1`: after
      # the Run.Server process exits, a later `await/1` must reconstruct
      # the Result from the on-disk event log and preserve `:partial`.
      run_id = unique_run_id("partial-rebuild")
      plan = partial_plan()

      Run.Server.start(run_id, plan)
      {:ok, result1} = Run.Server.await(run_id, 5_000)
      assert result1.status == :partial

      # Let the Run.Server terminate (schedule is `Process.send_after(self(), :stop, 0)`).
      Process.sleep(50)

      # Second await: server is gone, so result comes from event log.
      assert {:ok, result2} = Run.Server.await(run_id, 1_000)
      assert result2.status == :partial
      assert result2.warning_count == result1.warning_count
      assert result2.degraded == true
      assert result2.degraded_nodes == result1.degraded_nodes
    end
  end

  describe "merged_bug_001: :failed (not :partial) rule is preserved" do
    test "pure :failed run (single failing node) remains degraded: false on the observation path" do
      # A single-node failing plan: no other node completes, so the run
      # is truly :failed (not :partial). `Run.Result.derive_degraded/2`
      # must still return false, and the ViewModel must continue to
      # project degraded: false — the rule in AC2 is only for :partial.
      # The :failed → false rule is not being changed.
      run_id = unique_run_id("pure-failed")

      plan =
        Plan.new()
        |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:literal, "x"}})

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)

      assert result.status == :failed
      # No warning-bearing node, so warning_count stays 0.
      assert result.warning_count == 0
      assert result.degraded == false

      state = await_observation(obs_pid, fn s -> s.run_status == :failed end)

      assert state.run_status == :failed
      assert state.degraded == false

      # And the terminal event is run_failed, not run_partial.
      events = Server.get_events(obs_pid)
      terminal = List.last(events)

      terminal_type =
        Map.get(terminal, :event_type) || Map.get(terminal, "event_type")

      assert terminal_type == "run_failed"

      GenServer.stop(obs_pid)
    end
  end
end
