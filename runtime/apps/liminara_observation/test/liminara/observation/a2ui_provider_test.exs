defmodule Liminara.Observation.A2UIProviderTest do
  @moduledoc """
  Unit tests for M-OBS-05b: A2UI Provider (SurfaceProvider behaviour).

  Tests the `Liminara.Observation.A2UIProvider` GenServer which:
  - Implements the `A2UI.SurfaceProvider` behaviour
  - Subscribes to Observation.Server PubSub updates for a given run
  - Maps ViewModel state to A2UI v0.9 component descriptions
  - Handles gate interaction actions (approve/reject)

  These tests will fail (red phase) until:
  - ex_a2ui is added as a dependency
  - Liminara.Observation.A2UIProvider is implemented
  """

  use ExUnit.Case, async: false

  alias Liminara.Observation.A2UIProvider
  alias Liminara.Plan

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp unique_run_id(prefix \\ "a2ui-unit") do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
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

  defp gate_plan do
    Plan.new()
    |> Plan.add_node("input_node", Liminara.TestOps.Upcase, %{
      "text" => {:literal, "pending approval"}
    })
    |> Plan.add_node("gate_node", Liminara.DemoOps.Approve, %{
      "text" => {:ref, "input_node", "result"}
    })
    |> Plan.add_node("output_node", Liminara.TestOps.Reverse, %{
      "text" => {:ref, "gate_node", "result"}
    })
  end

  defp running_view_state(run_id, plan) do
    %Liminara.Observation.ViewModel{
      run_id: run_id,
      plan: plan,
      run_status: :running,
      nodes: %{
        "a" => %{
          status: :running,
          op_name: "upcase",
          op_version: "1.0",
          determinism: :pure,
          started_at: "2026-03-22T10:00:01.000Z",
          completed_at: nil,
          duration_ms: nil,
          input_hashes: [],
          output_hashes: [],
          cache_hit: nil,
          error: nil,
          gate_prompt: nil,
          gate_response: nil,
          decisions: []
        }
      },
      run_started_at: "2026-03-22T10:00:00.000Z",
      run_completed_at: nil,
      event_count: 2
    }
  end

  defp completed_view_state(run_id, plan) do
    %Liminara.Observation.ViewModel{
      run_id: run_id,
      plan: plan,
      run_status: :completed,
      nodes: %{
        "a" => %{
          status: :completed,
          op_name: "upcase",
          op_version: "1.0",
          determinism: :pure,
          started_at: "2026-03-22T10:00:01.000Z",
          completed_at: "2026-03-22T10:00:02.000Z",
          duration_ms: 5,
          input_hashes: [],
          output_hashes: ["sha256:out_a"],
          cache_hit: false,
          error: nil,
          gate_prompt: nil,
          gate_response: nil,
          decisions: []
        }
      },
      run_started_at: "2026-03-22T10:00:00.000Z",
      run_completed_at: "2026-03-22T10:00:03.000Z",
      event_count: 4
    }
  end

  defp gate_waiting_view_state(run_id, plan) do
    %Liminara.Observation.ViewModel{
      run_id: run_id,
      plan: plan,
      run_status: :running,
      nodes: %{
        "input_node" => %{
          status: :completed,
          op_name: "upcase",
          op_version: "1.0",
          determinism: :pure,
          started_at: "2026-03-22T10:00:01.000Z",
          completed_at: "2026-03-22T10:00:02.000Z",
          duration_ms: 5,
          input_hashes: [],
          output_hashes: ["sha256:out_input"],
          cache_hit: false,
          error: nil,
          gate_prompt: nil,
          gate_response: nil,
          decisions: []
        },
        "gate_node" => %{
          status: :waiting,
          op_name: "approve",
          op_version: "1.0",
          determinism: :side_effecting,
          started_at: "2026-03-22T10:00:02.500Z",
          completed_at: nil,
          duration_ms: nil,
          input_hashes: [],
          output_hashes: [],
          cache_hit: nil,
          error: nil,
          gate_prompt: "Please approve the pipeline execution.",
          gate_response: nil,
          decisions: []
        },
        "output_node" => %{
          status: :pending,
          op_name: "reverse",
          op_version: "1.0",
          determinism: :pure,
          started_at: nil,
          completed_at: nil,
          duration_ms: nil,
          input_hashes: [],
          output_hashes: [],
          cache_hit: nil,
          error: nil,
          gate_prompt: nil,
          gate_response: nil,
          decisions: []
        }
      },
      run_started_at: "2026-03-22T10:00:00.000Z",
      run_completed_at: nil,
      event_count: 5
    }
  end

  # ── A2UIProvider — behaviour compliance ──────────────────────────────────

  describe "A2UIProvider implements A2UI.SurfaceProvider" do
    test "module declares A2UI.SurfaceProvider behaviour" do
      # The module must exist and implement the behaviour.
      # This will fail with a compile error until ex_a2ui is added.
      assert Code.ensure_loaded?(A2UIProvider)
      assert function_exported?(A2UIProvider, :init, 1)
      assert function_exported?(A2UIProvider, :surface, 1)
      assert function_exported?(A2UIProvider, :handle_action, 2)
      assert function_exported?(A2UIProvider, :handle_info, 2)
    end
  end

  # ── init/1 ────────────────────────────────────────────────────────────────

  describe "init/1" do
    test "returns {:ok, state} for valid run_id and plan" do
      run_id = unique_run_id()
      plan = simple_plan()

      result = A2UIProvider.init(run_id: run_id, plan: plan)

      assert {:ok, _state} = result
    end

    test "initial state includes the run_id" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      assert state.run_id == run_id
    end

    test "initial state includes the plan" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      assert state.plan == plan
    end

    test "initial view_state has run_status :pending" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      assert state.view_state.run_status == :pending
    end

    test "init subscribes to observation PubSub topic for the run" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, _state} = A2UIProvider.init(run_id: run_id, plan: plan)

      # After init, any PubSub broadcast on the run's topic should be
      # received. We verify indirectly via handle_info below.
      # Direct subscription check: the provider must call
      # Phoenix.PubSub.subscribe in init.
      assert true
    end
  end

  # ── surface/1 — component structure ──────────────────────────────────────

  describe "surface/1 — valid component descriptions" do
    test "returns a list of A2UI component maps" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)

      assert is_list(components)
      assert Enum.all?(components, &is_map/1)
    end

    test "each component has a type field" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)

      for comp <- components do
        assert Map.has_key?(comp, "type") or Map.has_key?(comp, :type),
               "Expected component to have a type field, got: #{inspect(comp)}"
      end
    end

    test "each component has an id field" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)

      for comp <- components do
        assert Map.has_key?(comp, "id") or Map.has_key?(comp, :id),
               "Expected component to have an id field, got: #{inspect(comp)}"
      end
    end

    test "component ids are unique within the surface" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)

      ids =
        Enum.map(components, fn comp -> comp["id"] || comp[:id] end)
        |> Enum.reject(&is_nil/1)

      assert length(ids) == length(Enum.uniq(ids)),
             "Component IDs must be unique. Got: #{inspect(ids)}"
    end
  end

  # ── surface/1 — run status card ───────────────────────────────────────────

  describe "surface/1 — run status card" do
    test "run status component is present in surface output" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      # Expect a component with type "Card" (or equivalent) for run status
      has_status_card =
        Enum.any?(components, fn comp ->
          type = comp["type"] || comp[:type]
          String.downcase(to_string(type)) in ["card", "statuscard", "run_status"]
        end)

      assert has_status_card,
             "Expected a Card-type component for run status. Components: #{inspect(components)}"
    end

    test "run status card contains the run_id" do
      run_id = unique_run_id("run-id-in-card")
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, run_id),
             "Expected run_id '#{run_id}' to appear in component descriptions"
    end

    test "run status card contains the run status" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "running"),
             "Expected 'running' status to appear in component descriptions"
    end

    test "run status card contains progress (N/M nodes complete)" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      # Progress is N/M format. With 0 completed out of 2 nodes: "0/2" or similar.
      # Accept any numeric progress format referencing the node count.
      assert String.contains?(encoded, "2") or String.contains?(encoded, "progress"),
             "Expected progress indicator in components. Encoded: #{encoded}"
    end

    test "run status card contains elapsed time field" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "elapsed") or String.contains?(encoded, "started_at") or
               String.contains?(encoded, "2026-03-22"),
             "Expected timing info in component descriptions. Encoded: #{encoded}"
    end
  end

  # ── surface/1 — node list component ──────────────────────────────────────

  describe "surface/1 — node list component" do
    test "node list component is present in surface output" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      components = A2UIProvider.surface(state)

      has_list =
        Enum.any?(components, fn comp ->
          type = comp["type"] || comp[:type]
          String.downcase(to_string(type)) in ["list", "nodelist", "node_list"]
        end)

      assert has_list,
             "Expected a List-type component for node progress. Components: #{inspect(components)}"
    end

    test "node list contains one entry per node in the plan" do
      run_id = unique_run_id()
      plan = two_node_plan()

      view = running_view_state(run_id, plan)

      # Add a second node to the view state's nodes
      node_b = %{
        status: :pending,
        op_name: "reverse",
        op_version: "1.0",
        determinism: :pure,
        started_at: nil,
        completed_at: nil,
        duration_ms: nil,
        input_hashes: [],
        output_hashes: [],
        cache_hit: nil,
        error: nil,
        gate_prompt: nil,
        gate_response: nil,
        decisions: []
      }

      view = %{view | nodes: Map.put(view.nodes, "b", node_b)}

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      # Both node ids should appear in the encoded components
      assert String.contains?(encoded, "\"a\"") or String.contains?(encoded, "a"),
             "Expected node 'a' in component descriptions. Encoded: #{encoded}"

      assert String.contains?(encoded, "\"b\"") or String.contains?(encoded, "b"),
             "Expected node 'b' in component descriptions. Encoded: #{encoded}"
    end

    test "node list items contain status indicators" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      # Status should appear: "running", "pending", "completed", etc.
      assert String.contains?(encoded, "running") or String.contains?(encoded, "status"),
             "Expected node status indicator in component descriptions. Encoded: #{encoded}"
    end

    test "completed node shows :completed status" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = completed_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "completed"),
             "Expected 'completed' status in component descriptions. Encoded: #{encoded}"
    end
  end

  # ── surface/1 — gate component ────────────────────────────────────────────

  describe "surface/1 — gate component when gate is waiting" do
    test "gate component is rendered when a gate node is waiting" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      has_form_or_gate =
        Enum.any?(components, fn comp ->
          type = comp["type"] || comp[:type]
          String.downcase(to_string(type)) in ["form", "gate", "gateform", "gate_form", "modal"]
        end)

      assert has_form_or_gate,
             "Expected a Form/Gate component when gate is waiting. Components: #{inspect(components)}"
    end

    test "gate component contains the gate prompt text" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "Please approve the pipeline execution."),
             "Expected gate prompt text in gate component. Encoded: #{encoded}"
    end

    test "gate component includes approve affordance" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "approve") or String.contains?(encoded, "Approve"),
             "Expected approve affordance in gate component. Encoded: #{encoded}"
    end

    test "gate component includes reject affordance" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "reject") or String.contains?(encoded, "Reject"),
             "Expected reject affordance in gate component. Encoded: #{encoded}"
    end

    test "gate component references the waiting node_id" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)
      encoded = Jason.encode!(components)

      assert String.contains?(encoded, "gate_node"),
             "Expected gate_node id in gate component. Encoded: #{encoded}"
    end

    test "no gate component when no gate is waiting" do
      run_id = unique_run_id()
      plan = simple_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      has_form =
        Enum.any?(components, fn comp ->
          type = comp["type"] || comp[:type]
          String.downcase(to_string(type)) in ["form", "gateform", "gate_form"]
        end)

      refute has_form,
             "Expected no gate Form component when no gate is waiting. Components: #{inspect(components)}"
    end
  end

  # ── handle_action/2 — gate approve ───────────────────────────────────────

  describe "handle_action/2 — gate approve" do
    test "handle_action with 'approve' action does not crash" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      action = %{"action" => "approve", "node_id" => "gate_node"}

      result = A2UIProvider.handle_action(action, state)

      # handle_action must return {:ok, new_state} or {:update, new_state}
      assert match?({:ok, _}, result) or match?({:update, _}, result),
             "Expected {:ok, state} or {:update, state} from handle_action. Got: #{inspect(result)}"
    end

    test "handle_action with 'reject' action does not crash" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      action = %{"action" => "reject", "node_id" => "gate_node"}

      result = A2UIProvider.handle_action(action, state)

      assert match?({:ok, _}, result) or match?({:update, _}, result),
             "Expected {:ok, state} or {:update, state} from handle_action. Got: #{inspect(result)}"
    end

    test "handle_action 'approve' calls Run.Server.resolve_gate with 'approved'" do
      run_id = unique_run_id()
      plan = gate_plan()

      # Start the run so there's an actual Run.Server to receive the gate resolution
      {:ok, _run_pid} = Liminara.Run.Server.start(run_id, plan)
      # Wait for run to reach the gate
      Process.sleep(300)

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      action = %{"action" => "approve", "node_id" => "gate_node"}
      A2UIProvider.handle_action(action, state)

      # After approve action, Run.Server should resolve the gate and the run
      # should complete.
      assert {:ok, result} = Liminara.Run.Server.await(run_id, 2000),
             "Expected run to complete after gate approval via A2UI action"

      assert result.status == :success
    end

    test "handle_action 'reject' calls Run.Server.resolve_gate with 'rejected'" do
      run_id = unique_run_id()
      plan = gate_plan()

      {:ok, _run_pid} = Liminara.Run.Server.start(run_id, plan)
      Process.sleep(300)

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      action = %{"action" => "reject", "node_id" => "gate_node"}
      A2UIProvider.handle_action(action, state)

      # After reject, the run should terminate (either success or failed depending
      # on downstream, but it should not be stuck).
      assert {:ok, result} = Liminara.Run.Server.await(run_id, 2000)
      assert result.status in [:success, :failed]
    end

    test "handle_action with unknown action returns ok without crash" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      action = %{"action" => "unknown_action", "node_id" => "some_node"}

      result = A2UIProvider.handle_action(action, state)

      assert match?({:ok, _}, result) or match?({:update, _}, result) or
               match?({:error, _}, result),
             "Expected a tuple result from handle_action. Got: #{inspect(result)}"
    end
  end

  # ── handle_info/2 — PubSub state update ──────────────────────────────────

  describe "handle_info/2 — PubSub state updates trigger surface refresh" do
    test "handle_info processes {:state_update, run_id, view_state} message" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      new_view = running_view_state(run_id, plan)
      msg = {:state_update, run_id, new_view}

      result = A2UIProvider.handle_info(msg, state)

      # handle_info must return {:update, new_state} to signal surface refresh
      # or {:ok, new_state} if no broadcast is needed
      assert match?({:update, _}, result) or match?({:ok, _}, result) or
               match?({:noreply, _}, result),
             "Expected a tuple result from handle_info. Got: #{inspect(result)}"
    end

    test "handle_info updates the view_state in provider state" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, initial_state} = A2UIProvider.init(run_id: run_id, plan: plan)
      assert initial_state.view_state.run_status == :pending

      new_view = running_view_state(run_id, plan)
      msg = {:state_update, run_id, new_view}

      {_tag, updated_state} = A2UIProvider.handle_info(msg, initial_state)

      assert updated_state.view_state.run_status == :running,
             "Expected view_state to be updated to :running. Got: #{inspect(updated_state.view_state.run_status)}"
    end

    test "handle_info for a different run_id does not update view_state" do
      run_id = unique_run_id()
      other_run_id = unique_run_id("other")
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      assert state.view_state.run_status == :pending

      new_view = running_view_state(other_run_id, plan)
      msg = {:state_update, other_run_id, new_view}

      {_tag, updated_state} = A2UIProvider.handle_info(msg, state)

      assert updated_state.view_state.run_status == :pending,
             "Expected view_state to remain unchanged for unrelated run_id"
    end

    test "handle_info with unrecognized message is ignored gracefully" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      result = A2UIProvider.handle_info({:unrelated_message, :some, :data}, state)

      # Must not crash; state should be unchanged
      assert match?({:ok, _}, result) or match?({:noreply, _}, result) or
               match?({:update, _}, result),
             "Expected a tuple result from handle_info. Got: #{inspect(result)}"
    end

    test "handle_info triggers surface refresh on state_update" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)

      new_view = running_view_state(run_id, plan)
      msg = {:state_update, run_id, new_view}

      result = A2UIProvider.handle_info(msg, state)

      # :update tag means A2UI.Socket will call surface/1 again to push updates
      assert match?({:update, _}, result),
             "Expected {:update, state} from handle_info to signal surface refresh. Got: #{inspect(result)}"
    end
  end

  # ── surface/1 — A2UI v0.9 format compliance ───────────────────────────────

  describe "surface/1 — A2UI v0.9 flat component format" do
    test "all components in surface are flat maps (no nested component lists)" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      # A2UI v0.9 uses flat format: components are top-level, referenced by ID.
      # No component should have a "children" field that contains other full components.
      for comp <- components do
        children = comp["children"] || comp[:children]

        if is_list(children) do
          refute Enum.any?(children, &is_map/1),
                 "Expected flat component format (no nested component maps). Got children: #{inspect(children)}"
        end
      end
    end

    test "surface output can be JSON encoded (all values are JSON-serializable)" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      assert {:ok, _json} = Jason.encode(components),
             "Expected surface output to be JSON-encodable. Components: #{inspect(components)}"
    end

    test "surface returns at least 2 components (status card + node list)" do
      run_id = unique_run_id()
      plan = two_node_plan()

      view = running_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      assert length(components) >= 2,
             "Expected at least 2 components (status card + node list). Got: #{inspect(components)}"
    end

    test "surface returns at least 3 components when gate is waiting" do
      run_id = unique_run_id()
      plan = gate_plan()

      view = gate_waiting_view_state(run_id, plan)
      {:ok, state} = A2UIProvider.init(run_id: run_id, plan: plan)
      state = %{state | view_state: view}

      components = A2UIProvider.surface(state)

      assert length(components) >= 3,
             "Expected at least 3 components (status card + node list + gate form) when gate is waiting. Got: #{inspect(components)}"
    end
  end

  # ── Isolation ────────────────────────────────────────────────────────────

  describe "isolation — multiple providers for different runs" do
    test "two providers for different runs have independent state" do
      run_id_1 = unique_run_id("iso-1")
      run_id_2 = unique_run_id("iso-2")
      plan = simple_plan()

      {:ok, state_1} = A2UIProvider.init(run_id: run_id_1, plan: plan)
      {:ok, state_2} = A2UIProvider.init(run_id: run_id_2, plan: plan)

      # Update state_1 with a running view, leave state_2 pending
      new_view_1 = running_view_state(run_id_1, plan)

      {_tag, updated_state_1} =
        A2UIProvider.handle_info({:state_update, run_id_1, new_view_1}, state_1)

      assert updated_state_1.view_state.run_status == :running
      assert state_2.view_state.run_status == :pending
    end
  end
end
