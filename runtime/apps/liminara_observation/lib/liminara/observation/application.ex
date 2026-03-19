defmodule Liminara.Observation.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Liminara.Observation.PubSub}
    ]

    opts = [strategy: :one_for_one, name: Liminara.Observation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
