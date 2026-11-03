defmodule ChessUIWeb.Router do
  use ChessUIWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChessUIWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug ChessUIWeb.Plugs.ApiRateLimit
  end

  scope "/", ChessUIWeb do
    pipe_through :browser

    live "/", GameLive
    live "/game", GameLive
    live "/history", HistoryLive
    live "/history/:id", GameViewLive
    get "/history/:id/download", GameDownloadController, :download
  end

  scope "/api", ChessUIWeb.Api do
    pipe_through :api

    get "/", DocsController, :index
    post "/games", GameController, :create
    get "/games/:id", GameController, :show
    post "/games/:id/move", GameController, :move

    match :*, "/", ErrorController, :method_not_allowed
    match :*, "/games", ErrorController, :method_not_allowed
    match :*, "/games/:id", ErrorController, :method_not_allowed
    match :*, "/games/:id/move", ErrorController, :method_not_allowed
    match :*, "/*path", ErrorController, :not_found
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:chess_ex_ui, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChessUIWeb.Telemetry
    end
  end
end
