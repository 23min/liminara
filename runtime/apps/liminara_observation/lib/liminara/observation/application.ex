defmodule Liminara.Observation.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Liminara.Observation.PubSub}
    ]

    opts = [strategy: :one_for_one, name: Liminara.Observation.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    # Start A2UI server as a separate step so port conflicts don't crash the app
    port = Application.get_env(:liminara_observation, :a2ui_port, 4001)

    case Supervisor.start_child(
           sup,
           {A2UI.Server,
            provider: Liminara.Observation.A2UISocketProvider, port: port, ip: {0, 0, 0, 0}}
         ) do
      {:ok, _} ->
        Logger.info("A2UI endpoint running on port #{port}")

      {:error, reason} ->
        Logger.warning(
          "A2UI endpoint failed to start: #{inspect(reason)} — continuing without it"
        )
    end

    {:ok, sup}
  end
end
