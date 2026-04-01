defmodule LiminaraWeb.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiminaraWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: LiminaraWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
