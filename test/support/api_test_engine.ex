defmodule ChessUI.ApiTestEngine do
  @moduledoc """
  A deterministic engine for the API tests.

  It plays the black side of the shortest checkmate so a test can reach a
  finished game without depending on the search.
  """

  alias Chess.{Rules, SAN}

  def play(game, _opts) do
    san =
      case length(game.moves) do
        1 -> "e5"
        3 -> "Qh4#"
        _other -> nil
      end

    if san do
      move = SAN.parse(san, game)
      {:ok, Rules.apply(game, move), move}
    else
      Chess.Engine.play(game, strategy: :random)
    end
  end
end
