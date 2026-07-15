defmodule BacView.BACnet.ClientResult do
  @moduledoc false

  alias BACnet.Protocol.APDU

  @doc """
  Normalizes bacstack / ClientHelper return shapes into BacView's
  `{:ok, _}` / `:ok` / `{:error, reason}` contract without double-wrapping.
  """
  @spec normalize(term()) :: :ok | {:ok, term()} | {:error, term()}
  def normalize(:ok), do: :ok
  def normalize({:ok, _value} = ok), do: ok
  def normalize({:error, _reason} = err), do: normalize_error(err)
  def normalize(other), do: normalize_error({:error, other})

  @doc false
  @spec normalize_error({:error, term()}) :: {:error, term()}
  def normalize_error({:error, %APDU.Error{} = err}), do: {:error, {:bacnet_error, err}}
  def normalize_error({:error, %APDU.Reject{} = rej}), do: {:error, {:bacnet_reject, rej}}
  def normalize_error({:error, %APDU.Abort{} = abort}), do: {:error, {:bacnet_abort, abort}}
  def normalize_error({:error, _err} = err), do: err
end
