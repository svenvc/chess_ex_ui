defmodule ChessUIWeb.ChessAssets do
  @moduledoc """
  Lookup of the board and piece images used by the chess board.

  The selected theme is deliberately kept in one place: swapping the board
  texture or the piece set is a change to the attributes below. The board
  component only asks for a board image and a piece image.
  """

  @board_theme %{id: :blue, file: "blue.png"}
  @piece_set %{id: :gioco, directory: "gioco"}

  @doc """
  Return the id of the selected board theme.
  """
  def board_theme, do: @board_theme.id

  @doc """
  Return the id of the selected piece set.
  """
  def piece_set, do: @piece_set.id

  @doc """
  Return the path of the board texture.
  """
  def board_image, do: "/images/boards/#{@board_theme.file}"

  @doc """
  Return the path of the image for a piece, as in `:Q` or `:p`.

  White pieces use a `w` prefix and black pieces a `b` prefix, matching the
  file names of the lichess piece sets.
  """
  def piece_image(piece) do
    "/images/pieces/#{@piece_set.directory}/#{piece_file(piece)}.svg"
  end

  @doc """
  Return the file name, without extension, of a piece image.
  """
  def piece_file(piece) do
    color = if Chess.Piece.white?(piece), do: "w", else: "b"
    color <> (piece |> to_string() |> String.upcase())
  end
end
