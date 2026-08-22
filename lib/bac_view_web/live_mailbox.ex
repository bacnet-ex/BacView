defmodule BacViewWeb.LiveMailbox do
  @moduledoc false

  @doc """
  Drop queued copies of `message` so a LiveView can handle a burst as one render.
  Unmatched mailbox items (clicks, patches, other infos) are left in place.
  """
  @spec drain_repeated(term()) :: :ok
  def drain_repeated(message) do
    receive do
      ^message -> drain_repeated(message)
    after
      0 -> :ok
    end
  end
end
