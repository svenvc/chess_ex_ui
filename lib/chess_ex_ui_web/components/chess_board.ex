defmodule ChessUIWeb.ChessBoard do
  @moduledoc """
  The visual chess board: squares, coordinates, pieces and move highlights.

  The component is presentational. It sends a single `square_click` event with
  the square name and lets the LiveView decide what the click means.
  """

  use ChessUIWeb, :html

  alias Chess.{Board, Castling, Color, Game, Move, Piece, Position}
  alias ChessUIWeb.ChessAssets

  attr :game, :any, required: true
  attr :orientation, :atom, default: :white
  attr :selected, :atom, default: nil
  attr :targets, :any, default: nil
  attr :disabled, :boolean, default: false

  def board(assigns) do
    assigns =
      assigns
      |> assign(:squares, squares(assigns.orientation))
      |> assign(:last_move, last_move(assigns.game))
      |> assign(:targets, assigns.targets || MapSet.new())

    ~H"""
    <div class="flex w-full justify-center">
      <div
        class="grid w-full max-w-[min(760px,calc(100dvh-9rem))] gap-1"
        style="grid-template-columns: 1.25rem minmax(0, 1fr); grid-template-rows: minmax(0, 1fr) 1.25rem;"
      >
        <div
          class="grid text-xs font-medium text-base-content/50"
          style="grid-template-rows: repeat(8, minmax(0, 1fr));"
          aria-hidden="true"
        >
          <span
            :for={rank <- ranks(@orientation)}
            id={"rank-#{rank}"}
            class="flex items-center justify-center tabular-nums"
          >
            {rank}
          </span>
        </div>

        <div
          id="board"
          role="group"
          aria-label={"Chess board, #{@orientation} at the bottom"}
          data-orientation={@orientation}
          class="chess-board grid aspect-square overflow-hidden rounded-lg shadow-xl ring-1 ring-black/10"
          style={"--board-image: url('#{ChessAssets.board_image()}'); grid-template-columns: repeat(8, minmax(0, 1fr)); grid-template-rows: repeat(8, minmax(0, 1fr));"}
        >
          <button
            :for={square <- @squares}
            type="button"
            id={"square-#{square}"}
            phx-click="square_click"
            phx-value-square={square}
            aria-label={square_label(@game, square)}
            aria-pressed={to_string(@selected == square)}
            data-selected={to_string(@selected == square)}
            data-target={to_string(MapSet.member?(@targets, square))}
            data-last-move={to_string(MapSet.member?(@last_move, square))}
            class={[
              "group relative flex items-center justify-center focus:outline-none focus-visible:z-20 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-blue-600",
              if(@disabled, do: "cursor-default", else: "cursor-pointer")
            ]}
          >
            <span
              :if={MapSet.member?(@last_move, square)}
              class="pointer-events-none absolute inset-0 bg-amber-300/45"
            />
            <span
              :if={@selected == square}
              class="pointer-events-none absolute inset-0 bg-amber-400/65 shadow-[inset_0_0_0_3px_rgba(180,83,9,0.65)]"
            />

            <%= if MapSet.member?(@targets, square) do %>
              <%= if Board.at(@game.board, square) do %>
                <span class="pointer-events-none absolute inset-[6%] rounded-full border-[0.35rem] border-emerald-700/35 transition group-hover:border-emerald-700/55" />
              <% else %>
                <span class="pointer-events-none absolute h-[22%] w-[22%] rounded-full bg-emerald-800/35 transition group-hover:scale-125 group-hover:bg-emerald-800/55" />
              <% end %>
            <% end %>

            <%= if piece = Board.at(@game.board, square) do %>
              <img
                src={ChessAssets.piece_image(piece)}
                alt=""
                draggable="false"
                class="pointer-events-none relative z-10 h-full w-full select-none drop-shadow-[0_1px_1px_rgba(0,0,0,0.35)]"
              />
            <% end %>
          </button>
        </div>

        <div aria-hidden="true"></div>

        <div
          class="grid text-center text-xs font-medium text-base-content/50"
          style="grid-template-columns: repeat(8, minmax(0, 1fr));"
          aria-hidden="true"
        >
          <span :for={file <- files(@orientation)} id={"file-#{file}"} class="pt-0.5">
            {file}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Return the 64 squares from the top left to the bottom right for the given
  orientation.
  """
  def squares(:white) do
    for rank <- 8..1//-1, file <- Position.files(), do: Position.new(file, rank)
  end

  def squares(:black) do
    for rank <- 1..8, file <- Enum.reverse(Position.files()), do: Position.new(file, rank)
  end

  @doc """
  Return the files in the order they are shown for the given orientation.
  """
  def files(:white), do: Position.files()
  def files(:black), do: Enum.reverse(Position.files())

  @doc """
  Return the ranks in the order they are shown for the given orientation.
  """
  def ranks(:white), do: Enum.reverse(Position.ranks())
  def ranks(:black), do: Position.ranks()

  # The squares of the last move: always the moving piece, plus both rooks of
  # a castle.
  defp last_move(%Game{moves: [move | _]} = game) do
    squares = [Move.from(move), Move.to(move)]

    squares =
      case move do
        {:castle, _from, _to} ->
          color = Color.opponent(game.side_to_move)
          side = Move.castle_side(move)

          squares ++
            [Castling.rook_start(color, side), Castling.rook_destination(color, side)]

        _other ->
          squares
      end

    MapSet.new(squares)
  end

  defp last_move(_game), do: MapSet.new()

  defp square_label(game, square) do
    case Board.at(game.board, square) do
      nil -> "#{square}, empty"
      piece -> "#{square}, #{Piece.color(piece)} #{Piece.type(piece)}"
    end
  end
end
