defmodule Liminara.Observation.IntegrationTest do
  use ExUnit.Case, async: false

  alias Liminara.Observation.{Server, ViewModel}
  alias Liminara.{Plan, Run}

  # Integration tests use Run.Server to produce real events on :pg.
  # Observation.Server subscribes and should build a matching view model.

  # ── Helpers ────────────────────────────────────────────────────────

  defp unique_run_id(prefix \\ "integ") do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
  end

  # Poll Observation.Server until condition is met, with timeout.
  # Replaces flaky Process.sleep + assert patterns.
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

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp recordable_plan do
    Plan.new()
    |> Plan.add_node("gen", Liminara.TestOps.Recordable, %{"prompt" => {:literal, "summarize"}})
  end

  defp failing_plan do
    Plan.new()
    |> Plan.add_node("ok", Liminara.TestOps.Upcase, %{"text" => {:literal, "fine"}})
    |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:ref, "ok", "result"}})
  end

  # ── Full lifecycle observation ─────────────────────────────────────

  describe "full run lifecycle" do
    test "observation server observes entire single-op run" do
      run_id = unique_run_id()
      plan = simple_plan()

      # Start observation server BEFORE run
      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      # Start Run.Server
      Run.Server.start(run_id, plan)
      {:ok, run_result} = Run.Server.await(run_id)

      assert run_result.status == :success

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      assert state.nodes["a"].status == :completed
      assert state.run_started_at != nil
      assert state.run_completed_at != nil

      GenServer.stop(obs_pid)
    end

    test "observation server observes two-node linear run" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state =
        await_observation(obs_pid, fn s ->
          s.run_status == :completed and s.nodes["b"].status == :completed
        end)

      assert state.nodes["a"].status == :completed

      GenServer.stop(obs_pid)
    end

    test "view model event_count matches total events in event log" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)
      {:ok, events} = Liminara.Event.Store.read_all(run_id)

      assert state.event_count == length(events)

      GenServer.stop(obs_pid)
    end

    test "node output_hashes in view model are present after op_completed" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state =
        await_observation(obs_pid, fn s ->
          s.nodes["a"].output_hashes != []
        end)

      Enum.each(state.nodes["a"].output_hashes, fn hash ->
        assert is_binary(hash)
        assert String.starts_with?(hash, "sha256:")
      end)

      GenServer.stop(obs_pid)
    end

    test "recordable op: decision reference appears in node view" do
      run_id = unique_run_id()
      plan = recordable_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state =
        await_observation(obs_pid, fn s ->
          s.nodes["gen"].decisions != []
        end)

      GenServer.stop(obs_pid)
    end

    test "failing run: failed node marked :failed, run_status :partial (one completed + one failed)" do
      # M-WARN-04 merged_bug_001: with the new 1:1 event-type -> status
      # mapping, a linear `ok -> fail` plan produces :partial (ok
      # completed, fail failed, nothing pending). Previously the terminal
      # event was always "run_failed" and the heuristic in
      # `terminal_status/2` rewrote status to :partial at the Result
      # boundary; now the event type itself discriminates.
      run_id = unique_run_id()
      plan = failing_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, run_result} = Run.Server.await(run_id)

      assert run_result.status == :partial

      state = await_observation(obs_pid, fn s -> s.run_status == :partial end)

      assert state.nodes["fail"].status == :failed
      assert state.nodes["ok"].status == :completed

      GenServer.stop(obs_pid)
    end

    test "failing run: node error info is populated" do
      run_id = unique_run_id()
      plan = failing_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state =
        await_observation(obs_pid, fn s ->
          s.nodes["fail"].error != nil
        end)

      GenServer.stop(obs_pid)
    end

    test "node timing: started_at and completed_at populated after op completes" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      assert is_binary(state.nodes["a"].started_at)
      assert is_binary(state.nodes["a"].completed_at)

      GenServer.stop(obs_pid)
    end
  end

  # ── Mid-run join (catch-up from event log) ─────────────────────────

  describe "mid-run join" do
    test "server started after run begins catches up from event log" do
      # Use a slow op so we can start the observer mid-run
      run_id = unique_run_id("midrun")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "catching up"}})

      # Start run first
      Run.Server.start(run_id, plan)

      # Give the run a head start (run_started + op_started should be recorded)
      Process.sleep(50)

      # Now start observation server
      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      # Wait for run to complete
      {:ok, run_result} = Run.Server.await(run_id, 2000)
      assert run_result.status == :success

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      # Observer should have seen all events (catch-up + live)
      {:ok, events} = Liminara.Event.Store.read_all(run_id)

      assert state.event_count == length(events)

      GenServer.stop(obs_pid)
    end

    test "mid-run join: final state matches expected completed state" do
      run_id = unique_run_id("midrun2")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "mid join"}})

      Run.Server.start(run_id, plan)
      Process.sleep(50)

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, _run_result} = Run.Server.await(run_id, 2000)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)
      assert state.nodes["slow"].status == :completed

      GenServer.stop(obs_pid)
    end
  end

  # ── Completed run observation ──────────────────────────────────────

  describe "completed run observation" do
    test "server started after run completion loads full state from event log" do
      run_id = unique_run_id("completed")
      plan = simple_plan()

      # Run to completion
      Run.Server.start(run_id, plan)
      {:ok, run_result} = Run.Server.await(run_id)
      assert run_result.status == :success

      # Wait a tick to ensure event log is fully flushed
      Process.sleep(50)

      # Start observer AFTER completion
      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      assert state.nodes["a"].status == :completed

      {:ok, events} = Liminara.Event.Store.read_all(run_id)
      assert state.event_count == length(events)

      GenServer.stop(obs_pid)
    end

    test "observer of completed run has correct timing info" do
      run_id = unique_run_id("completed-timing")
      plan = simple_plan()

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      Process.sleep(50)

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      assert is_binary(state.run_started_at)
      assert is_binary(state.run_completed_at)

      GenServer.stop(obs_pid)
    end
  end

  # ── Two observers same run ─────────────────────────────────────────

  describe "two observers for the same run" do
    test "both observers see the same final state" do
      run_id = unique_run_id("twoobs")
      plan = two_node_plan()

      {:ok, obs_pid1} = Server.start_link(run_id: run_id, plan: plan)
      {:ok, obs_pid2} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _run_result} = Run.Server.await(run_id)

      state1 = await_observation(obs_pid1, fn s -> s.run_status == :completed end)
      state2 = await_observation(obs_pid2, fn s -> s.run_status == :completed end)

      assert state1.run_status == state2.run_status
      assert state1.event_count == state2.event_count
      assert state1.nodes["a"].status == state2.nodes["a"].status
      assert state1.nodes["b"].status == state2.nodes["b"].status

      GenServer.stop(obs_pid1)
      GenServer.stop(obs_pid2)
    end

    test "both observers receive PubSub updates for the same run" do
      run_id = unique_run_id("twoobs-pubsub")
      plan = simple_plan()

      topic = "observation:#{run_id}:state"

      # Subscribe two test processes to PubSub
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      parent = self()

      sub2 =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)
          send(parent, :sub2_ready)

          msgs = collect_pubsub_messages(run_id, [])
          send(parent, {:sub2_messages, msgs})
        end)

      assert_receive :sub2_ready, 1000

      {:ok, obs_pid1} = Server.start_link(run_id: run_id, plan: plan)
      {:ok, obs_pid2} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _} = Run.Server.await(run_id)

      # Wait until at least one observer has processed the completion
      await_observation(obs_pid1, fn s -> s.run_status == :completed end)

      send(sub2, :done)

      assert_receive {:sub2_messages, msgs2}, 1000

      # Collect this process's messages
      msgs1 = collect_pubsub_messages_inbox(run_id, [])

      assert msgs1 != []
      assert msgs2 != []

      GenServer.stop(obs_pid1)
      GenServer.stop(obs_pid2)
    end
  end

  # ── Isolation: Observation.Server crash ───────────────────────────

  describe "isolation" do
    test "killing Observation.Server does not affect Run.Server" do
      run_id = unique_run_id("isolation")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "survive"}})

      Run.Server.start(run_id, plan)

      Process.sleep(50)

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      # Kill the observation server mid-run
      Process.exit(obs_pid, :kill)
      Process.sleep(50)

      refute Process.alive?(obs_pid)

      # Run.Server should still complete normally
      {:ok, run_result} = Run.Server.await(run_id, 2000)
      assert run_result.status == :success
    end

    test "observation server crash is isolated (doesn't crash test process)" do
      run_id = unique_run_id("isolation2")
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      # We are not linked, so killing obs_pid shouldn't affect test
      Process.exit(obs_pid, :kill)
      Process.sleep(50)

      refute Process.alive?(obs_pid)
      # Test process still alive
      assert Process.alive?(self())
    end
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp collect_pubsub_messages(run_id, acc) do
    receive do
      {:state_update, ^run_id, _state} = msg ->
        collect_pubsub_messages(run_id, acc ++ [msg])

      :done ->
        acc
    after
      2000 ->
        acc
    end
  end

  defp collect_pubsub_messages_inbox(run_id, acc) do
    receive do
      {:state_update, ^run_id, _state} = msg ->
        collect_pubsub_messages_inbox(run_id, acc ++ [msg])
    after
      200 ->
        acc
    end
  end
end
