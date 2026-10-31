defmodule ChessUI.GameArchiveTest do
  use ExUnit.Case, async: true

  alias Chess.PGN
  alias ChessUI.{GameArchive, GameFixtures}

  setup do
    directory =
      Path.join([
        File.cwd!(),
        "tmp",
        "game_archive_test",
        Integer.to_string(System.unique_integer([:positive]))
      ])

    File.rm_rf!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    {:ok, dir: directory}
  end

  test "saves a completed game as a PGN with metadata", %{dir: dir} do
    started_at = ~U[2026-10-30 14:00:00Z]
    ended_at = ~U[2026-10-30 14:01:05Z]

    assert {:ok, id} =
             GameArchive.save(
               GameFixtures.fools_mate(),
               %{player_color: :white, started_at: started_at, ended_at: ended_at},
               dir: dir
             )

    assert GameArchive.id?(id)

    path = Path.join(dir, id <> ".pgn")
    assert File.exists?(path)

    text = File.read!(path)
    assert text =~ ~s([Event "Chess Ex Online Game"])
    assert text =~ ~s([White "Visitor"])
    assert text =~ ~s([Black "ChessEx"])
    assert text =~ ~s([Result "0-1"])
    assert text =~ ~s([Termination "normal"])
    assert text =~ ~s([TerminationReason "checkmate"])
    assert text =~ ~s([GameId "#{id}"])
    assert text =~ ~s([PlayerColor "white"])
    assert text =~ ~s([PlyCount "4"])
    assert text =~ ~s([DurationSeconds "65"])
    assert text =~ ~s([StartTime "2026-10-30T14:00:00Z"])
    assert text =~ ~s([EndTime "2026-10-30T14:01:05Z"])

    pgn = PGN.parse(text)
    assert pgn.result == "0-1"
    assert length(pgn.moves) == 4
    assert pgn.headers["FinalFEN"] != nil
  end

  test "records a resignation with the correct winner", %{dir: dir} do
    assert {:ok, id} =
             GameArchive.save(
               GameFixtures.short_game(),
               %{
                 player_color: :black,
                 resigned_by: :black,
                 started_at: ~U[2026-10-30 14:00:00Z],
                 ended_at: ~U[2026-10-30 14:02:00Z]
               },
               dir: dir
             )

    pgn = PGN.parse_file(Path.join(dir, id <> ".pgn"))

    assert pgn.result == "1-0"
    assert pgn.headers["White"] == "ChessEx"
    assert pgn.headers["Black"] == "Visitor"
    assert pgn.headers["TerminationReason"] == "resignation"
    assert pgn.headers["PlayerColor"] == "black"
  end

  test "refuses an unfinished game", %{dir: dir} do
    assert {:error, :game_not_finished} =
             GameArchive.save(Chess.Game.new(), %{}, dir: dir)
  end

  test "maps a stalemate to a draw" do
    game = Chess.FEN.parse("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")

    assert GameArchive.outcome(game, nil) == %{
             result: "1/2-1/2",
             termination: "stalemate",
             winner: nil
           }
  end

  test "lists games newest first", %{dir: dir} do
    assert {:ok, older} =
             GameArchive.save(
               GameFixtures.fools_mate(),
               %{
                 player_color: :white,
                 started_at: ~U[2026-10-29 10:00:00Z],
                 ended_at: ~U[2026-10-29 10:01:00Z]
               },
               dir: dir
             )

    assert {:ok, newer} =
             GameArchive.save(
               GameFixtures.short_game(),
               %{
                 player_color: :white,
                 resigned_by: :white,
                 started_at: ~U[2026-10-30 10:00:00Z],
                 ended_at: ~U[2026-10-30 10:01:00Z]
               },
               dir: dir
             )

    games = GameArchive.list(dir: dir)

    assert Enum.map(games, & &1.id) == [newer, older]

    [newest, oldest] = games
    assert newest.termination == "resignation"
    assert newest.outcome == :engine_win
    assert newest.result == "0-1"
    assert newest.ply_count == 5
    assert oldest.termination == "checkmate"
    assert oldest.outcome == :engine_win
    assert oldest.result == "0-1"
  end

  @tag capture_log: true
  test "skips corrupt games and non-PGN files", %{dir: dir} do
    assert {:ok, id} =
             GameArchive.save(
               GameFixtures.fools_mate(),
               %{
                 player_color: :white,
                 started_at: ~U[2026-10-30 10:00:00Z],
                 ended_at: ~U[2026-10-30 10:01:00Z]
               },
               dir: dir
             )

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, GameArchive.new_id() <> ".pgn"), "not a pgn")
    File.write!(Path.join(dir, "notes.txt"), "not a game")

    assert [%{id: ^id}] = GameArchive.list(dir: dir)
  end

  test "fetches a game and rejects invalid ids", %{dir: dir} do
    assert {:ok, id} =
             GameArchive.save(
               GameFixtures.fools_mate(),
               %{
                 player_color: :white,
                 started_at: ~U[2026-10-30 10:00:00Z],
                 ended_at: ~U[2026-10-30 10:01:00Z]
               },
               dir: dir
             )

    assert {:ok, record} = GameArchive.get(id, dir: dir)
    assert record.id == id
    assert record.summary.ply_count == 4

    assert :error = GameArchive.get("../" <> id, dir: dir)
    assert :error = GameArchive.get(GameArchive.new_id(), dir: dir)
  end

  test "returns an empty list for a missing directory" do
    assert GameArchive.list(dir: Path.join([File.cwd!(), "tmp", "missing-games-directory"])) == []
  end
end
