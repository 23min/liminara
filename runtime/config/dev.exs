import Config

config :liminara_web, LiminaraWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4005],
  server: true,
  debug_errors: true,
  check_origin: false

# A2UI WebSocket endpoint
config :liminara_observation, a2ui_port: 4006

# Persistent storage — survives container restarts
config :liminara_core,
  store_root: Path.expand("../data/store", __DIR__),
  runs_root: Path.expand("../data/runs", __DIR__)

config :logger, :console, level: :info
