import Config

# Persistent storage — survives container restarts
config :liminara_core,
  store_root: Path.expand("../data/store", __DIR__),
  runs_root: Path.expand("../data/runs", __DIR__)

# A2UI WebSocket endpoint
config :liminara_observation, a2ui_port: 4006

config :liminara_radar,
  lancedb_path: Path.expand("../data/radar/lancedb", __DIR__)

config :liminara_web, LiminaraWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4005],
  server: true,
  debug_errors: true,
  check_origin: false

config :logger, :console, level: :info
