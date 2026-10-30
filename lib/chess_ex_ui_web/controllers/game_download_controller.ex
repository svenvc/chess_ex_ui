defmodule ChessUIWeb.GameDownloadController do
  @moduledoc """
  Serves an archived game as a downloadable PGN file.
  """

  use ChessUIWeb, :controller

  alias ChessUI.GameArchive

  def download(conn, %{"id" => id}) do
    case GameArchive.file_path(id) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/x-chess-pgn")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"chess-ex-#{id}.pgn\""
        )
        |> send_file(200, path)

      :error ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Game not found")
    end
  end
end
