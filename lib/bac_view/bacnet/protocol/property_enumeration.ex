defmodule BacView.BACnet.Protocol.PropertyEnumeration do
  @moduledoc """
  Resolves BACnet constant enumerations for object properties.
  """

  alias BACnet.Protocol.Constants

  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.EventFormatter
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter

  alias BacView.Text

  @spec constant_type?(term()) :: boolean()
  def constant_type?({:constant, type}) when is_atom(type), do: true
  def constant_type?(_type), do: false

  @spec enum_type(term()) :: atom() | nil
  def enum_type({:constant, type}) when is_atom(type), do: type
  def enum_type(_type), do: nil

  @spec options(atom()) :: [%{value: atom(), label: String.t()}]
  def options(enum_type) when is_atom(enum_type) do
    case Map.get(Constants.get_typespecs(), enum_type) do
      {names, values, _doc} when is_list(names) and is_list(values) ->
        names
        |> Enum.zip(values)
        |> Enum.sort_by(fn {name, _value} -> name end)
        |> Enum.map(fn {name, int_value} ->
          %{value: name, label: option_label(enum_type, name, int_value)}
        end)

      {names, _values, _doc} when is_list(names) ->
        names
        |> Enum.sort()
        |> Enum.map(fn name ->
          %{
            value: name,
            label: option_label(enum_type, name, Constants.by_name!(enum_type, name))
          }
        end)

      _enum_type ->
        []
    end
  end

  def options(_enum_type), do: []

  @spec label(atom(), atom() | nil) :: String.t()
  def label(_enum_type, nil), do: "—"

  def label(:event_state, value), do: EventFormatter.event_state_label(value)
  def label(:notify_type, value), do: EventFormatter.notify_type_label(value)
  def label(:engineering_unit, value), do: EngineeringUnits.label(value)

  def label(_enum_type, value) when is_atom(value), do: humanize_atom(value)
  def label(_enum_type, value), do: to_string(value)

  @spec relocalize_property(map(), keyword()) :: map()
  def relocalize_property(prop, opts \\ []) do
    units = Keyword.get(opts, :units)
    value = Map.get(prop, :value)
    bac_type = Map.get(prop, :bac_type)
    display = PropertyDisplay.build(value)

    formatted =
      if Map.get(prop, :property) == :present_value do
        PropertyFormatter.format_value(value, units)
      else
        display.formatted
      end

    prop =
      prop
      |> Map.put(:value_display, display)
      |> Map.put(:value_formatted, formatted)

    prop =
      case enum_type(bac_type) do
        nil ->
          prop

        enum_type ->
          prop
          |> Map.put(:enum_type, enum_type)
          |> Map.put(:enum_options, options(enum_type))
          |> refresh_display(enum_type)
      end

    Text.sanitize_property_row(prop)
  end

  @spec enrich_property(map(), term()) :: map()
  def enrich_property(prop, bac_type) do
    prop =
      case enum_type(bac_type) do
        nil ->
          prop

        enum_type ->
          options = options(enum_type)

          prop
          |> Map.put(:enum_type, enum_type)
          |> Map.put(:enum_options, options)
          |> Map.put(:type, "ENUMERATED")
          |> refresh_display(enum_type)
      end

    Text.sanitize_property_row(prop)
  end

  @spec dropdown?(%{optional(:enum_options) => term()}) :: boolean()
  def dropdown?(%{enum_options: options}) when is_list(options) and options != [], do: true
  def dropdown?(_options), do: false

  @spec parse_value(String.t(), atom()) :: {:ok, atom()} | {:error, term()}
  def parse_value(value, enum_type) when is_binary(value) and is_atom(enum_type) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :empty_value}
    else
      atom =
        try do
          String.to_existing_atom(trimmed)
        rescue
          ArgumentError -> nil
        end

      cond do
        is_nil(atom) ->
          {:error, :invalid_enum}

        Constants.has_by_name(enum_type, atom) ->
          {:ok, atom}

        true ->
          {:error, :invalid_enum}
      end
    end
  end

  defp refresh_display(%{value: value} = prop, enum_type) when is_atom(value) do
    formatted = label(enum_type, value)
    display = Map.put(prop.value_display, :formatted, formatted)

    prop
    |> Map.put(:value_display, display)
    |> Map.put(:value_formatted, formatted)
  end

  defp refresh_display(prop, _enum_type), do: prop

  defp option_label(enum_type, name, int_value) do
    "#{label(enum_type, name)} (#{format_constant_value(int_value)})"
  end

  defp format_constant_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_constant_value(value), do: to_string(value)

  defp humanize_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
