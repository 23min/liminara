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

    test "await fallback preserves named output keys after the server exits" do
      run_id = "lifecycle-fallback-outputs-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Identity, %{
          "alpha" => {:literal, "one"},
          "beta" => {:literal, "two"}
        })

      {:ok, _pid} = start_run_server(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)

      assert result.status == :success
      Process.sleep(50)

      assert {:ok, rebuilt_result} = Run.Server.await(run_id)

      assert Map.has_key?(rebuilt_result.outputs["a"], "alpha")
      assert Map.has_key?(rebuilt_result.outputs["a"], "beta")

      {:ok, alpha} = Artifact.Store.get(rebuilt_result.outputs["a"]["alpha"])
      {:ok, beta} = Artifact.Store.get(rebuilt_result.outputs["a"]["beta"])

      assert alpha == "one"
      assert beta == "two"
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

    test "task-backed canonical execution specs run successfully in Run.Server" do
      run_id = "flow-task-spec-#{:erlang.unique_integer([:positive])}"

      plan =
        Plan.new()
        |> Plan.add_node("task", Liminara.TestOps.WithTaskExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      start_run_server(run_id, plan)

      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :success

      {:ok, content} = Artifact.Store.get(result.outputs["task"]["result"])
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

    test "explicit replay_policy can reexecute even when determinism class is side_effecting" do
      plan =
        Plan.new()
        |> Plan.add_node("replay", Liminara.TestOps.WithReplayReexecuteExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-policy-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)

      run_id2 = "replay-policy-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      refute replay.outputs["replay"] == %{}
      {:ok, content} = Artifact.Store.get(replay.outputs["replay"]["result"])
      assert content == "HELLO"

      {:ok, events} = Event.Store.read_all(run_id2)

      completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "replay"
        end)

      assert completed["payload"]["cache_hit"] == false
      assert discovery.status == :success
      assert replay.status == :success
    end

    test "replay reuses stored execution context for context-aware ops" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-context-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)

      run_id2 = "replay-context-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      {:ok, discovery_run_id} = Artifact.Store.get(discovery.outputs["ctx"]["run_id"])

      {:ok, discovery_started_at} =
        Artifact.Store.get(discovery.outputs["ctx"]["started_at"])

      {:ok, replay_run_id} = Artifact.Store.get(replay.outputs["ctx"]["run_id"])
      {:ok, replay_started_at} = Artifact.Store.get(replay.outputs["ctx"]["started_at"])

      assert replay_run_id == discovery_run_id
      assert replay_started_at == discovery_started_at
    end

    test "replay fails explicitly when a context-aware source run is missing execution_context.json" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-context-missing-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "execution_context.json"]))

      run_id2 = "replay-context-missing-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :failed
      assert replay.failed_nodes == ["ctx"]

      {:ok, events} = Event.Store.read_all(run_id2)
      run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
      op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

      assert run_started["payload"]["execution_context"] == nil
      assert op_failed["payload"]["error_type"] == "missing_replay_execution_context"
      refute File.exists?(Path.join([runs_root, run_id2, "execution_context.json"]))
    end

    test "replay with multiple context-aware roots emits one terminal failure event" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "alpha"}
        })
        |> Plan.add_node("b", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "beta"}
        })

      run_id1 = "replay-context-multi-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "execution_context.json"]))

      run_id2 = "replay-context-multi-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :failed
      assert Enum.sort(replay.failed_nodes) == ["a", "b"]

      {:ok, events} = Event.Store.read_all(run_id2)

      assert events |> Enum.filter(&(&1["event_type"] == "run_failed")) |> length() == 1

      assert events
             |> Enum.filter(&(&1["event_type"] == "op_failed"))
             |> Enum.map(& &1["payload"]["node_id"])
             |> Enum.sort() == ["a", "b"]

      assert List.last(events)["event_type"] == "run_failed"
    end

    test "replay_recorded context-aware ops still replay when the source execution context is missing" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.RecordableWithRuntimeContextExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-recordable-context-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "execution_context.json"]))

      run_id2 = "replay-recordable-context-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :success
      assert {:ok, replay_context} = Event.Store.read_execution_context(run_id2)
      assert replay_context.run_id == run_id2
      assert replay_context.replay_of_run_id == run_id1

      {:ok, replay_output_run_id} = Artifact.Store.get(replay.outputs["ctx"]["run_id"])
      assert replay_output_run_id == run_id1

      {:ok, events} = Event.Store.read_all(run_id2)
      run_started = Enum.find(events, &(&1["event_type"] == "run_started"))

      assert run_started["payload"]["execution_context"]["run_id"] == run_id2
    end

    test "replay_recorded context-aware ops fail explicitly when replay data is missing and the source context is missing" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.RecordableWithRuntimeContextExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id1 =
        "replay-recordable-context-missing-discovery-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "execution_context.json"]))
      File.rm!(Path.join([runs_root, run_id1, "decisions", "ctx.json"]))

      run_id2 = "replay-recordable-context-missing-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :failed
      assert replay.failed_nodes == ["ctx"]

      {:ok, events} = Event.Store.read_all(run_id2)
      run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
      op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

      assert run_started["payload"]["execution_context"] == nil
      assert op_failed["payload"]["error_type"] == "missing_replay_execution_context"
      refute File.exists?(Path.join([runs_root, run_id2, "execution_context.json"]))
    end

    test "replay_recorded context-aware ops fail explicitly when replay data is missing even if the source context exists" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.RecordableWithRuntimeContextExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-recordable-missing-data-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "decisions", "ctx.json"]))

      run_id2 = "replay-recordable-missing-data-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :failed
      assert replay.failed_nodes == ["ctx"]

      {:ok, events} = Event.Store.read_all(run_id2)
      op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

      assert op_failed["payload"]["error_type"] == "missing_replay_recording"
    end

    test "replay fails explicitly when a context-aware source run has invalid execution_context.json" do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "hello"}
        })

      run_id1 = "replay-context-invalid-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.write!(Path.join([runs_root, run_id1, "execution_context.json"]), "{bad json")

      run_id2 = "replay-context-invalid-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :failed
      assert replay.failed_nodes == ["ctx"]

      {:ok, events} = Event.Store.read_all(run_id2)
      run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
      op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

      assert run_started["payload"]["execution_context"] == nil
      assert op_failed["payload"]["error_type"] == "invalid_replay_execution_context"
      refute File.exists?(Path.join([runs_root, run_id2, "execution_context.json"]))
    end

    test "replay without context-aware ops still records replay-owned execution context" do
      plan = single_op_plan()

      run_id1 = "replay-no-context-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      runs_root = :sys.get_state(Liminara.Event.Store).runs_root
      File.rm!(Path.join([runs_root, run_id1, "execution_context.json"]))

      run_id2 = "replay-no-context-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)

      assert replay.status == :success
      assert {:ok, replay_context} = Event.Store.read_execution_context(run_id2)
      assert replay_context.run_id == run_id2
      assert replay_context.replay_of_run_id == run_id1

      {:ok, events} = Event.Store.read_all(run_id2)
      run_started = Enum.find(events, &(&1["event_type"] == "run_started"))

      assert run_started["payload"]["execution_context"]["run_id"] == run_id2
    end

    test "recordable replay preserves warnings alongside stored decisions in Run.Server" do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.RecordableWithWarningExecutionSpec, %{
          "prompt" => {:literal, "hello"}
        })

      run_id1 = "replay-warning-discovery-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id1, plan)
      {:ok, discovery} = Run.Server.await(run_id1)
      assert discovery.status == :success

      run_id2 = "replay-warning-replay-#{:erlang.unique_integer([:positive])}"
      start_run_server(run_id2, plan, replay: run_id1)
      {:ok, replay} = Run.Server.await(run_id2)
      assert replay.status == :success

      {:ok, events} = Event.Store.read_all(run_id2)

      completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "warn"
        end)

      assert [%{"code" => "recordable_warning", "severity" => "low"}] =
               completed["payload"]["warnings"]
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

    test "await falls back to the event log when a registered process exits normally without replying" do
      run_id = "await-fallback-race-#{:erlang.unique_integer([:positive])}"

      start_run_server(run_id, single_op_plan())
      {:ok, completed} = Run.Server.await(run_id)
      assert completed.status == :success

      Process.sleep(50)

      parent = self()

      pid =
        spawn_link(fn ->
          Registry.register(Liminara.Run.Registry, run_id, nil)
          send(parent, {:registered, self()})

          receive do
            {:await, _caller} -> :ok
          end

          :ok
        end)

      assert_receive {:registered, ^pid}, 1000

      assert {:ok, rebuilt} = Run.Server.await(run_id)
      assert rebuilt.status == :success
      assert rebuilt.outputs == completed.outputs
    end
  end

  # ── Introspection ────────────────────────────────────────────────

  describe "introspection" do
    test ":sys.get_state returns state with plan, node_states, run_id" do
      unique = :erlang.unique_integer([:positive])
      run_id = "intro-state-#{unique}"

      # Use a slow op with unique input to avoid cache hits
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{
          "text" => {:literal, "inspect-#{unique}"}
        })

      {:ok, pid} = start_run_server(run_id, plan)

      # Give it a moment to start and process handle_continue
      Process.sleep(50)

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
