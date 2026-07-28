defmodule BacView.BACnet.Protocol.PropertyEnumeration do
  @moduledoc """
  Resolves BACnet constant enumerations and `{:in_list, ...}` property schemas
  for object property dropdowns.

  Known constant values remain atoms. Unknown / vendor / future values may be
  non-negative integers (bacstack `allow_numeric_constants`); those are labeled
  for display and injected as a synthetic dropdown option for the current value.
  """

  alias BACnet.Protocol.Constants

  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.EngineeringUnits
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyFormatter

  alias BacView.Text

  @type enum_option :: %{value: term(), label: String.t()}

  @spec constant_type?(term()) :: boolean()
  def constant_type?({:constant, type}) when is_atom(type), do: true
  def constant_type?(_type), do: false

  @spec in_list_type?(term()) :: boolean()
  def in_list_type?({:in_list, values}), do: atom_in_list?(values)
  def in_list_type?(_type), do: false

  @doc """
  True when `values` is a non-empty list of atoms (dropdown-eligible `{:in_list, ...}`).
  """
  @spec atom_in_list?(term()) :: boolean()
  def atom_in_list?(values) when is_list(values) and values != [],
    do: Enum.all?(values, &is_atom/1)

  def atom_in_list?(_values), do: false

  @spec enum_type(term()) :: atom() | nil
  def enum_type({:constant, type}) when is_atom(type), do: type
  def enum_type(_type), do: nil

  @spec options(atom()) :: [enum_option()]
  def options(enum_type) when is_atom(enum_type) do
    case Map.get(Constants.get_typespecs(), enum_type) do
      {names, values, _doc} when is_list(names) and is_list(values) ->
        names
        |> Enum.zip(values)
        |> Enum.sort_by(fn {name, _value} -> name end)
        |> Enum.map(fn {name, int_value} ->
          %{value: name, label: option_label(enum_type, name, int_value)}
        end)

      _enum_type ->
        []
    end
  end

  def options(_enum_type), do: []

  @doc """
  Builds dropdown options from a bacstack `{:in_list, values}` property type.

  Returns `[]` unless every element is an atom (mixed/non-atom lists are not dropdowns).
  """
  @spec in_list_options([term()]) :: [enum_option()]
  def in_list_options(values) when is_list(values) do
    if atom_in_list?(values) do
      Enum.map(values, fn atom ->
        %{value: atom, label: humanize_atom(atom)}
      end)
    else
      []
    end
  end

  def in_list_options(_values), do: []

  @doc """
  Ensures a synthetic dropdown option exists for an unknown non-neg integer value.

  Known options are unchanged; if `value` already matches an option, returns them as-is.
  """
  @spec with_current_value_option([enum_option()], term(), atom() | nil) :: [enum_option()]
  def with_current_value_option(options, value, enum_type \\ nil)
      when is_list(options) do
    cond do
      is_nil(value) ->
        options

      Enum.any?(options, &enum_option_matches?(value, &1.value)) ->
        options

      is_integer(value) and value >= 0 ->
        # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
        options ++ [%{value: value, label: unknown_constant_label(enum_type, value)}]

      true ->
        options
    end
  end

  @spec label(atom(), atom() | integer() | nil) :: String.t()
  def label(_enum_type, nil), do: "-"

  # Engineering units keep their dedicated labels; BACnet constants use the atom
  # name with underscores as spaces (no title-case / gettext capitalization).
  def label(:engineering_unit, value), do: EngineeringUnits.label(value)

  def label(_enum_type, value) when is_atom(value), do: humanize_atom(value)
  def label(_enum_type, value) when is_integer(value), do: Integer.to_string(value)
  def label(_enum_type, value), do: to_string(value)

  @doc """
  Formats a BACnet constant for display like known properties: `Name (N)`.

  Returns `nil` when `enum_type` is not a Constants typespec or the value cannot
  be labeled (caller should keep its fallback formatting).
  """
  @spec format_constant(atom(), term()) :: String.t() | nil
  def format_constant(enum_type, value) when is_atom(enum_type) do
    if constant_typespec?(enum_type) do
      cond do
        is_atom(value) and value not in [nil, :unspecified] ->
          display_label(enum_type, value)

        is_integer(value) and value >= 0 ->
          unknown_constant_label(enum_type, value)

        true ->
          nil
      end
    else
      nil
    end
  end

  def format_constant(_enum_type, _value), do: nil

  defp constant_typespec?(enum_type) when is_atom(enum_type) do
    Map.has_key?(Constants.get_typespecs(), enum_type)
  end

  @spec relocalize_property(map(), keyword()) :: map()
  def relocalize_property(prop, opts \\ []) do
    units = Keyword.get(opts, :units)
    object = Keyword.get(opts, :object)
    value = Map.get(prop, :value)
    bac_type = Map.get(prop, :bac_type)

    display_opts =
      if BinaryPV.binary_object?(object), do: [object: object], else: []

    display = PropertyDisplay.build(value, display_opts)

    formatted = multistate_state_property_formatted(prop, value, object, units, display)

    display = Map.put(display, :formatted, formatted)

    prop =
      prop
      |> Map.put(:value_display, display)
      |> Map.put(:value_formatted, formatted)
      |> maybe_enrich_multistate_state_property(object)
      |> enrich_from_bac_type(bac_type)

    Text.sanitize_property_row(prop)
  end

  @spec enrich_property(map(), term()) :: map()
  def enrich_property(prop, bac_type) do
    prop = enrich_from_bac_type(prop, bac_type)
    Text.sanitize_property_row(prop)
  end

  @doc """
  True when the property has non-empty enum options (dropdown is the default editor).

  Unknown integer constants keep the dropdown after synthetic option injection.
  Callers may still switch to free numeric input via UI toggle.
  """
  @spec dropdown?(map()) :: boolean()
  def dropdown?(%{enum_options: options}) when is_list(options) and options != [], do: true
  def dropdown?(_prop), do: false

  @doc false
  @spec enum_value_supported?(term(), [enum_option()]) :: boolean()
  def enum_value_supported?(value, options) when is_list(options) and options != [] do
    is_nil(value) or Enum.any?(options, &enum_option_matches?(value, &1.value))
  end

  def enum_value_supported?(_value, _options), do: false

  @doc """
  Parses a select/text value for a constant enum type.

  Accepts known atom names and non-negative integers (vendor / unknown constants).
  """
  @spec parse_value(String.t(), atom()) :: {:ok, atom() | non_neg_integer()} | {:error, term()}
  def parse_value(value, enum_type) when is_binary(value) and is_atom(enum_type) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :empty_value}
    else
      case existing_atom(trimmed) do
        {:ok, atom} ->
          if Constants.has_by_name(enum_type, atom) do
            {:ok, atom}
          else
            parse_non_neg_integer_for_type(trimmed, enum_type)
          end

        :error ->
          parse_non_neg_integer_for_type(trimmed, enum_type)
      end
    end
  end

  @doc """
  Parses a select/text value against a list of `enum_options` (constants, in_list, multistate).

  When no option matches, accepts a bare non-negative integer (free numeric input).
  """
  @spec parse_option_value(String.t(), [enum_option()]) :: {:ok, term()} | {:error, term()}
  def parse_option_value(value, options) when is_binary(value) and is_list(options) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :empty_value}
    else
      case find_matching_option(trimmed, options) do
        {:ok, matched} ->
          {:ok, matched}

        :error ->
          parse_non_neg_integer(trimmed)
      end
    end
  end

  def parse_option_value(_value, _options), do: {:error, :invalid_enum}

  @doc false
  @spec option_value_to_string(term()) :: String.t()
  def option_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  def option_value_to_string(value) when is_integer(value), do: Integer.to_string(value)
  def option_value_to_string(value), do: to_string(value)

  @doc """
  Formats a constant/enum value for free numeric input.

  Atoms are resolved to their BACnet integer via `enum_type` when known.
  """
  @spec free_input_value_string(term(), atom() | nil) :: String.t()
  def free_input_value_string(value, enum_type \\ nil)

  def free_input_value_string(value, enum_type)
      when is_atom(value) and not is_nil(value) and is_atom(enum_type) and not is_nil(enum_type) do
    case Constants.by_name(enum_type, value) do
      {:ok, int_value} when is_integer(int_value) -> Integer.to_string(int_value)
      _unknown -> Atom.to_string(value)
    end
  end

  def free_input_value_string(value, _enum_type) when is_integer(value),
    do: Integer.to_string(value)

  def free_input_value_string(value, _enum_type) when is_atom(value) and not is_nil(value),
    do: Atom.to_string(value)

  def free_input_value_string(_value, _enum_type), do: ""

  defp enrich_from_bac_type(prop, {:constant, enum_type}) when is_atom(enum_type) do
    options =
      enum_type
      |> options()
      |> with_current_value_option(Map.get(prop, :value), enum_type)

    prop
    |> Map.put(:enum_type, enum_type)
    |> Map.put(:enum_options, options)
    |> Map.put(:type, "ENUMERATED")
    |> refresh_display(enum_type)
  end

  defp enrich_from_bac_type(prop, {:in_list, values}) do
    options =
      values
      |> in_list_options()
      |> with_current_value_option(Map.get(prop, :value), nil)

    if options == [] do
      prop
    else
      prop
      |> Map.put(:enum_options, options)
      |> Map.put(:type, "ENUMERATED")
      |> refresh_in_list_display(options)
    end
  end

  defp enrich_from_bac_type(prop, _bac_type), do: prop

  defp refresh_display(%{value: value} = prop, enum_type) when is_atom(value) do
    formatted = display_label(enum_type, value)
    put_formatted(prop, formatted)
  end

  defp refresh_display(%{value: value} = prop, enum_type)
       when is_integer(value) and value >= 0 do
    formatted = unknown_constant_label(enum_type, value)
    put_formatted(prop, formatted)
  end

  defp refresh_display(prop, _enum_type), do: prop

  defp put_formatted(%{value_display: display} = prop, formatted) when is_map(display) do
    display = Map.put(display, :formatted, formatted)

    prop
    |> Map.put(:value_display, display)
    |> Map.put(:value_formatted, formatted)
  end

  defp put_formatted(prop, formatted) do
    Map.put(prop, :value_formatted, formatted)
  end

  defp refresh_in_list_display(%{value: value, value_display: display} = prop, options)
       when not is_nil(value) and is_map(display) do
    case Enum.find(options, &enum_option_matches?(value, &1.value)) do
      %{label: label} ->
        put_formatted(prop, label)

      nil ->
        prop
    end
  end

  defp refresh_in_list_display(prop, _options), do: prop

  defp find_matching_option(trimmed, options) do
    Enum.find_value(options, :error, fn
      %{value: option_value} ->
        if option_value_matches_input?(trimmed, option_value) do
          {:ok, option_value}
        else
          nil
        end

      _opt ->
        nil
    end)
  end

  defp option_value_matches_input?(trimmed, option_value) when is_atom(option_value) do
    Atom.to_string(option_value) == trimmed
  end

  defp option_value_matches_input?(trimmed, option_value) when is_integer(option_value) do
    case Integer.parse(trimmed) do
      {int, ""} -> int == option_value
      _parse -> false
    end
  end

  defp option_value_matches_input?(trimmed, option_value) when is_float(option_value) do
    case Float.parse(trimmed) do
      {float, ""} -> trunc(float) == trunc(option_value)
      _parse -> false
    end
  end

  defp option_value_matches_input?(trimmed, option_value) do
    to_string(option_value) == trimmed
  end

  defp existing_atom(string) when is_binary(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp parse_non_neg_integer(trimmed) do
    case Integer.parse(trimmed) do
      {int, ""} when int >= 0 -> {:ok, int}
      _parse -> {:error, :invalid_enum}
    end
  end

  # Prefer known atom when the numeric value maps to a constant name.
  defp parse_non_neg_integer_for_type(trimmed, enum_type) when is_atom(enum_type) do
    case parse_non_neg_integer(trimmed) do
      {:ok, int} ->
        case Constants.by_value(enum_type, int) do
          {:ok, name} -> {:ok, name}
          :error -> {:ok, int}
        end

      error ->
        error
    end
  end

  defp maybe_enrich_multistate_state_property(%{property: property} = prop, object)
       when property in [:present_value, :relinquish_default] and is_map(object) do
    if MultistateState.multistate_object?(object) do
      options =
        object
        |> MultistateState.state_options()
        |> with_current_value_option(Map.get(prop, :value), nil)

      prop
      |> Map.put(:enum_options, options)
      |> Map.put(:type, "INTEGER")
    else
      prop
    end
  end

  defp maybe_enrich_multistate_state_property(prop, _object), do: prop

  defp multistate_state_property_formatted(
         %{property: :present_value} = prop,
         value,
         object,
         _units,
         _display
       ) do
    PropertyFormatter.format_present_value(value, object, prop)
  end

  defp multistate_state_property_formatted(
         %{property: :relinquish_default},
         value,
         object,
         units,
         display
       ) do
    cond do
      MultistateState.multistate_object?(object) ->
        MultistateState.format_present_value(value, object) ||
          PropertyFormatter.format_value(value, units)

      BinaryPV.binary_object?(object) ->
        BinaryPV.format_value(value, object) || PropertyFormatter.format_value(value, units)

      true ->
        display.formatted
    end
  end

  defp multistate_state_property_formatted(
         %{property: :priority_array},
         value,
         object,
         _units,
         display
       ) do
    if BinaryPV.binary_object?(object) do
      PropertyDisplay.build(value, object: object).formatted
    else
      display.formatted
    end
  end

  defp multistate_state_property_formatted(_prop, _value, _object, _units, display),
    do: display.formatted

  defp display_label(enum_type, name) when is_atom(name) do
    case Constants.by_name(enum_type, name) do
      {:ok, int_value} -> option_label(enum_type, name, int_value)
      :error -> label(enum_type, name)
    end
  end

  defp option_label(enum_type, name, int_value) do
    "#{label(enum_type, name)} (#{format_constant_value(int_value)})"
  end

  defp unknown_constant_label(enum_type, int_value)
       when is_atom(enum_type) and not is_nil(enum_type) and is_integer(int_value) do
    case Constants.by_value(enum_type, int_value) do
      {:ok, name} -> option_label(enum_type, name, int_value)
      :error -> Integer.to_string(int_value)
    end
  end

  defp unknown_constant_label(_enum_type, int_value) when is_integer(int_value),
    do: Integer.to_string(int_value)

  defp format_constant_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_constant_value(value), do: to_string(value)

  defp humanize_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp enum_option_matches?(value, option_value)
       when is_integer(value) and is_integer(option_value),
       do: value == option_value

  defp enum_option_matches?(value, option_value)
       when is_float(value) and is_integer(option_value),
       do: trunc(value) == option_value

  defp enum_option_matches?(value, option_value)
       when is_integer(value) and is_float(option_value),
       do: value == trunc(option_value)

  defp enum_option_matches?(value, option_value) when is_float(value) and is_float(option_value),
    do: trunc(value) == trunc(option_value)

  defp enum_option_matches?(value, option_value), do: value == option_value
end
