defmodule ChessUI.TestEngine do
  @moduledoc """
  A deliberately slow engine used to exercise the thinking state.

  It answers with a random legal move after a short delay, so a test can observe
  the board lock and then cancel the search before it finishes.
  """

  @delay 200

  def play(game, _opts) do
    Process.sleep(@delay)
    {:ok, next_game, move} = Chess.Engine.play(game, strategy: :random)
    {:ok, next_game, move}
  end
end
