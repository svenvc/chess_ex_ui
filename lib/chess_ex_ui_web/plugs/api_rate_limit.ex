defmodule ChessUIWeb.Plugs.ApiRateLimit do
  @moduledoc """
  Rate limits requests to the anonymous REST API by client address.

  The bucket is derived from the route: creating a game, moving, and reading
  have separate limits. A rejected request gets `429` and `Retry-After`.

  Addresses come from `conn.remote_ip`. Behind a reverse proxy, enable
  `ChessUIWeb.Plugs.ProxyRewrite` with `CHESS_EX_UI_PROXY_REWRITE_ON` so the
  proxy does not become the only address the limiter sees.
  """

  import Plug.Conn

  alias ChessUI.Api.RateLimit

  def init(opts), do: opts

  def call(conn, _opts) do
    bucket = bucket(conn)

    case RateLimit.hit(bucket, address(conn)) do
      {:ok, _remaining} ->
        conn

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_resp_content_type("text/plain")
        |> send_resp(429, "rate limit exceeded, retry in #{retry_after}s\n")
        |> halt()
    end
  end

  defp bucket(%{method: "POST", request_path: path}) do
    if String.ends_with?(path, "/move"), do: :move, else: :create
  end

  defp bucket(_conn), do: :read

  defp address(conn) do
    case conn.remote_ip do
      nil -> "unknown"
      ip -> ip |> :inet.ntoa() |> to_string()
    end
  end
end
