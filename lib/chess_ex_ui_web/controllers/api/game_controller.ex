defmodule ChessUIWeb.Api.GameController do
  @moduledoc """
  The anonymous REST API for playing against the engine.

  Successful responses are the position as FEN; the rest of the state is in
  `X-Chess-*` headers. See `ChessUIWeb.Api.DocsController` for the public
  description.
  """

  use ChessUIWeb, :controller

  alias Chess.FEN
  alias ChessUI.Api
  alias ChessUI.Api.Config
  alias ChessUI.GameArchive

  def create(conn, params) do
    case Api.create_game(player_color(params), conn.remote_ip) do
      {:ok, entry} ->
        conn
        |> put_resp_header("location", "/api/games/#{entry.id}")
        |> respond(entry, 201)

      {:error, :at_capacity} ->
        error(conn, 503, "no game slots available, try again later")

      {:error, :too_many_games} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(Config.get(:game_ttl_seconds)))
        |> error(429, "too many active games for this address")

      {:error, _reason} ->
        error(conn, 500, "could not create a game")
    end
  end

  def show(conn, %{"id" => id}) do
    case Api.get_game(id) do
      {:ok, entry} -> respond(conn, entry, 200)
      :error -> error(conn, 404, "game not found")
    end
  end

  def show(conn, _params), do: error(conn, 404, "game not found")

  def move(conn, %{"id" => id} = params) do
    case move_input(conn, params) do
      {:too_large, conn} ->
        error(conn, 413, "request body too large")

      {:bad_request, conn} ->
        error(conn, 400, "no move in the request body")

      {input, conn} ->
        case Api.play_move(id, input) do
          {:ok, entry} -> respond(conn, entry, 200)
          {:error, reason} -> error_for(conn, reason)
        end
    end
  end

  def move(conn, _params), do: error(conn, 404, "game not found")

  ## Response

  defp respond(conn, entry, status) do
    outcome = GameArchive.outcome(entry.game, entry.resigned_by)

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("x-chess-game-id", entry.id)
    |> put_resp_header("x-chess-side-to-move", to_string(entry.game.side_to_move))
    |> put_resp_header("x-chess-player-color", to_string(entry.player_color))
    |> put_resp_header("x-chess-your-turn", to_string(Api.your_turn?(entry)))
    |> put_resp_header("x-chess-status", to_string(Api.status(entry)))
    |> put_resp_header("x-chess-result", outcome.result)
    |> put_resp_header("x-chess-ply", Integer.to_string(length(entry.game.moves)))
    |> put_resp_header("x-chess-last-move", entry.last_move || "")
    |> put_resp_header("x-chess-game-over", to_string(Api.finished?(entry)))
    |> put_recorded_header(entry)
    |> send_resp(status, FEN.to_fen(entry.game))
  end

  defp put_recorded_header(conn, %{recorded_id: nil}), do: conn

  defp put_recorded_header(conn, %{recorded_id: id}),
    do: put_resp_header(conn, "x-chess-recorded-game", id)

  defp error(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message <> "\n")
  end

  defp error_for(conn, :not_found), do: error(conn, 404, "game not found")
  defp error_for(conn, :game_over), do: error(conn, 409, "the game is over")
  defp error_for(conn, :not_your_turn), do: error(conn, 409, "not your turn")
  defp error_for(conn, :not_engine_turn), do: error(conn, 409, "not the engine's turn")
  defp error_for(conn, :busy), do: error(conn, 409, "the engine is already thinking")

  defp error_for(conn, :engine_capacity),
    do: error(conn, 503, "the engine is busy, try again later")

  defp error_for(conn, :timeout), do: error(conn, 504, "the engine timed out")

  defp error_for(conn, {:engine, reason}),
    do: error(conn, 503, "the engine could not move: #{inspect(reason)}")

  defp error_for(conn, {:illegal, message}), do: error(conn, 422, "illegal move: #{message}")

  defp error_for(conn, {:ambiguous, message}),
    do: error(conn, 422, "ambiguous move: #{message}")

  defp error_for(conn, :promotion_required),
    do: error(conn, 422, "a promotion piece is required")

  defp error_for(conn, _reason), do: error(conn, 422, "illegal move")

  ## Input

  defp player_color(%{"color" => color}) when is_binary(color) do
    case String.downcase(color) do
      "black" -> :black
      "b" -> :black
      _other -> :white
    end
  end

  defp player_color(_params), do: :white

  defp move_input(conn, params) do
    if is_binary(params["move"]) do
      {params["move"], conn}
    else
      read_text_body(conn)
    end
  end

  defp read_text_body(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        case read_body(conn, length: 1_000_000, read_length: 64_000) do
          {:ok, body, conn} -> {body, conn}
          {:more, _body, conn} -> {:too_large, conn}
          {:error, _reason} -> {:bad_request, conn}
        end

      %{} = params ->
        case params["move"] do
          move when is_binary(move) ->
            {move, conn}

          _other ->
            # `curl --data 'e4'` without a content type is form-encoded and
            # arrives as `%{"e4" => ""}`. Treat a single valueless field as the
            # move token so the obvious command line works.
            case Map.to_list(params) do
              [] -> {"", conn}
              [{move, value}] when is_binary(move) and value in ["", nil] -> {move, conn}
              _other -> {:bad_request, conn}
            end
        end

      _other ->
        {"", conn}
    end
  end
end
