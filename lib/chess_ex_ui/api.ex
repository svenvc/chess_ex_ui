defmodule ChessUI.Api do
  @moduledoc """
  The context for anonymous, in-memory games played over the REST API.

  A game is created for a player color (White by default). The player sends
  moves in SAN or UCI notation; an empty move request lets the engine answer
  for the other side. The store owns the authoritative `Chess.Game`; FEN is
  only the representation on the wire.

  A finished game is archived once through `ChessUI.GameArchive`, with the
  same PGN format as a game played in the browser. Resignation is accepted as
  the reserved move body `resign` because chess has no SAN for it.
  """

  require Logger

  alias Chess.{Game, Rules, SAN}
  alias ChessUI.Api.{Config, GameStore, Move}
  alias ChessUI.{Engine, GameArchive}

  @doc """
  Create a game for `player_color`, owned by `owner_ip`.
  """
  def create_game(player_color, owner_ip) do
    GameStore.create(player_color, owner_ip)
  end

  @doc """
  Fetch a game by id.
  """
  def get_game(id), do: GameStore.get(id)

  @doc """
  Play a move request.

  The body is classified by `ChessUI.Api.Move.command/1`: empty asks the engine
  to move, `resign` resigns the player's side, and anything else is a move for
  the player's side.
  """
  def play_move(id, input) do
    case Move.command(input) do
      :resign -> resign_game(id)
      :engine -> play_engine(id)
      :move -> play_human(id, input)
    end
  end

  @doc """
  Let the engine move for the side to move.
  """
  def play_engine(id) do
    case GameStore.begin_engine(id) do
      {:ok, entry} ->
        result = run_engine(entry.game)

        case GameStore.finish_engine(id, result) do
          {:ok, entry} -> {:ok, maybe_record(entry)}
          :error -> {:error, :not_found}
          {:error, :stale} -> {:error, :game_over}
          {:error, :timeout} -> {:error, :timeout}
          {:error, reason} -> {:error, {:engine, reason}}
        end

      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Resign the player's side.
  """
  def resign_game(id) do
    case GameStore.resign(id) do
      {:ok, entry} -> {:ok, maybe_record(entry)}
      {:error, reason} -> {:error, reason}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Return true when the game has a result, by the rules or by resignation.
  """
  def finished?(entry), do: entry.resigned_by != nil or Game.over?(entry.game)

  @doc """
  Return the status shown to an API client.
  """
  def status(entry) do
    if entry.resigned_by != nil, do: :resigned, else: Game.status(entry.game)
  end

  @doc """
  Return true when it is the player's turn.
  """
  def your_turn?(entry),
    do: not finished?(entry) and entry.game.side_to_move == entry.player_color

  ## Human moves

  defp play_human(id, input) do
    case GameStore.update(id, fn entry -> apply_human_move(entry, input) end) do
      {:ok, entry} -> {:ok, maybe_record(entry)}
      {:error, reason} -> {:error, reason}
      :error -> {:error, :not_found}
    end
  end

  defp apply_human_move(entry, input) do
    cond do
      finished?(entry) ->
        {:error, :game_over}

      entry.game.side_to_move != entry.player_color ->
        {:error, :not_your_turn}

      true ->
        case Move.parse(input, entry.game) do
          {:ok, move} ->
            next_game = Rules.apply(entry.game, move)

            {:ok,
             %{
               entry
               | game: next_game,
                 last_move: SAN.to_san(move, entry.game)
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  ## Engine

  defp run_engine(game) do
    timeout = Config.get(:engine_timeout_ms)

    task =
      Task.Supervisor.async_nolink(ChessUI.Api.TaskSupervisor, fn ->
        Engine.play(game)
      end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, {:engine, reason}}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  ## Archive

  defp maybe_record(%{recorded_id: nil} = entry) do
    if finished?(entry) do
      meta = %{
        player_color: entry.player_color,
        resigned_by: entry.resigned_by,
        started_at: entry.started_at,
        ended_at: DateTime.utc_now(),
        player_name: "API",
        event: "Chess Ex API Game"
      }

      case GameArchive.save(entry.game, meta) do
        {:ok, recorded_id} ->
          GameStore.mark_recorded(entry.id, recorded_id)
          %{entry | recorded_id: recorded_id}

        {:error, reason} ->
          Logger.error("Could not save the API game: #{inspect(reason)}")
          entry
      end
    else
      entry
    end
  end

  defp maybe_record(entry), do: entry
end
