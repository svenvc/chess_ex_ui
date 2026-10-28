defmodule ChessUIWeb.PageController do
  use ChessUIWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
