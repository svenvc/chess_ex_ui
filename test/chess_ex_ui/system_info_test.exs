defmodule ChessUI.SystemInfoTest do
  use ExUnit.Case, async: true

  alias ChessUI.SystemInfo

  test "all/0 reports the application and its version" do
    info = SystemInfo.all()

    assert info.application == :chess_ex_ui
    assert is_binary(info.application_version)
    assert info.application_version == SystemInfo.application_version()
  end

  test "all/0 returns every documented key" do
    assert SystemInfo.all()
           |> Map.keys()
           |> Enum.sort() ==
             [
               :application,
               :application_version,
               :config_environment,
               :elixir_version,
               :erlang_otp_version,
               :erts_version,
               :memory,
               :uptime
             ]
  end

  test "the version fields are non-empty strings" do
    info = SystemInfo.all()

    assert info.elixir_version == System.version()
    assert info.elixir_version != ""
    assert is_binary(info.erts_version) and info.erts_version != ""
  end

  test "the config environment matches the application environment" do
    assert SystemInfo.config_environment() ==
             "#{Application.get_env(:chess_ex_ui, :config_env)}"
  end

  test "the Erlang/OTP version is a version string or unavailable" do
    case SystemInfo.erlang_otp_version() do
      nil -> assert true
      version -> assert version =~ ~r/^\d+/
    end
  end

  test "format_duration omits zero units" do
    assert SystemInfo.format_duration(0) == ""
    assert SystemInfo.format_duration(59) == "59s"
    assert SystemInfo.format_duration(60) == "1m"
    assert SystemInfo.format_duration(90) == "1m 30s"
    assert SystemInfo.format_duration(3_600) == "1h"
    assert SystemInfo.format_duration(3_661) == "1h 1m 1s"
  end

  test "uptime and memory are human readable" do
    assert SystemInfo.uptime() =~ ~r/^(\d+h )?(\d+m )?(\d+s)?$/
    assert SystemInfo.memory() =~ ~r/^\d+ MB$/
  end
end
