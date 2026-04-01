defmodule Liminara.Observation.ServerEventsTest do
  @moduledoc """
  Tests for M-OBS-04b: Observation.Server filtered events API.

  Covers:
  - get_events/2 with %{event_type: ...} filter
  - get_events/2 with %{node_id: ...} filter
  - get_events/2 with empty filter (returns all)
  - Events broadcast on observation:{run_id}:events PubSub topic

  These tests will fail (red phase) until get_events/2 is added to Server.
  """
  use ExUnit.Case, async: false

  alias Liminara.Observation.Server
  alias Liminara.Plan

  # ── Helpers ────────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp unique_run_id do
    "obs-events-#{:erlang.unique_integer([:positive])}"
  end

  defp send_pg_event(run_id, event) do
    :pg.get_members(:liminara, {:run, run_id})
    |> Enum.each(&send(&1, {:run_event, run_id, event}))
  end

  defp run_started_event(run_id) do
    %{
      event_hash: "sha256:rs_#{run_id}",
      event_type: "run_started",
      payload: %{
        "run_id" => run_id,
        "pack_id" => "test_pack",
        "pack_version" => "0.1.0",
        "plan_hash" => "sha256:abc"
      },
      prev_hash: nil,
      timestamp: "2026-03-19T14:00:00.000Z"
    }
  end

  defp op_started_event(node_id) do
    %{
      event_hash: "sha256:os_#{node_id}",
      event_type: "op_started",
      payload: %{
        "node_id" => node_id,
        "op_id" => "upcase",
        "op_version" => "1.0",
        "determinism" => "pure",
        "input_hashes" => []
      },
      prev_hash: "sha256:rs",
      timestamp: "2026-03-19T14:00:01.000Z"
    }
  end

  defp op_completed_event(node_id) do
    %{
      event_hash: "sha256:oc_#{node_id}",
      event_type: "op_completed",
      payload: %{
        "node_id" => node_id,
        "output_hashes" => ["sha256:out_#{node_id}"],
        "cache_hit" => false,
        "duration_ms" => 10
      },
      prev_hash: "sha256:os_#{node_id}",
      timestamp: "2026-03-19T14:00:02.000Z"
    }
  end

  defp decision_recorded_event(node_id) do
    %{
      event_hash: "sha256:dec_#{node_id}",
      event_type: "decision_recorded",
      payload: %{
        "node_id" => node_id,
        "decision_hash" => "sha256:dechash",
        "decision_type" => "llm_response"
      },
      prev_hash: "sha256:os_#{node_id}",
      timestamp: "2026-03-19T14:00:01.500Z"
    }
  end

  defp run_completed_event(run_id) do
    %{
      event_hash: "sha256:rc_#{run_id}",
      event_type: "run_completed",
      payload: %{
        "run_id" => run_id,
        "outcome" => "success",
        "artifact_hashes" => []
      },
      prev_hash: "sha256:oc_a",
      timestamp: "2026-03-19T14:00:05.000Z"
    }
  end

  # Helper to populate a server with a full set of events (run_started + node a + node b + run_completed)
  defp send_full_run(run_id) do
    send_pg_event(run_id, run_started_event(run_id))
    send_pg_event(run_id, op_started_event("a"))
    send_pg_event(run_id, op_completed_event("a"))
    send_pg_event(run_id, op_started_event("b"))
    send_pg_event(run_id, op_completed_event("b"))
    send_pg_event(run_id, run_completed_event(run_id))
    Process.sleep(100)
  end

  # ── get_events/2 signature exists ──────────────────────────────────

  describe "Server.get_events/2 — API exists" do
    test "get_events/2 is callable with a pid and a filter map" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      # Must not raise UndefinedFunctionError or FunctionClauseError
      result = Server.get_events(pid, %{})

      assert is_list(result),
             "Expected get_events/2 to return a list, got: #{inspect(result)}"

      GenServer.stop(pid)
    end
  end

  # ── get_events/2 with empty filter ─────────────────────────────────

  describe "Server.get_events/2 with %{} — returns all events" do
    test "empty filter returns all stored events" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      all_events = Server.get_events(pid, %{})

      # run_started + op_started_a + op_completed_a + op_started_b + op_completed_b + run_completed
      assert length(all_events) == 6,
             "Expected 6 events from empty filter, got #{length(all_events)}"

      GenServer.stop(pid)
    end

    test "get_events/2 with empty filter returns same result as get_events/1" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_pg_event(run_id, run_started_event(run_id))
      send_pg_event(run_id, op_started_event("a"))
      Process.sleep(50)

      events_no_filter = Server.get_events(pid)
      events_empty_filter = Server.get_events(pid, %{})

      assert events_no_filter == events_empty_filter,
             "get_events/1 and get_events/2 with %{} should return the same result"

      GenServer.stop(pid)
    end
  end

  # ── get_events/2 with event_type filter ────────────────────────────

  describe "Server.get_events/2 — filter by event_type" do
    test "filter %{event_type: 'op_completed'} returns only op_completed events" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{event_type: "op_completed"})

      assert is_list(filtered)

      assert length(filtered) == 2,
             "Expected 2 op_completed events, got #{length(filtered)}: #{inspect(filtered)}"

      for e <- filtered do
        et = e[:event_type] || e["event_type"]

        assert et == "op_completed",
               "Expected event_type 'op_completed', got: #{inspect(et)}"
      end

      GenServer.stop(pid)
    end

    test "filter %{event_type: 'run_started'} returns only the run_started event" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{event_type: "run_started"})

      assert length(filtered) == 1,
             "Expected 1 run_started event, got #{length(filtered)}"

      e = hd(filtered)
      et = e[:event_type] || e["event_type"]
      assert et == "run_started"

      GenServer.stop(pid)
    end

    test "filter by event_type with no matching events returns empty list" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_pg_event(run_id, run_started_event(run_id))
      Process.sleep(50)

      # decision_recorded events were never sent
      filtered = Server.get_events(pid, %{event_type: "decision_recorded"})

      assert filtered == [],
             "Expected empty list for unmatched event_type filter, got: #{inspect(filtered)}"

      GenServer.stop(pid)
    end

    test "filter %{event_type: 'decision_recorded'} returns only decision events" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)

      send_pg_event(run_id, run_started_event(run_id))
      send_pg_event(run_id, op_started_event("a"))
      send_pg_event(run_id, decision_recorded_event("a"))
      send_pg_event(run_id, op_completed_event("a"))
      Process.sleep(100)

      filtered = Server.get_events(pid, %{event_type: "decision_recorded"})

      assert length(filtered) == 1,
             "Expected 1 decision_recorded event, got #{length(filtered)}"

      e = hd(filtered)
      et = e[:event_type] || e["event_type"]
      assert et == "decision_recorded"

      GenServer.stop(pid)
    end
  end

  # ── get_events/2 with node_id filter ───────────────────────────────

  describe "Server.get_events/2 — filter by node_id" do
    test "filter %{node_id: 'a'} returns only events with payload.node_id == 'a'" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{node_id: "a"})

      assert is_list(filtered)
      # op_started_a and op_completed_a
      assert length(filtered) == 2,
             "Expected 2 events for node 'a', got #{length(filtered)}: #{inspect(filtered)}"

      for e <- filtered do
        pl = e[:payload] || e["payload"] || %{}
        node = pl["node_id"] || pl[:node_id]

        assert node == "a",
               "Expected all events to have node_id 'a', got: #{inspect(e)}"
      end

      GenServer.stop(pid)
    end

    test "filter by node_id excludes run-level events (run_started, run_completed)" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{node_id: "a"})

      types = Enum.map(filtered, fn e -> e[:event_type] || e["event_type"] end)

      refute "run_started" in types,
             "run_started should not appear when filtering by node_id. Got: #{inspect(types)}"

      refute "run_completed" in types,
             "run_completed should not appear when filtering by node_id. Got: #{inspect(types)}"

      GenServer.stop(pid)
    end

    test "filter %{node_id: 'b'} returns only events for node 'b'" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{node_id: "b"})

      assert length(filtered) == 2,
             "Expected 2 events for node 'b', got #{length(filtered)}"

      for e <- filtered do
        pl = e[:payload] || e["payload"] || %{}
        node = pl["node_id"] || pl[:node_id]
        assert node == "b"
      end

      GenServer.stop(pid)
    end

    test "filter by nonexistent node_id returns empty list" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)
      send_full_run(run_id)

      filtered = Server.get_events(pid, %{node_id: "nonexistent"})

      assert filtered == [],
             "Expected empty list for unknown node_id, got: #{inspect(filtered)}"

      GenServer.stop(pid)
    end
  end

  # ── PubSub event topic ─────────────────────────────────────────────

  describe "Server PubSub — observation:{run_id}:events topic" do
    test "each event is broadcast on the events topic" do
      run_id = unique_run_id()
      plan = simple_plan()

      topic = "observation:#{run_id}:events"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)

      send_pg_event(run_id, run_started_event(run_id))

      assert_receive {:event_update, ^run_id, event}, 500, "Expected to receive event on #{topic}"

      et = event[:event_type] || event["event_type"]
      assert et == "run_started"

      GenServer.stop(pid)
    end

    test "events topic receives each event independently" do
      run_id = unique_run_id()
      plan = simple_plan()

      topic = "observation:#{run_id}:events"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)

      send_pg_event(run_id, run_started_event(run_id))
      send_pg_event(run_id, op_started_event("a"))

      assert_receive {:event_update, ^run_id, e1}, 500
      assert_receive {:event_update, ^run_id, e2}, 500

      t1 = e1[:event_type] || e1["event_type"]
      t2 = e2[:event_type] || e2["event_type"]

      assert t1 == "run_started"
      assert t2 == "op_started"

      GenServer.stop(pid)
    end
  end
end
