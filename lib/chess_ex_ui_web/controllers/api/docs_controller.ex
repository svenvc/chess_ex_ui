defmodule ChessUIWeb.Api.DocsController do
  @moduledoc """
  The plain-text description of the REST API at `GET /api`.
  """

  use ChessUIWeb, :controller

  alias ChessUI.Api.Config

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text())
  end

  defp text do
    max_games = Config.get(:max_games)
    ttl = Config.get(:game_ttl_seconds)
    max_age = Config.get(:max_game_age_seconds)
    rate_limit = Config.get(:rate_limit)
    {create_limit, create_window} = Map.fetch!(rate_limit, :create)
    {move_limit, move_window} = Map.fetch!(rate_limit, :move)

    """
    Chess Ex API
    ============

    Anonymous, no signup. Successful game responses are text/plain FEN.
    Extra state is in X-Chess-* response headers.

    POST /api/games[?color=white|black]
      Create a game. The default color is white.
      201 Created, Location: /api/games/{id}, body: FEN.

    GET /api/games/{id}
      200 OK, body: FEN.
      404 Not Found when the game is unknown or has expired.

    POST /api/games/{id}/move
      Body: a move for your side, or empty for the engine's move.
      Moves may be SAN (e4, Nf3, O-O, exd5, e8=Q) or UCI (e2e4, e7e8q).
      The body is plain text; no content type is required.
      JSON request bodies are not supported and are rejected with 415.
      A body of "resign" resigns your side; chess has no SAN for resignation.
      200 OK, body: FEN.
      404 Not Found, 409 Conflict for a wrong turn or a finished game,
      422 Unprocessable Entity for an illegal or ambiguous move.

    Example:

      curl -i -X POST http://localhost:4000/api/games
      curl -i http://localhost:4000/api/games/{id}
      curl -i -X POST --data 'e4' http://localhost:4000/api/games/{id}/move
      curl -i -X POST http://localhost:4000/api/games/{id}/move

    Headers on a game response include:

      X-Chess-Game-Id, X-Chess-Side-To-Move, X-Chess-Player-Color,
      X-Chess-Your-Turn, X-Chess-Status, X-Chess-Result, X-Chess-Ply,
      X-Chess-Last-Move, X-Chess-Game-Over and, once archived,
      X-Chess-Recorded-Game.

    Games live in memory for #{ttl} seconds after the last request (at most
    #{max_age} seconds from creation) and are lost when the application
    restarts. At most #{max_games} games are kept. Finished games are archived
    at /history.

    Rate limits per client address: #{create_limit} game creations per
    #{create_window}s and #{move_limit} move requests per #{move_window}s.
    A limited request gets 429 with Retry-After.

    Errors are text/plain. Unknown API paths return 404, wrong methods 405 and
    malformed bodies 400, all as plain text, not Phoenix HTML pages.
    JSON request bodies return 415.

    Promotion without a piece in UCI notation defaults to a queen.
    """
  end
end
