defmodule Mix.Tasks.Radar.Run do
  @moduledoc """
  Run the Radar pipeline — fetch all enabled sources, collect items.

  ## Usage

      mix radar.run [--tags ai,elixir] [--config path/to/sources.jsonl]
  """

  use Mix.Task

  alias Liminara.Radar
  alias Liminara.Radar.Config
  alias Liminara.Run

  @default_config Path.expand("../../../../priv/sources.jsonl", __DIR__)

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: [tags: :string, config: :string])

    config_path = Keyword.get(opts, :config, @default_config)

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

      {:error, reason} ->
        Mix.shell().error("Radar: run failed — #{inspect(reason)}")
    end
  end
end
