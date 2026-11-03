defmodule ChessUIWeb.Api.ErrorController do
  @moduledoc """
  Plain-text answers for API routes that do not exist or use the wrong method.

  These routes catch requests before Phoenix can raise `NoRouteError`, so the
  client never receives the HTML error page.
  """

  use ChessUIWeb, :controller

  def not_found(conn, _params) do
    text(conn, 404, "not found")
  end

  def method_not_allowed(conn, _params) do
    text(conn, 405, "method not allowed")
  end

  defp text(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message <> "\n")
  end
end
