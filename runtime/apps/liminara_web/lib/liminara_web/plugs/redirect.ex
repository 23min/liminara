defmodule LiminaraWeb.Plugs.Redirect do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn
    |> Phoenix.Controller.redirect(to: Keyword.fetch!(opts, :to))
    |> Plug.Conn.halt()
  end
end
