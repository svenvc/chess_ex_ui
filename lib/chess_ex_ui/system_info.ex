defmodule ChessUI.SystemInfo do
  @moduledoc """
  Runtime information about the running application.

  Every value is collected on demand from the application environment, the
  runtime or the filesystem, so a caller sees the current state rather than a
  snapshot from start-up. `all/0` gathers the full set into a map, which is
  what the about dialog displays.
  """

  @application :chess_ex_ui

  @doc """
  Returns the OTP application name.

  ## Examples

      iex> ChessUI.SystemInfo.application()
      :chess_ex_ui

  """
  def application, do: @application

  @doc """
  Returns the application version as a string.

  The value comes from the `:vsn` entry of the application specification and is
  `""` when the application is not loaded.

  ## Examples

      iex> ChessUI.SystemInfo.application_version()
      "0.1.1"

  """
  def application_version, do: "#{Application.spec(@application, :vsn)}"

  @doc """
  Returns the configured environment as a string.

  The environment is read from the `:config_env` application key, which
  `config/config.exs` sets to the Mix environment, for example `"dev"` or
  `"test"`. It is `""` when the key is not configured.

  ## Examples

      iex> ChessUI.SystemInfo.config_environment()
      "dev"

  """
  def config_environment, do: "#{Application.get_env(@application, :config_env)}"

  @doc """
  Returns the running Elixir version.

  ## Examples

      iex> ChessUI.SystemInfo.elixir_version()
      "1.20.5"

  """
  def elixir_version, do: System.version()

  @doc """
  Returns the Erlang/OTP release version, for example `"29.1.2"`.

  The full version is read from an `OTP_VERSION` file, which the release build
  step in `mix.exs` copies from the build machine into the release root. When
  running outside a release the file is read from the Erlang installation
  instead. If no such file is available, the function falls back to the major
  release reported by the runtime, for example `"29"`.

  ## Examples

      iex> ChessUI.SystemInfo.erlang_otp_version()
      "29.1.2"

  """
  def erlang_otp_version do
    otp_release = to_string(:erlang.system_info(:otp_release))

    version =
      [
        Path.join(:code.root_dir(), "OTP_VERSION"),
        Path.join([:code.root_dir(), "releases", otp_release, "OTP_VERSION"])
      ]
      |> Enum.find_value(&read_otp_version/1)

    version || otp_release
  end

  defp read_otp_version(path) do
    with {:ok, contents} <- File.read(path),
         version when version != "" <- String.trim(contents) do
      version
    else
      _ -> nil
    end
  end

  @doc """
  Returns the version of the Erlang runtime system (ERTS).

  ## Examples

      iex> ChessUI.SystemInfo.erts_version()
      "15.2.2"

  """
  def erts_version, do: to_string(:erlang.system_info(:version))

  @doc """
  Returns the wall-clock uptime of the node as a compact string.

  The uptime is measured in seconds and formatted with `format_duration/1`.
  Zero-valued units are omitted, so a node that started less than a second ago
  returns an empty string.

  ## Examples

      iex> ChessUI.SystemInfo.uptime()
      "1h 4m 12s"

  """
  def uptime() do
    :erlang.statistics(:wall_clock)
    |> then(fn {ms, _} -> Integer.floor_div(ms, 1000) end)
    |> format_duration()
  end

  @doc """
  Returns the total memory allocated by the Erlang VM, rounded to whole
  megabytes.

  ## Examples

      iex> ChessUI.SystemInfo.memory()
      "42 MB"

  """
  def memory() do
    "#{(:erlang.memory(:total) / 1024 / 1024) |> round()} MB"
  end

  @doc """
  Returns all runtime information as a map.

  The map contains the same keys as the individual functions:

    * `:application` — see `application/0`
    * `:application_version` — see `application_version/0`
    * `:config_environment` — see `config_environment/0`
    * `:elixir_version` — see `elixir_version/0`
    * `:erlang_otp_version` — see `erlang_otp_version/0`
    * `:erts_version` — see `erts_version/0`
    * `:uptime` — see `uptime/0`
    * `:memory` — see `memory/0`

  ## Examples

      iex> info = ChessUI.SystemInfo.all()
      iex> Map.has_key?(info, :elixir_version)
      true

  """
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

  @doc """
  Formats a duration in seconds as a compact string.

  Hours, minutes and seconds are joined with single spaces, and units whose
  value is zero are omitted. A duration of zero therefore formats as an empty
  string.

  ## Examples

      iex> ChessUI.SystemInfo.format_duration(0)
      ""
      iex> ChessUI.SystemInfo.format_duration(59)
      "59s"
      iex> ChessUI.SystemInfo.format_duration(90)
      "1m 30s"
      iex> ChessUI.SystemInfo.format_duration(3661)
      "1h 1m 1s"

  """
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
