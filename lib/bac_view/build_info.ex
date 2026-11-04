defmodule BacView.BuildInfo do
  @moduledoc """
  Application version label and compile-time build stamp for UI footers.
  """

  @built_at System.get_env("BACVIEW_BUILD_TIME") ||
              DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  @git_suffix BacView.Application.get_git_suffix()

  def __mix_recompile__?() do
    @git_suffix != BacView.Application.get_git_suffix()
  end

  @doc """
  Base version string from the running application (e.g. `"0.1.0"`).
  """
  @spec version() :: String.t()
  def version() do
    case Application.spec(:bacview, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn when is_binary(vsn) -> vsn
      _other -> "0.0.0"
    end
  end

  @doc """
  Version for display. When HEAD is not exactly on a git tag, appends `+` and the
  short commit SHA (e.g. `"0.1.0+a1b2c3d"`).
  """
  @spec version_label() :: String.t()
  def version_label() do
    version() <> @git_suffix
  end

  @doc """
  ISO-8601 UTC build timestamp (from `BACVIEW_BUILD_TIME` or compile time).
  """
  @spec built_at() :: String.t()
  def built_at(), do: @built_at

  @doc false
  @spec git_suffix() :: String.t()
  def git_suffix(), do: @git_suffix
end
