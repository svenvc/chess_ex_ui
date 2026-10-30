defmodule ChessUIWeb.HistoryLiveTest do
  use ChessUIWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChessUI.{GameArchive, GameFixtures}

  setup do
    directory =
      Path.join([
        File.cwd!(),
        "tmp",
        "history_live_test",
        Integer.to_string(System.unique_integer([:positive]))
      ])

    previous = Application.get_env(:chess_ex_ui, :games_dir)
    Application.put_env(:chess_ex_ui, :games_dir, directory)
    File.rm_rf!(directory)

    on_exit(fn ->
      if previous do
        Application.put_env(:chess_ex_ui, :games_dir, previous)
      else
        Application.delete_env(:chess_ex_ui, :games_dir)
      end

      File.rm_rf(directory)
    end)

    {:ok, dir: directory}
  end

  test "shows an empty state when no game has been completed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history")

    assert has_element?(view, "#games-empty")
    assert has_element?(view, "#stat-total", "0")
    assert has_element?(view, "#history-play")
    refute has_element?(view, "#nav-history")
  end

  test "lists completed games newest first with stats", %{conn: conn, dir: dir} do
    older =
      save_game(GameFixtures.fools_mate(), %{
        player_color: :white,
        started_at: ~U[2026-10-29 10:00:00Z],
        ended_at: ~U[2026-10-29 10:01:00Z]
      })

    middle =
      save_game(GameFixtures.short_game(), %{
        player_color: :black,
        resigned_by: :white,
        started_at: ~U[2026-10-30 10:00:00Z],
        ended_at: ~U[2026-10-30 10:01:00Z]
      })

    newer =
      save_game(GameFixtures.short_game(), %{
        player_color: :white,
        resigned_by: :white,
        started_at: ~U[2026-10-30 11:00:00Z],
        ended_at: ~U[2026-10-30 11:01:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/history")

    assert has_element?(view, "#game-#{newer}[data-result='0-1'][data-outcome='engine_win']")
    assert has_element?(view, "#game-#{middle}[data-result='0-1'][data-outcome='visitor_win']")
    assert has_element?(view, "#game-#{older}[data-result='0-1'][data-outcome='engine_win']")

    assert has_element?(view, "#game-#{middle}", "Visitor wins")
    assert has_element?(view, "#stat-total", "3")
    assert has_element?(view, "#stat-visitor-wins", "1")
    assert has_element?(view, "#stat-engine-wins", "2")
    assert has_element?(view, "#stat-draws", "0")

    document = LazyHTML.from_fragment(render(view))

    ids =
      document
      |> LazyHTML.query("#games > [id^='game-']")
      |> LazyHTML.attribute("id")

    assert ids == ["game-#{newer}", "game-#{middle}", "game-#{older}"]

    download_class =
      document
      |> LazyHTML.query("#download-#{newer}")
      |> LazyHTML.attribute("class")
      |> List.first()

    assert download_class =~ "border"
    assert File.exists?(Path.join(dir, newer <> ".pgn"))
  end

  test "downloads a game as PGN", %{conn: conn} do
    id =
      save_game(GameFixtures.fools_mate(), %{
        player_color: :white,
        started_at: ~U[2026-10-30 10:00:00Z],
        ended_at: ~U[2026-10-30 10:01:00Z]
      })

    conn = get(conn, ~p"/history/#{id}/download")

    assert response(conn, 200) =~ "[Event \"Chess Ex Web UI\"]"
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-chess-pgn"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "chess-ex-#{id}.pgn"
  end

  test "returns 404 for an unknown download", %{conn: conn} do
    conn = get(conn, ~p"/history/#{GameArchive.new_id()}/download")

    assert response(conn, 404) == "Game not found"
  end

  test "replays a game move by move", %{conn: conn} do
    id =
      save_game(GameFixtures.fools_mate(), %{
        player_color: :white,
        started_at: ~U[2026-10-30 10:00:00Z],
        ended_at: ~U[2026-10-30 10:01:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/history/#{id}")

    assert has_element?(view, "#board[data-orientation='white']")
    refute has_element?(view, "#nav-history")
    assert has_element?(view, "#replay-step", "Move 4 of 4")
    assert has_element?(view, "#replay-status", "Engine wins")
    assert has_element?(view, "#replay-move-1")
    assert has_element?(view, "#replay-move-4")
    assert has_element?(view, "#game-id", id)
    assert has_element?(view, "#back-to-history[href='/history']")
    assert has_element?(view, "#download-pgn[href='/history/#{id}/download']")
    assert has_element?(view, "dt", "Started")
    refute has_element?(view, "dt", "Played")
    refute has_element?(view, "dt", "Visitor")
    refute has_element?(view, "dt", "App")
    refute render(view) =~ "phx-click=\"square_click\""

    view |> element("#replay-prev") |> render_click()
    assert has_element?(view, "#replay-step", "Move 3 of 4")

    view |> element("#replay-first") |> render_click()
    assert has_element?(view, "#replay-step", "Start position")

    view |> element("#replay-move-2") |> render_click()
    assert has_element?(view, "#replay-step", "Move 2 of 4")

    view |> element("#replay-next") |> render_click()
    assert has_element?(view, "#replay-step", "Move 3 of 4")

    view |> element("#replay-last") |> render_click()
    assert has_element?(view, "#replay-step", "Move 4 of 4")
  end

  test "redirects to the history page for an unknown game", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/history"}}} =
             live(conn, ~p"/history/#{GameArchive.new_id()}")
  end

  defp save_game(game, metadata) do
    {:ok, id} = GameArchive.save(game, metadata)
    id
  end
end
