defmodule Liminara.Run.WarningAggregationTest do
  use ExUnit.Case, async: false

  alias Liminara.{Event, Plan, Run}

  @moduledoc """
  M-WARN-01: run-level warning aggregation on `Run.Result`.

  Verifies that `warning_count`, `degraded_nodes`, and the derived `degraded`
  flag are populated consistently across:
  - synchronous forward execution (`Run.execute/2`)
  - asynchronous execution via `Run.Server`
  - result reconstruction from the event log (`await/2` fallback)
  - replay of warning-bearing source runs
  - crash-recovered runs rebuilt from events
  """

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_warning_aggregation_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  describe "Run.Result aggregation (synchronous forward execution)" do
    test "plain success run has warning_count 0, empty degraded_nodes, and degraded: false",
         ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert result.warning_count == 0
      assert result.degraded_nodes == []
      assert result.degraded == false
    end

    test "warning-bearing success populates warning_count, degraded_nodes, and degraded: true",
         ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert result.warning_count == 1
      assert result.degraded_nodes == ["warn"]
      assert result.degraded == true
    end

    test "node emitting multiple warnings counts each and reports node once in degraded_nodes",
         ctx do
      plan =
        Plan.new()
        |> Plan.add_node("multi", Liminara.TestOps.WithMultipleWarningsSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert result.warning_count == 3
      assert result.degraded_nodes == ["multi"]
      assert result.degraded == true
    end

    test "multi-node run aggregates across warning-bearing nodes only", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("clean", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:ref, "clean", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert result.warning_count == 1
      assert result.degraded_nodes == ["warn"]
      assert result.degraded == true
    end

    test "runtime-injected violation warning contributes to aggregation", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("violator", Liminara.TestOps.WithViolatingWarningExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      # 1 op-emitted + 1 runtime-injected violation
      assert result.warning_count == 2
      assert result.degraded_nodes == ["violator"]
      assert result.degraded == true
    end

    test "failed runs are not marked degraded even when warning-bearing nodes exist", ctx do
      # A warning-bearing node followed by a failing node produces :failed,
      # and degraded is false because degraded is operator-output quality on
      # non-failed runs.
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })
        |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:ref, "warn", "result"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :failed
      # warning_count still reflects what was emitted, but degraded is false
      assert result.warning_count == 1
      assert result.degraded == false
    end
  end

  describe "Run.Server aggregation and result_from_event_log parity" do
    test "Run.Server.await returns aggregation in live result" do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id = "warnaggr-server-#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)

      assert result.status == :success
      assert result.warning_count == 1
      assert result.degraded_nodes == ["warn"]
      assert result.degraded == true
    end

    test "result_from_event_log returns the same aggregation after the server exits" do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id = "warnaggr-fallback-#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, live_result} = Run.Server.await(run_id, 5_000)
      Process.sleep(50)

      {:ok, rebuilt_result} = Run.Server.await(run_id, 5_000)

      assert rebuilt_result.warning_count == live_result.warning_count
      assert rebuilt_result.degraded_nodes == live_result.degraded_nodes
      assert rebuilt_result.degraded == live_result.degraded
    end

    test "result_from_event_log handles plain success as non-degraded" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})

      run_id = "warnaggr-plain-#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, _} = Run.Server.await(run_id, 5_000)
      Process.sleep(50)

      {:ok, rebuilt_result} = Run.Server.await(run_id, 5_000)
      assert rebuilt_result.warning_count == 0
      assert rebuilt_result.degraded_nodes == []
      assert rebuilt_result.degraded == false
    end

    test "crash-recovered runs report the same aggregation the original run would have" do
      # Run to completion once, then restart with the same run_id. Recovery path
      # must reconstruct aggregation from the event log.
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id = "warnaggr-recover-#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, live_result} = Run.Server.await(run_id, 5_000)
      Process.sleep(50)

      # Restart with the same run_id — should detect completion via the rebuild path
      {:ok, _pid2} = Run.Server.start(run_id, plan)
      {:ok, recovered} = Run.Server.await(run_id, 5_000)

      assert recovered.status == :success
      assert recovered.warning_count == live_result.warning_count
      assert recovered.degraded_nodes == live_result.degraded_nodes
      assert recovered.degraded == live_result.degraded
    end
  end

  describe "replay preserves aggregation" do
    test "replaying a warning-bearing recordable run reproduces the aggregation", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.RecordableWithWarningExecutionSpec, %{
          "prompt" => {:literal, "hello"}
        })

      {:ok, discovery} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert discovery.warning_count == 1
      assert discovery.degraded_nodes == ["warn"]
      assert discovery.degraded == true

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      assert replay.warning_count == discovery.warning_count
      assert replay.degraded_nodes == discovery.degraded_nodes
      assert replay.degraded == discovery.degraded
    end
  end

  describe "run_completed event payload carries warning_summary" do
    test "plain success runs still carry a warning_summary with zeros", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      run_completed = Enum.find(events, &(&1["event_type"] == "run_completed"))

      assert run_completed["payload"]["warning_summary"] == %{
               "warning_count" => 0,
               "degraded_node_ids" => []
             }
    end

    test "warning-bearing runs carry the aggregation in warning_summary", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      run_completed = Enum.find(events, &(&1["event_type"] == "run_completed"))

      assert run_completed["payload"]["warning_summary"] == %{
               "warning_count" => 1,
               "degraded_node_ids" => ["warn"]
             }
    end

    test "warning_summary survives the event hash chain verification", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert {:ok, _count} = Event.Store.verify(ctx.runs_root, result.run_id)
    end

    test "Run.Server emits run_completed with warning_summary" do
      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      run_id = "warnaggr-server-payload-#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, _} = Run.Server.await(run_id, 5_000)

      {:ok, events} = Event.Store.read_all(run_id)
      run_completed = Enum.find(events, &(&1["event_type"] == "run_completed"))

      assert run_completed["payload"]["warning_summary"] == %{
               "warning_count" => 1,
               "degraded_node_ids" => ["warn"]
             }
    end
  end
end
