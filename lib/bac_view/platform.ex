defmodule BacView.Platform do
  @moduledoc false

  @desktop Application.compile_env!(:bacview, :desktop_mode)
  @mstp_enabled Application.compile_env!(:bacview, :mstp_enabled)

  @spec desktop?() :: boolean()
  def desktop?(), do: @desktop

  @spec web?() :: boolean()
  def web?(), do: not @desktop

  @spec mstp_enabled?() :: boolean()
  def mstp_enabled?(), do: @mstp_enabled
end
