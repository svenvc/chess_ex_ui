defmodule ChessUI.GameFixtures do
  @moduledoc """
  Small, deterministic games for the history and archive tests.
  """

  alias Chess.{Game, Rules, SAN}

  @doc """
  Play a list of SAN tokens from the initial position.
  """
  def game(moves) when is_list(moves) do
    Enum.reduce(moves, Game.new(), fn san, game ->
      move = SAN.parse(san, game)
      Rules.apply(game, move)
    end)
  end

  @doc """
  The shortest checkmate: 1. f3 e5 2. g4 Qh4#
  """
  def fools_mate, do: game(~w(f3 e5 g4 Qh4#))

  @doc """
  A short unfinished game that is convenient for resignation tests.
  """
  def short_game, do: game(~w(e4 e5 Nf3 Nc6 Bb5))
end
