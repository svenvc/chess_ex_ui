defmodule ChessUI.Api.RateLimit do
  @moduledoc """
  A small fixed-window rate limiter backed by ETS.

  Each bucket has a limit and a window in seconds, configured under
  `config :chess_ex_ui, :api, rate_limit: %{bucket => {limit, window}}`. The
  window key includes the window number, so a counter is created lazily and
  never needs to be reset. Expired windows are swept periodically.
  """

  use GenServer

  alias ChessUI.Api.Config

  @table __MODULE__
  @sweep_interval 60_000

  ## Client

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Count one request in `bucket` for `key`.

  Returns `{:ok, remaining}` or `{:error, retry_after_seconds}`.
  """
  def hit(bucket, key) do
    {limit, window} = limit(bucket)
    now = System.system_time(:second)
    window_id = div(now, window)
    ets_key = {bucket, key, window_id}
    expires_at = (window_id + 1) * window
    count = :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0, expires_at})

    if count <= limit do
      {:ok, max(limit - count, 0)}
    else
      {:error, max(expires_at - now, 1)}
    end
  end

  @doc """
  Clear every counter. Intended for tests.
  """
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  ## Server

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)

    :ets.select_delete(@table, [
      {{{:_, :_, :_}, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  defp limit(bucket) do
    Config.get(:rate_limit) |> Map.get(bucket, {60, 60})
  end
end
