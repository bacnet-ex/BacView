defmodule BacView.BACnet.Protocol.StructFieldTypes do
  @moduledoc false

  @beam_env %Macro.Env{
    module: __MODULE__,
    function: {:enum_type_for_field, 2},
    file: __ENV__.file,
    line: 1
  }

  @spec enum_type_for_field(struct(), atom()) :: atom() | nil
  def enum_type_for_field(%_enum_type_for_field{} = struct, key) when is_atom(key) do
    struct.__struct__
    |> field_types()
    |> Map.get(key)
    |> field_type_to_enum()
  end

  def enum_type_for_field(_enum_type_for_field, _enum_type_for_field2), do: nil

  defp field_types(module) when is_atom(module) do
    cache_key = {__MODULE__, module}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        types =
          try do
            BACnet.BeamTypes.resolve_struct_type(module, :t, @beam_env)
          rescue
            _module -> %{}
          end

        :persistent_term.put(cache_key, types)
        types

      types ->
        types
    end
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
