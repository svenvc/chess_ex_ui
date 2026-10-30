defmodule ChessUIWeb.GameFormat do
  @moduledoc """
  Formatting helpers for the game history and replay views.
  """

  alias ChessUI.SystemInfo

  @doc "Format a UTC timestamp for display."
  def datetime(%DateTime{} = date_time) do
    Calendar.strftime(date_time, "%Y-%m-%d %H:%M:%S UTC")
  end

  def datetime(_date_time), do: "—"

  @doc "Format a duration in seconds."
  def duration(seconds) when is_integer(seconds) and seconds >= 0 do
    case SystemInfo.format_duration(seconds) do
      "" -> "0s"
      text -> text
    end
  end

  def duration(_seconds), do: "—"

  @doc "Return the human-readable outcome of a completed game."
  def outcome_label(:visitor_win), do: "Visitor wins"
  def outcome_label(:engine_win), do: "Engine wins"
  def outcome_label(:draw), do: "Draw"
  def outcome_label(:unfinished), do: "Unfinished"
  def outcome_label(_outcome), do: "Completed"

  @doc "Return the badge classes for an outcome."
  def outcome_class(:visitor_win), do: "border-success/30 bg-success/10 text-success"
  def outcome_class(:engine_win), do: "border-error/30 bg-error/10 text-error"
  def outcome_class(:draw), do: "border-base-300 bg-base-200 text-base-content/70"
  def outcome_class(_outcome), do: "border-base-300 bg-base-200 text-base-content/60"

  @doc "Return a short form of a game id."
  def short_id(id) when is_binary(id) and byte_size(id) > 8, do: String.slice(id, 0, 8)
  def short_id(id), do: id
end
