defmodule ChessUIWeb.ChessBoardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Chess.{FEN, Game}
  alias ChessUIWeb.{ChessAssets, ChessBoard}

  test "white orientation runs from a8 to h1" do
    assert hd(ChessBoard.squares(:white)) == :a8
    assert List.last(ChessBoard.squares(:white)) == :h1

    assert ChessBoard.files(:white) == [:a, :b, :c, :d, :e, :f, :g, :h]
    assert ChessBoard.ranks(:white) == [8, 7, 6, 5, 4, 3, 2, 1]
  end

  test "black orientation runs from h1 to a8" do
    assert hd(ChessBoard.squares(:black)) == :h1
    assert List.last(ChessBoard.squares(:black)) == :a8

    assert ChessBoard.files(:black) == [:h, :g, :f, :e, :d, :c, :b, :a]
    assert ChessBoard.ranks(:black) == [1, 2, 3, 4, 5, 6, 7, 8]
  end

  test "the selected assets are the blue board and the gioco set" do
    assert ChessAssets.board_theme() == :blue
    assert ChessAssets.piece_set() == :gioco
    assert ChessAssets.board_image() == "/images/boards/blue.png"
  end

  test "piece image paths use the lichess file naming" do
    assert ChessAssets.piece_image(:K) == "/images/pieces/gioco/wK.svg"
    assert ChessAssets.piece_image(:q) == "/images/pieces/gioco/bQ.svg"
    assert ChessAssets.piece_file(:N) == "wN"
    assert ChessAssets.piece_file(:p) == "bP"
  end

  test "check_square is nil when the side to move is not in check" do
    assert ChessBoard.check_square(Game.new()) == nil
  end

  test "check_square is the square of the checked king" do
    assert ChessBoard.check_square(FEN.parse("4k3/8/8/8/8/8/8/4R1K1 b - - 0 1")) == :e8
  end

  test "check_square still finds the king when the check is checkmate" do
    game = FEN.parse("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")

    assert Game.status(game) == :checkmate
    assert ChessBoard.check_square(game) == :e1
  end

  test "only the king in check is marked" do
    game = FEN.parse("4k3/8/8/8/8/8/8/4R1K1 b - - 0 1")

    assert checked_squares(game) == ["square-e8"]

    labels =
      game
      |> render_board()
      |> LazyHTML.query("#square-e8")
      |> LazyHTML.attribute("aria-label")

    assert labels == ["e8, black king, in check"]
  end

  test "no square is marked when neither king is in check" do
    assert checked_squares(Game.new()) == []
  end

  test "a read-only board does not send square clicks" do
    html =
      render_component(&ChessBoard.board/1,
        game: Game.new(),
        orientation: :white,
        selected: nil,
        targets: nil,
        disabled: true,
        busy: false,
        interactive: false
      )

    refute html =~ "phx-click=\"square_click\""
    assert html =~ "disabled"
    assert html =~ "aria-disabled=\"true\""
  end

  defp checked_squares(game) do
    game
    |> render_board()
    |> LazyHTML.query("[data-check='true']")
    |> LazyHTML.attribute("id")
  end

  defp render_board(game) do
    render_component(&ChessBoard.board/1,
      game: game,
      orientation: :white,
      selected: nil,
      targets: nil,
      disabled: false,
      busy: false
    )
    |> LazyHTML.from_fragment()
  end
end
