defmodule ChessUI.Api.Config do
  @moduledoc """
  Configuration for the anonymous REST API.

  The defaults are deliberately conservative: the API keeps games in memory,
  so both the number of games and the number of engine searches have to be
  bounded. Every value can be overridden in `config/config.exs` under
  `config :chess_ex_ui, :api`.
  """

  @defaults [
    max_games: 1_000,
    max_games_per_ip: 20,
    game_ttl_seconds: 3_600,
    max_game_age_seconds: 86_400,
    engine_timeout_ms: 10_000,
    max_engine_concurrency: 4,
    rate_limit: %{create: {10, 60}, move: {60, 60}, read: {120, 60}}
  ]

  @doc """
  Return the full API configuration, with defaults filled in.
  """
  def all, do: Keyword.merge(@defaults, Application.get_env(:chess_ex_ui, :api, []))

  @doc """
  Return one configuration value.
  """
  def get(key), do: Keyword.fetch!(all(), key)
end
