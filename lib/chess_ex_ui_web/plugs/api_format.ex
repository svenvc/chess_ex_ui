defmodule ChessUIWeb.Plugs.ApiFormat do
  @moduledoc """
  Marks requests under `/api` with the `text` format.

  Phoenix renders errors through the format stored on the connection. Setting
  it before `Plug.Parsers` and the router means a malformed body or an unknown
  API route is rendered by `ChessUIWeb.Api.ErrorText` instead of the HTML error
  page.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if api?(conn) do
      Plug.Conn.put_private(conn, :phoenix_format, "text")
    else
      conn
    end
  end

  defp api?(conn) do
    conn.request_path == "/api" or String.starts_with?(conn.request_path, "/api/")
  end
end
