defmodule BacView.BACnet.Protocol.StructFieldTypes do
  @moduledoc false

  alias BacView.BACnet.Protocol.BeamTypesCache

  @spec enum_type_for_field(struct(), atom()) :: atom() | nil
  def enum_type_for_field(%_enum_type_for_field{} = struct, key) when is_atom(key) do
    struct.__struct__
    |> field_types()
    |> Map.get(key)
    |> field_type_to_enum()
  end

  def enum_type_for_field(_enum_type_for_field, _enum_type_for_field2), do: nil

  defp field_types(module) when is_atom(module) do
    BeamTypesCache.resolve_struct_fields(module)
  end

  defp field_type_to_enum({:constant, type}) when is_atom(type), do: type

  defp field_type_to_enum({:type_list, types}) when is_list(types) do
    Enum.find_value(types, fn
      {:constant, type} when is_atom(type) -> type
      _type -> nil
    end)
  end

  defp field_type_to_enum(_type), do: nil
end
