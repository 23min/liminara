defmodule Liminara.Observation.A2UIIntegrationTest do
  @moduledoc """
  Integration tests for M-OBS-05b: A2UI WebSocket endpoint and end-to-end gate interaction.

  These tests verify:
  - A test WebSocket client can connect to the A2UI endpoint
  - Client receives initial surface state (createSurface + updateComponents messages)
  - Client receives updates as run events occur
  - Gate approval via A2UI action resolves the gate in Run.Server
  - Multiple clients receive the same updates
  - Client disconnect is handled gracefully

  All tests are tagged @tag :integration and will fail (red phase) until:
  - ex_a2ui is added as a dependency
  - A2UI.Supervisor is started in the observation or web application
  - The A2UI WebSocket endpoint is mounted at a configurable path
  - Liminara.Observation.A2UIProvider is implemented
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Liminara.{Plan, Run}
  alias Liminara.Observation.{Server, A2UIProvider}

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
  end

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

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  # Resolves the A2UI WebSocket endpoint URL for integration tests.
  # The implementation must expose this config or a well-known default.
  defp a2ui_ws_url(run_id) do
    port = Application.get_env(:liminara_observation, :a2ui_port, 4001)
    path = Application.get_env(:liminara_observation, :a2ui_path, "/a2ui/ws")
    "ws://localhost:#{port}#{path}?run_id=#{run_id}"
  end

  # Connect a minimal test WebSocket client.
  # Returns the connected client process or raises if connection fails.
  defp connect_test_client(run_id) do
    url = a2ui_ws_url(run_id)
    # Use A2UI.Socket test client or a simple WebSocket client.
    # The implementation must provide a way to connect a test client.
    # A2UI.TestClient.connect/1 is expected from ex_a2ui.
    A2UI.TestClient.connect(url)
  end

  # Collect A2UI messages from the WebSocket client within a timeout.
  defp collect_messages(client, timeout) do
    collect_messages_loop(client, [], deadline(timeout))
  end

  defp deadline(timeout_ms) do
    System.monotonic_time(:millisecond) + timeout_ms
  end

  defp collect_messages_loop(client, acc, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Enum.reverse(acc)
    else
      case A2UI.TestClient.receive(client, min(remaining, 100)) do
        {:ok, msg} -> collect_messages_loop(client, [msg | acc], deadline)
        {:timeout, _} -> Enum.reverse(acc)
        {:error, _} -> Enum.reverse(acc)
      end
    end
  end

  # Await a specific message type from the client.
  defp await_message_type(client, type, timeout \\ 2000) do
    deadline = deadline(timeout)
    await_message_type_loop(client, type, deadline)
  end

  defp await_message_type_loop(client, type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      flunk("Timed out waiting for message type '#{type}' from A2UI WebSocket client")
    else
      case A2UI.TestClient.receive(client, min(remaining, 100)) do
        {:ok, %{"type" => ^type} = msg} ->
          msg

        {:ok, _other} ->
          await_message_type_loop(client, type, deadline)

        {:timeout, _} ->
          await_message_type_loop(client, type, deadline)

        {:error, reason} ->
          flunk("WebSocket error while waiting for '#{type}': #{inspect(reason)}")
      end
    end
  end

  # ── A2UI Supervisor is running ────────────────────────────────────────────

  describe "A2UI endpoint availability" do
    @tag :integration
    test "A2UI.Supervisor is running as part of the application" do
      # The implementation must start A2UI.Supervisor in the supervision tree.
      # We verify it is alive by checking for the process.
      assert A2UI.Supervisor.running?(),
             "Expected A2UI.Supervisor to be running. Add it to the application supervision tree."
    end

    @tag :integration
    test "A2UI WebSocket endpoint accepts connections" do
      run_id = unique_run_id("ws-connect")

      assert {:ok, client} = connect_test_client(run_id),
             "Expected A2UI WebSocket endpoint to accept connections at #{a2ui_ws_url(run_id)}"

      A2UI.TestClient.disconnect(client)
    end
  end

  # ── Initial surface on connect ────────────────────────────────────────────

  describe "WebSocket — initial state on connect" do
    @tag :integration
    test "client receives createSurface message on connection" do
      run_id = unique_run_id("ws-initial")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      msg = await_message_type(client, "createSurface")

      assert msg["type"] == "createSurface",
             "Expected 'createSurface' message. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "createSurface message includes components list" do
      run_id = unique_run_id("ws-create-surface")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      msg = await_message_type(client, "createSurface")

      assert is_list(msg["components"]),
             "Expected createSurface to have a 'components' list. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "createSurface components are non-empty for a pending run" do
      run_id = unique_run_id("ws-nonempty-surface")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      msg = await_message_type(client, "createSurface")

      assert msg["components"] != [],
             "Expected at least one component in createSurface. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "initial surface includes run_id in component data" do
      run_id = unique_run_id("ws-runid-in-surface")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      msg = await_message_type(client, "createSurface")
      encoded = Jason.encode!(msg)

      assert String.contains?(encoded, run_id),
             "Expected run_id '#{run_id}' to appear in createSurface message. Got: #{encoded}"

      A2UI.TestClient.disconnect(client)
    end
  end

  # ── Streaming updates as run events occur ────────────────────────────────

  describe "WebSocket — streaming updates as run events occur" do
    @tag :integration
    test "client receives updateComponents message after run starts" do
      run_id = unique_run_id("ws-update")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      # Drain the initial createSurface
      _initial = await_message_type(client, "createSurface")

      # Start the run — events will flow
      Run.Server.start(run_id, plan)

      msg = await_message_type(client, "updateComponents", 3000)

      assert msg["type"] == "updateComponents",
             "Expected 'updateComponents' message after run starts. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "updateComponents message includes component updates list" do
      run_id = unique_run_id("ws-update-list")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      {:ok, _} = Run.Server.await(run_id, 3000)

      msg = await_message_type(client, "updateComponents", 3000)

      assert is_list(msg["updates"]) or is_list(msg["components"]),
             "Expected updateComponents to have an 'updates' or 'components' list. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "client receives update showing run status as running after start" do
      run_id = unique_run_id("ws-running-status")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)

      # Collect updates over 2 seconds
      messages = collect_messages(client, 2000)
      all_encoded = Jason.encode!(messages)

      assert String.contains?(all_encoded, "running"),
             "Expected 'running' status to appear in streamed updates. Messages: #{all_encoded}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "client receives update showing completed status after run finishes" do
      run_id = unique_run_id("ws-completed")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 3000)
      assert result.status == :success

      messages = collect_messages(client, 2000)
      all_encoded = Jason.encode!(messages)

      assert String.contains?(all_encoded, "completed"),
             "Expected 'completed' status in streamed updates. Messages: #{all_encoded}"

      A2UI.TestClient.disconnect(client)
    end
  end

  # ── Gate interaction via A2UI ─────────────────────────────────────────────

  describe "gate interaction — client sees gate and resolves it" do
    @tag :integration
    test "client receives gate component when gate node is waiting" do
      run_id = unique_run_id("ws-gate-waiting")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      # Start the run — it will pause at the gate
      Run.Server.start(run_id, plan)
      Process.sleep(500)

      # Collect updates — one of them should contain a gate component
      messages = collect_messages(client, 1000)
      all_encoded = Jason.encode!(messages)

      assert String.contains?(all_encoded, "approve") or String.contains?(all_encoded, "gate"),
             "Expected gate component (approve/reject) in updates. Messages: #{all_encoded}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "gate component contains the prompt text" do
      run_id = unique_run_id("ws-gate-prompt")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(500)

      messages = collect_messages(client, 1000)
      all_encoded = Jason.encode!(messages)

      # The gate prompt from DemoOps.Approve is "Please approve: <text>"
      assert String.contains?(all_encoded, "approve") or
               String.contains?(all_encoded, "Please approve"),
             "Expected gate prompt in streamed updates. Messages: #{all_encoded}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "sending approve action via A2UI resolves the gate in Run.Server" do
      run_id = unique_run_id("ws-gate-approve")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(500)

      # Send the approve action via A2UI interaction protocol
      A2UI.TestClient.send_action(client, %{
        "action" => "approve",
        "node_id" => "gate_node"
      })

      # The gate should resolve and the run should complete
      assert {:ok, result} = Run.Server.await(run_id, 3000),
             "Expected run to complete after A2UI gate approval"

      assert result.status == :success

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "after gate approval, client receives updateComponents with completed gate node" do
      run_id = unique_run_id("ws-gate-approved-update")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(500)

      A2UI.TestClient.send_action(client, %{
        "action" => "approve",
        "node_id" => "gate_node"
      })

      {:ok, _result} = Run.Server.await(run_id, 3000)

      messages = collect_messages(client, 2000)
      all_encoded = Jason.encode!(messages)

      assert String.contains?(all_encoded, "completed"),
             "Expected 'completed' in updates after gate approval. Messages: #{all_encoded}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "full roundtrip: connect → see gate → approve → run completes" do
      run_id = unique_run_id("ws-full-roundtrip")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      # Step 1: receive initial surface
      initial = await_message_type(client, "createSurface")
      assert initial["type"] == "createSurface"

      # Step 2: start run and wait for gate
      Run.Server.start(run_id, plan)
      Process.sleep(500)

      # Step 3: collect updates to see the gate component
      gate_updates = collect_messages(client, 1000)
      gate_encoded = Jason.encode!(gate_updates)

      assert String.contains?(gate_encoded, "gate_node") or
               String.contains?(gate_encoded, "approve"),
             "Expected gate state in updates before approval. Messages: #{gate_encoded}"

      # Step 4: send approve action
      A2UI.TestClient.send_action(client, %{
        "action" => "approve",
        "node_id" => "gate_node"
      })

      # Step 5: run should complete
      assert {:ok, result} = Run.Server.await(run_id, 3000)
      assert result.status == :success

      # Step 6: receive completion updates
      completion_updates = collect_messages(client, 2000)
      completion_encoded = Jason.encode!(completion_updates)

      assert String.contains?(completion_encoded, "completed"),
             "Expected completion state in final updates. Messages: #{completion_encoded}"

      A2UI.TestClient.disconnect(client)
    end
  end

  # ── Multiple concurrent clients ────────────────────────────────────────────

  describe "multiple concurrent clients" do
    @tag :integration
    test "two clients both receive createSurface on connection" do
      run_id = unique_run_id("ws-two-clients")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client1} = connect_test_client(run_id)
      {:ok, client2} = connect_test_client(run_id)

      msg1 = await_message_type(client1, "createSurface")
      msg2 = await_message_type(client2, "createSurface")

      assert msg1["type"] == "createSurface"
      assert msg2["type"] == "createSurface"

      A2UI.TestClient.disconnect(client1)
      A2UI.TestClient.disconnect(client2)
    end

    @tag :integration
    test "both clients receive updateComponents when run events occur" do
      run_id = unique_run_id("ws-two-updates")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client1} = connect_test_client(run_id)
      {:ok, client2} = connect_test_client(run_id)

      _init1 = await_message_type(client1, "createSurface")
      _init2 = await_message_type(client2, "createSurface")

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 3000)

      msgs1 = collect_messages(client1, 2000)
      msgs2 = collect_messages(client2, 2000)

      assert msgs1 != [],
             "Expected client1 to receive updates. Got no messages."

      assert msgs2 != [],
             "Expected client2 to receive updates. Got no messages."

      A2UI.TestClient.disconnect(client1)
      A2UI.TestClient.disconnect(client2)
    end

    @tag :integration
    test "both clients receive the same gate component when gate is waiting" do
      run_id = unique_run_id("ws-two-gate")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client1} = connect_test_client(run_id)
      {:ok, client2} = connect_test_client(run_id)

      _init1 = await_message_type(client1, "createSurface")
      _init2 = await_message_type(client2, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(500)

      msgs1 = collect_messages(client1, 1000)
      msgs2 = collect_messages(client2, 1000)

      enc1 = Jason.encode!(msgs1)
      enc2 = Jason.encode!(msgs2)

      assert String.contains?(enc1, "gate_node") or String.contains?(enc1, "approve"),
             "Expected client1 to see gate state. Messages: #{enc1}"

      assert String.contains?(enc2, "gate_node") or String.contains?(enc2, "approve"),
             "Expected client2 to see gate state. Messages: #{enc2}"

      A2UI.TestClient.disconnect(client1)
      A2UI.TestClient.disconnect(client2)
    end

    @tag :integration
    test "gate resolved by one client is seen by both clients" do
      run_id = unique_run_id("ws-gate-both-see-resolve")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client1} = connect_test_client(run_id)
      {:ok, client2} = connect_test_client(run_id)

      _init1 = await_message_type(client1, "createSurface")
      _init2 = await_message_type(client2, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(500)

      # client1 resolves the gate
      A2UI.TestClient.send_action(client1, %{
        "action" => "approve",
        "node_id" => "gate_node"
      })

      {:ok, _result} = Run.Server.await(run_id, 3000)

      # Both clients should see the completion updates
      msgs2 = collect_messages(client2, 2000)
      enc2 = Jason.encode!(msgs2)

      assert String.contains?(enc2, "completed"),
             "Expected client2 to see completion after client1 approved gate. Messages: #{enc2}"

      A2UI.TestClient.disconnect(client1)
      A2UI.TestClient.disconnect(client2)
    end
  end

  # ── Client disconnect ─────────────────────────────────────────────────────

  describe "client disconnect — graceful handling" do
    @tag :integration
    test "disconnecting a client does not crash the A2UI server" do
      run_id = unique_run_id("ws-disconnect")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      A2UI.TestClient.disconnect(client)

      # Give the server time to handle the disconnect
      Process.sleep(200)

      # A2UI.Supervisor should still be alive — disconnect must not crash anything
      assert A2UI.Supervisor.running?(),
             "Expected A2UI.Supervisor to still be running after client disconnect"
    end

    @tag :integration
    test "second client can connect after first client disconnects" do
      run_id = unique_run_id("ws-reconnect")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client1} = connect_test_client(run_id)
      _initial1 = await_message_type(client1, "createSurface")
      A2UI.TestClient.disconnect(client1)

      Process.sleep(200)

      {:ok, client2} = connect_test_client(run_id)
      msg2 = await_message_type(client2, "createSurface", 2000)

      assert msg2["type"] == "createSurface",
             "Expected second client to receive createSurface after first disconnects. Got: #{inspect(msg2)}"

      A2UI.TestClient.disconnect(client2)
    end

    @tag :integration
    test "run can continue after all A2UI clients disconnect" do
      run_id = unique_run_id("ws-run-after-disconnect")
      plan = gate_pipeline_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)
      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)
      Process.sleep(300)

      # Disconnect the client while the run is paused at the gate
      A2UI.TestClient.disconnect(client)
      Process.sleep(200)

      # Resolve the gate directly — run should still work
      Run.Server.resolve_gate(run_id, "gate_node", "approved")

      assert {:ok, result} = Run.Server.await(run_id, 3000)

      assert result.status == :success,
             "Expected run to complete after client disconnect + direct gate resolution"
    end

    @tag :integration
    test "no leaked state after client disconnect (no messages to disconnected client)" do
      run_id = unique_run_id("ws-no-leak")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)
      _initial = await_message_type(client, "createSurface")

      A2UI.TestClient.disconnect(client)
      Process.sleep(200)

      # Start run after disconnect — should not raise or produce errors
      # (no delivery attempt to disconnected client)
      assert {:ok, _pid} = Run.Server.start(run_id, plan)
      assert {:ok, result} = Run.Server.await(run_id, 3000)
      assert result.status == :success
    end
  end

  # ── A2UI wire format compliance (v0.9) ────────────────────────────────────

  describe "A2UI v0.9 wire format" do
    @tag :integration
    test "createSurface message has required top-level fields" do
      run_id = unique_run_id("ws-wire-create")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      msg = await_message_type(client, "createSurface")

      assert Map.has_key?(msg, "type"), "createSurface must have 'type' field"
      assert Map.has_key?(msg, "components"), "createSurface must have 'components' field"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "updateComponents message has required top-level fields" do
      run_id = unique_run_id("ws-wire-update")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      _initial = await_message_type(client, "createSurface")

      Run.Server.start(run_id, plan)

      msg = await_message_type(client, "updateComponents", 3000)

      assert Map.has_key?(msg, "type"), "updateComponents must have 'type' field"

      assert Map.has_key?(msg, "updates") or Map.has_key?(msg, "components"),
             "updateComponents must have 'updates' or 'components' field. Got: #{inspect(msg)}"

      A2UI.TestClient.disconnect(client)
    end

    @tag :integration
    test "all WebSocket messages are valid JSON" do
      run_id = unique_run_id("ws-json-valid")
      plan = simple_plan()

      {:ok, _obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      {:ok, client} = connect_test_client(run_id)

      # Receive initial message as raw string and verify JSON parseable
      raw = A2UI.TestClient.receive_raw(client, 2000)

      assert is_binary(raw), "Expected raw WebSocket message to be a binary string"
      assert {:ok, _parsed} = Jason.decode(raw), "Expected valid JSON in WebSocket message"

      A2UI.TestClient.disconnect(client)
    end
  end

  # ── A2UIProvider started as part of Observation.Server ──────────────────

  describe "A2UIProvider GenServer lifecycle" do
    @tag :integration
    test "A2UIProvider can be started as a standalone GenServer for a run" do
      run_id = unique_run_id("provider-lifecycle")
      plan = simple_plan()

      result = GenServer.start(A2UIProvider, run_id: run_id, plan: plan)

      assert match?({:ok, _pid}, result),
             "Expected A2UIProvider to start successfully as a GenServer. Got: #{inspect(result)}"

      {:ok, pid} = result
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    @tag :integration
    test "stopping A2UIProvider GenServer does not crash the run" do
      run_id = unique_run_id("provider-stop-safe")
      plan = simple_plan()

      {:ok, provider_pid} = GenServer.start(A2UIProvider, run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      Process.sleep(100)

      # Stop the provider mid-run
      GenServer.stop(provider_pid)
      Process.sleep(100)

      refute Process.alive?(provider_pid)

      # Run should complete normally
      assert {:ok, result} = Run.Server.await(run_id, 3000)
      assert result.status == :success
    end
  end
end
