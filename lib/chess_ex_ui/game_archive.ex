defmodule ChessUI.GameArchive do
  @moduledoc """
  Stores completed games as PGN files.

  Every finished game is written to the configured games directory as one PGN
  file named after a random UUID. The PGN carries the standard seven tag
  roster plus the metadata the UI knows: start and end time, duration,
  termination reason, player colors, engine configuration and the final FEN.

  The archive reads the directory on demand; there is no database or index.
  A corrupt or unreadable PGN is skipped when listing and treated as missing
  when fetching a single game.
  """

  require Logger

  alias Chess.{Color, FEN, Game, PGN}
  alias ChessUI.{Engine, SystemInfo}

  @id_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @doc """
  Return the directory completed games are written to.

  The application environment key `:games_dir` wins; `var/games` is the
  fallback when it is not configured.
  """
  def dir do
    Application.get_env(:chess_ex_ui, :games_dir) || Path.expand("var/games")
  end

  @doc """
  Save a finished game as a PGN file.

  `meta` holds the context the PGN needs beyond the game itself:

    * `:player_color` - `:white` or `:black`, the visitor's side
    * `:resigned_by` - the side that resigned, or `nil`
    * `:started_at` - when the game started
    * `:ended_at` - when the game finished
    * `:engine` - the engine name, `"ChessEx"` by default
    * `:engine_options` - a description of the engine configuration

  The optional `:dir` overrides the configured games directory. Returns
  `{:ok, id}` or `{:error, reason}`. A game that is neither over nor resigned
  is refused, so unfinished games are never written.
  """
  def save(%Game{} = game, meta \\ %{}, opts \\ []) do
    started_at = meta |> Map.get(:started_at, DateTime.utc_now()) |> truncate()
    ended_at = meta |> Map.get(:ended_at, DateTime.utc_now()) |> truncate()
    player_color = Map.get(meta, :player_color, :white)
    resigned_by = Map.get(meta, :resigned_by)
    outcome = outcome(game, resigned_by)

    if outcome.result == "*" do
      {:error, :game_not_finished}
    else
      id = new_id()
      directory = Keyword.get(opts, :dir, dir())
      path = Path.join(directory, id <> ".pgn")
      temporary_path = path <> ".tmp"

      headers = %{
        "Event" => "Chess Ex Web UI",
        "Site" => "Chess Ex Web UI",
        "Date" => Calendar.strftime(started_at, "%Y.%m.%d"),
        "Round" => "-",
        "White" => player_name(player_color, :white),
        "Black" => player_name(player_color, :black),
        "Result" => outcome.result,
        "UTCDate" => Calendar.strftime(started_at, "%Y.%m.%d"),
        "UTCTime" => Calendar.strftime(started_at, "%H:%M:%S"),
        "StartTime" => DateTime.to_iso8601(started_at),
        "EndTime" => DateTime.to_iso8601(ended_at),
        "DurationSeconds" =>
          Integer.to_string(max(DateTime.diff(ended_at, started_at, :second), 0)),
        "TimeControl" => "-",
        "Termination" => "normal",
        "TerminationReason" => outcome.termination,
        "GameId" => id,
        "PlyCount" => Integer.to_string(length(game.moves)),
        "PlayerColor" => to_string(player_color),
        "Variant" => "Standard",
        "Engine" => Map.get(meta, :engine) || "ChessEx",
        "EngineOptions" => Map.get(meta, :engine_options) || Engine.description(),
        "AppVersion" => SystemInfo.application_version(),
        "FinalFEN" => FEN.to_fen(game)
      }

      pgn = %PGN.Game{
        headers: headers,
        moves: Game.moves_in_order(game),
        result: outcome.result,
        comments: %{},
        game: game
      }

      write(id, path, temporary_path, directory, PGN.to_pgn(pgn))
    end
  rescue
    error ->
      {:error, error}
  end

  @doc """
  List the completed games, newest first.

  Options:

    * `:dir` - override the configured games directory
    * `:limit` - return at most this many summaries

  Files that are not UUID-named PGNs, and PGNs that cannot be parsed, are
  skipped.
  """
  def list(opts \\ []) do
    directory = Keyword.get(opts, :dir, dir())
    limit = Keyword.get(opts, :limit)

    case File.ls(directory) do
      {:ok, names} ->
        names
        |> Enum.filter(&pgn_filename?/1)
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.flat_map(fn path ->
          case read_path(path) do
            {:ok, record} -> [record.summary]
            :error -> []
          end
        end)
        |> sort_newest_first()
        |> maybe_limit(limit)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Could not list the games directory #{directory}: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Fetch one game by id.

  Returns `{:ok, %{id: id, path: path, pgn: pgn, summary: summary}}` or
  `:error` when the id is malformed, the file is missing or it cannot be
  parsed.
  """
  def get(id, opts \\ []) do
    with {:ok, path} <- file_path(id, opts),
         {:ok, record} <- read_path(path) do
      {:ok, record}
    else
      _other -> :error
    end
  end

  @doc """
  Return the path of a stored game without reading it.

  Returns `{:ok, path}` or `:error` when the id is malformed or the file does
  not exist.
  """
  def file_path(id, opts \\ []) do
    if id?(id) do
      path = Path.join(Keyword.get(opts, :dir, dir()), id <> ".pgn")

      if File.regular?(path) do
        {:ok, path}
      else
        :error
      end
    else
      :error
    end
  end

  @doc """
  Return true when `id` has the shape of a game id.

  The check runs before any path is built, so a caller cannot use an id to
  leave the games directory.
  """
  def id?(id) when is_binary(id), do: Regex.match?(@id_pattern, id)
  def id?(_id), do: false

  @doc """
  Generate a random version 4 UUID.
  """
  def new_id do
    <<a::48, _version::4, b::12, _variant::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  @doc """
  Return the result, termination reason and winner of a game.

  The result is `"1-0"`, `"0-1"`, `"1/2-1/2"` or `"*"` for a game that is
  still running. A resignation gives the win to the other side.
  """
  def outcome(%Game{} = game, resigned_by) do
    cond do
      resigned_by != nil ->
        winner = Color.opponent(resigned_by)
        %{result: result_for(winner), termination: "resignation", winner: winner}

      true ->
        case Game.status(game) do
          :ongoing ->
            %{result: "*", termination: "unfinished", winner: nil}

          :checkmate ->
            winner = Game.winner(game)
            %{result: result_for(winner), termination: "checkmate", winner: winner}

          :stalemate ->
            %{result: "1/2-1/2", termination: "stalemate", winner: nil}

          :draw_fivefold_repetition ->
            %{result: "1/2-1/2", termination: "fivefold repetition", winner: nil}

          :draw_repetition ->
            %{result: "1/2-1/2", termination: "threefold repetition", winner: nil}

          :draw_seventy_five_moves ->
            %{result: "1/2-1/2", termination: "seventy-five-move rule", winner: nil}

          :draw_fifty_moves ->
            %{result: "1/2-1/2", termination: "fifty-move rule", winner: nil}

          :draw_insufficient_material ->
            %{result: "1/2-1/2", termination: "insufficient material", winner: nil}
        end
    end
  end

  ## Writing

  defp write(id, path, temporary_path, directory, pgn) do
    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(temporary_path, pgn),
         :ok <- File.rename(temporary_path, path) do
      {:ok, id}
    else
      {:error, reason} ->
        File.rm(temporary_path)
        {:error, reason}
    end
  end

  defp truncate(%DateTime{} = date_time), do: DateTime.truncate(date_time, :second)

  defp truncate(%NaiveDateTime{} = date_time),
    do: date_time |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

  defp truncate(_other), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp player_name(:white, :white), do: "Visitor"
  defp player_name(:white, :black), do: "ChessEx"
  defp player_name(:black, :white), do: "ChessEx"
  defp player_name(:black, :black), do: "Visitor"

  defp result_for(:white), do: "1-0"
  defp result_for(:black), do: "0-1"
  defp result_for(nil), do: "1/2-1/2"

  defp format_uuid(
         <<p1::binary-size(8), p2::binary-size(4), p3::binary-size(4), p4::binary-size(4),
           p5::binary-size(12)>>
       ) do
    Enum.join([p1, p2, p3, p4, p5], "-")
  end

  ## Reading

  defp read_path(path) do
    id = Path.basename(path, ".pgn")

    with {:ok, text} <- File.read(path),
         {:ok, pgn} <- parse(text, path) do
      {:ok, %{id: id, path: path, pgn: pgn, summary: summary(pgn, id, path)}}
    else
      :error ->
        :error

      {:error, reason} ->
        Logger.warning("Skipping the unreadable game #{path}: #{inspect(reason)}")
        :error
    end
  end

  defp parse(text, _path) do
    {:ok, PGN.parse(text)}
  rescue
    error -> {:error, error}
  end

  defp summary(%PGN.Game{} = pgn, id, path) do
    headers = pgn.headers
    started_at = started_at(headers, path)
    ended_at = ended_at(headers, path, started_at)
    player_color = player_color(headers)
    result = pgn.result || headers["Result"] || "*"
    termination = headers["TerminationReason"] || headers["Termination"] || "unknown"
    white = headers["White"] || "?"
    black = headers["Black"] || "?"

    %{
      id: id,
      started_at: started_at,
      ended_at: ended_at,
      duration_seconds: duration_seconds(headers, started_at, ended_at),
      white: white,
      black: black,
      result: result,
      termination: termination,
      winner: winner_name(result, white, black),
      outcome: outcome_for(result, player_color),
      player_color: player_color,
      ply_count: length(pgn.moves),
      engine: headers["Engine"] || "ChessEx",
      engine_options: headers["EngineOptions"],
      app_version: headers["AppVersion"]
    }
  end

  defp started_at(headers, path) do
    parse_iso8601(headers["StartTime"]) || parse_utc_datetime(headers) || file_time(path)
  end

  defp ended_at(headers, path, started_at) do
    parse_iso8601(headers["EndTime"]) || parse_utc_datetime(headers) || started_at ||
      file_time(path)
  end

  defp parse_iso8601(nil), do: nil

  defp parse_iso8601(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> date_time
      _other -> nil
    end
  end

  defp parse_utc_datetime(headers) do
    date = headers["UTCDate"] || headers["Date"]
    time = headers["UTCTime"] || headers["Time"]

    with {:ok, date} <- parse_date(date),
         {:ok, time} <- parse_time(time),
         {:ok, date_time} <- DateTime.new(date, time, "Etc/UTC") do
      date_time
    else
      _other -> nil
    end
  end

  defp parse_date(nil), do: :error

  defp parse_date(value) do
    case Regex.run(~r/\A(\d{4})[.\-](\d{2})[.\-](\d{2})\z/, value) do
      [_, year, month, day] ->
        Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      _other ->
        :error
    end
  end

  defp parse_time(nil), do: :error

  defp parse_time(value) do
    case Regex.run(~r/\A(\d{2}):(\d{2}):(\d{2})\z/, value) do
      [_, hour, minute, second] ->
        Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second))

      _other ->
        :error
    end
  end

  defp file_time(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: seconds}} -> DateTime.from_unix!(seconds)
      _other -> DateTime.utc_now()
    end
  end

  defp duration_seconds(headers, started_at, ended_at) do
    parse_integer(headers["DurationSeconds"]) ||
      max(DateTime.diff(ended_at, started_at, :second), 0)
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp player_color(headers) do
    case headers["PlayerColor"] do
      "white" -> :white
      "black" -> :black
      _other -> infer_player_color(headers)
    end
  end

  defp infer_player_color(headers) do
    cond do
      headers["White"] == "Visitor" -> :white
      headers["Black"] == "Visitor" -> :black
      true -> nil
    end
  end

  defp outcome_for("1-0", :white), do: :visitor_win
  defp outcome_for("1-0", :black), do: :engine_win
  defp outcome_for("0-1", :black), do: :visitor_win
  defp outcome_for("0-1", :white), do: :engine_win
  defp outcome_for("1/2-1/2", _player_color), do: :draw
  defp outcome_for(_result, _player_color), do: :unfinished

  defp winner_name("1-0", white, _black), do: white
  defp winner_name("0-1", _white, black), do: black
  defp winner_name(_result, _white, _black), do: nil

  defp pgn_filename?(name) do
    String.ends_with?(name, ".pgn") and id?(Path.rootname(name))
  end

  defp sort_newest_first(summaries) do
    Enum.sort(summaries, fn left, right ->
      case DateTime.compare(left.started_at, right.started_at) do
        :gt -> true
        :lt -> false
        :eq -> left.id >= right.id
      end
    end)
  end

  defp maybe_limit(summaries, nil), do: summaries

  defp maybe_limit(summaries, limit) when is_integer(limit) and limit > 0,
    do: Enum.take(summaries, limit)

  defp maybe_limit(summaries, _limit), do: summaries
end
