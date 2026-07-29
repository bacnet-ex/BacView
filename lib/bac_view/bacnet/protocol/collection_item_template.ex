defmodule BacView.BACnet.Protocol.CollectionItemTemplate do
  @moduledoc false

  # Builds blank collection item templates from bacstack property type maps
  # (`get_properties_type_map/0`) and BeamTypes typechecker shapes.

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.CalendarEntry
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.DateRange
  alias BACnet.Protocol.DaysOfWeek
  alias BACnet.Protocol.Destination
  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.EventTransitionBits
  alias BACnet.Protocol.NameValue
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectPropertyRef
  alias BACnet.Protocol.ObjectsUtility
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.WeekNDay

  alias BacView.BACnet.Protocol.PropertyEnumeration

  @beam_env %Macro.Env{
    module: __MODULE__,
    function: {:struct_field_types, 1},
    file: __ENV__.file,
    line: 1
  }

  @item_type_cache_key {__MODULE__, :item_type_by_property}

  @doc """
  Resolves the element type of a list/array property and builds a blank item.
  """
  @spec default_item(keyword()) :: {:ok, term()} | {:error, term()}
  def default_item(opts) when is_list(opts) do
    property = Keyword.get(opts, :property)
    object_type = Keyword.get(opts, :object_type)

    case collection_item_type(property, object_type) do
      {:ok, bac_type} -> blank_from_bac_type(bac_type)
      {:error, _reason} = err -> err
    end
  end

  @doc """
  Resolves the element type of a list/array property from bacstack schemas.

  When `object_type` is given, the object module type map is preferred. Otherwise
  (or on miss) a cross-object cache of collection element types is used.
  """
  @spec collection_item_type(term(), term()) :: {:ok, term()} | {:error, term()}
  def collection_item_type(property, object_type \\ nil)

  def collection_item_type(property, object_type)
      when is_atom(property) and property != nil do
    case property_collection_element_type(property, object_type) do
      {:ok, _element_type} = ok -> ok
      :error -> {:error, :unknown_collection_item_type}
    end
  end

  def collection_item_type(_property, _object_type), do: {:error, :unknown_collection_item_type}

  @doc """
  Builds a blank value for a BeamTypes typechecker shape.
  """
  @spec blank_from_bac_type(term()) :: {:ok, term()} | {:error, term()}
  def blank_from_bac_type(type)

  def blank_from_bac_type(nil), do: {:ok, nil}
  def blank_from_bac_type(:any), do: {:error, :unknown_collection_item_type}
  def blank_from_bac_type(:boolean), do: {:ok, false}
  def blank_from_bac_type(:string), do: {:ok, ""}
  def blank_from_bac_type(:octet_string), do: {:ok, ""}
  def blank_from_bac_type(:signed_integer), do: {:ok, 0}
  def blank_from_bac_type(:unsigned_integer), do: {:ok, 0}
  def blank_from_bac_type(:real), do: {:ok, 0.0}
  def blank_from_bac_type(:double), do: {:ok, 0.0}
  def blank_from_bac_type(:bitstring), do: {:error, :unknown_collection_item_type}

  def blank_from_bac_type({:literal, value}), do: {:ok, value}

  def blank_from_bac_type({:constant, enum_type}) when is_atom(enum_type) do
    case default_constant(enum_type) do
      {:ok, _value} = ok -> ok
      :error -> {:error, :unknown_collection_item_type}
    end
  end

  def blank_from_bac_type({:in_list, values}) when is_list(values) and values != [] do
    {:ok, hd(values)}
  end

  def blank_from_bac_type({:in_range, low, _high}) when is_integer(low), do: {:ok, low}

  def blank_from_bac_type({:list, _subtype}), do: {:ok, []}

  def blank_from_bac_type({:array, _subtype}), do: {:ok, BACnetArray.new()}

  def blank_from_bac_type({:array, _subtype, fixed_size})
      when is_integer(fixed_size) and fixed_size >= 1 do
    {:ok, BACnetArray.new(fixed_size)}
  end

  def blank_from_bac_type({:struct, module}) when is_atom(module) do
    blank_struct(module)
  end

  def blank_from_bac_type({:type_list, types}) when is_list(types) do
    blank_from_type_list(types)
  end

  def blank_from_bac_type({:with_validator, type, _validator}) do
    blank_from_bac_type(type)
  end

  def blank_from_bac_type({:tuple, element_types}) when is_list(element_types) do
    element_types
    |> Enum.reduce_while({:ok, []}, fn element_type, {:ok, acc} ->
      case blank_from_bac_type(element_type) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _reason} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, List.to_tuple(Enum.reverse(values))}
      {:error, _reason} = err -> err
    end
  end

  def blank_from_bac_type(_type), do: {:error, :unknown_collection_item_type}

  @doc """
  Blank override for known protocol structs (including CHOICE defaults).
  """
  @spec blank_struct(module()) :: {:ok, struct()} | {:error, term()}
  def blank_struct(module) when is_atom(module) do
    case known_blank_struct(module) do
      {:ok, _struct} = ok ->
        ok

      :error ->
        blank_struct_from_typespec(module)
    end
  end

  # Returns the *element* type of a collection property (already unwrapped).
  defp property_collection_element_type(property, object_type) when is_atom(object_type) do
    case ObjectsUtility.get_object_type_mappings()[object_type] do
      mod when is_atom(mod) ->
        type_map = type_map_from_module(mod)

        case Map.fetch(type_map, property) do
          {:ok, bac_type} ->
            case unwrap_collection_element(bac_type) do
              {:ok, element_type} -> {:ok, element_type}
              {:error, _reason} -> element_type_from_cache(property)
            end

          :error ->
            element_type_from_cache(property)
        end

      _unknown ->
        element_type_from_cache(property)
    end
  end

  defp property_collection_element_type(property, _object_type),
    do: element_type_from_cache(property)

  defp element_type_from_cache(property) when is_atom(property) do
    case Map.fetch(item_type_cache(), property) do
      {:ok, element_type} -> {:ok, element_type}
      :error -> :error
    end
  end

  defp item_type_cache() do
    case :persistent_term.get(@item_type_cache_key, :missing) do
      :missing ->
        cache = build_item_type_cache()
        :persistent_term.put(@item_type_cache_key, cache)
        cache

      cache ->
        cache
    end
  end

  defp build_item_type_cache() do
    mappings = ObjectsUtility.get_object_type_mappings()

    Enum.reduce(mappings, %{}, fn {_object_type, mod}, acc ->
      type_map = type_map_from_module(mod)

      Enum.reduce(type_map, acc, fn {property, bac_type}, acc ->
        case unwrap_collection_element(bac_type) do
          {:ok, element_type} ->
            Map.update(acc, property, element_type, fn existing ->
              prefer_item_type(existing, element_type)
            end)

          {:error, _reason} ->
            acc
        end
      end)
    end)
  end

  # Prefer struct element types over primitives when the same property name
  # appears with different shapes on different object types.
  defp prefer_item_type(existing, new) do
    cond do
      match?({:struct, _mod}, existing) -> existing
      match?({:struct, _mod}, new) -> new
      true -> existing
    end
  end

  defp type_map_from_module(mod) when is_atom(mod) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, :get_properties_type_map, 0) do
      mod.get_properties_type_map()
    else
      %{}
    end
  end

  defp unwrap_collection_element({:list, element_type}), do: {:ok, element_type}
  defp unwrap_collection_element({:array, element_type}), do: {:ok, element_type}

  defp unwrap_collection_element({:array, element_type, _fixed_size}),
    do: {:ok, element_type}

  defp unwrap_collection_element({:with_validator, type, _validator}),
    do: unwrap_collection_element(type)

  defp unwrap_collection_element(_type), do: {:error, :not_collection_property}

  defp blank_from_type_list(types) when is_list(types) do
    # Prefer optional absence when the union includes nil.
    if nil in types or Enum.any?(types, &match?({:literal, nil}, &1)) do
      {:ok, nil}
    else
      types
      |> Enum.find_value(fn type ->
        case blank_from_bac_type(type) do
          {:ok, value} -> {:ok, value}
          {:error, _reason} -> nil
        end
      end)
      |> case do
        {:ok, _value} = ok -> ok
        nil -> {:error, :unknown_collection_item_type}
      end
    end
  end

  defp default_constant(:property_identifier), do: {:ok, :present_value}
  defp default_constant(:object_type), do: {:ok, :analog_input}
  defp default_constant(:engineering_unit), do: {:ok, :no_units}
  defp default_constant(:event_state), do: {:ok, :normal}
  defp default_constant(:reliability), do: {:ok, :no_fault_detected}
  defp default_constant(:notify_type), do: {:ok, :alarm}
  defp default_constant(:binary_pv), do: {:ok, :inactive}
  defp default_constant(:polarity), do: {:ok, :normal}

  defp default_constant(enum_type) when is_atom(enum_type) do
    case PropertyEnumeration.options(enum_type) do
      [%{value: value} | _rest] -> {:ok, value}
      [] -> first_constant_name(enum_type)
    end
  end

  defp first_constant_name(enum_type) do
    case Map.get(Constants.get_typespecs(), enum_type) do
      {[name | _rest], _values, _doc} -> {:ok, name}
      _enum_type -> :error
    end
  end

  defp known_blank_struct(NameValue) do
    {:ok, %NameValue{name: "", value: nil}}
  end

  defp known_blank_struct(ObjectIdentifier) do
    {:ok, %ObjectIdentifier{type: :analog_input, instance: 0}}
  end

  defp known_blank_struct(ObjectPropertyRef) do
    {:ok,
     %ObjectPropertyRef{
       object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
       property_identifier: :present_value,
       property_array_index: nil
     }}
  end

  defp known_blank_struct(DeviceObjectPropertyRef) do
    {:ok,
     %DeviceObjectPropertyRef{
       object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
       property_identifier: :present_value,
       property_array_index: nil,
       device_identifier: nil
     }}
  end

  defp known_blank_struct(Recipient) do
    {:ok, blank_recipient(:address)}
  end

  defp known_blank_struct(RecipientAddress) do
    {:ok, %RecipientAddress{network: 0, address: :broadcast}}
  end

  defp known_blank_struct(Destination) do
    {:ok, blank_destination()}
  end

  defp known_blank_struct(CalendarEntry) do
    {:ok, blank_calendar_entry(:date)}
  end

  defp known_blank_struct(DateRange) do
    date = blank_bacnet_date()
    {:ok, %DateRange{start_date: date, end_date: date}}
  end

  defp known_blank_struct(WeekNDay) do
    {:ok, %WeekNDay{month: :unspecified, week_of_month: 1, weekday: 1}}
  end

  defp known_blank_struct(DailySchedule) do
    {:ok, %DailySchedule{schedule: []}}
  end

  defp known_blank_struct(BACnetDate) do
    {:ok, blank_bacnet_date()}
  end

  defp known_blank_struct(BACnetTime) do
    {:ok, blank_bacnet_time()}
  end

  defp known_blank_struct(BACnetDateTime) do
    {:ok, %BACnetDateTime{date: blank_bacnet_date(), time: blank_bacnet_time()}}
  end

  defp known_blank_struct(BACnetTimestamp) do
    {:ok,
     %BACnetTimestamp{
       type: :time,
       time: blank_bacnet_time(),
       sequence_number: nil,
       datetime: nil
     }}
  end

  defp known_blank_struct(Encoding) do
    {:ok, blank_encoding()}
  end

  defp known_blank_struct(DaysOfWeek) do
    {:ok,
     %DaysOfWeek{
       monday: true,
       tuesday: true,
       wednesday: true,
       thursday: true,
       friday: true,
       saturday: true,
       sunday: true
     }}
  end

  defp known_blank_struct(EventTransitionBits) do
    {:ok,
     %EventTransitionBits{
       to_offnormal: true,
       to_fault: true,
       to_normal: true
     }}
  end

  defp known_blank_struct(_module), do: :error

  defp blank_struct_from_typespec(module) when is_atom(module) do
    Code.ensure_loaded(module)

    field_types = struct_field_types(module)

    if map_size(field_types) == 0 do
      {:error, :unknown_collection_item_type}
    else
      field_types
      |> Enum.reduce_while({:ok, %{}}, fn {key, field_type}, {:ok, acc} ->
        case blank_from_bac_type(field_type) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
          {:error, _reason} = err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, attrs} ->
          try do
            {:ok, struct!(module, attrs)}
          rescue
            _attrs -> {:error, :unknown_collection_item_type}
          end

        {:error, _reason} = err ->
          err
      end
    end
  end

  defp struct_field_types(module) when is_atom(module) do
    cache_key = {__MODULE__, :struct_fields, module}

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

  @doc false
  @spec blank_recipient(:device | :address) :: Recipient.t()
  def blank_recipient(:device) do
    %Recipient{
      type: :device,
      address: nil,
      device: %ObjectIdentifier{type: :device, instance: 0}
    }
  end

  def blank_recipient(:address) do
    %Recipient{
      type: :address,
      device: nil,
      address: %RecipientAddress{network: 0, address: :broadcast}
    }
  end

  @doc false
  @spec blank_calendar_entry(:date | :date_range | :week_n_day) :: CalendarEntry.t()
  def blank_calendar_entry(:date) do
    %CalendarEntry{
      type: :date,
      date: blank_bacnet_date(),
      date_range: nil,
      week_n_day: nil
    }
  end

  def blank_calendar_entry(:date_range) do
    date = blank_bacnet_date()

    %CalendarEntry{
      type: :date_range,
      date: nil,
      date_range: %DateRange{start_date: date, end_date: date},
      week_n_day: nil
    }
  end

  def blank_calendar_entry(:week_n_day) do
    %CalendarEntry{
      type: :week_n_day,
      date: nil,
      date_range: nil,
      week_n_day: %WeekNDay{month: :unspecified, week_of_month: 1, weekday: 1}
    }
  end

  @doc false
  @spec blank_encoding() :: Encoding.t()
  def blank_encoding() do
    %Encoding{
      encoding: :primitive,
      extras: [],
      type: :character_string,
      value: ""
    }
  end

  @doc false
  @spec blank_destination() :: Destination.t()
  def blank_destination() do
    %Destination{
      recipient: blank_recipient(:address),
      process_identifier: 0,
      issue_confirmed_notifications: false,
      transitions: %EventTransitionBits{
        to_offnormal: true,
        to_fault: true,
        to_normal: true
      },
      valid_days: %DaysOfWeek{
        monday: true,
        tuesday: true,
        wednesday: true,
        thursday: true,
        friday: true,
        saturday: true,
        sunday: true
      },
      from_time: blank_bacnet_time(),
      to_time: %BACnetTime{hour: 23, minute: 59, second: 59, hundredth: 99}
    }
  end

  defp blank_bacnet_date() do
    %BACnetDate{
      year: :unspecified,
      month: :unspecified,
      day: :unspecified,
      weekday: :unspecified
    }
  end

  defp blank_bacnet_time() do
    %BACnetTime{hour: 0, minute: 0, second: 0, hundredth: 0}
  end
end
