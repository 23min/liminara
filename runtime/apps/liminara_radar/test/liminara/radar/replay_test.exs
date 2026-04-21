defmodule Liminara.Radar.ReplayTest do
  @moduledoc """
  End-to-end Radar pipeline replay test.

  Runs discovery through cluster → rank → summarize → compose → render,
  then replays and asserts identical output artifacts and decision events.
  """
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_radar_replay_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  defp without_api_key(fun) do
    previous = System.get_env("ANTHROPIC_API_KEY")
    System.delete_env("ANTHROPIC_API_KEY")

    try do
      fun.()
    after
      case previous do
        nil -> System.delete_env("ANTHROPIC_API_KEY")
        value -> System.put_env("ANTHROPIC_API_KEY", value)
      end
    end
  end

  describe "full Radar pipeline replay" do
    @tag timeout: 60_000
    test "discovery → replay produces identical output artifacts", ctx do
      without_api_key(fn ->
        {:ok, discovery} =
          Liminara.run(Liminara.RadarReplayTestPack, :ignored,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        assert discovery.status == :success

        {:ok, replay} =
          Liminara.replay(
            Liminara.RadarReplayTestPack,
            :ignored,
            discovery.run_id,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        assert replay.status == :success

        # All output node hashes must match
        for node_id <- ["cluster", "rank", "summarize", "compose_briefing", "render_html"] do
          discovery_hashes = discovery.outputs[node_id]
          replay_hashes = replay.outputs[node_id]

          assert discovery_hashes != nil, "discovery missing outputs for #{node_id}"
          assert replay_hashes != nil, "replay missing outputs for #{node_id}"

          # Compare actual artifact content (not just hashes, which are identical for same content)
          for {key, d_hash} <- discovery_hashes do
            r_hash = replay_hashes[key]
            assert r_hash != nil, "replay missing output key #{key} for #{node_id}"

            {:ok, d_content} = Artifact.Store.get(ctx.store_root, d_hash)
            {:ok, r_content} = Artifact.Store.get(ctx.store_root, r_hash)

            assert d_content == r_content,
                   "artifact mismatch for #{node_id}/#{key}"
          end
        end
      end)
    end

    @tag timeout: 60_000
    test "replay preserves recorded decision and warning events", ctx do
      without_api_key(fn ->
        {:ok, discovery} =
          Liminara.run(Liminara.RadarReplayTestPack, :ignored,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        {:ok, replay} =
          Liminara.replay(
            Liminara.RadarReplayTestPack,
            :ignored,
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

        discovery_warnings =
          discovery_events
          |> Enum.filter(&(&1["event_type"] == "op_completed"))
          |> Enum.map(&{&1["payload"]["node_id"], &1["payload"]["warnings"] || []})
          |> Enum.reject(fn {_node_id, warnings} -> warnings == [] end)

        replay_warnings =
          replay_events
          |> Enum.filter(&(&1["event_type"] == "op_completed"))
          |> Enum.map(&{&1["payload"]["node_id"], &1["payload"]["warnings"] || []})
          |> Enum.reject(fn {_node_id, warnings} -> warnings == [] end)

        assert replay_decisions == discovery_decisions
        assert replay_warnings == discovery_warnings
      end)
    end

    @tag timeout: 60_000
    test "replay HTML briefing is identical to discovery", ctx do
      without_api_key(fn ->
        {:ok, discovery} =
          Liminara.run(Liminara.RadarReplayTestPack, :ignored,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        {:ok, replay} =
          Liminara.replay(
            Liminara.RadarReplayTestPack,
            :ignored,
            discovery.run_id,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        {:ok, d_html} =
          Artifact.Store.get(ctx.store_root, discovery.outputs["render_html"]["html"])

        {:ok, r_html} =
          Artifact.Store.get(ctx.store_root, replay.outputs["render_html"]["html"])

        assert d_html == r_html
        assert String.contains?(d_html, "AI")
        assert String.contains?(d_html, "<!DOCTYPE html>")
      end)
    end

    @tag timeout: 60_000
    test "replay preserves degraded annotation in briefing and Run.Result", ctx do
      without_api_key(fn ->
        {:ok, discovery} =
          Liminara.run(Liminara.RadarReplayTestPack, :ignored,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        # Sanity: discovery should be degraded because Anthropic is disabled.
        assert discovery.status == :success
        assert discovery.degraded == true
        assert discovery.warning_count >= 1
        assert "summarize" in discovery.degraded_nodes

        {:ok, replay} =
          Liminara.replay(
            Liminara.RadarReplayTestPack,
            :ignored,
            discovery.run_id,
            store_root: ctx.store_root,
            runs_root: ctx.runs_root
          )

        # Replay reproduces the same quality signal — warnings persist and
        # are re-emitted, and the result's derived degraded flag matches.
        assert replay.status == :success
        assert replay.degraded == true
        assert replay.warning_count == discovery.warning_count
        assert Enum.sort(replay.degraded_nodes) == Enum.sort(discovery.degraded_nodes)

        # Briefing artifact is identical (content-addressed), and the degraded
        # annotation in the JSON is preserved.
        {:ok, d_briefing_json} =
          Artifact.Store.get(ctx.store_root, discovery.outputs["compose_briefing"]["briefing"])

        {:ok, r_briefing_json} =
          Artifact.Store.get(ctx.store_root, replay.outputs["compose_briefing"]["briefing"])

        assert d_briefing_json == r_briefing_json

        d_briefing = Jason.decode!(d_briefing_json)
        assert d_briefing["degraded"] == true
        assert d_briefing["degraded_cluster_ids"] != []
      end)
    end
  end
end
