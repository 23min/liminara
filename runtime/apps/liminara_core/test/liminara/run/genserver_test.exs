defmodule Liminara.Run.GenServerTest do
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event, Plan, Run}

  # These tests verify the GenServer-based Run.Server (M-OTP-02).
  # The Run.Server is started under Run.DynamicSupervisor, registered
  # in Run.Registry, dispatches ops as supervised Tasks, and supports
  # fan-out, fan-in, replay, and cache.

  # ── GenServer lifecycle ──────────────────────────────────────────

  describe "GenServer lifecycle" do
    test "starting a Run.Server registers it in the Registry" do
      run_id = "lifecycle-registry-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = start_run_server(run_id, single_op_plan())

      assert [{^pid, _}] = Registry.lookup(Liminara.Run.Registry, run_id)
      await_run(run_id)
    end

    test "Run.Server is findable via Registry.lookup" do
      run_id = "lifecycle-lookup-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = start_run_server(run_id, single_op_plan())

      [{found_pid, _}] = Registry.lookup(Liminara.Run.Registry, run_id)
      assert found_pid == pid
      await_run(run_id)
    end

    test "completed run: server exits normally" do
      run_id = "lifecycle-complete-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = start_run_server(run_id, single_op_plan())
      ref = Process.monitor(pid)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      # Server should exit normally
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "failed run: server exits normally (not a crash)" do
      run_id = "lifecycle-fail-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Fail, %{"data" => {:literal, "x"}})

      {:ok, pid} = start_run_server(run_id, plan)
      ref = Process.monitor(pid)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :failed

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  # ── Execution flow ───────────────────────────────────────────────

  describe "execution flow" do
    test "single-op plan completes" do
      run_id = "flow-single-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id, single_op_plan())

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success
      assert Map.has_key?(result.outputs, "a")

      {:ok, content} = Artifact.Store.get(result.outputs["a"]["result"])
      assert content == "HELLO"
    end

    test "linear 3-op plan: ops execute in sequence" do
      run_id = "flow-linear-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Identity, %{"result" => {:ref, "b", "result"}})

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      {:ok, content} = Artifact.Store.get(result.outputs["c"]["result"])
      assert content == "OLLEH"
    end

    test "fan-out plan (A → B, A → C): B and C dispatched concurrently" do
      run_id = "flow-fanout-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "fan"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Identity, %{"result" => {:ref, "a", "result"}})

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      {:ok, b_content} = Artifact.Store.get(result.outputs["b"]["result"])
      {:ok, c_content} = Artifact.Store.get(result.outputs["c"]["result"])
      assert b_content == "NAF"
      assert c_content == "FAN"
    end

    test "fan-in plan (A → C, B → C): C dispatched only after both complete" do
      run_id = "flow-fanin-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("b", Liminara.TestOps.Upcase, %{"text" => {:literal, "world"}})
        |> Plan.add_node("c", Liminara.TestOps.Concat, %{
          "a" => {:ref, "a", "result"},
          "b" => {:ref, "b", "result"}
        })

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      {:ok, content} = Artifact.Store.get(result.outputs["c"]["result"])
      assert content == "HELLOWORLD"
    end

    test "diamond plan (A → B, A → C, B → D, C → D): D waits for both" do
      run_id = "flow-diamond-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Identity, %{"result" => {:ref, "a", "result"}})
        |> Plan.add_node("d", Liminara.TestOps.Concat, %{
          "a" => {:ref, "b", "result"},
          "b" => {:ref, "c", "result"}
        })

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      {:ok, content} = Artifact.Store.get(result.outputs["d"]["result"])
      assert content == "IHHI"
    end
  end

  # ── Event recording ──────────────────────────────────────────────

  describe "event recording" do
    test "all events written with valid hash chain" do
      run_id = "events-chain-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "chain"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      start_run_server(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id)

      assert {:ok, count} = Event.Store.verify(run_id)
      assert count > 0
    end

    test "event types emitted in order for linear plan" do
      run_id = "events-types-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "order"}})

      start_run_server(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id)

      {:ok, events} = Event.Store.read_all(run_id)
      types = Enum.map(events, & &1["event_type"])
      assert types == ["run_started", "op_started", "op_completed", "run_completed"]
    end

    test "failed node emits op_failed event" do
      run_id = "events-fail-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Fail, %{"data" => {:literal, "x"}})

      start_run_server(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id)

      {:ok, events} = Event.Store.read_all(run_id)
      types = Enum.map(events, & &1["event_type"])
      assert "op_failed" in types
      assert "run_failed" in types
    end

    test "run seal is computed on completion" do
      run_id = "events-seal-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id, single_op_plan())
      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      # The seal should have been written — verify via read_all
      {:ok, events} = Event.Store.read_all(run_id)
      final_hash = List.last(events)["event_hash"]
      assert is_binary(final_hash)
    end
  end

  # ── Artifacts and cache ──────────────────────────────────────────

  describe "artifacts and cache" do
    test "output artifacts stored in artifact store" do
      run_id = "cache-artifacts-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id, single_op_plan())
      {:ok, result} = Run.Server.await(run_id)

      hash = result.outputs["a"]["result"]
      assert hash =~ ~r/^sha256:/
      {:ok, content} = Artifact.Store.get(hash)
      assert content == "HELLO"
    end

    test "pure op results are cached (second run cache hit)" do
      # First run
      run_id1 = "cache-hit1-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, single_op_plan())
      {:ok, _result1} = Run.Server.await(run_id1)

      # Second run with same plan
      run_id2 = "cache-hit2-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, single_op_plan())
      {:ok, _result2} = Run.Server.await(run_id2)

      {:ok, events} = Event.Store.read_all(run_id2)

      completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "a"
        end)

      assert completed["payload"]["cache_hit"] == true
    end

    test "recordable ops are not cached" do
      plan =
        Plan.new()
        |> Plan.add_node("gen", Liminara.TestOps.Recordable, %{
          "prompt" => {:literal, "test"}
        })

      # First run
      run_id1 = "cache-recordable1-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, _r1} = Run.Server.await(run_id1)

      # Second run
      run_id2 = "cache-recordable2-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan)
      {:ok, _r2} = Run.Server.await(run_id2)

      {:ok, events} = Event.Store.read_all(run_id2)

      completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "gen"
        end)

      assert completed["payload"]["cache_hit"] == false
    end
  end

  # ── Replay ───────────────────────────────────────────────────────

  describe "replay" do
    test "replay injects stored decisions for recordable ops" do
      plan = discovery_plan()

      # Discovery run
      run_id1 = "replay-inject1-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      # Replay
      run_id2 = "replay-inject2-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)
      assert replay.status == :success

      # Recordable op output should match
      {:ok, disc_content} = Artifact.Store.get(discovery.outputs["transform"]["result"])
      {:ok, replay_content} = Artifact.Store.get(replay.outputs["transform"]["result"])
      assert disc_content == replay_content
    end

    test "side-effecting ops are skipped on replay" do
      plan = discovery_plan()

      run_id1 = "replay-skip1-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, _discovery} = Run.Server.await(run_id1)

      run_id2 = "replay-skip2-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, _replay} = Run.Server.await(run_id2)

      {:ok, events} = Event.Store.read_all(run_id2)

      save_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "save"
        end)

      assert save_completed["payload"]["cache_hit"] == true
    end

    test "replay produces matching output for pure ops" do
      plan = discovery_plan()

      run_id1 = "replay-pure1-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)

      run_id2 = "replay-pure2-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert discovery.outputs["load"] == replay.outputs["load"]
    end
  end

  # ── Await API ────────────────────────────────────────────────────

  describe "await API" do
    test "await returns result after run completes" do
      run_id = "await-ok-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id, single_op_plan())

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success
      assert result.run_id == run_id
    end

    test "await returns result after run fails" do
      run_id = "await-fail-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Fail, %{"data" => {:literal, "x"}})

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :failed
    end

    test "await times out if run doesn't complete" do
      run_id = "await-timeout-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "slow"}})

      start_run_server(run_id, plan)

      assert {:error, :timeout} = Run.Server.await(run_id, 50)
    end
  end

  # ── Introspection ────────────────────────────────────────────────

  describe "introspection" do
    test ":sys.get_state returns state with plan, node_states, run_id" do
      run_id = "intro-state-#{:erlang.unique_integer([:positive])}"

      # Use a slow op so we can inspect mid-run
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "inspect"}})

      {:ok, pid} = start_run_server(run_id, plan)

      # Give it a moment to start
      Process.sleep(10)

      state = :sys.get_state(pid)
      assert state.run_id == run_id
      assert %Plan{} = state.plan
      assert is_map(state.node_states)

      # Clean up — let the slow op finish
      await_run(run_id)
    end
  end

  # ── Public API ───────────────────────────────────────────────────

  describe "public API" do
    test "Liminara.run/3 starts Run.Server and returns result" do
      {:ok, result} = Liminara.run(Liminara.TestPack, "genserver test")
      assert result.status == :success
      assert is_binary(result.run_id)
    end

    test "Liminara.replay/4 replays through Run.Server" do
      {:ok, discovery} = Liminara.run(Liminara.TestPack, "replay api test")

      {:ok, replay} =
        Liminara.replay(Liminara.TestPack, "replay api test", discovery.run_id)

      assert replay.status == :success
      assert discovery.outputs["load"] == replay.outputs["load"]
      assert discovery.outputs["transform"] == replay.outputs["transform"]
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

  defp start_run_server(run_id, plan, opts \\ []) do
    Run.Server.start(run_id, plan, opts)
  end

  defp await_run(run_id) do
    Run.Server.await(run_id, 5000)
  end
end
