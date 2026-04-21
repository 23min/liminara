defmodule Liminara.Radar.DegradationPipelineTest do
  @moduledoc """
  End-to-end test for the M-WARN-03 degraded-briefing contract.

  Drives the Radar pipeline (cluster -> rank -> summarize -> compose ->
  render_html) with `ANTHROPIC_API_KEY` deliberately removed so the
  `radar_summarize` op falls back to the placeholder path. Asserts the
  full chain:

  - run reaches terminal `:success` (degraded is not failure)
  - `Run.Result.warning_count >= 1` and `summarize` is in `degraded_nodes`
  - the `briefing` artifact has `degraded: true` and a non-empty
    `degraded_cluster_ids` list
  - the rendered HTML contains the banner element and the per-cluster pill
  """
  use ExUnit.Case, async: false

  alias Liminara.Artifact
  alias Liminara.RadarReplayTestPack

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_radar_degradation_pipeline_test_#{:erlang.unique_integer([:positive])}"
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

  @tag timeout: 60_000
  test "Anthropic disabled: degraded briefing flows from summarize to HTML", ctx do
    without_api_key(fn ->
      {:ok, result} =
        Liminara.run(RadarReplayTestPack, :ignored,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      # Run reaches terminal success (degraded is not failure).
      assert result.status == :success
      assert result.degraded == true
      assert result.warning_count >= 1
      assert "summarize" in result.degraded_nodes

      # Briefing artifact carries the degraded annotation.
      briefing_hash = result.outputs["compose_briefing"]["briefing"]
      {:ok, briefing_json} = Artifact.Store.get(ctx.store_root, briefing_hash)
      briefing = Jason.decode!(briefing_json)

      assert briefing["degraded"] == true
      assert is_list(briefing["degraded_cluster_ids"])
      assert briefing["degraded_cluster_ids"] != []

      # Every cluster in the degraded list carries per-cluster flags.
      for cluster <- briefing["clusters"] do
        assert Map.has_key?(cluster, "degraded")
        assert Map.has_key?(cluster, "degradation_code")
        assert Map.has_key?(cluster, "degradation_note")

        if cluster["cluster_id"] in briefing["degraded_cluster_ids"] do
          assert cluster["degraded"] == true
          assert cluster["degradation_code"] == "radar_summarize_placeholder"
          assert is_binary(cluster["degradation_note"])
        end
      end

      # Rendered HTML contains the banner element and the per-cluster pill element.
      html_hash = result.outputs["render_html"]["html"]
      {:ok, html} = Artifact.Store.get(ctx.store_root, html_hash)

      assert String.contains?(html, ~s(class="briefing--degraded"))
      assert String.contains?(html, ~s(class="cluster--degraded"))
      assert String.contains?(html, "cluster summaries are degraded")

      assert String.contains?(
               html,
               "Using placeholder summaries because Anthropic access is unavailable"
             )
    end)
  end
end
