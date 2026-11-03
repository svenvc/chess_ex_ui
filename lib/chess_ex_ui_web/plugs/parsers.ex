defmodule ChessUIWeb.Plugs.Parsers do
  @moduledoc """
  Wraps `Plug.Parsers` to keep API request bodies plain text.

  A JSON body is not part of the API contract, so an API request with a JSON
  content type is rejected with `415` and a plain-text message. Other malformed
  bodies or query strings are also answered as plain text.

  For non-API paths the error is re-raised so the browser and development
  debugger behave as usual.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: Plug.Parsers.init(opts)

  @impl true
  def call(conn, opts) do
    if api?(conn) and json?(conn) do
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(415, "JSON is not supported; send a plain-text body\n")
      |> Plug.Conn.halt()
    else
      Plug.Parsers.call(conn, opts)
    end
  rescue
    error in [
      Plug.Parsers.ParseError,
      Plug.Parsers.UnsupportedMediaTypeError,
      Plug.Parsers.RequestTooLargeError,
      Plug.Parsers.BadEncodingError,
      Plug.Conn.InvalidQueryError
    ] ->
      if api?(conn) do
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(status(error), Exception.message(error) <> "\n")
        |> Plug.Conn.halt()
      else
        reraise error, __STACKTRACE__
      end
  end

  defp api?(conn) do
    conn.request_path == "/api" or String.starts_with?(conn.request_path, "/api/")
  end

  defp json?(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [header | _rest] ->
        case Plug.Conn.Utils.content_type(header) do
          {:ok, _type, "json", _params} -> true
          {:ok, _type, subtype, _params} -> String.ends_with?(subtype, "+json")
          :error -> false
        end

      [] ->
        false
    end
  end

  defp status(%{plug_status: status}) when is_integer(status), do: status
  defp status(_error), do: 400
end
