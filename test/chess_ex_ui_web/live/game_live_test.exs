defmodule ChessUIWeb.GameLiveTest do
  use ChessUIWeb.ConnCase

  import Phoenix.LiveViewTest

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
