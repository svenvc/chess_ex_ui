defmodule ChessUIWeb.Api.GameControllerTest do
  use ChessUIWeb.ConnCase, async: false

  alias ChessUI.Api.{Config, GameStore, RateLimit}
  alias ChessUI.GameArchive

  setup do
    previous_api = Application.get_env(:chess_ex_ui, :api)
    previous_engine = Application.get_env(:chess_ex_ui, :engine)

    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(),
        max_games: 100,
        max_games_per_ip: 100,
        game_ttl_seconds: 3_600,
        max_game_age_seconds: 86_400,
        max_engine_concurrency: 4,
        rate_limit: %{create: {100, 60}, move: {100, 60}, read: {100, 60}}
      )
    )

    Application.delete_env(:chess_ex_ui, :engine)
    GameStore.reset()
    RateLimit.reset()

    on_exit(fn ->
      GameStore.reset()
      RateLimit.reset()
      restore(:api, previous_api)
      restore(:engine, previous_engine)
    end)

    :ok
  end

  test "describes the API", %{conn: conn} do
    conn = get(conn, "/api")

    assert conn.status == 200
    assert conn.resp_body =~ "POST /api/games"
    assert conn.resp_body =~ "resign"
    assert hd(get_resp_header(conn, "content-type")) =~ "text/plain"
  end

  test "creates a game", %{conn: conn} do
    conn = post(conn, "/api/games")

    assert conn.status == 201
    assert [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, "/api/games/")
    assert conn.resp_body == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    assert get_resp_header(conn, "x-chess-player-color") == ["white"]
    assert get_resp_header(conn, "x-chess-your-turn") == ["true"]
    assert get_resp_header(conn, "x-chess-status") == ["ongoing"]
    assert get_resp_header(conn, "x-chess-result") == ["*"]
  end

  test "creates a game as Black", %{conn: conn} do
    conn = post(conn, "/api/games?color=black")

    assert conn.status == 201
    assert get_resp_header(conn, "x-chess-player-color") == ["black"]
    assert get_resp_header(conn, "x-chess-your-turn") == ["false"]
    assert get_resp_header(conn, "x-chess-side-to-move") == ["white"]
  end

  test "fetches a game", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = get(conn, "/api/games/#{id}")

    assert conn.status == 200
    assert conn.resp_body =~ "rnbqkbnr"
    assert get_resp_header(conn, "x-chess-game-id") == [id]
  end

  test "plays a human move", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post_move(conn, id, "e4")

    assert conn.status == 200
    assert conn.resp_body == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    assert get_resp_header(conn, "x-chess-side-to-move") == ["black"]
    assert get_resp_header(conn, "x-chess-last-move") == ["e4"]
    assert get_resp_header(conn, "x-chess-ply") == ["1"]
    assert get_resp_header(conn, "x-chess-your-turn") == ["false"]
  end

  test "accepts a form-encoded move", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post(conn, "/api/games/#{id}/move", %{"e4" => ""})

    assert conn.status == 200
    assert get_resp_header(conn, "x-chess-last-move") == ["e4"]
  end

  test "rejects a body with no move", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post(conn, "/api/games/#{id}/move", %{"foo" => "bar"})

    assert conn.status == 400
    assert conn.resp_body =~ "no move in the request body"
  end

  test "plays an engine move", %{conn: conn} do
    {_conn, id} = create_game(conn, "?color=black")

    conn = post(conn, "/api/games/#{id}/move")

    assert conn.status == 200
    assert get_resp_header(conn, "x-chess-side-to-move") == ["black"]
    assert get_resp_header(conn, "x-chess-your-turn") == ["true"]
    assert get_resp_header(conn, "x-chess-ply") == ["1"]
    assert get_resp_header(conn, "x-chess-last-move") != [""]
  end

  test "rejects an empty move on the player's turn", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post(conn, "/api/games/#{id}/move")

    assert conn.status == 409
    assert conn.resp_body =~ "not the engine's turn"
  end

  test "rejects a move on the engine's turn", %{conn: conn} do
    {_conn, id} = create_game(conn, "?color=black")

    conn = post_move(conn, id, "e4")

    assert conn.status == 409
    assert conn.resp_body =~ "not your turn"
  end

  test "rejects an illegal move", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post_move(conn, id, "e5")

    assert conn.status == 422
    assert conn.resp_body =~ "illegal move"
  end

  test "returns 404 for an unknown game", %{conn: conn} do
    conn = get(conn, "/api/games/00000000-0000-4000-8000-000000000000")

    assert conn.status == 404
    assert conn.resp_body =~ "game not found"
  end

  test "returns a plain-text 404 for an unknown API path", %{conn: conn} do
    conn = get(conn, "/api/nope")

    assert conn.status == 404
    assert hd(get_resp_header(conn, "content-type")) =~ "text/plain"
    assert conn.resp_body == "not found\n"
  end

  test "returns a plain-text 405 for a wrong API method", %{conn: conn} do
    conn = put(conn, "/api/games")

    assert conn.status == 405
    assert hd(get_resp_header(conn, "content-type")) =~ "text/plain"
    assert conn.resp_body == "method not allowed\n"
  end

  test "rejects a JSON body on create", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/games", ~s({"color": "black"}))

    assert conn.status == 415
    assert hd(get_resp_header(conn, "content-type")) =~ "text/plain"
    assert conn.resp_body =~ "JSON is not supported"
  end

  test "rejects malformed JSON on create", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/games", "{bad")

    assert conn.status == 415
    assert conn.resp_body =~ "JSON is not supported"
  end

  test "rejects a JSON body on move", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/games/#{id}/move", ~s({"move": "e4"}))

    assert conn.status == 415
    assert conn.resp_body =~ "JSON is not supported"
  end

  test "keeps the HTML error page for non-API routes", %{conn: conn} do
    conn = get(conn, "/nope")

    assert conn.status == 404
    assert hd(get_resp_header(conn, "content-type")) =~ "text/html"
  end

  test "renders API errors as plain text" do
    assert ChessUIWeb.Api.ErrorText.render("500.text", %{
             status: 500,
             reason: %RuntimeError{message: "boom"}
           }) == "Internal Server Error\n"

    assert ChessUIWeb.Api.ErrorText.render("400.text", %{
             status: 400,
             reason: %Plug.Conn.InvalidQueryError{}
           }) =~ "Bad Request"
  end

  test "returns 404 for an expired game", %{conn: conn} do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), game_ttl_seconds: 0)
    )

    {_conn, id} = create_game(conn)
    assert :ok = GameStore.sweep()

    conn = get(conn, "/api/games/#{id}")

    assert conn.status == 404
  end

  test "resigns and archives the game", %{conn: conn} do
    {_conn, id} = create_game(conn)

    conn = post_move(conn, id, "resign")

    assert conn.status == 200
    assert get_resp_header(conn, "x-chess-status") == ["resigned"]
    assert get_resp_header(conn, "x-chess-result") == ["0-1"]
    assert get_resp_header(conn, "x-chess-game-over") == ["true"]

    assert [recorded_id] = get_resp_header(conn, "x-chess-recorded-game")
    assert {:ok, record} = GameArchive.get(recorded_id)
    assert record.summary.result == "0-1"
    assert record.summary.termination == "resignation"
    assert record.summary.player_color == :white
    assert record.summary.white == "API"
    assert record.summary.black == "ChessEx"
    assert record.pgn.headers["Event"] == "Chess Ex API Game"

    conn = post_move(conn, id, "e4")
    assert conn.status == 409
  end

  test "archives a checkmate", %{conn: conn} do
    Application.put_env(:chess_ex_ui, :engine, ChessUI.ApiTestEngine)

    {_conn, id} = create_game(conn)

    conn = post_move(conn, id, "f3")
    assert conn.status == 200

    conn = post(conn, "/api/games/#{id}/move")
    assert conn.status == 200

    conn = post_move(conn, id, "g4")
    assert conn.status == 200

    conn = post(conn, "/api/games/#{id}/move")
    assert conn.status == 200
    assert get_resp_header(conn, "x-chess-status") == ["checkmate"]
    assert get_resp_header(conn, "x-chess-result") == ["0-1"]
    assert get_resp_header(conn, "x-chess-game-over") == ["true"]

    assert [recorded_id] = get_resp_header(conn, "x-chess-recorded-game")
    assert {:ok, record} = GameArchive.get(recorded_id)
    assert record.summary.result == "0-1"
    assert record.summary.termination == "checkmate"

    conn = post_move(conn, id, "e4")
    assert conn.status == 409
  end

  test "rate limits game creation", %{conn: conn} do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(),
        rate_limit: %{create: {1, 60}, move: {100, 60}, read: {100, 60}}
      )
    )

    conn = post(conn, "/api/games")
    assert conn.status == 201

    conn = post(conn, "/api/games")
    assert conn.status == 429
    assert [_retry_after] = get_resp_header(conn, "retry-after")
  end

  test "rate limits by the forwarded address when proxy rewriting is enabled" do
    previous = Application.get_env(:chess_ex_ui, :proxy_rewrite_on)
    Application.put_env(:chess_ex_ui, :proxy_rewrite_on, [:x_forwarded_for])

    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(),
        rate_limit: %{create: {1, 60}, move: {100, 60}, read: {100, 60}}
      )
    )

    RateLimit.reset()

    on_exit(fn ->
      if previous do
        Application.put_env(:chess_ex_ui, :proxy_rewrite_on, previous)
      else
        Application.delete_env(:chess_ex_ui, :proxy_rewrite_on)
      end
    end)

    conn = forwarded_conn("203.0.113.1") |> post("/api/games")
    assert conn.status == 201

    conn = forwarded_conn("203.0.113.1") |> post("/api/games")
    assert conn.status == 429

    conn = forwarded_conn("203.0.113.2") |> post("/api/games")
    assert conn.status == 201
  end

  test "returns 503 when the store is full", %{conn: conn} do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), max_games: 1, max_games_per_ip: 100)
    )

    conn = post(conn, "/api/games")
    assert conn.status == 201

    conn = post(conn, "/api/games")
    assert conn.status == 503
    assert conn.resp_body =~ "no game slots"
  end

  test "returns 429 when an address has too many games", %{conn: conn} do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), max_games: 100, max_games_per_ip: 1)
    )

    conn = post(conn, "/api/games")
    assert conn.status == 201

    conn = post(conn, "/api/games")
    assert conn.status == 429
    assert conn.resp_body =~ "too many active games"
    assert [_retry_after] = get_resp_header(conn, "retry-after")
  end

  defp create_game(conn, query \\ "") do
    conn = post(conn, "/api/games" <> query)
    assert conn.status == 201
    [location] = get_resp_header(conn, "location")
    id = location |> String.split("/") |> List.last()
    {conn, id}
  end

  defp forwarded_conn(ip) do
    build_conn() |> put_req_header("x-forwarded-for", ip)
  end

  defp post_move(conn, id, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "text/plain")
    |> post("/api/games/#{id}/move", body)
  end

  defp restore(key, nil), do: Application.delete_env(:chess_ex_ui, key)
  defp restore(key, value), do: Application.put_env(:chess_ex_ui, key, value)
end
