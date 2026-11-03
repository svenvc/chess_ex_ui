defmodule ChessUI.Api.Move do
  @moduledoc """
  Parses the textual move a REST client sends.

  SAN is the primary notation: `e4`, `Nf3`, `O-O`, `exd5`, `e8=Q`, with or
  without the `+` and `#` markers. As a fallback the coordinate notation used
  by UCI is accepted as well: `e2e4`, `e2-e4`, `e7e8q`.

  A body of `resign` is a command rather than a move: chess has no SAN for
  resignation. An empty body asks the engine to move.
  """

  alias Chess.{Move, Position, Rules, SAN}

  @uci ~r/\A([a-h][1-8])-?([a-h][1-8])(?:=?([qrbnQRBN]))?\z/

  @doc """
  Classify the body of a move request.

  Returns `:engine` for an empty body, `:resign` for the reserved word
  `resign`, and `:move` for everything else.
  """
  def command(input) when is_binary(input) do
    case input |> String.trim() |> String.downcase() do
      "" -> :engine
      "resign" -> :resign
      _other -> :move
    end
  end

  def command(_input), do: :engine

  @doc """
  Parse a move for the side to move.

  Returns `{:ok, move}` or `{:error, reason}` where reason is
  `{:illegal, message}`, `{:ambiguous, message}` or `:promotion_required`.
  """
  def parse(input, game) when is_binary(input) do
    token = normalize(input)

    case parse_san(token, game) do
      {:ok, move} -> {:ok, move}
      {:error, {:ambiguous, _message} = reason} -> {:error, reason}
      {:error, _reason} -> parse_uci(token, game)
    end
  end

  def parse(_input, _game), do: {:error, {:illegal, "no move given"}}

  ## SAN

  defp parse_san("", _game), do: {:error, {:illegal, "no move given"}}

  defp parse_san(token, game) do
    move = SAN.parse(token, game, validate_marker: false)

    if Rules.legal_move?(game, move) do
      {:ok, move}
    else
      {:error, {:illegal, "#{token} is not a legal move"}}
    end
  rescue
    error in SAN.ParseError ->
      message = Exception.message(error)

      if Regex.match?(~r/matches \d+ legal moves/, message) do
        {:error, {:ambiguous, message}}
      else
        {:error, {:illegal, message}}
      end

    _error ->
      {:error, {:illegal, "#{token} is not a legal move"}}
  end

  ## UCI

  defp parse_uci(token, game) do
    case Regex.run(@uci, token) do
      [_, from, to] -> match_uci(game, from, to, nil)
      [_, from, to, promotion] -> match_uci(game, from, to, promotion)
      _other -> {:error, {:illegal, "#{token} is not a legal move"}}
    end
  end

  defp match_uci(game, from, to, promotion) do
    from = Position.from_string(from)
    to = Position.from_string(to)

    candidates =
      game
      |> Rules.legal_moves()
      |> Enum.filter(&(Move.from(&1) == from and Move.to(&1) == to))

    case candidates do
      [] ->
        {:error, {:illegal, "no legal move goes from #{from} to #{to}"}}

      moves ->
        case choose(moves, promotion) do
          nil -> {:error, :promotion_required}
          move -> {:ok, move}
        end
    end
  end

  # A promotion is the only case where one from/to pair has several moves. A
  # UCI token without a promotion piece promotes to a queen, like the board.
  defp choose(moves, nil) do
    Enum.find(moves, &queen?/1) || List.first(moves)
  end

  defp choose(moves, promotion) do
    Enum.find(moves, &promotion?(&1, promotion))
  end

  defp queen?(move) do
    case Move.promotion_piece(move) do
      nil -> false
      piece -> String.upcase(to_string(piece)) == "Q"
    end
  end

  defp promotion?(move, promotion) do
    case Move.promotion_piece(move) do
      nil -> false
      piece -> String.upcase(to_string(piece)) == String.upcase(promotion)
    end
  end

  ## Normalization

  # Accept the common decorations around a move: a move number from a PGN move
  # list, annotation suffixes and an en passant marker.
  defp normalize(token) do
    token
    |> String.trim()
    |> String.replace(~r/^\d+\.(?:\.\.)?\s*/, "")
    |> String.replace(~r/[!?]+$/, "")
    |> String.replace(~r/[+#]+$/, "")
    |> String.replace(~r/\s*e\.p\.$/i, "")
    |> String.trim()
  end
end
