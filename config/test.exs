import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chess_ex_ui, ChessUIWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "XAy0GDwCe09xan5annWbaGLFaFO4zzF0/pIIEzVO4F5fbEop+gc4QlTx6r9byI2j",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# A fast engine keeps the suite quick; the search itself is tested in chess_ex.
config :chess_ex_ui,
  engine_options: [strategy: :best, book: false],
  engine_min_think_ms: 0

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
