defmodule ChessUI.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ChessUIWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:chess_ex_ui, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ChessUI.PubSub},
      # Start a worker by calling: ChessUI.Worker.start_link(arg)
      # {ChessUI.Worker, arg},
      # Start to serve requests, typically the last entry
      ChessUIWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChessUI.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChessUIWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
