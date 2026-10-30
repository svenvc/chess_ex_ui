defmodule ChessUI.SystemInfo do
  @application :chess_ex_ui

  def application, do: @application

  def application_version, do: "#{Application.spec(@application, :vsn)}"

  def config_environment, do: "#{Application.get_env(@application, :config_env)}"

  def elixir_version, do: System.version()

  def erlang_otp_version do
    otp_release = to_string(:erlang.system_info(:otp_release))

    [
      Path.join([:code.root_dir(), "releases", otp_release, "OTP_VERSION"]),
      Path.join([:code.root_dir(), "OTP_VERSION"])
    ]
    |> Enum.find_value(fn path ->
      case File.read(path) do
        {:ok, contents} -> String.trim(contents)
        {:error, _} -> nil
      end
    end)
  end

  def erts_version, do: to_string(:erlang.system_info(:version))

  def uptime() do
    :erlang.statistics(:wall_clock)
    |> then(fn {ms, _} -> Integer.floor_div(ms, 1000) end)
    |> format_duration()
  end

  def memory() do
    "#{(:erlang.memory(:total) / 1024 / 1024) |> round()} MB"
  end

  def all do
    %{
      application: application(),
      application_version: application_version(),
      config_environment: config_environment(),
      elixir_version: elixir_version(),
      erlang_otp_version: erlang_otp_version(),
      erts_version: erts_version(),
      uptime: uptime(),
      memory: memory()
    }
  end

  def format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    seconds = rem(seconds, 60)

    [
      {hours, "h"},
      {minutes, "m"},
      {seconds, "s"}
    ]
    |> Enum.reject(fn {value, _unit} -> value == 0 end)
    |> Enum.map_join(" ", fn {value, unit} -> "#{value}#{unit}" end)
  end
end
