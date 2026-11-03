defmodule ChessUIWeb.Plugs.ProxyRewrite do
  @moduledoc """
  Applies `Plug.RewriteOn` when the deployment trusts its reverse proxy.

  The rewrites are read from `config :chess_ex_ui, :proxy_rewrite_on` at
  runtime, so an operator can enable them without rebuilding the release. The
  default is an empty list, which leaves the connection untouched.

  Only enable a rewrite when the proxy strips or overwrites the corresponding
  `X-Forwarded-*` header. Otherwise a client can spoof its address or scheme.

  In production the list comes from `CHESS_EX_UI_PROXY_REWRITE_ON`, a
  comma-separated list of `x_forwarded_for`, `x_forwarded_proto`,
  `x_forwarded_host` and `x_forwarded_port`.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:chess_ex_ui, :proxy_rewrite_on, []) |> List.wrap() do
      [] -> conn
      rewrites -> Plug.RewriteOn.call(conn, rewrites)
    end
  end
end
