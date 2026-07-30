defmodule BacView.BACnet.Protocol.ChoiceSchema do
  @moduledoc """
  Derives CHOICE / optional-union form schema from `BACnet.BeamTypes`.

  Used by `BacView.BACnet.Protocol.ComplexPropertyEditor` for kind pickers, active-arm
  fields, and kind-switch blanks. Field maps come from
  `BacView.BACnet.Protocol.BeamTypesCache`.

  ## Shapes

  * **Tagged** — discriminant field of `{:literal, atom}` members plus matching
    optional payload fields (`CalendarEntry`, `Recipient`, `BACnetTimestamp`).
    Form path is the real key (usually `type`).
  * **Inline** — optional (`payload | nil`) or multi-struct `type_list` on one field
    (`NameValue.value`, `SpecialEvent.period`). Form path is synthetic:
    `value` → `value_kind`, `period` → `period_kind`, else `:"\#{field}_kind"`.

  Inline detection requires optional-with-nil **or** all non-nil members to be
  `{:struct, _}` so type aliases like `ObjectIdentifier.type` are not treated as CHOICE.

  ## Overrides

  Arm *existence* always comes from BeamTypes. Module attributes only adjust polish:

  * `@synthetic_discriminant_keys` — stable LiveView/test paths
  * `@arm_id_overrides` — e.g. SpecialEvent `ObjectIdentifier` → `:calendar_reference`
  * `@label_overrides` — display strings (`"Calendar Reference"`, `"Date Time"`)
  * `special_blank/2` — domain blanks (Recipient device id, calendar reference)

  See `docs/choice_schema.md` for detection rules, apply/collect behaviour, and how
  to onboard a new bacstack CHOICE type.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.SpecialEvent

  alias BacView.BACnet.Protocol.BeamTypesCache
  alias BacView.BACnet.Protocol.CollectionItemTemplate

  @type arm :: %{
          id: atom(),
          label: String.t(),
          member: term(),
          field: atom() | nil,
          payload_type: term() | nil
        }

  @type choice :: %{
          kind: :tagged | :inline,
          discriminant_key: atom(),
          payload_key: atom() | nil,
          arms: [arm()],
          source_field: atom()
        }

  @type schema :: %{
          module: module(),
          fields: map(),
          choices: [choice()],
          plain_fields: [atom()]
        }

  # Stable synthetic form paths used by LiveView / tests.
  @synthetic_discriminant_keys %{
    value: :value_kind,
    period: :period_kind
  }

  # Product arm ids that differ from module_kind_id/1 (path stability).
  @arm_id_overrides %{
    {SpecialEvent, :period, ObjectIdentifier} => :calendar_reference
  }

  @label_overrides %{
    none: "None",
    calendar_reference: "Calendar Reference",
    # Match historical editor labels (datetime is one token in the atom).
    datetime: "Date Time"
  }

  @doc """
  Analyzes a protocol struct module and returns its CHOICE schema (cached).
  """
  @spec analyze(module()) :: schema()
  def analyze(module) when is_atom(module) do
    cache_key = {__MODULE__, :schema, module}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        schema = do_analyze(module)
        :persistent_term.put(cache_key, schema)
        schema

      schema ->
        schema
    end
  end

  @doc """
  Like `analyze/1` but returns `:error` when the module has no CHOICE groups.
  """
  @spec fetch(module()) :: {:ok, schema()} | :error
  def fetch(module) when is_atom(module) do
    schema = analyze(module)

    if schema.choices == [] do
      :error
    else
      {:ok, schema}
    end
  end

  @doc """
  Finds the choice whose discriminant key matches `key`.
  """
  @spec choice_for_discriminant(schema(), atom()) :: {:ok, choice()} | :error
  def choice_for_discriminant(%{choices: choices}, key) when is_atom(key) do
    case Enum.find(choices, &(&1.discriminant_key == key)) do
      nil -> :error
      choice -> {:ok, choice}
    end
  end

  @doc """
  True when `key` is a CHOICE discriminant on the given schema.
  """
  @spec discriminant_key?(schema(), atom()) :: boolean()
  def discriminant_key?(schema, key) when is_atom(key) do
    match?({:ok, _choice}, choice_for_discriminant(schema, key))
  end

  @doc """
  Active arm id for a struct instance and choice group.
  """
  @spec active_arm_id(struct(), choice()) :: atom()
  def active_arm_id(struct, %{kind: :tagged, discriminant_key: key, arms: arms})
      when is_struct(struct) do
    value = Map.get(struct, key)

    if Enum.any?(arms, &(&1.id == value)) do
      value
    else
      case arms do
        [arm | _rest] -> arm.id
        [] -> value
      end
    end
  end

  def active_arm_id(struct, %{kind: :inline, payload_key: key, arms: arms})
      when is_struct(struct) do
    value = Map.get(struct, key)
    match_value_to_arm(value, arms)
  end

  @doc """
  Enum options for a choice group (`%{value: arm_id, label: ...}`).
  """
  @spec options(choice()) :: [%{value: atom(), label: String.t()}]
  def options(%{arms: arms}) do
    Enum.map(arms, fn arm ->
      %{value: arm.id, label: arm.label}
    end)
  end

  @doc """
  Applies a kind switch: blanks the active arm and nils inactive tagged arms.
  """
  @spec apply_arm(struct(), choice(), atom()) :: struct()
  def apply_arm(%mod{} = struct, %{kind: :tagged} = choice, arm_id) when is_atom(mod) do
    arm = fetch_arm!(choice, arm_id)

    attrs =
      Map.new(choice.arms, fn a ->
        value =
          if a.id == arm_id do
            blank_arm_payload!(mod, a)
          else
            nil
          end

        {a.field, value}
      end)

    struct
    |> Map.put(choice.discriminant_key, arm.id)
    |> Map.merge(attrs)
  end

  def apply_arm(%mod{} = struct, %{kind: :inline} = choice, arm_id) when is_atom(mod) do
    arm = fetch_arm!(choice, arm_id)
    payload = blank_arm_payload!(mod, arm)
    Map.put(struct, choice.payload_key, payload)
  end

  @doc """
  Parses a form string into an arm id for the choice, or an error.
  """
  @spec parse_arm_id(String.t() | atom(), choice()) :: {:ok, atom()} | {:error, term()}
  def parse_arm_id(string_value, %{arms: arms}) do
    trimmed = string_value |> to_string() |> String.trim()
    allowed = Enum.map(arms, & &1.id)

    cond do
      trimmed == "" ->
        {:error, :empty_value}

      Enum.any?(allowed, &(Atom.to_string(&1) == trimmed)) ->
        {:ok, String.to_existing_atom(trimmed)}

      true ->
        {:error, :invalid_enum}
    end
  end

  @doc """
  Human label for a field key (discriminant or payload).
  """
  @spec field_label(atom()) :: String.t()
  def field_label(:value_kind), do: "Value Kind"
  def field_label(:period_kind), do: "Period Kind"
  def field_label(key) when is_atom(key), do: humanize_name(Atom.to_string(key))

  # --- analysis ----------------------------------------------------------------

  defp do_analyze(module) do
    fields = BeamTypesCache.resolve_struct_fields(module)

    if map_size(fields) == 0 do
      empty_schema(module, fields)
    else
      {tagged, tagged_owned} = find_tagged_choices(module, fields)
      {inline, inline_owned} = find_inline_choices(module, fields, tagged_owned)
      choices = tagged ++ inline
      owned = MapSet.union(tagged_owned, inline_owned)

      plain_fields =
        fields
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(owned, &1))

      %{
        module: module,
        fields: fields,
        choices: choices,
        plain_fields: plain_fields
      }
    end
  end

  defp empty_schema(module, fields) do
    %{module: module, fields: fields, choices: [], plain_fields: Map.keys(fields)}
  end

  defp find_tagged_choices(module, fields) do
    {choices_rev, owned} =
      Enum.reduce(fields, {[], MapSet.new()}, fn {key, type}, {choices, owned} ->
        case tagged_choice_from_field(module, fields, key, type, owned) do
          {:ok, choice, arm_fields} ->
            new_owned =
              arm_fields
              |> MapSet.new()
              |> MapSet.put(key)
              |> MapSet.union(owned)

            {[choice | choices], new_owned}

          :error ->
            {choices, owned}
        end
      end)

    {Enum.reverse(choices_rev), owned}
  end

  defp tagged_choice_from_field(_module, fields, key, {:type_list, members}, owned)
       when is_list(members) do
    if MapSet.member?(owned, key) do
      :error
    else
      literals = literal_atoms(members)

      if length(literals) < 2 do
        :error
      else
        arms =
          Enum.flat_map(literals, fn lit ->
            case Map.fetch(fields, lit) do
              {:ok, arm_type} ->
                payload_type = unwrap_optional_payload(arm_type)

                [
                  %{
                    id: lit,
                    label: arm_label(lit, {:literal, lit}),
                    member: {:literal, lit},
                    field: lit,
                    payload_type: payload_type
                  }
                ]

              :error ->
                []
            end
          end)

        if length(arms) >= 2 do
          arm_fields = Enum.map(arms, & &1.field)

          choice = %{
            kind: :tagged,
            discriminant_key: key,
            payload_key: nil,
            arms: arms,
            source_field: key
          }

          {:ok, choice, arm_fields}
        else
          :error
        end
      end
    end
  end

  defp tagged_choice_from_field(_module, _fields, _key, _type, _owned), do: :error

  defp find_inline_choices(module, fields, owned) do
    {choices_rev, inline_owned} =
      Enum.reduce(fields, {[], MapSet.new()}, fn {key, type}, {choices, inline_owned} ->
        if MapSet.member?(owned, key) or MapSet.member?(inline_owned, key) do
          {choices, inline_owned}
        else
          case inline_choice_from_field(module, key, type) do
            {:ok, choice} ->
              {[choice | choices], MapSet.put(inline_owned, key)}

            :error ->
              {choices, inline_owned}
          end
        end
      end)

    {Enum.reverse(choices_rev), inline_owned}
  end

  defp inline_choice_from_field(module, key, {:type_list, members}) when is_list(members) do
    arms = inline_arms(module, key, members)

    if valid_inline_arms?(arms) do
      {:ok,
       %{
         kind: :inline,
         discriminant_key: synthetic_discriminant_key(key),
         payload_key: key,
         arms: arms,
         source_field: key
       }}
    else
      :error
    end
  end

  defp inline_choice_from_field(_module, _key, _type), do: :error

  defp valid_inline_arms?(arms), do: length(arms) >= 2

  # Inline CHOICE only for optional unions (… | nil) or multi-struct unions.
  # Reject type aliases like ObjectIdentifier.type (`object_type | unsigned`).
  defp inline_arms(module, field, members) do
    non_nil = Enum.reject(members, &nil_member?/1)
    has_nil? = Enum.any?(members, &nil_member?/1)

    multi_or_optional? =
      length(non_nil) >= 2 or (length(non_nil) == 1 and has_nil?)

    # Prefer structs (SpecialEvent period, NameValue value). Optional non-struct
    # payloads are allowed when nil is present (rare but valid).
    choice_shaped? =
      has_nil? or Enum.all?(non_nil, &match?({:struct, _mod}, &1))

    if multi_or_optional? and choice_shaped? do
      payload_arms =
        Enum.map(non_nil, fn member ->
          id = member_arm_id(module, field, member)

          %{
            id: id,
            label: arm_label(id, member),
            member: member,
            field: nil,
            payload_type: member
          }
        end)

      if has_nil? do
        # Prefer None first (NameValue UX).
        [none_arm() | payload_arms]
      else
        payload_arms
      end
    else
      []
    end
  end

  defp none_arm() do
    %{
      id: :none,
      label: arm_label(:none, nil),
      member: {:literal, nil},
      field: nil,
      payload_type: nil
    }
  end

  defp synthetic_discriminant_key(field) do
    Map.get_lazy(@synthetic_discriminant_keys, field, fn ->
      atom_from_string("#{field}_kind")
    end)
  end

  defp literal_atoms(members) do
    non_nil = Enum.reject(members, &nil_member?/1)

    if non_nil != [] and
         Enum.all?(non_nil, fn
           {:literal, lit} when is_atom(lit) and not is_nil(lit) -> true
           _member -> false
         end) do
      Enum.map(non_nil, fn {:literal, lit} -> lit end)
    else
      []
    end
  end

  defp unwrap_optional_payload({:type_list, members}) when is_list(members) do
    non_nil = Enum.reject(members, &nil_member?/1)

    case non_nil do
      [type] -> type
      _types -> {:type_list, non_nil}
    end
  end

  defp unwrap_optional_payload(type), do: type

  defp nil_member?(nil), do: true
  defp nil_member?({:literal, nil}), do: true
  defp nil_member?(_member), do: false

  defp member_arm_id(module, field, {:struct, mod}) do
    Map.get_lazy(@arm_id_overrides, {module, field, mod}, fn ->
      module_kind_id(mod)
    end)
  end

  defp member_arm_id(_module, _field, {:literal, lit}) when is_atom(lit), do: lit
  defp member_arm_id(_module, _field, type) when is_atom(type), do: type

  defp member_arm_id(_module, _field, member) do
    name =
      member
      |> inspect()
      |> String.replace(~r/[^a-zA-Z0-9_]+/, "_")
      |> String.trim("_")
      |> String.downcase()

    atom_from_string(name)
  end

  defp module_kind_id(mod) when is_atom(mod) do
    name =
      mod
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    atom_from_string(name)
  end

  # Kind ids are derived from already-loaded bacstack modules / field names.
  # Prefer existing atoms; create only on first analysis of a new shape.
  defp atom_from_string(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError ->
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      String.to_atom(name)
  end

  defp arm_label(id, _member) when is_map_key(@label_overrides, id) do
    Map.fetch!(@label_overrides, id)
  end

  defp arm_label(_id, {:struct, mod}) when is_atom(mod) do
    name =
      mod
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    humanize_name(name)
  end

  defp arm_label(_id, {:literal, lit}) when is_atom(lit), do: humanize_name(Atom.to_string(lit))
  defp arm_label(id, _member) when is_atom(id), do: humanize_name(Atom.to_string(id))

  defp humanize_name(name) when is_binary(name) do
    name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # --- runtime -----------------------------------------------------------------

  defp match_value_to_arm(nil, arms) do
    case Enum.find(arms, &(&1.id == :none)) do
      %{id: id} -> id
      nil -> default_arm_id(arms)
    end
  end

  defp match_value_to_arm(%mod{} = _value, arms) when is_atom(mod) do
    case Enum.find(arms, fn
           %{member: {:struct, ^mod}} -> true
           %{payload_type: {:struct, ^mod}} -> true
           _arm -> false
         end) do
      %{id: id} -> id
      nil -> default_arm_id(arms)
    end
  end

  defp match_value_to_arm(_value, arms), do: default_arm_id(arms)

  defp default_arm_id([arm | _rest]), do: arm.id
  defp default_arm_id([]), do: :none

  defp fetch_arm!(%{arms: arms}, arm_id) do
    case Enum.find(arms, &(&1.id == arm_id)) do
      nil -> raise ArgumentError, "unknown CHOICE arm #{inspect(arm_id)}"
      arm -> arm
    end
  end

  defp blank_arm_payload!(_module, %{id: :none}), do: nil
  defp blank_arm_payload!(_module, %{payload_type: nil}), do: nil

  defp blank_arm_payload!(module, arm) do
    case special_blank(module, arm) do
      {:ok, value} ->
        value

      :error ->
        case blank_from_member(arm.payload_type || arm.member) do
          {:ok, value} -> value
          {:error, reason} -> raise ArgumentError, "cannot blank CHOICE arm: #{inspect(reason)}"
        end
    end
  end

  # Recipient device defaults to object type :device (not analog_input).
  defp special_blank(Recipient, %{id: :device, payload_type: {:struct, ObjectIdentifier}}) do
    {:ok, %ObjectIdentifier{type: :device, instance: 0}}
  end

  # Calendar reference should open a Calendar object id.
  defp special_blank(SpecialEvent, %{id: :calendar_reference}) do
    {:ok, %ObjectIdentifier{type: :calendar, instance: 0}}
  end

  defp special_blank(_module, _arm), do: :error

  defp blank_from_member(nil), do: {:ok, nil}
  defp blank_from_member({:literal, nil}), do: {:ok, nil}

  defp blank_from_member(member) do
    CollectionItemTemplate.blank_from_bac_type(member)
  end
end
