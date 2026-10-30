# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :chess_ex_ui,
  namespace: ChessUI,
  generators: [timestamp_type: :utc_datetime]

# The engine plays a full 4-ply search and uses the opening book when the
# position is known. See `ChessUI.Engine`.
config :chess_ex_ui,
  engine_options: [strategy: :search, depth: 4, book: true],
  engine_min_think_ms: 400

# Configures the endpoint
config :chess_ex_ui, ChessUIWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChessUIWeb.ErrorHTML, json: ChessUIWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChessUI.PubSub,
  live_view: [signing_salt: "vUVLAO0L"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  chess_ex_ui: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  chess_ex_ui: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Expose the environment for future reference
config :chess_ex_ui, :config_env, config_env()

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
