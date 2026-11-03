defmodule ChessUIWeb.Plugs.ProxyRewriteTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias ChessUIWeb.Plugs.ProxyRewrite

  setup do
    previous = Application.get_env(:chess_ex_ui, :proxy_rewrite_on)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  test "leaves the connection alone when no rewrite is configured" do
    Application.put_env(:chess_ex_ui, :proxy_rewrite_on, [])

    conn = ProxyRewrite.call(forwarded_conn("203.0.113.7"), [])

    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "rewrites the remote ip from the first x-forwarded-for entry" do
    Application.put_env(:chess_ex_ui, :proxy_rewrite_on, [:x_forwarded_for])

    conn = ProxyRewrite.call(forwarded_conn("203.0.113.7, 10.0.0.1"), [])

    assert conn.remote_ip == {203, 0, 113, 7}
  end

  test "leaves an invalid x-forwarded-for alone" do
    Application.put_env(:chess_ex_ui, :proxy_rewrite_on, [:x_forwarded_for])

    conn = ProxyRewrite.call(forwarded_conn("not-an-ip"), [])

    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "rewrites the scheme and port from x-forwarded-proto" do
    Application.put_env(:chess_ex_ui, :proxy_rewrite_on, [:x_forwarded_proto])

    conn =
      :get
      |> Plug.Test.conn("/")
      |> put_req_header("x-forwarded-proto", "https")
      |> ProxyRewrite.call([])

    assert conn.scheme == :https
    assert conn.port == 443
  end

  defp forwarded_conn(value) do
    :get
    |> Plug.Test.conn("/")
    |> put_req_header("x-forwarded-for", value)
  end

  defp restore(nil), do: Application.delete_env(:chess_ex_ui, :proxy_rewrite_on)
  defp restore(value), do: Application.put_env(:chess_ex_ui, :proxy_rewrite_on, value)
end
