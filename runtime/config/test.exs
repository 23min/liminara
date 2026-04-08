import Config

config :liminara_radar,
	lancedb_path: Path.join(System.tmp_dir!(), "liminara_test_radar_lancedb")

# A2UI WebSocket endpoint — use port 0 for OS-assigned port in tests
config :liminara_observation, a2ui_path: "/ws"
config :liminara_observation, a2ui_port: 14001

# Server off for tests
config :liminara_web, LiminaraWeb.Endpoint, server: false

config :logger, :console, level: :warning
