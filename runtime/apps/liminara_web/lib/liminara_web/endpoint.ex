defmodule LiminaraWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :liminara_web

  @session_options [
    store: :cookie,
    key: "_liminara_web_key",
    signing_salt: "liminara_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :liminara_web,
    gzip: false,
    only: LiminaraWeb.static_paths()

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LiminaraWeb.Router
end
