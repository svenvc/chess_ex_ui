defmodule ChessUI.Api.GameStore do
  @moduledoc """
  Keeps in-progress API games in memory.

  A game is a full `Chess.Game`, not just its FEN: the move history is needed
  for the repetition draw rules. The FEN is only the wire format.

  The store is a single GenServer because it owns the map and has to serialize
  two moves on the same game. It never runs an engine search itself: a caller
  reserves a game with `begin_engine/1`, searches outside the store, and
  reports back with `finish_engine/2`. If the caller dies while searching, the
  monitor clears the reservation.
  """

  use GenServer

  alias Chess.Game
  alias ChessUI.Api.Config
  alias ChessUI.GameArchive

  @sweep_interval 60_000

  ## Client

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Create a new game for `player_color`, owned by `owner_ip`.
  """
  def create(player_color, owner_ip) do
    GenServer.call(__MODULE__, {:create, player_color, owner_ip})
  end

  @doc """
  Fetch a game and mark it as recently seen.
  """
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @doc """
  Run `fun` against the entry while the store is locked.

  The function returns `{:ok, entry}` or `{:error, reason}`. This is how a
  human move is validated and applied atomically.
  """
  def update(id, fun), do: GenServer.call(__MODULE__, {:update, id, fun})

  @doc """
  Reserve a game for an engine search.

  Returns `{:ok, entry}` when it is the engine's turn and no other search holds
  the game or the global engine slot. The caller must follow up with
  `finish_engine/2`.
  """
  def begin_engine(id), do: GenServer.call(__MODULE__, {:begin_engine, id})

  @doc """
  Apply the result of an engine search and release the reservation.
  """
  def finish_engine(id, result), do: GenServer.call(__MODULE__, {:finish_engine, id, result})

  @doc """
  Resign the player's side.
  """
  def resign(id), do: GenServer.call(__MODULE__, {:resign, id})

  @doc """
  Remember the id of the archived PGN for a finished game.
  """
  def mark_recorded(id, recorded_id) do
    GenServer.call(__MODULE__, {:mark_recorded, id, recorded_id})
  end

  @doc """
  Remove expired games now.
  """
  def sweep, do: GenServer.call(__MODULE__, :sweep)

  @doc """
  Return the number of games held in memory.
  """
  def count, do: GenServer.call(__MODULE__, :count)

  @doc """
  Return every in-memory game, newest first.

  Intended for IEx debugging. The entries are the full store records, including
  the `Chess.Game`, so use `Enum.map/2` if you only want ids or summaries.
  Reading the list does not refresh the idle expiry.
  """
  def list, do: GenServer.call(__MODULE__, :list)

  @doc """
  Drop every game. Intended for tests.
  """
  def reset, do: GenServer.call(__MODULE__, :reset)

  ## Server

  @impl true
  def init(_opts) do
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{games: %{}, engine_count: 0}}
  end

  @impl true
  def handle_call({:create, player_color, owner_ip}, _from, state) do
    state = sweep_expired(state)

    cond do
      map_size(state.games) >= Config.get(:max_games) ->
        {:reply, {:error, :at_capacity}, state}

      count_for_ip(state, owner_ip) >= Config.get(:max_games_per_ip) ->
        {:reply, {:error, :too_many_games}, state}

      true ->
        now = DateTime.utc_now()

        entry = %{
          id: GameArchive.new_id(),
          game: Game.new(),
          player_color: player_color,
          owner_ip: owner_ip,
          started_at: now,
          last_seen_at: now,
          recorded_id: nil,
          resigned_by: nil,
          last_move: nil,
          engine_busy: nil,
          version: 0
        }

        {:reply, {:ok, entry}, put_game(state, entry)}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.games, id) do
      {:ok, entry} ->
        entry = touch(entry)
        {:reply, {:ok, entry}, put_game(state, entry)}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:update, id, fun}, _from, state) do
    case Map.fetch(state.games, id) do
      {:ok, entry} ->
        case fun.(entry) do
          {:ok, entry} ->
            entry = entry |> touch() |> bump_version()
            {:reply, {:ok, entry}, put_game(state, entry)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:begin_engine, id}, {pid, _tag}, state) do
    case Map.fetch(state.games, id) do
      {:ok, %{engine_busy: nil} = entry} ->
        cond do
          finished?(entry) ->
            {:reply, {:error, :game_over}, state}

          entry.game.side_to_move == entry.player_color ->
            {:reply, {:error, :not_engine_turn}, state}

          state.engine_count >= Config.get(:max_engine_concurrency) ->
            {:reply, {:error, :engine_capacity}, state}

          true ->
            ref = Process.monitor(pid)

            entry = %{
              entry
              | engine_busy: %{pid: pid, ref: ref},
                last_seen_at: DateTime.utc_now()
            }

            {:reply, {:ok, entry},
             %{put_game(state, entry) | engine_count: state.engine_count + 1}}
        end

      {:ok, _busy} ->
        {:reply, {:error, :busy}, state}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:finish_engine, id, result}, _from, state) do
    case Map.fetch(state.games, id) do
      {:ok, %{engine_busy: nil}} ->
        {:reply, {:error, :stale}, state}

      {:ok, entry} ->
        {entry, state} = release_engine(entry, state)

        case result do
          {:ok, next_game, move} ->
            entry = %{
              entry
              | game: next_game,
                last_move: safe_san(move, entry.game),
                last_seen_at: DateTime.utc_now()
            }

            entry = bump_version(entry)
            {:reply, {:ok, entry}, put_game(state, entry)}

          {:error, reason} ->
            entry = touch(entry)
            {:reply, {:error, reason}, put_game(state, entry)}
        end

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:resign, id}, _from, state) do
    case Map.fetch(state.games, id) do
      {:ok, %{resigned_by: nil} = entry} ->
        if Game.over?(entry.game) do
          {:reply, {:error, :game_over}, state}
        else
          {entry, state} = release_engine(entry, state)

          entry = %{
            entry
            | resigned_by: entry.player_color,
              last_seen_at: DateTime.utc_now()
          }

          entry = bump_version(entry)
          {:reply, {:ok, entry}, put_game(state, entry)}
        end

      {:ok, _resigned} ->
        {:reply, {:error, :game_over}, state}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:mark_recorded, id, recorded_id}, _from, state) do
    case Map.fetch(state.games, id) do
      {:ok, entry} ->
        entry = %{entry | recorded_id: entry.recorded_id || recorded_id}
        {:reply, {:ok, entry}, put_game(state, entry)}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call(:sweep, _from, state), do: {:reply, :ok, sweep_expired(state)}
  def handle_call(:count, _from, state), do: {:reply, map_size(state.games), state}

  def handle_call(:list, _from, state) do
    games =
      state.games
      |> Map.values()
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

    {:reply, games, state}
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.games, fn {_id, entry} ->
      if entry.engine_busy, do: Process.demonitor(entry.engine_busy.ref, [:flush])
    end)

    {:reply, :ok, %{games: %{}, engine_count: 0}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, sweep_expired(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.games, fn {_id, entry} ->
           match?(%{ref: ^ref}, entry.engine_busy)
         end) do
      {_id, entry} ->
        entry = %{entry | engine_busy: nil, last_seen_at: DateTime.utc_now()}

        state = %{
          put_game(state, entry)
          | engine_count: max(state.engine_count - 1, 0)
        }

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  ## Helpers

  defp put_game(state, entry), do: %{state | games: Map.put(state.games, entry.id, entry)}

  defp touch(entry), do: %{entry | last_seen_at: DateTime.utc_now()}
  defp bump_version(entry), do: %{entry | version: entry.version + 1}

  defp finished?(entry), do: entry.resigned_by != nil or Game.over?(entry.game)

  defp clear_busy(%{engine_busy: %{ref: ref}} = entry) do
    Process.demonitor(ref, [:flush])
    %{entry | engine_busy: nil}
  end

  defp release_engine(%{engine_busy: nil} = entry, state), do: {entry, state}

  defp release_engine(entry, state) do
    {clear_busy(entry), %{state | engine_count: max(state.engine_count - 1, 0)}}
  end

  defp safe_san(move, game) do
    Chess.SAN.to_san(move, game)
  rescue
    _error -> nil
  end

  defp count_for_ip(state, owner_ip) do
    Enum.count(state.games, fn {_id, entry} ->
      entry.owner_ip == owner_ip and not finished?(entry)
    end)
  end

  defp sweep_expired(state) do
    now = DateTime.utc_now()
    ttl = Config.get(:game_ttl_seconds)
    max_age = Config.get(:max_game_age_seconds)

    games =
      state.games
      |> Enum.reject(fn {_id, entry} ->
        entry.engine_busy == nil and
          (DateTime.diff(now, entry.last_seen_at, :second) >= ttl or
             DateTime.diff(now, entry.started_at, :second) >= max_age)
      end)
      |> Map.new()

    %{state | games: games}
  end
end
