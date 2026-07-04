defmodule BacView.BACnet.Protocol.StatusFlagsParser do
  @moduledoc false

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.StatusFlags

  @spec normalize(term()) :: StatusFlags.t() | nil
  def normalize(%StatusFlags{} = flags), do: flags

  def normalize(%Encoding{value: value}), do: normalize(value)

  def normalize({:bitstring, tuple}) when is_tuple(tuple) and tuple_size(tuple) == 4 do
    StatusFlags.from_bitstring(tuple)
  end

  def normalize(tuple) when is_tuple(tuple) and tuple_size(tuple) == 4 do
    StatusFlags.from_bitstring(tuple)
  end

  def normalize(tags) when is_list(tags) do
    case StatusFlags.parse(tags) do
      {:ok, {flags, _rest}} -> flags
      _flags -> nil
    end
  end

  def normalize(_flags), do: nil
end
