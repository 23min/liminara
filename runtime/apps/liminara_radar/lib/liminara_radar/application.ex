defmodule LiminaraRadar.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = scheduler_child_spec()

    opts = [strategy: :one_for_one, name: LiminaraRadar.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp scheduler_child_spec do
    config = Application.get_env(:liminara_radar, :scheduler, [])

    if Keyword.get(config, :enabled, false) do
      daily_at = Keyword.get(config, :daily_at, ~T[06:00:00])

      [
        {Liminara.Radar.Scheduler,
         daily_at: daily_at, run_fn: &run_radar/0, name: Liminara.Radar.Scheduler}
      ]
    else
      []
    end
  end

  defp run_radar do
    alias Liminara.Radar
    alias Liminara.Radar.Config

    config_path = Application.app_dir(:liminara_radar, "priv/sources.jsonl")

    with {:ok, sources} <- Config.load(config_path) do
      enabled = Config.enabled(sources)
      plan = Radar.plan(enabled)

      store_root =
        Application.get_env(:liminara_core, :store_root) ||
          Path.join(System.tmp_dir!(), "liminara_store")

      runs_root =
        Application.get_env(:liminara_core, :runs_root) ||
          Path.join(System.tmp_dir!(), "liminara_runs")

      Liminara.Run.execute(plan,
        pack_id: Atom.to_string(Radar.id()),
        pack_version: Radar.version(),
        store_root: store_root,
        runs_root: runs_root
      )
    end
  end
end
