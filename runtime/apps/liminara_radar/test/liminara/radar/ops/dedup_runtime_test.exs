defmodule Liminara.Radar.Ops.DedupRuntimeTest do
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event, Plan, Run}
  alias Liminara.Radar.Ops.Dedup

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_radar_dedup_runtime_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    lancedb_path = Path.join(tmp, "lancedb")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    cache = :ets.new(:radar_dedup_runtime_test_cache, [:set, :public])

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root, lancedb_path: lancedb_path, cache: cache}
  end

  defp run_opts(ctx, extra \\ []) do
    [
      pack_id: "radar",
      pack_version: "0.1.0",
      store_root: ctx.store_root,
      runs_root: ctx.runs_root,
      cache: ctx.cache
    ] ++ extra
  end

  defp dedup_plan(ctx, items) do
    Plan.new()
    |> Plan.add_node("dedup", Dedup, %{
      "items" => {:literal, Jason.encode!(items)},
      "lancedb_path" => {:literal, ctx.lancedb_path},
      "dims" => {:literal, "32"}
    })
  end

  defp sample_item(id) do
    %{
      "id" => id,
      "title" => "Story #{id}",
      "clean_text" => "Content for #{id}",
      "url" => "https://example.com/#{id}",
      "embedding" => List.duplicate(0.5, 32),
      "source_id" => "src_1"
    }
  end

  defp decode_output(store_root, output_hash) do
    {:ok, content} = Artifact.Store.get(store_root, output_hash)
    Jason.decode!(content)
  end

  defp dedup_result(store_root, run_result) do
    decode_output(store_root, run_result.outputs["dedup"]["result"])
  end

  test "separate live runs do not reuse cached dedup outputs across mutated history", ctx do
    plan = dedup_plan(ctx, [sample_item("a1")])

    {:ok, first} = Run.execute(plan, run_opts(ctx))
    first_result = dedup_result(ctx.store_root, first)

    assert first_result["new_items"] |> Enum.map(& &1["id"]) == ["a1"]
    assert first_result["duplicate_items"] == []

    {:ok, second} = Run.execute(plan, run_opts(ctx))
    second_result = dedup_result(ctx.store_root, second)

    assert second_result["new_items"] == []
    assert second_result["ambiguous_items"] == []
    assert second_result["duplicate_items"] |> Enum.map(& &1["id"]) == ["a1"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, second.run_id)

    completed =
      Enum.find(events, fn event ->
        event["event_type"] == "op_completed" and event["payload"]["node_id"] == "dedup"
      end)

    assert completed["payload"]["cache_hit"] == false
  end

  test "replay injects recorded dedup outputs instead of re-running against updated history",
       ctx do
    plan = dedup_plan(ctx, [sample_item("a1")])
    opts = run_opts(ctx)

    {:ok, discovery} = Run.execute(plan, opts)
    discovery_result = dedup_result(ctx.store_root, discovery)

    {:ok, live_second} = Run.execute(plan, opts)
    live_second_result = dedup_result(ctx.store_root, live_second)

    {:ok, replay} = Run.execute(plan, Keyword.put(opts, :replay, discovery.run_id))
    replay_result = dedup_result(ctx.store_root, replay)

    assert discovery_result["new_items"] |> Enum.map(& &1["id"]) == ["a1"]
    assert live_second_result["duplicate_items"] |> Enum.map(& &1["id"]) == ["a1"]
    assert replay_result == discovery_result
    refute replay_result == live_second_result

    {:ok, replay_events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

    completed =
      Enum.find(replay_events, fn event ->
        event["event_type"] == "op_completed" and event["payload"]["node_id"] == "dedup"
      end)

    assert completed["payload"]["cache_hit"] == false
  end
end
