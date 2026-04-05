defmodule Liminara.Radar.Ops.DegradationWarningTest do
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event, Plan, Run}
  alias Liminara.Radar.Ops.{FetchRss, LlmDedupCheck, Summarize}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_radar_degradation_warning_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    cache = :ets.new(:radar_degradation_warning_test_cache, [:set, :public])

    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root, cache: cache}
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

  defp completed_event!(runs_root, run_id, node_id) do
    {:ok, events} = Event.Store.read_all(runs_root, run_id)

    Enum.find(events, fn event ->
      event["event_type"] == "op_completed" and event["payload"]["node_id"] == node_id
    end) || flunk("missing op_completed event for #{node_id}")
  end

  defp decision_events(runs_root, run_id, node_id) do
    {:ok, events} = Event.Store.read_all(runs_root, run_id)

    Enum.filter(events, fn event ->
      event["event_type"] == "decision_recorded" and event["payload"]["node_id"] == node_id
    end)
  end

  test "summarize placeholder mode emits warnings and replay preserves them without decisions",
       ctx do
    clusters = [
      %{
        "cluster_id" => "c0",
        "label" => "AI",
        "items" => [
          %{
            "id" => "a1",
            "title" => "Item A",
            "clean_text" => "Text A",
            "url" => "https://example.com/a1",
            "source_id" => "src_1"
          }
        ],
        "centroid" => List.duplicate(0.0, 32)
      }
    ]

    plan =
      Plan.new()
      |> Plan.add_node("summarize", Summarize, %{
        "clusters" => {:literal, Jason.encode!(clusters)}
      })

    without_api_key(fn ->
      {:ok, discovery} = Run.execute(plan, run_opts(ctx))
      assert discovery.status == :success

      {:ok, replay} = Run.execute(plan, run_opts(ctx, replay: discovery.run_id))
      assert replay.status == :success
      assert replay.outputs["summarize"] == discovery.outputs["summarize"]

      assert decision_events(ctx.runs_root, discovery.run_id, "summarize") == []
      assert decision_events(ctx.runs_root, replay.run_id, "summarize") == []

      discovery_completed = completed_event!(ctx.runs_root, discovery.run_id, "summarize")
      replay_completed = completed_event!(ctx.runs_root, replay.run_id, "summarize")

      assert [%{"code" => "radar_summarize_placeholder", "severity" => "degraded"}] =
               discovery_completed["payload"]["warnings"]

      assert [%{"code" => "radar_summarize_placeholder", "severity" => "degraded"}] =
               replay_completed["payload"]["warnings"]
    end)
  end

  test "llm dedup safe default emits warnings instead of synthetic decisions", ctx do
    items = [
      %{
        "id" => "a1",
        "title" => "News Story",
        "clean_text" => "Some article content here",
        "url" => "https://example.com/a1",
        "source_id" => "src_1",
        "_match_title" => "Similar Story",
        "_match_url" => "https://other.com/existing",
        "_similarity" => 0.85
      }
    ]

    plan =
      Plan.new()
      |> Plan.add_node("llm", LlmDedupCheck, %{
        "items" => {:literal, Jason.encode!(items)}
      })

    without_api_key(fn ->
      {:ok, result} = Run.execute(plan, run_opts(ctx))
      assert result.status == :success

      {:ok, kept_items_json} = Artifact.Store.get(ctx.store_root, result.outputs["llm"]["items"])
      kept_items = Jason.decode!(kept_items_json)

      assert Enum.map(kept_items, & &1["id"]) == ["a1"]
      assert decision_events(ctx.runs_root, result.run_id, "llm") == []

      completed = completed_event!(ctx.runs_root, result.run_id, "llm")

      assert [%{"code" => "radar_llm_dedup_safe_default", "severity" => "degraded"}] =
               completed["payload"]["warnings"]
    end)
  end

  test "fetch rss failure is warning-bearing success", ctx do
    source = %{"id" => "bad_src", "feed_url" => "://invalid"}

    plan =
      Plan.new()
      |> Plan.add_node("fetch", FetchRss, %{
        "source" => {:literal, Jason.encode!(source)}
      })

    {:ok, result} = Run.execute(plan, run_opts(ctx))
    assert result.status == :success

    {:ok, fetch_json} = Artifact.Store.get(ctx.store_root, result.outputs["fetch"]["result"])
    fetch_result = Jason.decode!(fetch_json)

    assert fetch_result["items"] == []
    assert is_binary(fetch_result["error"])

    completed = completed_event!(ctx.runs_root, result.run_id, "fetch")

    assert [%{"code" => "radar_fetch_rss_failed", "severity" => "degraded"}] =
             completed["payload"]["warnings"]
  end
end
