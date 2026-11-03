defmodule ChessUIWeb.Api.ErrorText do
  @moduledoc """
  Plain-text error view for API requests.

  Phoenix uses this for unexpected errors raised inside an API controller.
  Expected API mistakes - unknown routes, wrong methods and malformed bodies -
  are answered directly by `ChessUIWeb.Api.ErrorController` and
  `ChessUIWeb.Plugs.Parsers`.
  """

  @doc """
  Render an error as a single line of plain text.
  """
  def render(_template, assigns) do
    status = Map.get(assigns, :status, 500)
    message = Phoenix.Controller.status_message_from_template("#{status}.text")
    detail = detail(status, Map.get(assigns, :reason))

    ([message | List.wrap(detail)] |> Enum.join(": ")) <> "\n"
  end

  # A parser or media-type error has a useful message; a server error does not
  # need to leak its internals to the client.
  defp detail(status, reason) when status in [400, 415] do
    if is_exception(reason), do: Exception.message(reason)
  end

  defp detail(_status, _reason), do: nil
end
