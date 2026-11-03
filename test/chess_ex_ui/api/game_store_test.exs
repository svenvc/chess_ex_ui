defmodule ChessUI.Api.GameStoreTest do
  use ExUnit.Case, async: false

  alias Chess.{Rules, SAN}
  alias ChessUI.Api.{Config, GameStore}

  @ip {127, 0, 0, 1}

  setup do
    previous = Application.get_env(:chess_ex_ui, :api)

    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(),
        max_games: 100,
        max_games_per_ip: 100,
        game_ttl_seconds: 3_600,
        max_game_age_seconds: 86_400,
        max_engine_concurrency: 2,
        rate_limit: %{create: {100, 60}, move: {100, 60}, read: {100, 60}}
      )
    )

    GameStore.reset()

    on_exit(fn ->
      GameStore.reset()

      if previous do
        Application.put_env(:chess_ex_ui, :api, previous)
      else
        Application.delete_env(:chess_ex_ui, :api)
      end
    end)

    :ok
  end

  test "creates and fetches a game" do
    assert {:ok, entry} = GameStore.create(:white, @ip)
    assert entry.player_color == :white
    assert entry.game == Chess.Game.new()
    assert {:ok, fetched} = GameStore.get(entry.id)
    assert fetched.id == entry.id
  end

  test "returns an error for an unknown game" do
    assert :error = GameStore.get("00000000-0000-4000-8000-000000000000")
  end

  test "lists the games in memory, newest first" do
    assert GameStore.list() == []

    assert {:ok, first} = GameStore.create(:white, @ip)
    assert {:ok, second} = GameStore.create(:black, @ip)

    games = GameStore.list()
    assert length(games) == 2
    assert Enum.sort(Enum.map(games, & &1.id)) == Enum.sort([first.id, second.id])
    assert DateTime.compare(hd(games).started_at, List.last(games).started_at) in [:gt, :eq]
  end

  test "applies an update atomically" do
    assert {:ok, entry} = GameStore.create(:white, @ip)

    assert {:ok, updated} =
             GameStore.update(entry.id, fn entry ->
               move = SAN.parse("e4", entry.game)
               {:ok, %{entry | game: Rules.apply(entry.game, move), last_move: "e4"}}
             end)

    assert updated.last_move == "e4"
    assert length(updated.game.moves) == 1
    assert updated.version == 1
  end

  test "enforces the global game cap" do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), max_games: 1, max_games_per_ip: 100)
    )

    assert {:ok, _entry} = GameStore.create(:white, {127, 0, 0, 1})
    assert {:error, :at_capacity} = GameStore.create(:white, {127, 0, 0, 2})
  end

  test "enforces the per-address game cap" do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), max_games: 100, max_games_per_ip: 1)
    )

    assert {:ok, _entry} = GameStore.create(:white, @ip)
    assert {:error, :too_many_games} = GameStore.create(:white, @ip)
    assert {:ok, _entry} = GameStore.create(:white, {127, 0, 0, 2})
  end

  test "reserves a game for the engine only on the engine's turn" do
    assert {:ok, entry} = GameStore.create(:white, @ip)
    assert {:error, :not_engine_turn} = GameStore.begin_engine(entry.id)

    assert {:ok, entry} = GameStore.create(:black, @ip)
    assert {:ok, reserved} = GameStore.begin_engine(entry.id)
    assert reserved.engine_busy != nil
    assert {:error, :busy} = GameStore.begin_engine(entry.id)

    move = SAN.parse("e4", reserved.game)
    next_game = Rules.apply(reserved.game, move)

    assert {:ok, finished} = GameStore.finish_engine(entry.id, {:ok, next_game, move})
    assert finished.engine_busy == nil
    assert finished.last_move == "e4"
    assert {:error, :not_engine_turn} = GameStore.begin_engine(entry.id)
  end

  test "enforces the engine concurrency cap" do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(),
        max_games: 100,
        max_games_per_ip: 100,
        max_engine_concurrency: 1
      )
    )

    assert {:ok, first} = GameStore.create(:black, @ip)
    assert {:ok, second} = GameStore.create(:black, @ip)
    assert {:ok, _reserved} = GameStore.begin_engine(first.id)
    assert {:error, :engine_capacity} = GameStore.begin_engine(second.id)
  end

  test "clears an engine reservation when the caller dies" do
    assert {:ok, entry} = GameStore.create(:black, @ip)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _entry} = GameStore.begin_engine(entry.id)
        send(parent, :reserved)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :reserved
    Process.exit(pid, :kill)

    assert eventually(fn -> match?({:ok, _entry}, GameStore.begin_engine(entry.id)) end)
  end

  test "resigns the player's side" do
    assert {:ok, entry} = GameStore.create(:white, @ip)
    assert {:ok, resigned} = GameStore.resign(entry.id)
    assert resigned.resigned_by == :white
    assert {:error, :game_over} = GameStore.resign(entry.id)
  end

  test "resignation releases an engine reservation" do
    assert {:ok, entry} = GameStore.create(:black, @ip)
    assert {:ok, reserved} = GameStore.begin_engine(entry.id)
    assert reserved.engine_busy != nil

    assert {:ok, resigned} = GameStore.resign(entry.id)
    assert resigned.resigned_by == :black
    assert resigned.engine_busy == nil
    assert {:error, :stale} = GameStore.finish_engine(entry.id, {:error, :timeout})
  end

  test "sweeps expired games" do
    Application.put_env(
      :chess_ex_ui,
      :api,
      Keyword.merge(Config.all(), game_ttl_seconds: 0)
    )

    assert {:ok, entry} = GameStore.create(:white, @ip)
    assert GameStore.count() == 1
    assert :ok = GameStore.sweep()
    assert :error = GameStore.get(entry.id)
    assert GameStore.count() == 0
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
