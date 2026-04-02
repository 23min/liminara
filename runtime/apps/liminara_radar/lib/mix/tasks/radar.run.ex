defmodule Mix.Tasks.Radar.Run do
  @moduledoc """
  Run the Radar pipeline — fetch all enabled sources, collect items.

  ## Usage

      mix radar.run [--tags ai,elixir] [--config path/to/sources.jsonl] [--output briefing.html]
  """

  use Mix.Task

  alias Liminara.Radar
  alias Liminara.Radar.Config
  alias Liminara.Run

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: [tags: :string, config: :string, output: :string])

    config_path =
      Keyword.get(opts, :config) ||
        Application.app_dir(:liminara_radar, "priv/sources.jsonl")

    {:ok, sources} = Config.load(config_path)
    enabled = Config.enabled(sources)

    enabled =
      case Keyword.get(opts, :tags) do
        nil -> enabled
        tags_str -> Config.by_tags(enabled, String.split(tags_str, ","))
      end

    Mix.shell().info("Radar: #{length(enabled)} sources enabled")

    plan = Radar.plan(enabled)

    store_root =
      Application.get_env(:liminara_core, :store_root) ||
        Path.join(System.tmp_dir!(), "liminara_store")

    runs_root =
      Application.get_env(:liminara_core, :runs_root) ||
        Path.join(System.tmp_dir!(), "liminara_runs")

    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    Mix.shell().info("Radar: starting run...")

    case Run.execute(plan,
           pack_id: Atom.to_string(Radar.id()),
           pack_version: Radar.version(),
           store_root: store_root,
           runs_root: runs_root
         ) do
      {:ok, result} ->
        Mix.shell().info("Radar: run #{result.run_id} completed (#{result.status})")

        if result.status == :failed do
          print_failure_details(result)
        end

        print_collect_summary(result, store_root)
        print_briefing_summary(result, store_root)
        maybe_write_output(result, store_root, Keyword.get(opts, :output))
    end
  end

  defp print_failure_details(result) do
    if result.failed_nodes != [] do
      Mix.shell().error("Radar: failed nodes: #{Enum.join(result.failed_nodes, ", ")}")
    end

    # Show node states for debugging
    result.node_states
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.each(fn {id, state} ->
      icon =
        case state do
          :completed -> "OK"
          :failed -> "FAIL"
          :pending -> "SKIP"
          :running -> "HANG"
          other -> to_string(other)
        end

      Mix.shell().info("  [#{icon}] #{id}")
    end)
  end

  defp print_collect_summary(result, store_root) do
    if result.outputs["collect_items"] do
      items_hash = result.outputs["collect_items"]["items"]
      {:ok, items_json} = Liminara.Artifact.Store.get(store_root, items_hash)
      items = Jason.decode!(items_json)
      Mix.shell().info("Radar: #{length(items)} items collected")

      health_hash = result.outputs["collect_items"]["source_health"]
      {:ok, health_json} = Liminara.Artifact.Store.get(store_root, health_hash)
      health = Jason.decode!(health_json)

      errors = Enum.filter(health, &(&1["error"] != nil))

      if errors != [] do
        Mix.shell().info("Radar: #{length(errors)} source(s) had errors:")

        for e <- errors do
          Mix.shell().info("  - #{e["source_id"]}: #{e["error"]}")
        end
      end
    end
  end

  defp maybe_write_output(_result, _store_root, nil), do: :ok

  defp maybe_write_output(result, store_root, path) do
    if result.outputs["render_html"] do
      html_hash = result.outputs["render_html"]["html"]
      {:ok, html} = Liminara.Artifact.Store.get(store_root, html_hash)
      File.write!(path, html)
      Mix.shell().info("Radar: briefing written to #{path}")
    end
  end

  defp print_briefing_summary(result, store_root) do
    if result.outputs["compose_briefing"] do
      briefing_hash = result.outputs["compose_briefing"]["briefing"]
      {:ok, briefing_json} = Liminara.Artifact.Store.get(store_root, briefing_hash)
      briefing = Jason.decode!(briefing_json)
      stats = briefing["stats"] || %{}

      Mix.shell().info(
        "Radar: #{stats["cluster_count"] || 0} clusters, " <>
          "#{stats["item_count"] || 0} items after dedup"
      )
    end

    if result.outputs["render_html"] do
      html_hash = result.outputs["render_html"]["html"]
      Mix.shell().info("Radar: HTML briefing artifact: #{html_hash}")
    end
  end
end
