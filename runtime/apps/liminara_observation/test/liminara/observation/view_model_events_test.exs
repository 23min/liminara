defmodule Liminara.Observation.ViewModelEventsTest do
  @moduledoc """
  Tests for M-OBS-04b: ViewModel event storage — the `events` field, configurable cap,
  and filtering by event_type / node_id.

  These tests will fail (red phase) until ViewModel.apply_event/2 begins appending
  to a new `events` field and ViewModel gains `filter_events/2`.
  """
  use ExUnit.Case, async: true

  alias Liminara.Observation.ViewModel
  alias Liminara.Plan

  # ── Helpers ────────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp run_started_event(run_id) do
    %{
      event_hash: "sha256:start",
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

  defp op_started_event(node_id, ts \\ "2026-03-19T14:00:01.000Z") do
    %{
      event_hash: "sha256:op_started_#{node_id}",
      event_type: "op_started",
      payload: %{
        "node_id" => node_id,
        "op_id" => "upcase",
        "op_version" => "1.0",
        "determinism" => "pure",
        "input_hashes" => []
      },
      prev_hash: "sha256:start",
      timestamp: ts
    }
  end

  defp op_completed_event(node_id, ts \\ "2026-03-19T14:00:02.000Z") do
    %{
      event_hash: "sha256:op_completed_#{node_id}",
      event_type: "op_completed",
      payload: %{
        "node_id" => node_id,
        "output_hashes" => ["sha256:out1"],
        "cache_hit" => false,
        "duration_ms" => 42
      },
      prev_hash: "sha256:op_started_#{node_id}",
      timestamp: ts
    }
  end

  defp decision_recorded_event(node_id) do
    %{
      event_hash: "sha256:decision_#{node_id}",
      event_type: "decision_recorded",
      payload: %{
        "node_id" => node_id,
        "decision_hash" => "sha256:dec1",
        "decision_type" => "llm_response"
      },
      prev_hash: "sha256:op_started_#{node_id}",
      timestamp: "2026-03-19T14:00:02.500Z"
    }
  end

  defp run_completed_event(run_id) do
    %{
      event_hash: "sha256:run_completed",
      event_type: "run_completed",
      payload: %{
        "run_id" => run_id,
        "outcome" => "success",
        "artifact_hashes" => []
      },
      prev_hash: "sha256:op_completed_a",
      timestamp: "2026-03-19T14:00:05.000Z"
    }
  end

  # ── ViewModel `events` field exists ────────────────────────────────

  describe "ViewModel.init/2 — events field" do
    test "init produces a ViewModel with an `events` field" do
      plan = simple_plan()
      state = ViewModel.init("run-events-init", plan)

      # ViewModel struct must have an `events` key after M-OBS-04b is implemented
      assert Map.has_key?(state, :events),
             "Expected ViewModel to have an :events field, got keys: #{inspect(Map.keys(state))}"
    end

    test "initial events list is empty" do
      plan = simple_plan()
      state = ViewModel.init("run-events-empty", plan)

      assert state.events == [],
             "Expected events to start empty, got: #{inspect(state.events)}"
    end
  end

  # ── apply_event appends to events list ─────────────────────────────

  describe "ViewModel.apply_event/2 — events accumulation" do
    test "applying one event populates the events list with one entry" do
      run_id = "vm-events-one"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert length(state.events) == 1,
             "Expected 1 event in list, got #{length(state.events)}"
    end

    test "applying multiple events accumulates them in order" do
      run_id = "vm-events-multi"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))

      assert length(state.events) == 3,
             "Expected 3 events in list, got #{length(state.events)}"
    end

    test "events list is in chronological (append) order" do
      run_id = "vm-events-order"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))

      types = Enum.map(state.events, fn e -> e[:event_type] || e["event_type"] end)

      assert types == ["run_started", "op_started", "op_completed"],
             "Expected chronological order, got: #{inspect(types)}"
    end

    test "each stored event retains its original data (event_type present)" do
      run_id = "vm-events-data"
      plan = simple_plan()
      event = run_started_event(run_id)

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(event)

      stored = hd(state.events)
      event_type = stored[:event_type] || stored["event_type"]

      assert event_type == "run_started",
             "Expected stored event to have event_type 'run_started', got: #{inspect(stored)}"
    end

    test "events list grows for all event types including decision_recorded" do
      run_id = "vm-events-decision"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      assert length(state.events) == 5,
             "Expected 5 events, got #{length(state.events)}"
    end
  end

  # ── Events cap (oldest-first drop) ──────────────────────────────────

  describe "ViewModel — events cap (oldest-first eviction)" do
    test "applying events beyond the default cap drops oldest events" do
      # The default cap is at most 1000 events according to the spec.
      # We test with a small configurable cap by initialising via ViewModel.init/3.
      # If ViewModel.init/3 with a cap option is not yet implemented, this test will
      # fail at compile time or raise — which is intentional (red phase).
      run_id = "vm-events-cap"
      plan = simple_plan()

      # init with explicit cap of 3
      state = ViewModel.init(run_id, plan, events_cap: 3)

      state =
        state
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a", "2026-03-19T14:00:01.000Z"))
        |> ViewModel.apply_event(op_completed_event("a", "2026-03-19T14:00:02.000Z"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      # With cap=3, 4 events were applied — only 3 should remain (oldest dropped)
      assert length(state.events) == 3,
             "Expected cap of 3, got #{length(state.events)} events"
    end

    test "the dropped event is the oldest (first inserted)" do
      run_id = "vm-events-cap-drop"
      plan = simple_plan()

      state = ViewModel.init(run_id, plan, events_cap: 3)

      e1 = run_started_event(run_id)
      e2 = op_started_event("a")
      e3 = op_completed_event("a")
      e4 = run_completed_event(run_id)

      state =
        state
        |> ViewModel.apply_event(e1)
        |> ViewModel.apply_event(e2)
        |> ViewModel.apply_event(e3)
        |> ViewModel.apply_event(e4)

      # First event (run_started) should have been evicted
      types = Enum.map(state.events, fn e -> e[:event_type] || e["event_type"] end)

      refute "run_started" in types,
             "Expected oldest event (run_started) to be evicted, but got: #{inspect(types)}"

      assert "run_completed" in types,
             "Expected newest event (run_completed) to remain, but got: #{inspect(types)}"
    end

    test "events list never exceeds the configured cap" do
      run_id = "vm-events-never-exceeds"
      plan = simple_plan()
      cap = 2

      state = ViewModel.init(run_id, plan, events_cap: cap)

      events_to_apply = [
        run_started_event(run_id),
        op_started_event("a"),
        op_completed_event("a"),
        run_completed_event(run_id)
      ]

      final_state =
        Enum.reduce(events_to_apply, state, fn e, acc ->
          ViewModel.apply_event(acc, e)
        end)

      assert length(final_state.events) <= cap,
             "Events list exceeded cap of #{cap}, got #{length(final_state.events)}"
    end

    test "cap of 1 keeps only the most recent event" do
      run_id = "vm-events-cap-one"
      plan = simple_plan()

      state = ViewModel.init(run_id, plan, events_cap: 1)

      e1 = run_started_event(run_id)
      e2 = op_started_event("a")

      state =
        state
        |> ViewModel.apply_event(e1)
        |> ViewModel.apply_event(e2)

      assert length(state.events) == 1
      [only_event] = state.events
      event_type = only_event[:event_type] || only_event["event_type"]

      assert event_type == "op_started",
             "Expected only the most recent event (op_started) to remain, got: #{inspect(event_type)}"
    end
  end

  # ── ViewModel.filter_events/2 ───────────────────────────────────────

  describe "ViewModel.filter_events/2 — by event_type" do
    test "filter by event_type returns only matching events" do
      run_id = "vm-filter-type"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(op_started_event("b"))
        |> ViewModel.apply_event(op_completed_event("b"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      filtered = ViewModel.filter_events(state, %{event_type: "op_completed"})

      assert is_list(filtered),
             "Expected filter_events to return a list"

      assert length(filtered) == 2,
             "Expected 2 op_completed events, got #{length(filtered)}: #{inspect(filtered)}"

      for e <- filtered do
        assert (e[:event_type] || e["event_type"]) == "op_completed"
      end
    end

    test "filter by event_type with no matches returns empty list" do
      run_id = "vm-filter-type-empty"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_completed_event(run_id))

      filtered = ViewModel.filter_events(state, %{event_type: "decision_recorded"})

      assert filtered == [],
             "Expected empty list for unmatched filter, got: #{inspect(filtered)}"
    end

    test "filter by string event_type key also works (string-keyed events)" do
      run_id = "vm-filter-type-str"
      plan = simple_plan()

      str_event = %{
        "event_hash" => "sha256:op_started_a",
        "event_type" => "op_started",
        "payload" => %{"node_id" => "a"},
        "prev_hash" => nil,
        "timestamp" => "2026-03-19T14:00:01.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(str_event)

      filtered = ViewModel.filter_events(state, %{event_type: "op_started"})

      assert length(filtered) == 1,
             "Expected 1 op_started event, got #{length(filtered)}"
    end
  end

  describe "ViewModel.filter_events/2 — by node_id" do
    test "filter by node_id returns only events for that node" do
      run_id = "vm-filter-node"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(op_started_event("b"))
        |> ViewModel.apply_event(op_completed_event("b"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      # Only events whose payload.node_id == "a"
      filtered = ViewModel.filter_events(state, %{node_id: "a"})

      assert is_list(filtered)

      for e <- filtered do
        pl = e[:payload] || e["payload"] || %{}
        node = pl["node_id"] || pl[:node_id]

        assert node == "a",
               "Expected node_id 'a', but event has: #{inspect(e)}"
      end
    end

    test "filter by node_id excludes run-level events (no payload.node_id)" do
      run_id = "vm-filter-node-run-events"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      filtered = ViewModel.filter_events(state, %{node_id: "a"})

      # run_started and run_completed have no node_id in payload — should be excluded
      types = Enum.map(filtered, fn e -> e[:event_type] || e["event_type"] end)

      refute "run_started" in types,
             "run_started should be excluded when filtering by node_id. Got: #{inspect(types)}"

      refute "run_completed" in types,
             "run_completed should be excluded when filtering by node_id. Got: #{inspect(types)}"
    end

    test "filter by node_id with no matches returns empty list" do
      run_id = "vm-filter-node-empty"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_completed_event(run_id))

      filtered = ViewModel.filter_events(state, %{node_id: "nonexistent_node"})

      assert filtered == []
    end
  end

  describe "ViewModel.filter_events/2 — empty filter (no-op)" do
    test "empty filter map returns all events" do
      run_id = "vm-filter-empty"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      filtered = ViewModel.filter_events(state, %{})

      assert length(filtered) == length(state.events),
             "Empty filter should return all #{length(state.events)} events, got #{length(filtered)}"
    end
  end
end
