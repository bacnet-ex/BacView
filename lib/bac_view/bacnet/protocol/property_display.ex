defmodule BacView.BACnet.Protocol.PropertyDisplay do
  @moduledoc """
  Builds structured display trees for BACnet property values in the UI.
  """

  use Gettext, backend: BacViewWeb.Gettext

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.PriorityArray
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BacView.BACnet.Protocol.BacnetCalendarFormat
  alias BacView.BACnet.Protocol.PropertyFormatter

  @type field :: %{
          key: atom() | integer(),
          label: String.t(),
          kind: :boolean | :scalar | :struct | :priority_slot | :array_item,
          value: term(),
          formatted: String.t(),
          fields: [field()]
        }

  @type t :: %{
          kind: :scalar | :struct | :priority_array | :array | :object_identifier,
          formatted: String.t(),
          fields: [field()],
          items: [field() | map()]
        }

  @spec build(term()) :: t()
  def build(value), do: do_build(value)

  @spec summary(t()) :: String.t()
  def summary(%{kind: :scalar, formatted: formatted}), do: formatted

  def summary(%{kind: :object_identifier, formatted: formatted}), do: formatted

  def summary(%{kind: :priority_array, items: items}) do
    active =
      items
      |> Enum.filter(fn item -> not is_nil(item.value) end)
      |> length()

    gettext("%{count} Prioritäten gesetzt", count: active)
  end

  def summary(%{kind: :array, items: items}) do
    gettext("%{count} Einträge", count: length(items))
  end

  def summary(%{kind: :struct, fields: fields}) do
    struct_fields_summary(fields)
  end

  def summary(_summary), do: "—"

  defp struct_fields_summary(fields) do
    Enum.map_join(fields, ", ", fn field -> "#{field.label}: #{field.formatted}" end)
  end

  @doc """
  Short label for collapsed nested values (lists, structs, priority arrays).
  """
  @spec brief_summary(t() | field() | map()) :: String.t()
  def brief_summary(%{kind: :struct, fields: fields}) do
    gettext("%{count} Felder", count: length(fields))
  end

  def brief_summary(%{kind: :array, items: items}) do
    gettext("%{count} Einträge", count: length(items))
  end

  def brief_summary(%{kind: :priority_array, items: items}) do
    active =
      items
      |> Enum.filter(fn item -> not is_nil(item.value) end)
      |> length()

    gettext("%{count} Prioritäten gesetzt", count: active)
  end

  def brief_summary(%{kind: :scalar, formatted: formatted}), do: formatted
  def brief_summary(%{kind: :object_identifier, formatted: formatted}), do: formatted
  def brief_summary(%{formatted: formatted}) when is_binary(formatted), do: formatted
  def brief_summary(_formatted), do: "—"

  defp do_build(nil), do: %{kind: :scalar, formatted: "—", fields: [], items: []}

  defp do_build(%Encoding{type: type} = encoding) when not is_nil(type) do
    %{
      kind: :scalar,
      formatted: PropertyFormatter.format_value(encoding, nil),
      fields: [],
      items: []
    }
  end

  defp do_build(%ObjectIdentifier{type: type, instance: instance}) do
    %{
      kind: :object_identifier,
      formatted: "#{type}:#{instance}",
      fields: [],
      items: []
    }
  end

  defp do_build(%RecipientAddress{network: network, address: address}) do
    formatted_address = PropertyFormatter.format_mac_address(address)

    fields = [
      %{
        key: :network,
        label: field_label(:network),
        kind: :scalar,
        value: network,
        formatted: Integer.to_string(network),
        fields: []
      },
      %{
        key: :address,
        label: field_label(:address),
        kind: :scalar,
        value: address,
        formatted: formatted_address,
        fields: []
      }
    ]

    %{
      kind: :struct,
      formatted: "Network: #{network}, Address: #{formatted_address}",
      fields: fields,
      items: []
    }
  end

  defp do_build(%Recipient{type: :device, device: %ObjectIdentifier{} = device, address: nil}) do
    device_display = do_build(device)

    fields = [
      %{
        key: :type,
        label: field_label(:type),
        kind: :scalar,
        value: :device,
        formatted: "device",
        fields: []
      },
      %{
        key: :device,
        label: field_label(:device),
        kind: :object_identifier,
        value: device,
        formatted: device_display.formatted,
        fields: []
      }
    ]

    %{
      kind: :struct,
      formatted: "device: #{device_display.formatted}",
      fields: fields,
      items: []
    }
  end

  defp do_build(%Recipient{
         type: :address,
         address: %RecipientAddress{} = address,
         device: nil
       }) do
    address_display = do_build(address)

    fields = [
      %{
        key: :type,
        label: field_label(:type),
        kind: :scalar,
        value: :address,
        formatted: "address",
        fields: []
      },
      %{
        key: :address,
        label: field_label(:address),
        kind: :struct,
        value: address,
        formatted: address_display.formatted,
        fields: address_display.fields,
        items: []
      }
    ]

    %{
      kind: :struct,
      formatted: "address: #{address_display.formatted}",
      fields: fields,
      items: []
    }
  end

  defp do_build(%PriorityArray{} = array) do
    items =
      Enum.map(1..16, fn priority ->
        value = Map.get(array, priority_field(priority))

        %{
          key: priority,
          label: "P#{priority}",
          kind: :priority_slot,
          value: value,
          formatted: format_slot_value(value),
          fields: []
        }
      end)

    %{
      kind: :priority_array,
      formatted: PropertyFormatter.format_value(array, nil),
      fields: [],
      items: items
    }
  end

  defp do_build(%BACnetArray{} = array) do
    items =
      array
      |> BACnetArray.to_list()
      |> Enum.with_index(1)
      |> Enum.map(fn {value, index} ->
        nested = do_build(value)

        %{
          key: index,
          label: "[#{index}]",
          kind: :array_item,
          value: value,
          formatted: nested.formatted,
          fields: nested.fields,
          items: Map.get(nested, :items, [])
        }
      end)

    %{
      kind: :array,
      formatted: Enum.map_join(items, ", ", & &1.formatted),
      fields: [],
      items: items
    }
  end

  defp do_build(value) when is_list(value) do
    items =
      value
      |> Enum.with_index(1)
      |> Enum.map(fn {item, index} ->
        nested = do_build(item)

        %{
          key: index,
          label: "[#{index}]",
          kind: :array_item,
          value: item,
          formatted: nested.formatted,
          fields: nested.fields,
          items: Map.get(nested, :items, [])
        }
      end)

    %{
      kind: :array,
      formatted: Enum.map_join(items, ", ", & &1.formatted),
      fields: [],
      items: items
    }
  end

  defp do_build(%BACnetDateTime{} = datetime), do: calendar_scalar(datetime)
  defp do_build(%BACnetDate{} = date), do: calendar_scalar(date)
  defp do_build(%BACnetTime{} = time), do: calendar_scalar(time)
  defp do_build(%BACnetTimestamp{} = timestamp), do: calendar_scalar(timestamp)

  defp do_build(%_nil{} = struct) do
    fields =
      struct
      |> Map.from_struct()
      |> Enum.map(fn {key, value} -> field_entry(key, value) end)
      |> Enum.sort_by(& &1.label)

    %{
      kind: :struct,
      formatted: struct_fields_summary(fields),
      fields: fields,
      items: []
    }
  end

  defp do_build(value) do
    %{
      kind: :scalar,
      formatted: PropertyFormatter.format_value(value, nil),
      fields: [],
      items: []
    }
  end

  defp calendar_scalar(value) do
    %{
      kind: :scalar,
      formatted: BacnetCalendarFormat.format(value),
      fields: [],
      items: []
    }
  end

  defp field_entry(key, value) do
    cond do
      is_boolean(value) ->
        %{
          key: key,
          label: field_label(key),
          kind: :boolean,
          value: value,
          formatted: boolean_label(value),
          fields: []
        }

      is_struct(value) or is_list(value) or is_map(value) ->
        nested = do_build(value)

        %{
          key: key,
          label: field_label(key),
          kind: nested.kind,
          value: value,
          formatted: nested.formatted,
          fields: nested.fields,
          items: nested.items
        }

      true ->
        %{
          key: key,
          label: field_label(key),
          kind: :scalar,
          value: value,
          formatted: PropertyFormatter.format_value(value, nil),
          fields: []
        }
    end
  end

  defp field_label(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &capitalize_word/1)
  end

  defp field_label(key), do: to_string(key)

  defp capitalize_word(word) do
    case String.split(word, "-") do
      [single] ->
        String.capitalize(single)

      parts ->
        Enum.map_join(parts, "-", &String.capitalize/1)
    end
  end

  defp boolean_label(true), do: gettext("Ja")
  defp boolean_label(false), do: gettext("Nein")

  defp format_slot_value(nil), do: "—"
  defp format_slot_value(value), do: PropertyFormatter.format_value(value, nil)

  defp priority_field(priority) when priority in 1..16,
    do: String.to_existing_atom("priority_#{priority}")
end
