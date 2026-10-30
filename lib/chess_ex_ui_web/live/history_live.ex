defmodule ChessUIWeb.HistoryLive do
  @moduledoc """
  The hall of fame: completed games, newest first.

  The page reads the PGN archive on mount. It shows a compact summary of the
  visitor's record against the engine and one row per game, with links to the
  replay view and the PGN download.
  """

  use ChessUIWeb, :live_view

  import ChessUIWeb.GameFormat,
    only: [datetime: 1, duration: 1, outcome_class: 1, outcome_label: 1]

  alias ChessUI.GameArchive

  @impl true
  def mount(_params, _session, socket) do
    games = GameArchive.list()

    {:ok,
     socket
     |> assign(:page_title, "History")
     |> assign(:games_empty?, games == [])
     |> assign(:total, length(games))
     |> assign(:stat_cards, stat_cards(games))
     |> stream(:games, games, dom_id: &"game-#{&1.id}")}
  end

  defp stat_cards(games) do
    [
      {"stat-total", "Completed", length(games)},
      {"stat-visitor-wins", "Visitor wins", Enum.count(games, &(&1.outcome == :visitor_win))},
      {"stat-engine-wins", "Engine wins", Enum.count(games, &(&1.outcome == :engine_win))},
      {"stat-draws", "Draws", Enum.count(games, &(&1.outcome == :draw))}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} bare scroll>
      <div class="mx-auto w-full max-w-5xl space-y-6">
        <header class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="space-y-2">
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
              Hall of Fame
            </p>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Completed games</h1>
            <p class="max-w-2xl text-sm leading-6 text-base-content/60">
              Every finished game is saved automatically as PGN. <br /> Use
              <span class="font-semibold text-base-content/80">View</span>
              to replay it or <span class="font-semibold text-base-content/80">PGN</span>
              to download the file.
            </p>
          </div>

          <.link
            id="history-play"
            navigate={~p"/"}
            class="inline-flex w-fit items-center gap-1.5 rounded-lg bg-base-content px-3.5 py-2 text-sm font-semibold text-base-100 shadow-sm transition hover:bg-base-content/85 hover:shadow-md"
          >
            <.icon name="hero-play" class="size-3.5" /> Play a game
          </.link>
        </header>

        <section id="history-stats" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div
            :for={{stat_id, label, value} <- @stat_cards}
            id={stat_id}
            class="rounded-xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur"
          >
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
              {label}
            </p>
            <p class="mt-1 text-2xl font-semibold tabular-nums text-base-content">
              {value}
            </p>
          </div>
        </section>

        <section class="overflow-hidden rounded-xl border border-base-300 bg-base-100/90 shadow-sm backdrop-blur">
          <div class="flex items-center justify-between gap-3 border-b border-base-300/70 px-4 py-3">
            <h2 class="text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
              Games
            </h2>
            <span class="rounded-full bg-base-200 px-2 py-0.5 font-mono text-[0.7rem] font-semibold text-base-content/70">
              {@total}
            </span>
          </div>

          <div id="games" phx-update="stream" class="divide-y divide-base-300/60">
            <p
              :if={@games_empty?}
              id="games-empty"
              class="px-4 py-14 text-center text-sm text-base-content/50"
            >
              No completed games yet. Finish a game and it will appear here.
            </p>

            <div
              :for={{dom_id, game} <- @streams.games}
              id={dom_id}
              data-result={game.result}
              data-outcome={game.outcome}
              data-termination={game.termination}
              class="flex flex-col gap-3 px-4 py-4 transition hover:bg-base-200/40 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0 space-y-1">
                <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span class="font-mono text-xs font-medium text-base-content/70">
                    {datetime(game.started_at)}
                  </span>
                  <span class={[
                    "rounded-full border px-2 py-0.5 text-[0.7rem] font-semibold",
                    outcome_class(game.outcome)
                  ]}>
                    {outcome_label(game.outcome)}
                  </span>
                </div>

                <p class="text-sm font-semibold text-base-content">
                  {game.white}
                  <span class="font-normal text-base-content/40">vs</span>
                  {game.black}
                </p>

                <p class="text-xs text-base-content/55">
                  {String.capitalize(game.termination)} · {game.ply_count} plies · {duration(
                    game.duration_seconds
                  )}
                </p>
              </div>

              <div class="flex shrink-0 items-center gap-2">
                <.link
                  id={"view-#{game.id}"}
                  navigate={~p"/history/#{game.id}"}
                  class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3 py-1.5 text-xs font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
                >
                  <.icon name="hero-play" class="size-3.5" /> View
                </.link>
                <.link
                  id={"download-#{game.id}"}
                  href={~p"/history/#{game.id}/download"}
                  download
                  class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/70 px-3 py-1.5 text-xs font-semibold text-base-content shadow-sm transition hover:bg-base-200 hover:shadow-md"
                >
                  <.icon name="hero-arrow-down-tray" class="size-3.5" /> PGN
                </.link>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
