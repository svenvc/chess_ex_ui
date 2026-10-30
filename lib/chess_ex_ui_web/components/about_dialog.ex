defmodule ChessUIWeb.AboutDialog do
  @moduledoc """
  The about dialog: a short description of the application plus the runtime
  details collected by `ChessUI.SystemInfo`.

  The component is presentational. The LiveView decides when the dialog is
  open and handles the `on_close` event for the backdrop, the close button and
  the Escape key.
  """

  use ChessUIWeb, :html

  @labels %{
    application: "Application",
    application_version: "Version",
    config_environment: "Environment",
    elixir_version: "Elixir",
    erlang_otp_version: "Erlang/OTP",
    erts_version: "ERTS",
    uptime: "Uptime",
    memory: "Memory"
  }

  attr :info, :map, required: true, doc: "the runtime details to show in the table"

  attr :on_close, :string,
    default: "close_about",
    doc: "the event sent when the dialog is dismissed"

  def about(assigns) do
    assigns = assign(assigns, :rows, Enum.sort(assigns.info))

    ~H"""
    <div
      id="about-dialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown={@on_close}
      phx-key="Escape"
      phx-remove={JS.focus(to: "#about-title")}
    >
      <button
        id="about-backdrop"
        type="button"
        phx-click={@on_close}
        aria-label="Close the about dialog"
        tabindex="-1"
        class="absolute inset-0 cursor-default bg-base-content/40 backdrop-blur-sm"
      />

      <section
        id="about-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="about-heading"
        phx-mounted={JS.focus_first()}
        class="relative flex max-h-[calc(100dvh-2rem)] w-full max-w-xl flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-2xl"
      >
        <header class="flex items-start justify-between gap-4 border-b border-base-300/70 px-5 py-4">
          <div class="min-w-0">
            <h2 id="about-heading" class="text-lg font-semibold tracking-tight text-base-content">
              About Chess Ex Web UI
            </h2>
            <p class="mt-0.5 text-xs text-base-content/50">
              A Phoenix LiveView front end for the pure Elixir ChessEx engine.
            </p>
          </div>

          <button
            id="about-close"
            type="button"
            phx-click={@on_close}
            aria-label="Close"
            class="-mr-1 inline-flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/50 transition hover:bg-base-200 hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </header>

        <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          <div class="space-y-3 text-sm leading-6 text-base-content/80">
            <p>
              For more information, see <.link
                href="https://git.stfx.eu/sven/chess_ex_ui"
                target="_blank"
                rel="noreferrer"
                class="font-medium text-primary underline decoration-primary/30 underline-offset-2 transition hover:decoration-primary"
              >
                ChessExUI
              </.link>, <.link
                href="https://git.stfx.eu/sven/chess_ex"
                target="_blank"
                rel="noreferrer"
                class="font-medium text-primary underline decoration-primary/30 underline-offset-2 transition hover:decoration-primary"
              >
                ChessEx
              </.link>,
              <.link
                href="https://www.phoenixframework.org"
                target="_blank"
                rel="noreferrer"
                class="font-medium text-primary underline decoration-primary/30 underline-offset-2 transition hover:decoration-primary"
              >
                Phoenix LiveView
              </.link>
              and the
              <.link
                href="https://lichess.org"
                target="_blank"
                rel="noreferrer"
                class="font-medium text-primary underline decoration-primary/30 underline-offset-2 transition hover:decoration-primary"
              >
                lichess
              </.link>
              board and piece assets.
            </p>
          </div>

          <h3 class="mt-5 text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-base-content/50">
            Runtime
          </h3>

          <table id="system-info" class="mt-2 w-full border-collapse text-xs">
            <tbody>
              <tr
                :for={{key, value} <- @rows}
                id={"system-info-#{key}"}
                class="border-t border-base-300/60 first:border-t-0"
              >
                <th
                  scope="row"
                  class="w-40 py-1.5 pr-3 text-left align-top font-medium text-base-content/60"
                >
                  {label(key)}
                </th>
                <td class="break-words py-1.5 align-top font-mono text-base-content">
                  {value || "unknown"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <footer class="flex justify-end border-t border-base-300/70 px-5 py-3">
          <button
            id="about-dismiss"
            type="button"
            phx-click={@on_close}
            class="inline-flex items-center rounded-lg bg-base-content px-3 py-1.5 text-sm font-semibold text-base-100 shadow-sm transition hover:bg-base-content/85 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            Close
          </button>
        </footer>
      </section>
    </div>
    """
  end

  defp label(key), do: Map.get(@labels, key, humanize(key))

  defp humanize(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
