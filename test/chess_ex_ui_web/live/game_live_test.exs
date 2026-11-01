defmodule ChessUIWeb.GameLiveTest do
  use ChessUIWeb.ConnCase

  import Phoenix.LiveViewTest

  test "serves the game at the root path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#board")
    assert has_element?(view, "#new-game")
    assert has_element?(view, "#history-link[href='/history']")
  end

  test "renders the board, coordinates and empty panels", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    assert has_element?(view, "#board[data-orientation='white']")
    assert has_element?(view, "#square-a8")
    assert has_element?(view, "#square-h1")
    assert has_element?(view, "#file-a", "a")
    assert has_element?(view, "#rank-8", "8")
    assert has_element?(view, "#status", "White to move")
    assert has_element?(view, "#moves", "No moves yet")
    assert has_element?(view, "#result", "*")
    assert has_element?(view, "#turn-indicator[data-thinking='false']", "White to move")
    refute has_element?(view, "#move-1")

    document = LazyHTML.from_fragment(render(view))

    assert document
           |> LazyHTML.query("#board button")
           |> Enum.count() == 64
  end

  test "publishes the state attributes the black-box driver reads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    assert has_element?(
             view,
             "#board[data-fen='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1']" <>
               "[data-side-to-move='white'][data-ply='0'][data-busy='false']"
           )

    assert has_element?(view, "#moves[data-ply='0']")
    assert has_element?(view, "#status[data-game-over='false']")
    assert has_element?(view, "#result[data-result='*']")
    assert has_element?(view, "#turn-indicator[data-side-to-move='white'][data-thinking='false']")

    view |> element("#square-e2") |> render_click()
    view |> element("#square-e4") |> render_click()
    render_async(view)

    assert has_element?(view, "#board[data-ply='2'][data-side-to-move='white']")
    assert has_element?(view, "#moves[data-ply='2']")
  end

  test "selects a piece and shows its legal targets", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#square-e2") |> render_click()

    assert has_element?(view, "#square-e2[data-selected='true']")
    assert has_element?(view, "#square-e3[data-target='true']")
    assert has_element?(view, "#square-e4[data-target='true']")
    refute has_element?(view, "#square-e5[data-target='true']")
  end

  test "clicks another own piece to change the selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#square-e2") |> render_click()
    view |> element("#square-d2") |> render_click()

    assert has_element?(view, "#square-d2[data-selected='true']")
    refute has_element?(view, "#square-e2[data-selected='true']")
  end

  test "plays a legal move and lets the engine answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#square-e2") |> render_click()
    view |> element("#square-e4") |> render_click()
    render_async(view)

    assert has_element?(view, "#square-e4 img[src$='wP.svg']")
    refute has_element?(view, "#square-e2 img")
    assert has_element?(view, "#move-1-white", "e4")
    assert has_element?(view, "[data-ply='1']")
    assert has_element?(view, "[data-ply='2']")
    assert has_element?(view, "#status", "White to move")
    refute has_element?(view, "#square-e2[data-selected='true']")

    document = LazyHTML.from_fragment(render(view))

    assert document
           |> LazyHTML.query("#board [data-last-move='true']")
           |> Enum.count() == 2
  end

  test "an illegal second click does not make a move", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#square-e2") |> render_click()
    view |> element("#square-e5") |> render_click()

    assert has_element?(view, "#messages", "not a legal move")
    refute has_element?(view, "#move-1")
    refute has_element?(view, "#square-e2[data-selected='true']")
  end

  test "switching sides starts a new game with the engine as White", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#switch-sides") |> render_click()
    render_async(view)

    assert has_element?(view, "#board[data-orientation='black']")
    assert has_element?(view, "#status", "Black to move")
    assert has_element?(view, "#move-1-white[data-ply='1']")
    refute has_element?(view, "[data-ply='2']")
  end

  test "new game clears the position and the notation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#square-e2") |> render_click()
    view |> element("#square-e4") |> render_click()
    render_async(view)
    assert has_element?(view, "#move-1-white", "e4")

    view |> element("#new-game") |> render_click()

    assert has_element?(view, "#moves", "No moves yet")
    refute has_element?(view, "[data-ply='1']")
    assert has_element?(view, "#status", "White to move")
  end

  test "resigning ends the game and further clicks are ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/game")

    view |> element("#resign") |> render_click()

    assert has_element?(view, "#status", "You resigned")
    assert has_element?(view, "#turn-indicator", "Game over")
    assert has_element?(view, "#result", "0-1")
    assert has_element?(view, "#resign[disabled]")

    view |> element("#square-e2") |> render_click()

    refute has_element?(view, "#square-e2[data-selected='true']")
    assert has_element?(view, "#messages", "game is over")
  end

  describe "about dialog" do
    test "the title opens the dialog with the runtime details", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      refute has_element?(view, "#about-dialog")

      view |> element("#about-title") |> render_click()

      assert has_element?(view, "#about-dialog")
      assert has_element?(view, "#about-panel[role='dialog'][aria-modal='true']")
      assert has_element?(view, "#about-heading", "About Chess Ex Web UI")
      assert has_element?(view, "#about-panel a[href='https://git.stfx.eu/sven/chess_ex_ui']")
      assert has_element?(view, "#about-panel a[href='https://git.stfx.eu/sven/chess_ex']")
      assert has_element?(view, "#about-panel a[href='https://www.phoenixframework.org']")
      assert has_element?(view, "#about-panel a[href='https://lichess.org']")

      info = ChessUI.SystemInfo.all()

      assert has_element?(view, "#system-info-application th", "Application")
      assert has_element?(view, "#system-info-application_version", info.application_version)
      assert has_element?(view, "#system-info-elixir_version", info.elixir_version)

      assert has_element?(
               view,
               "#system-info-erlang_otp_version",
               info.erlang_otp_version || "unknown"
             )

      document = LazyHTML.from_fragment(render(view))

      assert document
             |> LazyHTML.query("#system-info tbody tr")
             |> Enum.count() == map_size(info)
    end

    test "the close and dismiss buttons hide the dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#about-title") |> render_click()
      assert has_element?(view, "#about-dialog")

      view |> element("#about-close") |> render_click()
      refute has_element?(view, "#about-dialog")

      view |> element("#about-title") |> render_click()
      view |> element("#about-dismiss") |> render_click()
      refute has_element?(view, "#about-dialog")
    end

    test "the backdrop and Escape close the dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#about-title") |> render_click()
      view |> element("#about-backdrop") |> render_click()
      refute has_element?(view, "#about-dialog")

      view |> element("#about-title") |> render_click()
      view |> element("#about-dialog") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#about-dialog")
    end
  end

  describe "engine thinking" do
    setup do
      install_test_engine()
      :ok
    end

    test "locks the board and shows the thinking state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#square-e2") |> render_click()
      view |> element("#square-e4") |> render_click()

      assert has_element?(view, "#turn-indicator[data-thinking='true']", "Engine thinking")
      assert has_element?(view, "#board[data-busy='true'][aria-busy='true']")

      view |> element("#square-g1") |> render_click()

      refute has_element?(view, "#square-g1[data-selected='true']")

      render_async(view, 1_000)

      assert has_element?(view, "#turn-indicator[data-thinking='false']")
      assert has_element?(view, "#board[data-busy='false'][aria-busy='false']")
      assert has_element?(view, "#status", "White to move")
      assert has_element?(view, "[data-ply='2']")
    end

    test "a new game during the engine turn discards the stale move", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#square-e2") |> render_click()
      view |> element("#square-e4") |> render_click()
      assert has_element?(view, "#turn-indicator[data-thinking='true']")

      view |> element("#new-game") |> render_click()

      assert has_element?(view, "#moves", "No moves yet")
      assert has_element?(view, "#turn-indicator[data-thinking='false']")

      # Wait past the point where the cancelled search would have answered.
      Process.sleep(400)

      assert has_element?(view, "#moves", "No moves yet")
      refute has_element?(view, "[data-ply='2']")
      assert has_element?(view, "#turn-indicator[data-thinking='false']")
    end

    test "resigning during the engine turn ends the game", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#square-e2") |> render_click()
      view |> element("#square-e4") |> render_click()
      assert has_element?(view, "#turn-indicator[data-thinking='true']")

      view |> element("#resign") |> render_click()

      assert has_element?(view, "#status", "You resigned")
      assert has_element?(view, "#turn-indicator[data-thinking='false']", "Game over")
      assert has_element?(view, "#result", "0-1")
      assert has_element?(view, "#board[data-busy='false']")
    end
  end

  describe "game records" do
    setup do
      directory =
        Path.join([
          File.cwd!(),
          "tmp",
          "game_live_test",
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

    test "records a resigned game and links to it", %{conn: conn, dir: dir} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#resign") |> render_click()

      assert has_element?(view, "#recorded-game", "Saved to history")
      assert has_element?(view, "#view-recorded-game")

      assert [file] = recorded_files(dir)
      id = Path.rootname(file)

      assert has_element?(view, "#recorded-game[data-game-id='#{id}']")
      assert has_element?(view, "#status[data-game-over='true']")
      assert has_element?(view, "#result[data-result='0-1']")
      assert has_element?(view, "#download-pgn[href='/history/#{id}/download']")
      assert File.read!(Path.join(dir, file)) =~ ~s([TerminationReason "resignation"])
    end

    test "does not record an abandoned game", %{conn: conn, dir: dir} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#square-e2") |> render_click()
      view |> element("#square-e4") |> render_click()
      render_async(view)

      view |> element("#new-game") |> render_click()
      view |> element("#switch-sides") |> render_click()

      assert recorded_files(dir) == []
      refute has_element?(view, "#recorded-game")
    end

    test "does not record the same game twice", %{conn: conn, dir: dir} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view |> element("#resign") |> render_click()
      render_click(view, "resign", %{})

      assert length(recorded_files(dir)) == 1
    end
  end

  defp recorded_files(dir) do
    case File.ls(dir) do
      {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".pgn"))
      {:error, :enoent} -> []
    end
  end

  defp install_test_engine do
    previous = Application.get_env(:chess_ex_ui, :engine)
    Application.put_env(:chess_ex_ui, :engine, ChessUI.TestEngine)

    on_exit(fn ->
      if previous do
        Application.put_env(:chess_ex_ui, :engine, previous)
      else
        Application.delete_env(:chess_ex_ui, :engine)
      end
    end)
  end
end
