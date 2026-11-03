import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/chess_ex_ui start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :chess_ex_ui, ChessUIWeb.Endpoint, server: true
end

if games_dir = System.get_env("CHESS_EX_UI_GAMES_DIR") do
  config :chess_ex_ui, games_dir: Path.expand(games_dir)
end

# Behind a reverse proxy, rewrite the connection from the X-Forwarded-* headers
# only when the proxy strips or overwrites them. The value is a comma-separated
# list of Plug.RewriteOn options:
#
#   x_forwarded_for, x_forwarded_proto, x_forwarded_host, x_forwarded_port
#
# For example, a Caddy edge needs only the client address for the API rate
# limiter:
#
#   CHESS_EX_UI_PROXY_REWRITE_ON=x_forwarded_for
#
# Unset or empty leaves the connection untouched.
if proxy_rewrite_on = System.get_env("CHESS_EX_UI_PROXY_REWRITE_ON") do
  rewrites =
    proxy_rewrite_on
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.downcase/1)
    |> Enum.map(fn
      "x_forwarded_for" -> :x_forwarded_for
      "x_forwarded_proto" -> :x_forwarded_proto
      "x_forwarded_host" -> :x_forwarded_host
      "x_forwarded_port" -> :x_forwarded_port
      other -> raise "unknown CHESS_EX_UI_PROXY_REWRITE_ON value: #{inspect(other)}"
    end)

  config :chess_ex_ui, proxy_rewrite_on: rewrites
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "lhn+mhcWUKL5NN+qKaFDbvG6W1P0/GdnmE8WxdICu/53NEJHRMwthoC+4E2bYC4m"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :chess_ex_ui, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :chess_ex_ui, ChessUIWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :chess_ex_ui, ChessUIWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :chess_ex_ui, ChessUIWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
