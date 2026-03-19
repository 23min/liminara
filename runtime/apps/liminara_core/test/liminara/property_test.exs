defmodule Liminara.PropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Liminara.{Event, Plan, Run}

  # M-OTP-05: Property-based stress tests for the OTP runtime layer.

  @moduletag timeout: 120_000

  # Use a session-unique prefix to avoid collisions with stale run data
  @session_id :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  describe "DAG generator validity" do
    property "all generated plans are valid" do
      check all(plan <- Liminara.Generators.dag_plan(), max_runs: 100) do
        assert :ok = Plan.validate(plan)
      end
    end

    property "generated plans have at least one node" do
      check all(plan <- Liminara.Generators.dag_plan(), max_runs: 50) do
        assert map_size(plan.nodes) >= 1
      end
    end
  end

  describe "termination invariant" do
    property "every plan terminates within 5 seconds" do
      check all(plan <- Liminara.Generators.dag_plan(), max_runs: 100) do
        run_id = "prop-term-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        Run.Server.start(run_id, plan)

        case Run.Server.await(run_id, 5000) do
          {:ok, result} ->
            assert result.status in [:success, :failed, :partial]

          {:error, :timeout} ->
            flunk("Run #{run_id} did not terminate within 5 seconds")
        end
      end
    end
  end

  describe "event integrity invariant" do
    property "every completed run has a valid hash chain" do
      check all(plan <- Liminara.Generators.dag_plan(), max_runs: 100) do
        run_id = "prop-integrity-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        Run.Server.start(run_id, plan)
        {:ok, _result} = Run.Server.await(run_id, 5000)

        assert {:ok, count} = Event.Store.verify(run_id)
        assert count > 0
      end
    end
  end

  describe "completeness invariant" do
    property "every node has a terminal event (completed or failed)" do
      check all(plan <- Liminara.Generators.dag_plan(), max_runs: 100) do
        run_id = "prop-complete-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        Run.Server.start(run_id, plan)
        {:ok, result} = Run.Server.await(run_id, 5000)

        {:ok, events} = Event.Store.read_all(run_id)

        # Every node in the plan should have at least an op_started event
        node_ids = Map.keys(plan.nodes)

        started_nodes =
          events
          |> Enum.filter(&(&1["event_type"] == "op_started"))
          |> Enum.map(& &1["payload"]["node_id"])
          |> MapSet.new()

        completed_or_failed =
          events
          |> Enum.filter(&(&1["event_type"] in ["op_completed", "op_failed"]))
          |> Enum.map(& &1["payload"]["node_id"])
          |> MapSet.new()

        # All started nodes should have a terminal event
        for node_id <- started_nodes do
          assert node_id in completed_or_failed,
                 "Node #{node_id} was started but has no terminal event"
        end

        # For successful runs, all nodes should have been started
        if result.status == :success do
          for node_id <- node_ids do
            assert node_id in started_nodes,
                   "Node #{node_id} was never started in a successful run. " <>
                     "Plan nodes: #{inspect(node_ids)}, " <>
                     "Started: #{inspect(MapSet.to_list(started_nodes))}, " <>
                     "Events: #{length(events)}, " <>
                     "Result node_states: #{inspect(result.node_states)}"
          end
        end
      end
    end
  end

  describe "determinism invariant" do
    property "same pure plan twice produces identical output hashes" do
      check all(
              plan <- Liminara.Generators.dag_plan(max_depth: 3, max_width: 3),
              max_runs: 50
            ) do
        run_id1 = "prop-det1-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        run_id2 = "prop-det2-#{@session_id}-#{:erlang.unique_integer([:positive])}"

        Run.Server.start(run_id1, plan)
        {:ok, result1} = Run.Server.await(run_id1, 5000)

        Run.Server.start(run_id2, plan)
        {:ok, result2} = Run.Server.await(run_id2, 5000)

        assert result1.status == result2.status

        if result1.status == :success do
          # Output hashes should be identical for pure ops
          for {node_id, outputs1} <- result1.outputs do
            outputs2 = result2.outputs[node_id]
            assert outputs1 == outputs2, "Output mismatch for node #{node_id}"
          end
        end
      end
    end
  end

  describe "isolation invariant" do
    property "concurrent runs produce independent valid event logs" do
      check all(
              plan1 <- Liminara.Generators.dag_plan(max_depth: 3, max_width: 3),
              plan2 <- Liminara.Generators.dag_plan(max_depth: 3, max_width: 3),
              max_runs: 50
            ) do
        run_id1 = "prop-iso1-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        run_id2 = "prop-iso2-#{@session_id}-#{:erlang.unique_integer([:positive])}"

        # Subscribe before starting so we get the result even if server exits fast
        :ok = Run.subscribe(run_id1)
        :ok = Run.subscribe(run_id2)

        Run.Server.start(run_id1, plan1)
        Run.Server.start(run_id2, plan2)

        # Await with fallback — server may exit before await
        await_or_events(run_id1)
        await_or_events(run_id2)

        assert {:ok, _} = Event.Store.verify(run_id1)
        assert {:ok, _} = Event.Store.verify(run_id2)

        Run.unsubscribe(run_id1)
        Run.unsubscribe(run_id2)
      end
    end
  end

  describe "crash resilience invariant" do
    property "random op failures: run terminates, event log valid" do
      check all(
              plan <- Liminara.Generators.dag_plan(include_failures: true),
              max_runs: 100
            ) do
        run_id = "prop-crash-#{@session_id}-#{:erlang.unique_integer([:positive])}"
        Run.Server.start(run_id, plan)
        {:ok, result} = Run.Server.await(run_id, 5000)

        assert result.status in [:success, :failed, :partial]
        assert {:ok, _} = Event.Store.verify(run_id)
      end
    end
  end

  # Wait for run completion, either via await or by waiting for events
  defp await_or_events(run_id) do
    case Run.Server.await(run_id, 5000) do
      {:ok, result} ->
        result

      {:error, :not_found} ->
        # Server already exited — check events
        wait_for_terminal_event(run_id)

      {:error, reason} when reason in [:not_found, :server_exited, {:crashed, :noproc}] ->
        # Server already exited — check events
        wait_for_terminal_event(run_id)

      {:error, :timeout} ->
        flunk("Run #{run_id} timed out")
    end
  end

  defp wait_for_terminal_event(run_id) do
    receive do
      {:run_event, ^run_id, %{event_type: type}} when type in ["run_completed", "run_failed"] ->
        :ok

      {:run_event, ^run_id, _} ->
        wait_for_terminal_event(run_id)
    after
      1000 ->
        # Check if already completed via event store
        {:ok, events} = Event.Store.read_all(run_id)
        last = List.last(events)

        if last && last["event_type"] in ["run_completed", "run_failed"] do
          :ok
        else
          flunk("Run #{run_id} has no terminal event")
        end
    end
  end
end
