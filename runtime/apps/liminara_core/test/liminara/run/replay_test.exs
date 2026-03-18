defmodule Liminara.Run.ReplayTest do
  use ExUnit.Case

  alias Liminara.{Artifact, Event, Plan, Run}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_replay_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  defp run_discovery(ctx) do
    plan =
      Plan.new()
      |> Plan.add_node("load", Liminara.TestOps.Upcase, %{"text" => {:literal, "replay test"}})
      |> Plan.add_node("transform", Liminara.TestOps.Recordable, %{
        "prompt" => {:ref, "load", "result"}
      })
      |> Plan.add_node("save", Liminara.TestOps.SideEffect, %{
        "data" => {:ref, "transform", "result"}
      })

    {:ok, result} =
      Run.execute(plan,
        pack_id: "test",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    {plan, result}
  end

  describe "replay" do
    test "discovery run produces output and decisions", ctx do
      {_plan, result} = run_discovery(ctx)

      assert result.status == :success
      assert Map.has_key?(result.outputs, "load")
      assert Map.has_key?(result.outputs, "transform")
      assert Map.has_key?(result.outputs, "save")

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      assert Enum.any?(events, &(&1["event_type"] == "decision_recorded"))
    end

    test "replay: recordable op returns same output as discovery", ctx do
      {plan, discovery} = run_discovery(ctx)

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      assert replay.status == :success

      # Recordable op output should match
      {:ok, disc_content} =
        Artifact.Store.get(ctx.store_root, discovery.outputs["transform"]["result"])

      {:ok, replay_content} =
        Artifact.Store.get(ctx.store_root, replay.outputs["transform"]["result"])

      assert disc_content == replay_content
    end

    test "replay: pure op re-executes and produces same output", ctx do
      {plan, discovery} = run_discovery(ctx)

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      {:ok, disc_content} =
        Artifact.Store.get(ctx.store_root, discovery.outputs["load"]["result"])

      {:ok, replay_content} =
        Artifact.Store.get(ctx.store_root, replay.outputs["load"]["result"])

      assert disc_content == replay_content
    end

    test "replay: side-effecting op is skipped", ctx do
      {plan, discovery} = run_discovery(ctx)

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

      # Find the save op_completed event
      save_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "save"
        end)

      # Should be marked as skipped (cache_hit: true, duration 0)
      assert save_completed["payload"]["cache_hit"] == true
    end

    test "replay run has its own valid hash chain", ctx do
      {plan, discovery} = run_discovery(ctx)

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      assert replay.run_id != discovery.run_id
      assert {:ok, _count} = Event.Store.verify(ctx.runs_root, replay.run_id)
    end

    test "replay run has its own seal", ctx do
      {plan, discovery} = run_discovery(ctx)

      {:ok, replay} =
        Run.execute(plan,
          pack_id: "test",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          replay: discovery.run_id
        )

      seal_path = Path.join([ctx.runs_root, replay.run_id, "seal.json"])
      assert File.exists?(seal_path)
    end
  end
end
