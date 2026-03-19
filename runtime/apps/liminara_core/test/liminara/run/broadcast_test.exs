defmodule Liminara.Run.BroadcastTest do
  use ExUnit.Case, async: false

  alias Liminara.{Plan, Run}

  # These tests verify :pg-based event broadcasting from Run.Server (M-OTP-03).

  # ── Subscription API ─────────────────────────────────────────────

  describe "subscription API" do
    test "subscribe adds calling process to the run's :pg group" do
      run_id = "sub-add-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      members = :pg.get_members(:liminara, {:run, run_id})
      assert self() in members

      :ok = Run.unsubscribe(run_id)
    end

    test "unsubscribe removes calling process from the group" do
      run_id = "sub-remove-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)
      :ok = Run.unsubscribe(run_id)

      members = :pg.get_members(:liminara, {:run, run_id})
      refute self() in members
    end

    test "subscribing to a non-existent run succeeds (group created lazily)" do
      run_id = "sub-lazy-#{:erlang.unique_integer([:positive])}"
      assert :ok = Run.subscribe(run_id)
      :ok = Run.unsubscribe(run_id)
    end
  end

  # ── Event delivery ──────────────────────────────────────────────

  describe "event delivery" do
    test "subscriber receives {:run_event, run_id, event} for each event" do
      run_id = "evt-delivery-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      assert length(events) > 0

      # All events should be maps with event_type
      for event <- events do
        assert is_map(event)
        assert Map.has_key?(event, :event_type) or Map.has_key?(event, "event_type")
      end
    end

    test "subscriber receives run_started as first event" do
      run_id = "evt-first-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      first = hd(events)
      assert first.event_type == "run_started" or first["event_type"] == "run_started"
    end

    test "subscriber receives run_completed as final event" do
      run_id = "evt-last-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      last = List.last(events)
      assert last.event_type == "run_completed" or last["event_type"] == "run_completed"
    end

    test "subscriber receives run_failed for failed runs" do
      run_id = "evt-fail-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Fail, %{"data" => {:literal, "x"}})

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      last = List.last(events)
      assert last.event_type == "run_failed" or last["event_type"] == "run_failed"
    end

    test "events arrive in order" do
      run_id = "evt-order-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      types = Enum.map(events, fn e -> e.event_type end)

      assert types == ["run_started", "op_started", "op_completed", "run_completed"]
    end
  end

  # ── Multiple subscribers ────────────────────────────────────────

  describe "multiple subscribers" do
    test "two subscribers both receive all events" do
      run_id = "multi-both-#{:erlang.unique_integer([:positive])}"

      # Subscribe from two processes
      parent = self()

      sub1 =
        spawn_link(fn ->
          Run.subscribe(run_id)
          send(parent, :sub1_ready)
          events = collect_events_loop(run_id, [])
          send(parent, {:sub1_events, events})
        end)

      sub2 =
        spawn_link(fn ->
          Run.subscribe(run_id)
          send(parent, :sub2_ready)
          events = collect_events_loop(run_id, [])
          send(parent, {:sub2_events, events})
        end)

      assert_receive :sub1_ready, 1000
      assert_receive :sub2_ready, 1000

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      # Give subscribers time to collect
      Process.sleep(100)
      send(sub1, :done)
      send(sub2, :done)

      assert_receive {:sub1_events, events1}, 1000
      assert_receive {:sub2_events, events2}, 1000

      assert length(events1) > 0
      assert length(events1) == length(events2)
    end

    test "subscriber to run A does not receive events from run B" do
      run_a = "multi-a-#{:erlang.unique_integer([:positive])}"
      run_b = "multi-b-#{:erlang.unique_integer([:positive])}"

      :ok = Run.subscribe(run_a)

      Run.Server.start(run_b, single_op_plan())
      {:ok, _result} = Run.Server.await(run_b)

      # Should not have received any events for run_b
      events = collect_events(run_a)
      assert events == []
    end

    test "unsubscribed process stops receiving events" do
      run_id = "multi-unsub-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)
      :ok = Run.unsubscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      assert events == []
    end
  end

  # ── Subscriber resilience ───────────────────────────────────────

  describe "subscriber resilience" do
    test "subscriber crash doesn't affect Run.Server" do
      run_id = "resilience-crash-#{:erlang.unique_integer([:positive])}"

      # Start a subscriber that will crash
      crasher =
        spawn(fn ->
          Run.subscribe(run_id)

          receive do
            {:run_event, _, _} -> exit(:intentional_crash)
          end
        end)

      # Give it time to subscribe
      Process.sleep(50)

      # Also subscribe ourselves to verify the run completes
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, result} = Run.Server.await(run_id)

      assert result.status == :success

      # The crasher should be dead
      refute Process.alive?(crasher)

      # We should still have received events
      events = collect_events(run_id)
      assert length(events) > 0
    end
  end

  # ── Integration with Run.Server ─────────────────────────────────

  describe "integration with Run.Server" do
    test "full run delivers all events to subscriber" do
      run_id = "integ-full-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id)

      events = collect_events(run_id)
      types = Enum.map(events, fn e -> e.event_type end)

      assert "run_started" in types
      assert "op_started" in types
      assert "op_completed" in types
      assert "run_completed" in types
    end

    test "event payloads match what's written to event store" do
      run_id = "integ-match-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id)

      Run.Server.start(run_id, single_op_plan())
      {:ok, _result} = Run.Server.await(run_id)

      broadcast_events = collect_events(run_id)
      {:ok, stored_events} = Liminara.Event.Store.read_all(run_id)

      # Same number of events
      assert length(broadcast_events) == length(stored_events)

      # Event types match in order
      broadcast_types = Enum.map(broadcast_events, fn e -> e.event_type end)
      stored_types = Enum.map(stored_events, fn e -> e["event_type"] end)
      assert broadcast_types == stored_types
    end

    test "replay run also broadcasts events" do
      plan = discovery_plan()

      run_id1 = "integ-replay1-#{:erlang.unique_integer([:positive])}"
      Run.Server.start(run_id1, plan)
      {:ok, _disc} = Run.Server.await(run_id1)

      run_id2 = "integ-replay2-#{:erlang.unique_integer([:positive])}"
      :ok = Run.subscribe(run_id2)

      Run.Server.start(run_id2, plan, replay: run_id1)
      {:ok, _replay} = Run.Server.await(run_id2)

      events = collect_events(run_id2)
      types = Enum.map(events, fn e -> e.event_type end)
      assert "run_started" in types
      assert "run_completed" in types
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp single_op_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp discovery_plan do
    Plan.new()
    |> Plan.add_node("load", Liminara.TestOps.Upcase, %{"text" => {:literal, "replay test"}})
    |> Plan.add_node("transform", Liminara.TestOps.Recordable, %{
      "prompt" => {:ref, "load", "result"}
    })
    |> Plan.add_node("save", Liminara.TestOps.SideEffect, %{
      "data" => {:ref, "transform", "result"}
    })
  end

  defp collect_events(run_id) do
    collect_events(run_id, [])
  end

  defp collect_events(run_id, acc) do
    receive do
      {:run_event, ^run_id, event} ->
        collect_events(run_id, acc ++ [event])
    after
      200 ->
        acc
    end
  end

  defp collect_events_loop(run_id, acc) do
    receive do
      {:run_event, ^run_id, event} ->
        collect_events_loop(run_id, acc ++ [event])

      :done ->
        acc
    after
      5000 ->
        acc
    end
  end
end
