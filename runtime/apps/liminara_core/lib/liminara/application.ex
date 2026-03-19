defmodule Liminara.Application do
  @moduledoc """
  OTP Application for liminara_core.

  Starts the supervision tree with all core services:
  stores, cache, run registry, and dynamic supervisor.
  """

  use Application

  @impl true
  def start(_type, _args) do
    store_root =
      Application.get_env(:liminara_core, :store_root) ||
        Path.join(System.tmp_dir!(), "liminara_store")

    runs_root =
      Application.get_env(:liminara_core, :runs_root) ||
        Path.join(System.tmp_dir!(), "liminara_runs")

    children = [
      {Liminara.Artifact.Store, store_root: store_root},
      {Liminara.Event.Store, runs_root: runs_root},
      {Liminara.Decision.Store, runs_root: runs_root},
      Liminara.Cache,
      %{id: :pg, start: {:pg, :start_link, [:liminara]}},
      {Registry, keys: :unique, name: Liminara.Run.Registry},
      {DynamicSupervisor, name: Liminara.Run.DynamicSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Liminara.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
