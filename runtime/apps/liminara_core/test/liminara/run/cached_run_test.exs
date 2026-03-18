defmodule Liminara.Run.CachedRunTest do
  use ExUnit.Case

  alias Liminara.{Artifact, Event, Plan, Run}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_cached_run_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    cache = :ets.new(:test_run_cache, [:set, :public])

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root, cache: cache}
  end

  describe "cache integration" do
    test "first run: all cache misses", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{
          "text" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      assert result.status == :success

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)

      op_completed_events =
        Enum.filter(events, &(&1["event_type"] == "op_completed"))

      assert Enum.all?(op_completed_events, &(&1["payload"]["cache_hit"] == false))
    end

    test "second run: pure ops are cache hits", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "cached"}})

      # First run — cache miss
      {:ok, _result1} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      # Second run — cache hit
      {:ok, result2} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      assert result2.status == :success

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result2.run_id)

      op_completed_events =
        Enum.filter(events, &(&1["event_type"] == "op_completed"))

      assert length(op_completed_events) == 1
      assert hd(op_completed_events)["payload"]["cache_hit"] == true
    end

    test "cached artifacts are still retrievable", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "persist"}})

      {:ok, _result1} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, result2} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      {:ok, content} = Artifact.Store.get(ctx.store_root, result2.outputs["a"]["result"])
      assert content == "PERSIST"
    end

    test "recordable op never cached, executes both times", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("gen", Liminara.TestOps.Recordable, %{
          "prompt" => {:literal, "test prompt"}
        })

      # First run
      {:ok, _result1} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      # Second run — recordable should NOT be cached
      {:ok, result2} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: ctx.cache
        )

      assert result2.status == :success

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result2.run_id)

      op_completed_events =
        Enum.filter(events, &(&1["event_type"] == "op_completed"))

      # Recordable op should show cache_hit: false
      assert Enum.all?(op_completed_events, &(&1["payload"]["cache_hit"] == false))

      # And decision_recorded should be present (op actually executed)
      assert Enum.any?(events, &(&1["event_type"] == "decision_recorded"))
    end
  end
end
