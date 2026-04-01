# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#

config :liminara_web, LiminaraWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: LiminaraWeb.ErrorHTML], layout: false],
  pubsub_server: Liminara.Observation.PubSub,
  live_view: [signing_salt: "liminara_live"],
  secret_key_base: String.duplicate("a", 64),
  server: false

# Import environment specific config
import_config "#{config_env()}.exs"
