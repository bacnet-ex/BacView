defmodule BacView.BACnet.ClientResult do
  @moduledoc false

  alias BACnet.Protocol.APDU

  # `Client.send/4` returns every response APDU, including Error, Reject, and
  # Abort, as `{:ok, apdu}`. Callers that reach this function already failed to
  # match the acknowledgement they accept as success, so a raw APDU here is a
  # failure. `Protocol.apdu/0` is exactly these eight structs.
  @response_apdus [
    APDU.Abort,
    APDU.ComplexACK,
    APDU.ConfirmedServiceRequest,
    APDU.Error,
    APDU.Reject,
    APDU.SegmentACK,
    APDU.SimpleACK,
    APDU.UnconfirmedServiceRequest
  ]

  @doc """
  Normalizes bacstack / ClientHelper return shapes into BacView's
  `:ok` / `{:ok, value}` / `{:error, reason}` contract without double-wrapping.

  A raw response APDU inside `{:ok, apdu}` becomes `{:error, apdu}`. Error,
  Reject, and Abort are then tagged `{:bacnet_error, _}`, `{:bacnet_reject, _}`,
  and `{:bacnet_abort, _}`.
  """
  @spec normalize(term()) :: :ok | {:ok, term()} | {:error, term()}
  def normalize(:ok), do: :ok

  def normalize({:ok, %{__struct__: module} = apdu}) when module in @response_apdus do
    normalize_error({:error, apdu})
  end

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
