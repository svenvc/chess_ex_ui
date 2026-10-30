defmodule ChessUIWeb.GameLive do
  @moduledoc """
  A game of chess against the ChessEx engine.

  The player picks a piece and then a legal destination, the engine answers
  for the other side, and the status panel narrates what happened. The engine
  searches in a background task while the turn indicator shows that it is
  thinking, and the board ignores clicks until the move arrives. The game
  state lives in this LiveView; there is no clock, persistence or history
  navigation.
  """

  use ChessUIWeb, :live_view

  import ChessUIWeb.AboutDialog, only: [about: 1]
  import ChessUIWeb.ChessBoard, only: [board: 1]

  alias Chess.{Board, Color, Game, Move, Narrator, Piece, Position, Rules, SAN}
  alias ChessUI.{Engine, GameArchive, SystemInfo}

  require Logger

  @max_messages 8

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Play")
     |> assign(thinking: false, turn: 0, about_open: false, system_info: nil)
     |> new_game(:white)}
  end

  @impl true
  def handle_async(:engine, result, socket) do
    case result do
      {:ok, {turn, {:ok, next_game, move}}} when turn == socket.assigns.turn ->
        san = SAN.to_san(move, socket.assigns.game)

        {:noreply,
         socket
         |> assign(thinking: false)
         |> put_game(next_game)
         |> clear_selection()
         |> add_message("Engine played #{san}.")
         |> maybe_record_game()
         |> maybe_engine_move()}

      {:ok, {_turn, {:ok, _next_game, _move}}} ->
        {:noreply, socket}

      {:ok, {turn, {:error, reason}}} when turn == socket.assigns.turn ->
        {:noreply,
         socket
         |> assign(thinking: false)
         |> add_message("The engine could not move (#{reason}).")}

      {:ok, {_turn, {:error, _reason}}} ->
        {:noreply, socket}

      # A cancelled search: the game already moved on and cleared `thinking`.
      {:exit, {:shutdown, _reason}} ->
        {:noreply, assign(socket, thinking: false)}

      {:exit, _reason} ->
        {:noreply,
         socket
         |> assign(thinking: false)
         |> add_message("The engine failed to move.")}
    end
  end

  @impl true
  def handle_event("square_click", %{"square" => square}, socket) do
    case parse_square(square) do
      {:ok, position} -> {:noreply, click(socket, position)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("new_game", _params, socket) do
    {:noreply, new_game(socket, socket.assigns.player_color)}
  end

  def handle_event("resign", _params, socket) do
    %{game: game, player_color: player_color, resigned_by: resigned_by} = socket.assigns

    if resigned_by == nil and not Game.over?(game) do
      socket =
        socket
        |> cancel_engine()
        |> assign(resigned_by: player_color)
        |> clear_selection()
        |> add_message("You resigned. #{color_name(Color.opponent(player_color))} wins.")
        |> maybe_record_game()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("switch_sides", _params, socket) do
    {:noreply, new_game(socket, Color.opponent(socket.assigns.player_color))}
  end

  def handle_event("open_about", _params, socket) do
    {:noreply, assign(socket, about_open: true, system_info: SystemInfo.all())}
  end

  def handle_event("close_about", _params, socket) do
    {:noreply, assign(socket, about_open: false)}
  end

  ## State

  defp new_game(socket, player_color) do
    socket
    |> cancel_engine()
    |> assign(
      player_color: player_color,
      orientation: player_color,
      selected: nil,
      targets: MapSet.new(),
      resigned_by: nil,
      messages: [],
      started_at: DateTime.utc_now(),
      recorded_id: nil
    )
    |> put_game(Game.new())
    |> add_message(
      "New game. You play #{color_name(player_color)}; the engine plays #{color_name(Color.opponent(player_color))}."
    )
    |> maybe_engine_move()
  end

  defp put_game(socket, game) do
    assign(socket,
      game: game,
      move_rows: move_rows(game),
      last_move_summary: last_move_summary(game)
    )
  end

  # Search off the LiveView process so the page stays responsive while the
  # engine thinks. `:turn` invalidates a result that belongs to a game which has
  # since been replaced or resigned.
  defp maybe_engine_move(socket) do
    %{game: game, player_color: player_color, resigned_by: resigned_by} = socket.assigns

    cond do
      socket.assigns.thinking ->
        socket

      resigned_by != nil or Game.over?(game) ->
        socket

      game.side_to_move == player_color ->
        socket

      # `start_async/3` is a no-op while disconnected. Mount starts as White,
      # so there is nothing to start before the socket connects.
      not connected?(socket) ->
        socket

      true ->
        start_engine_move(socket, game)
    end
  end

  defp start_engine_move(socket, game) do
    turn = socket.assigns.turn + 1
    min_think_ms = Application.get_env(:chess_ex_ui, :engine_min_think_ms, 400)

    socket
    |> assign(thinking: true, turn: turn)
    |> start_async(:engine, fn ->
      started_at = System.monotonic_time(:millisecond)
      result = Engine.play(game)
      remaining = min_think_ms - (System.monotonic_time(:millisecond) - started_at)
      if remaining > 0, do: Process.sleep(remaining)
      {turn, result}
    end)
  end

  defp cancel_engine(socket) do
    socket
    |> cancel_async(:engine, {:shutdown, :replaced})
    |> assign(thinking: false, turn: socket.assigns.turn + 1)
  end

  # A game is recorded once, when it has a result. New game, switch sides and
  # closing the page are deliberate abandonments and never write a record.
  defp maybe_record_game(%{assigns: %{recorded_id: id}} = socket) when id != nil, do: socket

  defp maybe_record_game(socket) do
    %{
      game: game,
      player_color: player_color,
      resigned_by: resigned_by,
      started_at: started_at
    } = socket.assigns

    if resigned_by != nil or Game.over?(game) do
      metadata = %{
        player_color: player_color,
        resigned_by: resigned_by,
        started_at: started_at,
        ended_at: DateTime.utc_now()
      }

      case GameArchive.save(game, metadata) do
        {:ok, id} ->
          socket
          |> assign(:recorded_id, id)
          |> add_message("Game saved to history.")

        {:error, reason} ->
          Logger.error("Could not save the game: #{inspect(reason)}")
          add_message(socket, "Could not save the game.")
      end
    else
      socket
    end
  end

  ## Clicks

  defp click(socket, square) do
    %{game: game, player_color: player_color, resigned_by: resigned_by} = socket.assigns

    cond do
      socket.assigns.thinking ->
        socket

      resigned_by != nil or Game.over?(game) ->
        add_message(socket, "The game is over. Start a new game.")

      game.side_to_move != player_color ->
        socket

      socket.assigns.selected == nil ->
        if own_piece?(game, square, player_color), do: select(socket, square), else: socket

      square == socket.assigns.selected ->
        clear_selection(socket)

      own_piece?(game, square, player_color) ->
        select(socket, square)

      MapSet.member?(socket.assigns.targets, square) ->
        play_move(socket, socket.assigns.selected, square)

      true ->
        socket
        |> clear_selection()
        |> add_message("That is not a legal move.")
    end
  end

  defp select(socket, square) do
    targets =
      socket.assigns.game
      |> Rules.legal_moves()
      |> Enum.filter(&(Move.from(&1) == square))
      |> Enum.map(&Move.to/1)
      |> MapSet.new()

    assign(socket, selected: square, targets: targets)
  end

  defp play_move(socket, from, to) do
    game = socket.assigns.game

    move =
      game
      |> Rules.legal_moves()
      |> Enum.filter(&(Move.from(&1) == from and Move.to(&1) == to))
      |> choose_move()

    if move != nil and Rules.legal_move?(game, move) do
      next_game = Rules.apply(game, move)
      san = SAN.to_san(move, game)

      socket
      |> put_game(next_game)
      |> clear_selection()
      |> add_message("You played #{san}.")
      |> maybe_record_game()
      |> maybe_engine_move()
    else
      socket
      |> clear_selection()
      |> add_message("That is not a legal move.")
    end
  end

  # A destination normally has exactly one legal move. Promotions have four;
  # the first pass always promotes to a queen.
  defp choose_move(moves) do
    Enum.find(moves, fn move ->
      case Move.promotion_piece(move) do
        nil -> false
        piece -> Piece.type(piece) == :queen
      end
    end) || List.first(moves)
  end

  defp own_piece?(game, square, color) do
    case Board.at(game.board, square) do
      nil -> false
      piece -> Piece.of_color?(piece, color)
    end
  end

  defp clear_selection(socket), do: assign(socket, selected: nil, targets: MapSet.new())

  defp add_message(socket, text) do
    update(socket, :messages, fn messages -> Enum.take([text | messages], @max_messages) end)
  end

  ## Presentation

  defp status_text(game, player_color, resigned_by) do
    cond do
      resigned_by != nil ->
        "You resigned. The engine wins."

      true ->
        base = game |> Narrator.describe_status() |> upcase_first()

        case Game.status(game) do
          :ongoing ->
            if Rules.in_check?(game) do
              base <> " #{color_name(game.side_to_move)} is in check."
            else
              base
            end

          :checkmate ->
            winner = Game.winner(game)
            side = color_name(game.side_to_move)

            if winner == player_color do
              "#{side} is checkmated. You win."
            else
              "#{side} is checkmated. The engine wins."
            end

          :stalemate ->
            "#{color_name(game.side_to_move)} is stalemated. The game is drawn."

          _draw ->
            base
        end
    end
  end

  defp turn_label(_game, _player_color, _resigned_by, true), do: "Engine thinking"

  defp turn_label(game, _player_color, resigned_by, false) do
    cond do
      resigned_by != nil or Game.over?(game) -> "Game over"
      true -> "#{color_name(game.side_to_move)} to move"
    end
  end

  defp result(_game, :white), do: "0-1"
  defp result(_game, :black), do: "1-0"

  defp result(game, nil) do
    case Game.status(game) do
      :ongoing -> "*"
      :checkmate -> if Game.winner(game) == :white, do: "1-0", else: "0-1"
      _draw -> "1/2-1/2"
    end
  end

  defp game_over?(game, resigned_by), do: resigned_by != nil or Game.over?(game)

  defp color_name(color), do: String.capitalize(to_string(color))

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(text), do: text

  defp last_move_summary(%Game{moves: []}), do: nil

  defp last_move_summary(game) do
    case String.split(Narrator.describe_last_move(game), "\n", parts: 3) do
      [san, description, _rest] ->
        san = san |> String.split(". ", parts: 2) |> List.last()
        "#{san} — #{description}"

      _other ->
        nil
    end
  end

  defp move_rows(game) do
    moves = Game.moves_in_order(game)
    states = Game.replay(game)

    moves
    |> Enum.zip(states)
    |> Enum.map(fn {move, state} ->
      %{
        number: state.fullmove_number,
        side: state.side_to_move,
        san: SAN.to_san(move, state)
      }
    end)
    |> Enum.chunk_by(& &1.number)
    |> Enum.map(fn entries ->
      %{
        number: hd(entries).number,
        white: Enum.find_value(entries, fn entry -> entry.side == :white && entry.san end),
        black: Enum.find_value(entries, fn entry -> entry.side == :black && entry.san end)
      }
    end)
  end

  defp parse_square(<<file, rank>>) when file in ?a..?h and rank in ?1..?8 do
    {:ok, Position.from_string(<<file, rank>>)}
  end

  defp parse_square(_square), do: :error

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} bare>
      <div class="flex h-full flex-col gap-3">
        <header class="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-2">
          <button
            id="about-title"
            type="button"
            phx-click="open_about"
            title="About Chess Ex Web UI"
            class="group inline-flex min-w-0 items-center gap-1.5 rounded-lg text-xl font-bold tracking-tight text-base-content transition hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            Chess Ex Web UI
            <.icon
              name="hero-information-circle"
              class="size-4 text-base-content/30 transition group-hover:text-primary/70"
            />
          </button>

          <div class="flex flex-wrap items-center gap-2">
            <button
              id="new-game"
              type="button"
              phx-click="new_game"
              class="inline-flex items-center gap-1.5 rounded-lg bg-base-content px-3 py-1.5 text-sm font-semibold text-base-100 shadow-sm transition hover:bg-base-content/85 hover:shadow-md"
            >
              <.icon name="hero-arrow-path" class="size-3.5" /> New game
            </button>

            <button
              id="switch-sides"
              type="button"
              phx-click="switch_sides"
              class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3 py-1.5 text-sm font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
            >
              <.icon name="hero-arrows-right-left" class="size-3.5" /> Switch sides
            </button>

            <button
              id="resign"
              type="button"
              phx-click="resign"
              disabled={game_over?(@game, @resigned_by)}
              class={[
                "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-semibold transition",
                if(game_over?(@game, @resigned_by),
                  do: "cursor-not-allowed border-base-300 text-base-content/30 opacity-50",
                  else:
                    "border-error/30 bg-base-100/70 text-error shadow-sm hover:bg-error/10 hover:shadow-md"
                )
              ]}
            >
              <.icon name="hero-flag" class="size-3.5" /> Resign
            </button>

            <.link
              id="history-link"
              navigate={~p"/history"}
              class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3 py-1.5 text-sm font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
            >
              <.icon name="hero-trophy" class="size-3.5" /> History
            </.link>

            <div
              id="turn-indicator"
              role="status"
              data-thinking={to_string(@thinking)}
              class={[
                "inline-flex min-w-36 items-center justify-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium",
                cond do
                  game_over?(@game, @resigned_by) ->
                    "border-base-300 bg-base-200 text-base-content/50"

                  @thinking ->
                    "border-warning/30 bg-warning/10 text-warning"

                  true ->
                    "border-success/30 bg-success/10 text-success"
                end
              ]}
            >
              <%= if @thinking do %>
                <span class="flex items-end gap-0.5" aria-hidden="true">
                  <span class="thinking-dot size-1 rounded-full bg-current" />
                  <span class="thinking-dot size-1 rounded-full bg-current" />
                  <span class="thinking-dot size-1 rounded-full bg-current" />
                </span>
              <% else %>
                <span class={[
                  "size-1.5 rounded-full",
                  if(game_over?(@game, @resigned_by), do: "bg-base-content/30", else: "bg-success")
                ]} />
              <% end %>
              {turn_label(@game, @player_color, @resigned_by, @thinking)}
            </div>
          </div>
        </header>

        <div class="grid min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)] gap-3 lg:grid-cols-[minmax(0,1fr)_20rem] lg:grid-rows-1 xl:grid-cols-[minmax(0,1fr)_24rem]">
          <section class="flex min-h-0 min-w-0 items-start justify-center">
            <.board
              game={@game}
              orientation={@orientation}
              selected={@selected}
              targets={@targets}
              disabled={game_over?(@game, @resigned_by) or @thinking}
              busy={@thinking}
            />
          </section>

          <aside class="flex min-h-0 flex-col gap-3 overflow-y-auto lg:overflow-hidden">
            <section class="shrink-0 rounded-xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur">
              <h2 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
                Status
              </h2>

              <p
                id="status"
                aria-live="polite"
                class="mt-1.5 text-base font-semibold leading-6 text-base-content"
              >
                {status_text(@game, @player_color, @resigned_by)}
              </p>

              <p
                :if={@last_move_summary}
                id="last-move"
                class="mt-1 text-xs leading-5 text-base-content/60"
              >
                {@last_move_summary}
              </p>

              <div
                :if={@recorded_id}
                id="recorded-game"
                class="mt-3 rounded-lg border border-success/30 bg-success/10 px-3 py-2"
              >
                <p class="flex items-center gap-1.5 text-xs font-semibold text-success">
                  <.icon name="hero-check-circle" class="size-3.5" /> Saved to history
                </p>
                <div class="mt-2 flex flex-wrap gap-2 text-xs">
                  <.link
                    id="view-recorded-game"
                    navigate={~p"/history/#{@recorded_id}"}
                    class="inline-flex items-center gap-1 rounded-md border border-base-300 bg-base-100/70 px-2 py-1 font-semibold text-base-content shadow-sm transition hover:bg-base-200"
                  >
                    View game
                  </.link>
                  <.link
                    id="download-pgn"
                    href={~p"/history/#{@recorded_id}/download"}
                    download
                    class="inline-flex items-center gap-1 rounded-md border border-base-300 bg-base-100/70 px-2 py-1 font-semibold text-base-content shadow-sm transition hover:bg-base-200"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-3" /> Download PGN
                  </.link>
                </div>
              </div>

              <div class="mt-3 border-t border-base-300/60 pt-2">
                <h3 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  Activity
                </h3>

                <ul id="messages" class="mt-1 max-h-20 space-y-1 overflow-y-auto pr-1">
                  <li
                    :for={{message, index} <- Enum.with_index(@messages)}
                    id={"message-#{index}"}
                    class="flex gap-2 text-xs leading-4 text-base-content/70"
                  >
                    <span class="mt-[0.35rem] size-1 shrink-0 rounded-full bg-base-content/30" />
                    <span>{message}</span>
                  </li>
                </ul>
              </div>
            </section>

            <section class="flex min-h-0 flex-1 flex-col rounded-xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur">
              <div class="flex items-center justify-between gap-3">
                <h2 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  Moves
                </h2>
                <span
                  id="result"
                  class="rounded-full bg-base-200 px-2 py-0.5 font-mono text-[0.7rem] font-semibold text-base-content/70"
                >
                  {result(@game, @resigned_by)}
                </span>
              </div>

              <div id="moves" class="mt-2 min-h-0 flex-1 overflow-y-auto pr-1">
                <p
                  :if={@move_rows == []}
                  class="py-4 text-center text-sm text-base-content/40"
                >
                  No moves yet.
                </p>

                <table :if={@move_rows != []} class="w-full border-collapse text-xs">
                  <thead>
                    <tr class="text-left text-[0.65rem] uppercase tracking-wider text-base-content/40">
                      <th class="w-8 pb-1.5 font-medium">#</th>
                      <th class="pb-1.5 font-medium">White</th>
                      <th class="pb-1.5 font-medium">Black</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={row <- @move_rows}
                      id={"move-#{row.number}"}
                      class="border-t border-base-300/60"
                    >
                      <td class="py-1 pr-2 align-top font-mono text-[0.7rem] text-base-content/40 tabular-nums">
                        {row.number}.
                      </td>
                      <td
                        id={"move-#{row.number}-white"}
                        data-ply={row.white && row.number * 2 - 1}
                        class="py-1 pr-2 align-top font-mono font-medium text-base-content"
                      >
                        {row.white}
                      </td>
                      <td
                        id={"move-#{row.number}-black"}
                        data-ply={row.black && row.number * 2}
                        class="py-1 align-top font-mono font-medium text-base-content"
                      >
                        {row.black}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
          </aside>
        </div>

        <.about :if={@about_open} info={@system_info} />
      </div>
    </Layouts.app>
    """
  end
end
