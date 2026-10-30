defmodule ChessUI.Engine do
  @moduledoc """
  The engine the game plays against.

  Strength is configured rather than hard-coded: `:engine_options` holds the
  options passed to `Chess.Engine.play/2` (a 4-ply alpha-beta search that
  consults the opening book), and `:engine` names the engine module so tests
  can substitute a stub. Both live in `config/config.exs` and its environment
  variants.
  """

  alias Chess.Game

  @default_options [strategy: :search, depth: 4, book: true]

  @doc """
  Play the engine's move for the side to move.

  Returns `{:ok, next_game, move}` or `{:error, status}`.
  """
  def play(%Game{} = game) do
    engine().play(game, options())
  end

  @doc """
  Return the options passed to the engine, as configured.
  """
  def options,
    do: Application.get_env(:chess_ex_ui, :engine_options, @default_options)

  @doc """
  Return a compact, human-readable description of the engine configuration.

  The description is written into the PGN of a completed game, so a later
  reader knows how strong the opponent was.
  """
  def description do
    options()
    |> Enum.map_join(", ", fn
      {:strategy, strategy} -> "strategy #{strategy}"
      {:depth, depth} -> "depth #{depth}"
      {:book, true} -> "book on"
      {:book, false} -> "book off"
      {key, value} -> "#{key} #{value}"
    end)
  end

  defp engine, do: Application.get_env(:chess_ex_ui, :engine, Chess.Engine)
end
