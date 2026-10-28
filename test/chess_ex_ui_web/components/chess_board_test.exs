defmodule ChessUIWeb.ChessBoardTest do
  use ExUnit.Case, async: true

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
end
