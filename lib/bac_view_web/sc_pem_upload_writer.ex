defmodule BacViewWeb.SCPemUploadWriter do
  @moduledoc false
  @behaviour Phoenix.LiveView.UploadWriter

  @derive {Inspect, except: [:chunks]}
  defstruct chunks: []

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl true
  def write_chunk(data, state), do: {:ok, %{state | chunks: [data | state.chunks]}}

  @impl true
  def meta(state), do: %{pem: IO.iodata_to_binary(Enum.reverse(state.chunks))}

  @impl true
  def close(state, :done), do: {:ok, state}
  def close(_state, _reason), do: {:ok, %__MODULE__{}}
end
