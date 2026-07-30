defmodule BacView.BACnet.Protocol.BeamTypesCache do
  @moduledoc """
  Shared cache for `BACnet.BeamTypes.resolve_struct_type/3` field maps.

  Consumers:

  * `BacView.BACnet.Protocol.ChoiceSchema` — CHOICE analysis
  * `BacView.BACnet.Protocol.CollectionItemTemplate` — blank struct fields
  * `BacView.BACnet.Protocol.StructFieldTypes` — enum type for form fields

  Results are stored in `:persistent_term` per module. Resolution failures yield `%{}`.
  """

  @beam_env %Macro.Env{
    module: __MODULE__,
    function: {:resolve_struct_fields, 1},
    file: __ENV__.file,
    line: 1
  }

  @doc """
  Resolves a protocol struct's `:t` typespec via BeamTypes, cached in `:persistent_term`.

  Returns an empty map when resolution fails.
  """
  @spec resolve_struct_fields(module()) :: map()
  def resolve_struct_fields(module) when is_atom(module) do
    cache_key = {__MODULE__, module}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        types =
          try do
            BACnet.BeamTypes.resolve_struct_type(module, :t, @beam_env)
          rescue
            _reason -> %{}
          end

        :persistent_term.put(cache_key, types)
        types

      types ->
        types
    end
  end
end
