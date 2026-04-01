defmodule Liminara.Run.GateIntegrationTest do
  @moduledoc """
  Integration tests for M-OBS-05a: Gate handling in Run.Server.

  Covers:
  - Run pauses at a gate node (status :running, gate node :waiting, downstream :pending)
  - resolve_gate/3 unblocks the run and allows completion
  - gate_requested and gate_resolved events appear in the event log
  - Downstream nodes execute after gate resolution
  - Run completes with :success after gate resolution
  - gate node state transitions: pending → running → waiting → completed

  All tests will fail (red phase) until DemoOps.Approve is implemented.
  The gate infrastructure in Run.Server already exists; only the op is missing.
  """
  use ExUnit.Case, async: false

  alias Liminara.{Event, Plan}
  alias Liminara.Run.Server, as: RunServer

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  # Plan: input_node → gate_node → output_node
  # input_node: pure Upcase op (runs immediately)
  # gate_node: DemoOps.Approve (pauses for human approval)
  # output_node: pure Reverse op (blocked until gate resolves)
  defp gate_pipeline_plan do
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

  # Plan: gate_node only (no upstream, no downstream)
  defp single_gate_plan do
    Plan.new()
    |> Plan.add_node("gate_node", Liminara.DemoOps.Approve, %{
      "text" => {:literal, "approve this please"}
    })
  end

  defp start_run(run_id, plan, opts \\ []) do
    RunServer.start(run_id, plan, opts)
  end

  # ── Run pauses at gate — does not complete automatically ──────────────────

  describe "run pauses at gate node" do
    test "run with gate does not complete automatically — times out on await" do
      run_id = unique_run_id("pause")
      plan = gate_pipeline_plan()

      {:ok, _pid} = start_run(run_id, plan)

      # The run should NOT complete until the gate is resolved.
      # Use a short timeout to verify it blocks.
      assert {:error, :timeout} = RunServer.await(run_id, 500),
             "Expected run to block at gate (timeout), but it completed or failed"
    end

    test "run status is :running while gate node is waiting" do
      run_id = unique_run_id("running-status")
      plan = gate_pipeline_plan()

      {:ok, pid} = start_run(run_id, plan)
      # Give the run time to start and hit the gate
      Process.sleep(200)

      state = :sys.get_state(pid)

      # Run is still in progress (not completed/failed)
      assert state.result == nil,
             "Expected run result to be nil while waiting at gate, got: #{inspect(state.result)}"
    end

    test "gate node transitions to :waiting status" do
      run_id = unique_run_id("waiting-node")
      plan = gate_pipeline_plan()

      {:ok, pid} = start_run(run_id, plan)
      Process.sleep(200)

      state = :sys.get_state(pid)

      assert state.node_states["gate_node"] == :waiting,
             "Expected gate_node to be :waiting, got: #{inspect(state.node_states["gate_node"])}"
    end

    test "upstream nodes complete before gate blocks" do
      run_id = unique_run_id("upstream-complete")
      plan = gate_pipeline_plan()

      {:ok, pid} = start_run(run_id, plan)
      Process.sleep(200)

      state = :sys.get_state(pid)

      assert state.node_states["input_node"] == :completed,
             "Expected input_node to be :completed (ran before gate), got: #{inspect(state.node_states["input_node"])}"
    end

    test "downstream nodes remain :pending while gate is waiting" do
      run_id = unique_run_id("downstream-pending")
      plan = gate_pipeline_plan()

      {:ok, pid} = start_run(run_id, plan)
      Process.sleep(200)

      state = :sys.get_state(pid)

      assert state.node_states["output_node"] == :pending,
             "Expected output_node to remain :pending while gate is waiting, got: #{inspect(state.node_states["output_node"])}"
    end

    test "single gate plan: gate node is :waiting after start" do
      run_id = unique_run_id("single-gate")
      plan = single_gate_plan()

      {:ok, pid} = start_run(run_id, plan)
      Process.sleep(200)

      state = :sys.get_state(pid)

      assert state.node_states["gate_node"] == :waiting,
             "Expected gate_node to be :waiting, got: #{inspect(state.node_states["gate_node"])}"
    end
  end

  # ── gate_requested event is emitted ───────────────────────────────────────

  describe "gate_requested event" do
    test "gate_requested event is emitted when gate node starts" do
      run_id = unique_run_id("gr-event")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(300)

      {:ok, events} = Event.Store.read_all(run_id)
      event_types = Enum.map(events, & &1["event_type"])

      assert "gate_requested" in event_types,
             "Expected gate_requested event in log, got: #{inspect(event_types)}"
    end

    test "gate_requested event payload contains node_id" do
      run_id = unique_run_id("gr-payload")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(300)

      {:ok, events} = Event.Store.read_all(run_id)

      gate_event =
        Enum.find(events, fn e -> e["event_type"] == "gate_requested" end)

      assert gate_event != nil, "Expected gate_requested event to exist"

      assert gate_event["payload"]["node_id"] == "gate_node",
             "Expected gate_requested payload node_id == 'gate_node', got: #{inspect(gate_event["payload"]["node_id"])}"
    end

    test "gate_requested event payload contains prompt" do
      run_id = unique_run_id("gr-prompt")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(300)

      {:ok, events} = Event.Store.read_all(run_id)

      gate_event = Enum.find(events, fn e -> e["event_type"] == "gate_requested" end)

      assert gate_event != nil, "Expected gate_requested event to exist"
      prompt = gate_event["payload"]["prompt"]

      assert is_binary(prompt) and prompt != "",
             "Expected gate_requested payload to have a non-empty prompt, got: #{inspect(prompt)}"
    end
  end

  # ── resolve_gate/3 unblocks the run ───────────────────────────────────────

  describe "resolve_gate/3 — approve" do
    test "resolve_gate with 'approved' completes the run" do
      run_id = unique_run_id("resolve-approve")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")

      assert {:ok, result} = RunServer.await(run_id, 2000),
             "Expected run to complete after gate resolution"

      assert result.status == :success,
             "Expected run status :success after approval, got: #{inspect(result.status)}"
    end

    test "resolve_gate transitions gate node from :waiting to :completed" do
      run_id = unique_run_id("resolve-state")
      plan = single_gate_plan()

      {:ok, pid} = start_run(run_id, plan)
      Process.sleep(200)

      assert :sys.get_state(pid).node_states["gate_node"] == :waiting

      RunServer.resolve_gate(run_id, "gate_node", "approved")

      {:ok, result} = RunServer.await(run_id, 2000)

      assert result.node_states["gate_node"] == :completed,
             "Expected gate_node to be :completed after resolution, got: #{inspect(result.node_states["gate_node"])}"
    end

    test "downstream nodes execute after gate resolution" do
      run_id = unique_run_id("resolve-downstream")
      plan = gate_pipeline_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")

      {:ok, result} = RunServer.await(run_id, 2000)

      assert result.status == :success

      assert result.node_states["output_node"] == :completed,
             "Expected output_node to complete after gate resolution, got: #{inspect(result.node_states["output_node"])}"
    end

    test "all nodes complete after gate resolution" do
      run_id = unique_run_id("resolve-all-nodes")
      plan = gate_pipeline_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")

      {:ok, result} = RunServer.await(run_id, 2000)

      assert result.status == :success

      for {node_id, status} <- result.node_states do
        assert status == :completed,
               "Expected node #{node_id} to be :completed, got: #{inspect(status)}"
      end
    end
  end

  # ── resolve_gate/3 — reject ───────────────────────────────────────────────

  describe "resolve_gate/3 — reject" do
    test "resolve_gate with 'rejected' also unblocks and completes the run" do
      run_id = unique_run_id("resolve-reject")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "rejected")

      assert {:ok, result} = RunServer.await(run_id, 2000),
             "Expected run to complete after rejection"

      # The run itself completes; what happens next (downstream) is up to the pack
      assert result.status in [:success, :failed],
             "Expected run to reach a terminal state, got: #{inspect(result.status)}"
    end

    test "resolve_gate with :reject atom also works" do
      run_id = unique_run_id("resolve-reject-atom")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", :rejected)

      assert {:ok, _result} = RunServer.await(run_id, 2000)
    end
  end

  # ── gate_resolved event is emitted ────────────────────────────────────────

  describe "gate_resolved event" do
    test "gate_resolved event is emitted after resolve_gate/3" do
      run_id = unique_run_id("gr-resolved-event")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      {:ok, events} = Event.Store.read_all(run_id)
      event_types = Enum.map(events, & &1["event_type"])

      assert "gate_resolved" in event_types,
             "Expected gate_resolved event in log, got: #{inspect(event_types)}"
    end

    test "gate_resolved event payload contains node_id and response" do
      run_id = unique_run_id("gr-resolved-payload")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      {:ok, events} = Event.Store.read_all(run_id)

      resolved_event = Enum.find(events, fn e -> e["event_type"] == "gate_resolved" end)

      assert resolved_event != nil, "Expected gate_resolved event to exist"
      assert resolved_event["payload"]["node_id"] == "gate_node"
      assert resolved_event["payload"]["response"] == "approved"
    end

    test "both gate_requested and gate_resolved events appear in log" do
      run_id = unique_run_id("gr-both-events")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      {:ok, events} = Event.Store.read_all(run_id)
      event_types = Enum.map(events, & &1["event_type"])

      assert "gate_requested" in event_types,
             "Expected gate_requested in event log. Got: #{inspect(event_types)}"

      assert "gate_resolved" in event_types,
             "Expected gate_resolved in event log. Got: #{inspect(event_types)}"
    end

    test "gate_requested appears before gate_resolved in the event log" do
      run_id = unique_run_id("gr-order")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      {:ok, events} = Event.Store.read_all(run_id)
      event_types = Enum.map(events, & &1["event_type"])

      requested_idx = Enum.find_index(event_types, &(&1 == "gate_requested"))
      resolved_idx = Enum.find_index(event_types, &(&1 == "gate_resolved"))

      assert requested_idx != nil, "gate_requested event must exist"
      assert resolved_idx != nil, "gate_resolved event must exist"

      assert requested_idx < resolved_idx,
             "gate_requested must appear before gate_resolved in the event log"
    end
  end

  # ── Event log integrity after gate ────────────────────────────────────────

  describe "event log integrity after gate resolution" do
    test "event log hash chain is valid after a gate run" do
      run_id = unique_run_id("gate-chain")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      assert {:ok, count} = Event.Store.verify(run_id)
      assert count > 0, "Expected non-zero event count"
    end

    test "event log for full pipeline with gate has valid hash chain" do
      run_id = unique_run_id("gate-pipeline-chain")
      plan = gate_pipeline_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      assert {:ok, count} = Event.Store.verify(run_id)
      assert count > 0
    end

    test "gate decision is recorded in decision store" do
      run_id = unique_run_id("gate-decision")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)

      {:ok, events} = Event.Store.read_all(run_id)
      event_types = Enum.map(events, & &1["event_type"])

      assert "decision_recorded" in event_types,
             "Expected decision_recorded event after gate resolution, got: #{inspect(event_types)}"
    end
  end

  # ── resolve_gate with no waiting node is a no-op ──────────────────────────

  describe "resolve_gate edge cases" do
    test "resolve_gate for a non-waiting node is ignored (no crash)" do
      run_id = unique_run_id("ignore-nonwaiting")

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})

      {:ok, _pid} = start_run(run_id, plan)
      {:ok, _result} = RunServer.await(run_id, 2000)

      # Calling resolve_gate on a run that has no waiting gate should not crash.
      # The result is ignored — we only verify no exception is raised.
      _result = RunServer.resolve_gate(run_id, "a", "approved")
      assert true, "resolve_gate on non-waiting node should not raise"
    end

    test "resolve_gate on completed run returns :error (run not found)" do
      run_id = unique_run_id("resolve-done-run")
      plan = single_gate_plan()

      {:ok, _pid} = start_run(run_id, plan)
      Process.sleep(200)

      # Resolve the gate to let the run finish
      RunServer.resolve_gate(run_id, "gate_node", "approved")
      {:ok, _result} = RunServer.await(run_id, 2000)
      # Wait for server to exit
      Process.sleep(100)

      # Now the server is gone — resolve_gate should return {:error, :not_found}
      result = RunServer.resolve_gate(run_id, "gate_node", "approved")

      assert result == {:error, :not_found},
             "Expected {:error, :not_found} when resolving after run completes, got: #{inspect(result)}"
    end
  end
end
