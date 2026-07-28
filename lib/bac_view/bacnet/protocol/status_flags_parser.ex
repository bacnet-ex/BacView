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

  @doc """
  Resolves status flags from a BACnet/summary object map.

  Prefers `object.status_flags`, then falls back to
  `object._unknown_properties.status_flags` (common when bacstack leaves the
  property unparsed under unknown properties).
  """
  @spec from_object(term()) :: StatusFlags.t() | nil
  def from_object(obj) when is_map(obj) do
    case normalize(Map.get(obj, :status_flags)) do
      %StatusFlags{} = flags -> flags
      nil -> unknown_status_flags(obj)
    end
  end

  def from_object(_obj), do: nil

  defp unknown_status_flags(obj) do
    case Map.get(obj, :_unknown_properties) do
      unknown when is_map(unknown) ->
        normalize(Map.get(unknown, :status_flags))

      _unknown ->
        nil
    end
  end
end
