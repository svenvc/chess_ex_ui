defmodule ChessUI.Api.MoveTest do
  use ExUnit.Case, async: true

  alias Chess.{FEN, Game, Rules, SAN}
  alias ChessUI.Api.Move
  alias ChessUI.GameFixtures

  describe "command/1" do
    test "an empty body asks the engine to move" do
      assert Move.command("") == :engine
      assert Move.command("   \n") == :engine
      assert Move.command(nil) == :engine
    end

    test "resign is a reserved command" do
      assert Move.command("resign") == :resign
      assert Move.command("RESIGN") == :resign
    end

    test "anything else is a move" do
      assert Move.command("e4") == :move
    end
  end

  describe "SAN" do
    test "parses a pawn move" do
      assert {:ok, move} = Move.parse("e4", Game.new())
      assert SAN.to_san(move, Game.new()) == "e4"
    end

    test "parses a piece move" do
      game = GameFixtures.game(~w(e4 e5))
      assert {:ok, move} = Move.parse("Nf3", game)
      assert SAN.to_san(move, game) == "Nf3"
    end

    test "accepts a missing check marker" do
      game = GameFixtures.game(~w(f3 e5 g4))
      assert {:ok, move} = Move.parse("Qh4", game)
      assert Rules.apply(game, move) |> Chess.Game.status() == :checkmate
    end

    test "accepts a check marker" do
      game = GameFixtures.game(~w(e4 e5))
      assert {:ok, move} = Move.parse("Qh5", game)
      assert SAN.to_san(move, game) == "Qh5"
    end

    test "parses castling" do
      game = GameFixtures.game(~w(e4 e5 Nf3 Nc6 Bc4 Nf6))
      assert {:ok, move} = Move.parse("O-O", game)
      assert SAN.to_san(move, game) == "O-O"
    end

    test "parses an en passant capture" do
      game = FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
      assert {:ok, move} = Move.parse("exd6", game)
      assert SAN.to_san(move, game) == "exd6"
    end

    test "parses a promotion" do
      game = FEN.parse("k7/4P3/8/8/8/8/8/4K3 w - - 0 1")
      assert {:ok, move} = Move.parse("e8=Q", game)
      assert SAN.to_san(move, game) == "e8=Q+"
    end

    test "normalizes a move number and annotations" do
      game = GameFixtures.game(~w(e4 e5))
      assert {:ok, move} = Move.parse("2. Nf3!", game)
      assert SAN.to_san(move, game) == "Nf3"
    end

    test "reports an ambiguous move" do
      game = FEN.parse("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")
      assert {:error, {:ambiguous, _message}} = Move.parse("Nd2", game)
    end

    test "reports an illegal move" do
      assert {:error, {:illegal, _message}} = Move.parse("e5", Game.new())
    end
  end

  describe "UCI" do
    test "parses a coordinate move" do
      assert {:ok, move} = Move.parse("e2e4", Game.new())
      assert SAN.to_san(move, Game.new()) == "e4"
    end

    test "accepts a separator" do
      assert {:ok, move} = Move.parse("e2-e4", Game.new())
      assert SAN.to_san(move, Game.new()) == "e4"
    end

    test "parses a promotion" do
      game = FEN.parse("k7/4P3/8/8/8/8/8/4K3 w - - 0 1")
      assert {:ok, move} = Move.parse("e7e8q", game)
      assert SAN.to_san(move, game) == "e8=Q+"
    end

    test "defaults a promotion to a queen" do
      game = FEN.parse("k7/4P3/8/8/8/8/8/4K3 w - - 0 1")
      assert {:ok, move} = Move.parse("e7e8", game)
      assert SAN.to_san(move, game) == "e8=Q+"
    end

    test "reports an illegal coordinate move" do
      assert {:error, {:illegal, _message}} = Move.parse("e2e5", Game.new())
    end
  end
end
