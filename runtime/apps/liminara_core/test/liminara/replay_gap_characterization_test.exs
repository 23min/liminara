defmodule Liminara.ReplayGapCharacterizationTest do
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event, Plan}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_replay_gap_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  describe "replay correctness" do
    @tag :deferred_stored_plan
    test "replay should persist the discovery plan instead of rebuilding it", ctx do
      {:ok, discovery} =
        Liminara.run(Liminara.StoredPlanReplayPack, :ignored,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, discovery_plan} = Event.Store.read_plan(ctx.runs_root, discovery.run_id)

      {:ok, replay} =
        Liminara.replay(Liminara.StoredPlanReplayPack, :ignored, discovery.run_id,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, replay_plan} = Event.Store.read_plan(ctx.runs_root, replay.run_id)

      assert Plan.hash(replay_plan) == Plan.hash(discovery_plan)
    end

    test "replay should restore all outputs from a multi-decision recordable op", ctx do
      {:ok, discovery} =
        Liminara.run(Liminara.MultiDecisionReplayPack, ["alpha", "beta"],
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, replay} =
        Liminara.replay(
          Liminara.MultiDecisionReplayPack,
          ["alpha", "beta"],
          discovery.run_id,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert replay.status == :success

      assert materialize_outputs(ctx.store_root, replay.outputs["multi"]) ==
               materialize_outputs(ctx.store_root, discovery.outputs["multi"])
    end

    test "replay emits the same decision_recorded events as discovery", ctx do
      {:ok, discovery} =
        Liminara.run(Liminara.MultiDecisionReplayPack, ["alpha", "beta"],
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, replay} =
        Liminara.replay(
          Liminara.MultiDecisionReplayPack,
          ["alpha", "beta"],
          discovery.run_id,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, discovery_events} = Event.Store.read_all(ctx.runs_root, discovery.run_id)
      {:ok, replay_events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

      discovery_decisions =
        discovery_events
        |> Enum.filter(&(&1["event_type"] == "decision_recorded"))
        |> Enum.map(&{&1["payload"]["node_id"], &1["payload"]["decision_hash"]})

      replay_decisions =
        replay_events
        |> Enum.filter(&(&1["event_type"] == "decision_recorded"))
        |> Enum.map(&{&1["payload"]["node_id"], &1["payload"]["decision_hash"]})

      assert length(replay_decisions) == length(discovery_decisions)
      assert replay_decisions == discovery_decisions
    end
  end

  defp materialize_outputs(store_root, output_hashes) do
    Map.new(output_hashes, fn {key, hash} ->
      {:ok, content} = Artifact.Store.get(store_root, hash)
      {key, content}
    end)
  end
end
