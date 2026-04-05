defmodule Liminara.ExecutionRuntimeContractTest do
  use ExUnit.Case, async: false

  alias Liminara.{
    Artifact,
    Cache,
    Decision,
    Event,
    ExecutionSpec,
    Executor,
    Op,
    OpResult,
    Plan,
    Run,
    Warning
  }

  @python_root Path.expand("../../../../python", __DIR__)
  @runner_path Path.join(@python_root, "src/liminara_op_runner.py")

  describe "execution spec bridge" do
    test "derives canonical spec from legacy inline callbacks" do
      spec = Op.execution_spec(Liminara.TestOps.Upcase)

      assert %ExecutionSpec{} = spec
      assert spec.identity.name == "upcase"
      assert spec.identity.version == "1.0"
      assert spec.determinism.class == :pure
      assert spec.execution.executor == :inline
      assert spec.execution.entrypoint == "upcase"
      assert spec.execution.requires_execution_context == false
      assert spec.contracts.decisions == %{may_emit: false}
      assert spec.contracts.warnings == %{may_emit: false}
    end

    test "derives canonical spec from legacy port callbacks" do
      spec = Op.execution_spec(Liminara.TestPortOps.Recordable)

      assert spec.identity.name == "test_recordable"
      assert spec.determinism.class == :recordable
      assert spec.execution.executor == :port
      assert spec.execution.entrypoint == "test_recordable"
      assert spec.isolation.env_vars == []
      assert spec.contracts.decisions == %{may_emit: true}
    end

    test "prefers explicit execution_spec over legacy callbacks" do
      spec = Op.execution_spec(Liminara.TestOps.WithExecutionSpec)

      assert spec.identity.name == "explicit_spec_op"
      assert spec.identity.version == "2.1.0"
      assert spec.determinism.class == :pure
      assert spec.execution.executor == :inline
      assert spec.execution.entrypoint == "explicit_spec_op"
      assert spec.contracts.warnings == %{may_emit: true}
    end
  end

  describe "executor normalization" do
    test "normalizes legacy tuple success into OpResult" do
      assert {:ok, %OpResult{} = result, duration_ms} =
               Executor.run(Liminara.TestOps.Upcase, %{"text" => "hello"}, executor: :inline)

      assert result.outputs == %{"result" => "HELLO"}
      assert result.decisions == []
      assert result.warnings == []
      assert is_integer(duration_ms) and duration_ms >= 0
    end

    test "normalizes legacy tuple success with decisions into OpResult" do
      assert {:ok, %OpResult{} = result, _duration_ms} =
               Executor.run(Liminara.TestOps.Recordable, %{"prompt" => "test"}, executor: :inline)

      assert result.outputs == %{"result" => "Generated response for: test"}
      assert [%{"decision_type" => "llm_response"}] = result.decisions
      assert result.warnings == []
    end

    test "passes through canonical OpResult from inline execution" do
      assert {:ok, %OpResult{} = result, _duration_ms} =
               Executor.run(Liminara.TestOps.WithExecutionSpec, %{"text" => "hello"},
                 executor: :inline
               )

      assert result.outputs == %{"result" => "HELLO"}
      assert [%Warning{code: "explicit_warning"}] = result.warnings
    end
  end

  describe "port normalization" do
    test "normalizes canonical Python warning-bearing success into OpResult" do
      assert {:ok, %OpResult{} = result, duration_ms} =
               Executor.run(Liminara.TestPortOps.Warning, %{"text" => "hello"},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert result.outputs == %{"result" => "hello"}
      assert result.decisions == []
      assert [%Warning{code: "python_warning", severity: :medium}] = result.warnings
      assert is_integer(duration_ms) and duration_ms >= 0
    end
  end

  describe "timeout propagation" do
    test "task executor honors canonical execution_spec timeout_ms" do
      {:ok, supervisor} = Task.Supervisor.start_link()
      on_exit(fn -> Process.exit(supervisor, :shutdown) end)

      assert_timeout_result(fn ->
        Executor.run(Liminara.TestOps.WithTaskTimeoutExecutionSpec, %{"text" => "hello"},
          task_supervisor: supervisor
        )
      end)
    end

    test "port executor honors canonical execution_spec timeout_ms" do
      assert_timeout_result(fn ->
        Executor.run(Liminara.TestPortOps.WithTimeoutExecutionSpec, %{},
          python_root: @python_root,
          runner: @runner_path
        )
      end)
    end
  end

  describe "canonical cache behavior" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "liminara_execution_runtime_contract_test_#{:erlang.unique_integer([:positive])}"
        )

      store_root = Path.join(tmp, "artifacts")
      runs_root = Path.join(tmp, "runs")
      cache = :ets.new(:execution_runtime_contract_cache, [:set, :public])

      File.mkdir_p!(store_root)
      File.mkdir_p!(runs_root)

      on_exit(fn ->
        if :ets.info(cache) != :undefined do
          :ets.delete(cache)
        end

        File.rm_rf!(tmp)
      end)

      %{cache: cache, store_root: store_root, runs_root: runs_root}
    end

    test "explicit execution_spec controls cacheability even when legacy determinism disagrees",
         ctx do
      plan =
        Plan.new()
        |> Plan.add_node("spec", Liminara.TestOps.WithExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, _first} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, second} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      assert Cache.cacheable?(Liminara.TestOps.WithExecutionSpec)

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, second.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "spec"
        end)

      assert completed["payload"]["cache_hit"] == true
    end

    test "explicit cache_policy none disables caching even for canonically pure ops", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("spec", Liminara.TestOps.WithNoCacheExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, _first} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, second} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      refute Cache.cacheable?(Liminara.TestOps.WithNoCacheExecutionSpec)

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, second.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "spec"
        end)

      assert completed["payload"]["cache_hit"] == false
    end

    test "execution-context-aware ops are never cached without a context hash", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("ctx", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:literal, "hello"}
        })

      {:ok, first} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, second} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      refute Cache.cacheable?(Liminara.TestOps.WithRuntimeContext)

      {:ok, first_run_id} = Artifact.Store.get(ctx.store_root, first.outputs["ctx"]["run_id"])
      {:ok, second_run_id} = Artifact.Store.get(ctx.store_root, second.outputs["ctx"]["run_id"])

      assert first_run_id == first.run_id
      assert second_run_id == second.run_id
      refute first_run_id == second_run_id

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, second.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "ctx"
        end)

      assert completed["payload"]["cache_hit"] == false
    end

    test "pinned_env ops remain uncached until environment hashing exists", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("render", Liminara.ToyOps.Render, %{
          "data" => {:literal, "hello"}
        })

      {:ok, _first} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, second} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      refute Cache.cacheable?(Liminara.ToyOps.Render)

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, second.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "render"
        end)

      assert completed["payload"]["cache_hit"] == false
    end
  end

  describe "runtime contract propagation" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "liminara_execution_runtime_contract_runtime_#{:erlang.unique_integer([:positive])}"
        )

      store_root = Path.join(tmp, "artifacts")
      runs_root = Path.join(tmp, "runs")

      File.mkdir_p!(store_root)
      File.mkdir_p!(runs_root)

      on_exit(fn -> File.rm_rf!(tmp) end)

      %{store_root: store_root, runs_root: runs_root}
    end

    test "run emits plain warning maps without crashing", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })

      assert {:ok, result} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root
               )

      assert result.status == :success

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "warn"
        end)

      assert [%{"code" => "inline_warning", "severity" => "low"}] =
               completed["payload"]["warnings"]
    end

    test "decision records use canonical execution spec identity", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("decide", Liminara.TestOps.RecordableWithExecutionSpec, %{
          "prompt" => {:literal, "hello"}
        })

      assert {:ok, result} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root
               )

      assert {:ok, [decision]} = Decision.Store.get(ctx.runs_root, result.run_id, "decide")
      assert decision["op_id"] == "canonical_recordable_op"
      assert decision["op_version"] == "2.0.0"
    end

    test "explicit replay_policy can reexecute even when determinism class is side_effecting",
         ctx do
      plan =
        Plan.new()
        |> Plan.add_node("replay", Liminara.TestOps.WithReplayReexecuteExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      assert {:ok, discovery} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root
               )

      assert {:ok, replay} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root,
                 replay: discovery.run_id
               )

      refute replay.outputs["replay"] == %{}

      assert {:ok, replay_content} =
               Artifact.Store.get(ctx.store_root, replay.outputs["replay"]["result"])

      assert replay_content == "HELLO"

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "replay"
        end)

      assert completed["payload"]["cache_hit"] == false
    end

    test "recordable replay preserves warnings alongside stored decisions", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.RecordableWithWarningExecutionSpec, %{
          "prompt" => {:literal, "hello"}
        })

      assert {:ok, discovery} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root
               )

      assert {:ok, replay} =
               Run.execute(plan,
                 pack_id: "test_pack",
                 pack_version: "0.1.0",
                 store_root: ctx.store_root,
                 runs_root: ctx.runs_root,
                 replay: discovery.run_id
               )

      assert {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

      completed =
        Enum.find(events, fn event ->
          event["event_type"] == "op_completed" and event["payload"]["node_id"] == "warn"
        end)

      assert [%{"code" => "recordable_warning", "severity" => "low"}] =
               completed["payload"]["warnings"]
    end
  end

  defp assert_timeout_result(fun, wait_timeout \\ 500) do
    task = Task.async(fun)

    case Task.yield(task, wait_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:error, :timeout, duration_ms}} ->
        assert is_integer(duration_ms) and duration_ms >= 0
        assert duration_ms < wait_timeout

      other ->
        flunk("expected executor timeout within #{wait_timeout}ms, got: #{inspect(other)}")
    end
  end
end
