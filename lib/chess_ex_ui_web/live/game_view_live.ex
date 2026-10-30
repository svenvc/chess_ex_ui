defmodule ChessUIWeb.GameViewLive do
  @moduledoc """
  A read-only replay of one archived game.

  The PGN is read with `Chess.PGN`, the positions are rebuilt with
  `Chess.Game.replay/1`, and the existing board component renders the position
  at the selected ply. The move list doubles as navigation.
  """

  use ChessUIWeb, :live_view

  import ChessUIWeb.ChessBoard, only: [board: 1]

  import ChessUIWeb.GameFormat,
    only: [
      datetime: 1,
      duration: 1,
      outcome_class: 1,
      outcome_label: 1,
      short_id: 1
    ]

  alias Chess.{Game, Narrator, SAN}
  alias ChessUI.GameArchive

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Game",
       record: nil,
       states: [],
       move_rows: [],
       step: 0,
       last_step: 0,
       current_game: nil,
       orientation: :white
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case GameArchive.get(id) do
      {:ok, record} ->
        states = Game.replay(record.pgn.game)
        last_step = length(states) - 1
        orientation = record.summary.player_color || :white

        socket =
          socket
          |> assign(:page_title, "Game #{short_id(record.id)}")
          |> assign(:record, %{id: record.id, summary: record.summary})
          |> assign(:states, states)
          |> assign(:last_step, last_step)
          |> assign(:move_rows, move_rows(record.pgn.moves, states))
          |> assign(:orientation, orientation)
          |> put_step(last_step)

        {:noreply, socket}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "That game could not be found.")
         |> push_navigate(to: ~p"/history")}
    end
  end

  @impl true
  def handle_event("goto", %{"step" => step}, socket) do
    case Integer.parse(step) do
      {step, ""} -> {:noreply, put_step(socket, step)}
      _other -> {:noreply, socket}
    end
  end

  defp put_step(socket, step) do
    step = step |> max(0) |> min(socket.assigns.last_step)

    assign(socket,
      step: step,
      current_game: Enum.at(socket.assigns.states, step)
    )
  end

  defp move_rows(moves, states) do
    moves
    |> Enum.with_index(1)
    |> Enum.map(fn {move, ply} ->
      before = Enum.at(states, ply - 1)

      %{
        ply: ply,
        san: SAN.to_san(move, before),
        number: before.fullmove_number,
        side: before.side_to_move
      }
    end)
    |> Enum.chunk_by(& &1.number)
    |> Enum.map(fn entries ->
      %{
        number: hd(entries).number,
        white: Enum.find(entries, &(&1.side == :white)),
        black: Enum.find(entries, &(&1.side == :black))
      }
    end)
  end

  defp replay_status(record, step, last_step, current_game) do
    if step == last_step do
      "#{outcome_label(record.summary.outcome)} · #{String.capitalize(record.summary.termination)}"
    else
      Narrator.describe_status(current_game)
    end
  end

  defp step_label(0, _last_step), do: "Start position"
  defp step_label(step, last_step), do: "Move #{step} of #{last_step}"

  defp control_class(true) do
    "cursor-not-allowed border-base-300 text-base-content/30 opacity-50"
  end

  defp control_class(false) do
    "border-base-300 bg-base-100/70 text-base-content shadow-sm hover:bg-base-200 hover:shadow-md"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} bare scroll>
      <div class="mx-auto w-full max-w-[1400px] space-y-5">
        <header class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div class="space-y-2">
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">
              Game {short_id(@record.id)}
            </h1>
            <p class="text-sm text-base-content/60">
              {datetime(@record.summary.started_at)} · {String.capitalize(@record.summary.termination)}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <.link
              id="back-to-history"
              navigate={~p"/history"}
              class="inline-flex w-fit items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3.5 py-2 text-sm font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
            >
              <.icon name="hero-arrow-left" class="size-3.5" /> Back to history
            </.link>
            <.link
              id="download-pgn"
              href={~p"/history/#{@record.id}/download"}
              download
              class="inline-flex w-fit items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3.5 py-2 text-sm font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
            >
              <.icon name="hero-arrow-down-tray" class="size-3.5" /> Download PGN
            </.link>
          </div>
        </header>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section class="flex min-w-0 flex-col rounded-xl border border-base-300 bg-base-100/90 p-3 shadow-sm backdrop-blur sm:p-4">
            <.board
              game={@current_game}
              orientation={@orientation}
              selected={nil}
              targets={nil}
              disabled={true}
              busy={false}
              interactive={false}
            />

            <div class="mt-3 flex flex-wrap items-center justify-center gap-2">
              <button
                id="replay-first"
                type="button"
                phx-click="goto"
                phx-value-step="0"
                disabled={@step == 0}
                aria-label="First position"
                class={[
                  "inline-flex size-8 items-center justify-center rounded-lg border transition",
                  control_class(@step == 0)
                ]}
              >
                <.icon name="hero-backward" class="size-3.5" />
              </button>
              <button
                id="replay-prev"
                type="button"
                phx-click="goto"
                phx-value-step={@step - 1}
                disabled={@step == 0}
                aria-label="Previous move"
                class={[
                  "inline-flex size-8 items-center justify-center rounded-lg border transition",
                  control_class(@step == 0)
                ]}
              >
                <.icon name="hero-chevron-left" class="size-3.5" />
              </button>

              <p id="replay-step" class="min-w-28 text-center font-mono text-xs text-base-content/60">
                {step_label(@step, @last_step)}
              </p>

              <button
                id="replay-next"
                type="button"
                phx-click="goto"
                phx-value-step={@step + 1}
                disabled={@step == @last_step}
                aria-label="Next move"
                class={[
                  "inline-flex size-8 items-center justify-center rounded-lg border transition",
                  control_class(@step == @last_step)
                ]}
              >
                <.icon name="hero-chevron-right" class="size-3.5" />
              </button>
              <button
                id="replay-last"
                type="button"
                phx-click="goto"
                phx-value-step={@last_step}
                disabled={@step == @last_step}
                aria-label="Final position"
                class={[
                  "inline-flex size-8 items-center justify-center rounded-lg border transition",
                  control_class(@step == @last_step)
                ]}
              >
                <.icon name="hero-forward" class="size-3.5" />
              </button>
            </div>

            <p
              id="replay-status"
              class="mt-2 text-center text-sm font-semibold text-base-content/70"
            >
              {replay_status(@record, @step, @last_step, @current_game)}
            </p>
          </section>

          <aside class="flex min-w-0 flex-col gap-4">
            <section class="rounded-xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur">
              <div class="flex items-center justify-between gap-2">
                <h2 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  Result
                </h2>
                <span class={[
                  "rounded-full border px-2 py-0.5 text-[0.7rem] font-semibold",
                  outcome_class(@record.summary.outcome)
                ]}>
                  {outcome_label(@record.summary.outcome)}
                </span>
              </div>

              <dl class="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
                <dt class="text-base-content/50">Started</dt>
                <dd class="text-base-content/80">{datetime(@record.summary.started_at)}</dd>
                <dt class="text-base-content/50">Finished</dt>
                <dd class="text-base-content/80">{datetime(@record.summary.ended_at)}</dd>
                <dt class="text-base-content/50">Duration</dt>
                <dd class="text-base-content/80">{duration(@record.summary.duration_seconds)}</dd>
                <dt class="text-base-content/50">White</dt>
                <dd class="font-semibold text-base-content">{@record.summary.white}</dd>
                <dt class="text-base-content/50">Black</dt>
                <dd class="font-semibold text-base-content">{@record.summary.black}</dd>
                <dt class="text-base-content/50">Result</dt>
                <dd class="text-base-content/80">
                  {@record.summary.result} · {String.capitalize(@record.summary.termination)}
                </dd>
                <dt class="text-base-content/50">Moves</dt>
                <dd class="text-base-content/80">{@record.summary.ply_count} plies</dd>
                <dt class="text-base-content/50">Engine</dt>
                <dd class="text-base-content/80">
                  {@record.summary.engine}
                  <span :if={@record.summary.engine_options} class="text-base-content/50">
                    ({@record.summary.engine_options})
                  </span>
                </dd>
                <dt class="text-base-content/50">Game ID</dt>
                <dd id="game-id" class="break-all font-mono text-[0.7rem] text-base-content/60">
                  {@record.id}
                </dd>
              </dl>
            </section>

            <section class="flex min-h-0 flex-1 flex-col rounded-xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur">
              <h2 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
                Moves
              </h2>

              <p :if={@move_rows == []} class="py-6 text-center text-sm text-base-content/50">
                No moves were played.
              </p>

              <div :if={@move_rows != []} class="mt-2 max-h-[26rem] overflow-y-auto pr-1">
                <table class="w-full border-collapse text-xs">
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
                      class="border-t border-base-300/60"
                    >
                      <td class="py-1 pr-2 align-top font-mono text-[0.7rem] text-base-content/40 tabular-nums">
                        {row.number}.
                      </td>
                      <td class="py-1 pr-2 align-top">
                        <button
                          :if={row.white}
                          id={"replay-move-#{row.white.ply}"}
                          type="button"
                          phx-click="goto"
                          phx-value-step={row.white.ply}
                          class={[
                            "rounded px-1.5 py-0.5 font-mono font-medium transition hover:bg-amber-300/30",
                            @step == row.white.ply && "bg-amber-300/40 text-base-content"
                          ]}
                        >
                          {row.white.san}
                        </button>
                      </td>
                      <td class="py-1 align-top">
                        <button
                          :if={row.black}
                          id={"replay-move-#{row.black.ply}"}
                          type="button"
                          phx-click="goto"
                          phx-value-step={row.black.ply}
                          class={[
                            "rounded px-1.5 py-0.5 font-mono font-medium transition hover:bg-amber-300/30",
                            @step == row.black.ply && "bg-amber-300/40 text-base-content"
                          ]}
                        >
                          {row.black.san}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
