defmodule BacView.BACnet.Protocol.ComplexPropertyEditor do
  @moduledoc """
  Builds and applies complex BACnet property form fields for the write modal.

  Scalar walks, collections, JSON encode/decode, and Encoding-specific fields live
  here. **CHOICE / optional-union kind pickers** are derived via
  `BacView.BACnet.Protocol.ChoiceSchema` (BeamTypes), not hard-coded option tables.

  See `docs/choice_schema.md`.
  """

  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.BACnetDate
  alias BACnet.Protocol.BACnetDateTime
  alias BACnet.Protocol.BACnetTime
  alias BACnet.Protocol.BACnetTimestamp
  alias BACnet.Protocol.CalendarEntry
  alias BACnet.Protocol.DailySchedule
  alias BACnet.Protocol.Destination
  alias BACnet.Protocol.DeviceObjectPropertyRef
  alias BACnet.Protocol.NameValue
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectPropertyRef
  alias BACnet.Protocol.PriorityArray
  alias BACnet.Protocol.Recipient
  alias BACnet.Protocol.RecipientAddress
  alias BACnet.Protocol.SpecialEvent

  alias BACnet.Protocol.ApplicationTags.Encoding

  alias BacView.BACnet.Protocol.ChoiceSchema
  alias BacView.BACnet.Protocol.CollectionItemTemplate
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.StructFieldTypes
  alias BacView.Text

  @type form_field :: %{
          path: String.t(),
          label: String.t(),
          value: String.t(),
          readonly: boolean(),
          enum_options: [%{value: atom(), label: String.t()}] | nil
        }

  @type form_field_group ::
          {:flat, [form_field()]}
          | {:items, [%{index: non_neg_integer(), fields: [form_field()]}]}

  @spec editor_type(term()) :: atom()
  def editor_type(%DailySchedule{}), do: :daily_schedule
  def editor_type(%SpecialEvent{}), do: :special_event
  def editor_type(%BACnetDateTime{}), do: :date_time
  def editor_type(%BACnetDate{}), do: :date
  def editor_type(%BACnetTime{}), do: :time
  def editor_type(%BACnetTimestamp{}), do: :timestamp
  def editor_type(%ObjectPropertyRef{}), do: :object_property_ref
  def editor_type(%DeviceObjectPropertyRef{}), do: :device_object_property_ref
  def editor_type(%ObjectIdentifier{}), do: :object_identifier
  def editor_type(%BACnetArray{}), do: :bacnet_array
  def editor_type(%Encoding{}), do: :encoding
  def editor_type(%_editor_type_arg1{}), do: :generic
  def editor_type(_editor_type_arg1), do: :generic

  @spec form_fields(term()) :: [form_field()]
  @spec form_fields(term(), keyword()) :: [form_field()]
  def form_fields(value, opts \\ [])

  def form_fields(value, opts) when is_list(opts) do
    ctx = editor_ctx(opts)

    case Map.get(ctx, :value_union) do
      nil ->
        value
        |> collect_form_fields([], [], nil, nil, ctx)
        |> Enum.reverse()

      choice ->
        value
        |> collect_union_value_fields(choice, [], [])
        |> Enum.reverse()
    end
  end

  @spec initial_field_params([form_field()]) :: %{String.t() => String.t()}
  def initial_field_params(fields) do
    Map.new(fields, fn %{path: path, value: value} -> {path, value} end)
  end

  @doc """
  Groups form fields for collection UIs.

  Variable lists/arrays with indexed paths become `{:items, [...]}` so the modal
  can show per-entry remove actions. Everything else stays `{:flat, fields}`.
  """
  @spec form_field_groups([form_field()]) :: form_field_group()
  def form_field_groups(fields) when is_list(fields) do
    indexed? =
      fields != [] and
        Enum.all?(fields, fn %{path: path} ->
          match?({:ok, _index}, collection_index_from_path(path))
        end)

    if indexed? do
      groups =
        fields
        |> Enum.group_by(fn %{path: path} ->
          {:ok, index} = collection_index_from_path(path)
          index
        end)
        |> Enum.sort_by(fn {index, _fields} -> index end)
        |> Enum.map(fn {index, group_fields} ->
          # Keep collect_form_fields order so CHOICE discriminants (type / value_kind /
          # period_kind) stay above the fields they control. Alphabetical path sort
          # wrongly put e.g. "0.value.*" before "0.value_kind".
          %{index: index, fields: group_fields}
        end)

      {:items, groups}
    else
      {:flat, fields}
    end
  end

  @doc """
  True when the value is a variable-size list or BACnetArray that can gain/lose entries.
  """
  @spec editable_collection?(term()) :: boolean()
  def editable_collection?(%BACnetArray{fixed_size: nil}), do: true
  def editable_collection?(list) when is_list(list), do: true
  def editable_collection?(_value), do: false

  @doc """
  True when a new entry can be appended (known item template or property hint).
  """
  @spec can_add_item?(term(), keyword()) :: boolean()
  def can_add_item?(value, opts \\ [])

  def can_add_item?(value, opts) do
    editable_collection?(value) and match?({:ok, _item}, default_collection_item(value, opts))
  end

  @spec can_remove_item?(term()) :: boolean()
  def can_remove_item?(value), do: editable_collection?(value) and collection_size(value) > 0

  @spec collection_size(term()) :: non_neg_integer()
  def collection_size(%BACnetArray{} = array), do: BACnetArray.size(array)
  def collection_size(list) when is_list(list), do: length(list)
  def collection_size(_value), do: 0

  @doc """
  Appends a blank entry using an existing element, array default, or property hint.
  """
  @spec add_item(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def add_item(value, opts \\ [])

  def add_item(%BACnetArray{fixed_size: nil} = array, opts) do
    with {:ok, item} <- default_collection_item(array, opts) do
      BACnetArray.set_item(array, nil, item)
    end
  end

  def add_item(list, opts) when is_list(list) do
    with {:ok, item} <- default_collection_item(list, opts) do
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      {:ok, list ++ [item]}
    end
  end

  def add_item(_value, _opts), do: {:error, :not_editable_collection}

  @doc """
  Removes the entry at the given 0-based index.

  Rebuilds variable BACnetArrays from a dense list so middle removals do not leave
  sparse holes (bacstack `remove_item/2` only shrinks trailing defaults).
  """
  @spec remove_item(term(), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def remove_item(%BACnetArray{fixed_size: nil} = array, index)
      when is_integer(index) and index >= 0 do
    items = bacnet_array_elements(array)

    if index < length(items) do
      new_items = List.delete_at(items, index)
      # Keep default :undefined so remaining items are never sparse-dropped on write.
      {:ok, BACnetArray.from_list(new_items, false, :undefined)}
    else
      {:error, :invalid_path}
    end
  end

  def remove_item(list, index) when is_list(list) and is_integer(index) and index >= 0 do
    if index < length(list) do
      {:ok, List.delete_at(list, index)}
    else
      {:error, :invalid_path}
    end
  end

  def remove_item(_value, _index), do: {:error, :not_editable_collection}

  @doc """
  Builds a blank collection item for add-entry UX.
  """
  @spec default_collection_item(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def default_collection_item(value, opts \\ [])

  def default_collection_item(%BACnetArray{} = array, opts) do
    case bacnet_array_elements(array) do
      [item | _rest] ->
        {:ok, blank_collection_item(item)}

      [] ->
        case BACnetArray.get_default(array) do
          default when is_struct(default) ->
            {:ok, blank_collection_item(default)}

          default when default not in [nil, :undefined] and not is_atom(default) ->
            {:ok, blank_collection_item(default)}

          _default ->
            default_item_from_property(opts)
        end
    end
  end

  def default_collection_item(list, opts) when is_list(list) do
    case list do
      [item | _rest] -> {:ok, blank_collection_item(item)}
      [] -> default_item_from_property(opts)
    end
  end

  def default_collection_item(_value, _opts), do: {:error, :not_editable_collection}

  # Root scalar form fields (empty path) use this key so the HTML name is
  # `field[_]` instead of invalid `field[]` (which Phoenix parses as a list).
  @root_field_path "_"

  @doc """
  Strips LiveView `_unused_*` form keys that appear when only a subset of inputs change.

  Also accepts a list (Phoenix form of `field[]`) and treats it as no updates so a
  mis-shaped submit cannot crash the LiveView.
  """
  @spec normalize_field_params(map() | list()) :: map()
  def normalize_field_params(fields) when is_map(fields) do
    fields
    |> Enum.reject(fn {key, _value} -> unused_field_key?(key) end)
    |> Map.new()
  end

  def normalize_field_params(fields) when is_list(fields), do: %{}

  @spec apply_form_fields(map(), term()) :: {:ok, term()} | {:error, term()}
  @spec apply_form_fields(map(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def apply_form_fields(params, template, opts \\ [])

  def apply_form_fields(params, template, opts) when is_list(opts) do
    ctx = editor_ctx(opts)

    case normalize_field_params(Map.get(params, "field", %{})) do
      fields when map_size(fields) == 0 ->
        {:ok, template}

      fields ->
        paths = sorted_field_paths(fields, template, ctx)
        choice_paths = choice_discriminant_paths(paths, template, ctx)

        # Kind/type switches must ignore all other field validation. The previous
        # branch's fields are still in the form payload and will always fail or
        # fight the rebuild (empty drafts, wrong shape, stale legs).
        apply_paths =
          if choice_discriminant_changed?(choice_paths, fields, template, ctx) do
            choice_paths
          else
            paths
          end

        finalize_apply_result(apply_field_paths(apply_paths, template, fields, ctx))
    end
  end

  defp apply_field_paths(paths, template, fields, ctx) do
    Enum.reduce_while(paths, {:ok, template}, fn path, {:ok, current} ->
      with {:ok, segments} <- parse_path(path),
           {:ok, ensured} <- ensure_path_collection_slots(current, segments),
           {:ok, updated} <-
             update_in_structure(ensured, segments, Map.get(fields, path), ctx) do
        {:cont, {:ok, updated}}
      else
        {:error, _reason} = err -> {:halt, err}
      end
    end)
  end

  defp choice_discriminant_paths(paths, template, ctx) do
    Enum.filter(paths, fn path ->
      case parse_path(path) do
        {:ok, segments} -> choice_discriminant_path?(template, segments, ctx)
        {:error, _reason} -> false
      end
    end)
  end

  defp choice_discriminant_changed?(choice_paths, fields, template, ctx) do
    Enum.any?(choice_paths, fn path ->
      with {:ok, segments} <- parse_path(path),
           {:ok, current} <- current_choice_value(template, segments, ctx) do
        submitted =
          fields
          |> Map.get(path, "")
          |> to_string()
          |> String.trim()

        value_to_string(current) != submitted
      else
        _no_change -> false
      end
    end)
  end

  # Value-level multi-struct union (event_parameters, …) — path is just "kind".
  defp current_choice_value(data, [key], %{value_union: %{discriminant_key: key} = choice}) do
    {:ok, ChoiceSchema.active_arm_id(data, choice)}
  end

  # Synthetic discriminants (value_kind / period_kind) resolve via ChoiceSchema arms.
  defp current_choice_value(%mod{} = data, [key], _ctx) when is_atom(mod) do
    with {:ok, schema} <- ChoiceSchema.fetch(mod),
         {:ok, choice} <- ChoiceSchema.choice_for_discriminant(schema, key) do
      {:ok, ChoiceSchema.active_arm_id(data, choice)}
    else
      :error -> {:error, :invalid_path}
    end
  end

  defp current_choice_value(data, [key | rest], ctx) when is_integer(key) do
    case get_child(data, key) do
      {:ok, child} ->
        item_ctx = collection_item_ctx(ctx)
        current_choice_value(child, rest, item_ctx)

      {:error, _reason} = err ->
        err
    end
  end

  defp current_choice_value(data, [key | rest], ctx) do
    case get_child(data, key) do
      {:ok, child} -> current_choice_value(child, rest, ctx)
      {:error, _reason} = err -> err
    end
  end

  defp current_choice_value(_data, _segments, _ctx), do: {:error, :invalid_path}

  # --- editor context (property / collection multi-struct unions) -------------

  defp editor_ctx(opts) when is_list(opts) do
    property = Keyword.get(opts, :property)
    object_type = Keyword.get(opts, :object_type)

    case CollectionItemTemplate.property_bac_type(property, object_type) do
      {:ok, bac_type} ->
        case ChoiceSchema.union_choice(bac_type) do
          {:ok, choice} ->
            %{value_union: choice}

          :error ->
            case unwrap_collection_element_type(bac_type) do
              {:ok, element_type} ->
                case ChoiceSchema.union_choice(element_type) do
                  {:ok, choice} -> %{element_union: choice}
                  :error -> %{}
                end

              :error ->
                %{}
            end
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp unwrap_collection_element_type({:list, element_type}), do: {:ok, element_type}
  defp unwrap_collection_element_type({:array, element_type}), do: {:ok, element_type}

  defp unwrap_collection_element_type({:array, element_type, _fixed_size}),
    do: {:ok, element_type}

  defp unwrap_collection_element_type({:with_validator, type, _validator}),
    do: unwrap_collection_element_type(type)

  defp unwrap_collection_element_type(_type), do: :error

  defp collection_item_ctx(%{element_union: choice}), do: %{value_union: choice}
  defp collection_item_ctx(_ctx), do: %{}

  @spec encode_json(term()) :: {:ok, String.t()} | {:error, term()}
  def encode_json(value) do
    Jason.encode(encode(value), pretty: true)
  end

  @spec decode_json(String.t(), term()) :: {:ok, term()} | {:error, term()}
  def decode_json(json, template) when is_binary(json) do
    trimmed = String.trim(json)

    if trimmed == "" do
      {:error, :empty_value}
    else
      with {:ok, decoded} <- Jason.decode(trimmed) do
        decode(decoded, template)
      end
    end
  end

  defp collect_form_fields(value, path_rev, acc, parent, field_key, ctx)

  defp collect_form_fields(%Encoding{} = encoding, path_rev, acc, _parent, _field_key, _ctx) do
    acc =
      [
        build_encoding_kind_field(encoding.encoding, [:encoding | path_rev])
        | acc
      ]

    acc =
      [
        build_encoding_type_field(encoding.type, [:type | path_rev])
        | acc
      ]

    extras_path = [:tag_number, :extras | path_rev]

    acc =
      [
        build_form_field(
          Keyword.get(encoding.extras, :tag_number),
          extras_path,
          encoding,
          :tag_number,
          field_label_at([:extras | path_rev], "Tag Number")
        )
        | acc
      ]

    collect_form_fields(encoding.value, [:value | path_rev], acc, encoding, :value, %{})
  end

  defp collect_form_fields(%BACnetArray{} = array, path_rev, acc, _parent, field_key, ctx) do
    array
    |> bacnet_array_elements()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc ->
      collect_collection_item(item, [index | path_rev], acc, array, field_key, ctx)
    end)
  end

  defp collect_form_fields(
         %ObjectIdentifier{type: type, instance: instance},
         path_rev,
         acc,
         _value,
         _path,
         _ctx
       ) do
    [
      build_form_field(
        type,
        [:type | path_rev],
        %ObjectIdentifier{type: type, instance: instance},
        :type,
        field_label_at(path_rev, "Type")
      ),
      build_form_field(
        instance,
        [:instance | path_rev],
        %ObjectIdentifier{type: type, instance: instance},
        :instance,
        field_label_at(path_rev, "Instance")
      )
      | acc
    ]
  end

  defp collect_form_fields(%mod{} = struct, path_rev, acc, _parent, _field_key, _ctx)
       when is_atom(mod) do
    case ChoiceSchema.analyze(mod) do
      %{choices: choices} = schema when choices != [] ->
        collect_choice_struct(struct, schema, path_rev, acc)

      _no_choice ->
        Enum.reduce(Map.from_struct(struct), acc, fn {key, value}, acc ->
          collect_form_fields(value, [key | path_rev], acc, struct, key, %{})
        end)
    end
  end

  defp collect_form_fields(list, path_rev, acc, parent, field_key, ctx) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc ->
      collect_collection_item(item, [index | path_rev], acc, parent, field_key, ctx)
    end)
  end

  defp collect_form_fields({tag, value}, path_rev, acc, parent, field_key, _ctx)
       when is_atom(tag) do
    [
      build_form_field(
        value,
        path_rev,
        parent,
        field_key,
        field_label_at(path_rev, "Value (#{tag})")
      )
      | acc
    ]
  end

  defp collect_form_fields(value, path_rev, acc, parent, field_key, _ctx) do
    [build_form_field(value, path_rev, parent, field_key, nil) | acc]
  end

  defp collect_collection_item(item, path_rev, acc, parent, field_key, ctx) do
    case Map.get(ctx, :element_union) do
      nil ->
        collect_form_fields(item, path_rev, acc, parent, field_key, %{})

      choice ->
        collect_union_value_fields(item, choice, path_rev, acc)
    end
  end

  # Property- / item-level multi-struct union: kind picker + active arm fields.
  defp collect_union_value_fields(value, choice, path_rev, acc) do
    active = ChoiceSchema.active_arm_id(value, choice)
    disc_key = choice.discriminant_key

    acc = [
      build_choice_field(
        active,
        [disc_key | path_rev],
        ChoiceSchema.options(choice),
        field_label_at(path_rev, ChoiceSchema.field_label(disc_key))
      )
      | acc
    ]

    collect_form_fields(value, path_rev, acc, nil, nil, %{})
  end

  defp build_form_field(value, path_rev, parent, field_key, label_override) do
    enum_type =
      if parent && field_key do
        StructFieldTypes.enum_type_for_field(parent, field_key)
      end

    %{
      path: path_string(path_rev),
      label: label_override || field_label_at(path_rev, nil),
      value: value_to_string(value),
      readonly: false,
      enum_options: enum_options_for(value, enum_type, parent, field_key)
    }
  end

  defp build_encoding_kind_field(encoding, path_rev) do
    %{
      path: path_string(path_rev),
      label: field_label_at(path_rev, nil),
      value: value_to_string(encoding),
      readonly: false,
      enum_options: encoding_kind_options()
    }
  end

  defp build_encoding_type_field(type, path_rev) do
    %{
      path: path_string(path_rev),
      label: field_label_at(path_rev, nil),
      value: value_to_string(type),
      readonly: false,
      enum_options: encoding_type_options()
    }
  end

  defp encoding_kind_options() do
    Enum.map([:primitive, :tagged, :constructed], fn kind ->
      %{value: kind, label: PropertyFormatter.encoding_type_label(kind)}
    end)
  end

  defp encoding_type_options() do
    Enum.map(PropertyFormatter.encoding_primitive_types(), fn type ->
      %{value: type, label: PropertyFormatter.encoding_type_label(type)}
    end)
  end

  defp build_choice_field(value, path_rev, options, label) do
    %{
      path: path_string(path_rev),
      label: label,
      value: value_to_string(value),
      readonly: false,
      enum_options: options
    }
  end

  # Walk BeamTypes field order; inject synthetic discriminants before inline payloads.
  defp collect_choice_struct(struct, schema, path_rev, acc) do
    tagged_arm_fields = tagged_arm_field_set(schema.choices)

    Enum.reduce(Map.keys(schema.fields), acc, fn key, acc ->
      cond do
        tagged_discriminant_key?(schema.choices, key) ->
          collect_tagged_choice_fields(struct, schema, key, path_rev, acc)

        MapSet.member?(tagged_arm_fields, key) ->
          # Active arm already emitted with its discriminant.
          acc

        inline_source_field?(schema.choices, key) ->
          collect_inline_choice_fields(struct, schema, key, path_rev, acc)

        true ->
          collect_form_fields(Map.get(struct, key), [key | path_rev], acc, struct, key, %{})
      end
    end)
  end

  defp tagged_arm_field_set(choices) do
    choices
    |> Enum.filter(&(&1.kind == :tagged))
    |> Enum.flat_map(fn choice -> Enum.map(choice.arms, & &1.field) end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp tagged_discriminant_key?(choices, key) do
    Enum.any?(choices, &(&1.kind == :tagged and &1.discriminant_key == key))
  end

  defp inline_source_field?(choices, key) do
    Enum.any?(choices, &(&1.kind == :inline and &1.source_field == key))
  end

  defp collect_tagged_choice_fields(struct, schema, disc_key, path_rev, acc) do
    {:ok, choice} = ChoiceSchema.choice_for_discriminant(schema, disc_key)
    active = ChoiceSchema.active_arm_id(struct, choice)

    acc = [
      build_choice_field(
        active,
        [disc_key | path_rev],
        ChoiceSchema.options(choice),
        field_label_at(path_rev, "Type")
      )
      | acc
    ]

    case Enum.find(choice.arms, &(&1.id == active)) do
      %{field: field} when is_atom(field) ->
        case Map.get(struct, field) do
          nil -> acc
          value -> collect_form_fields(value, [field | path_rev], acc, struct, field, %{})
        end

      _no_arm ->
        acc
    end
  end

  defp collect_inline_choice_fields(struct, schema, source_key, path_rev, acc) do
    choice = Enum.find(schema.choices, &(&1.kind == :inline and &1.source_field == source_key))
    active = ChoiceSchema.active_arm_id(struct, choice)
    disc_key = choice.discriminant_key

    acc = [
      build_choice_field(
        active,
        [disc_key | path_rev],
        ChoiceSchema.options(choice),
        field_label_at(path_rev, ChoiceSchema.field_label(disc_key))
      )
      | acc
    ]

    case Map.get(struct, source_key) do
      nil -> acc
      value -> collect_form_fields(value, [source_key | path_rev], acc, struct, source_key, %{})
    end
  end

  defp enum_options_for(_value, enum_type, _parent, _field_key) when is_atom(enum_type) do
    case PropertyEnumeration.options(enum_type) do
      [] -> nil
      options -> options
    end
  end

  defp update_in_structure(data, segments, string_value, ctx)

  defp update_in_structure(%Encoding{} = data, [:encoding], string_value, _ctx) do
    with {:ok, encoding} <- decode_encoding_kind(string_value) do
      extras = strip_tag_number_for_primitive(encoding, data.extras)
      {:ok, %{data | encoding: encoding, extras: extras}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:type], string_value, _ctx) do
    with {:ok, type} <- decode_encoding_type_field(string_value, data.type) do
      {:ok, %{data | type: type}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:extras, :tag_number], string_value, _ctx) do
    with {:ok, extras} <- apply_tag_number_change(data.extras, string_value) do
      {:ok, %{data | extras: extras}}
    end
  end

  defp update_in_structure(%Encoding{} = data, [:value], string_value, _ctx) do
    with {:ok, parsed} <- parse_encoding_value(data.type, data.value, string_value) do
      {:ok, %{data | value: parsed}}
    end
  end

  defp update_in_structure({tag, current}, [], string_value, _ctx) when is_atom(tag) do
    case parse_field_value(current, string_value) do
      {:ok, parsed} -> {:ok, {tag, parsed}}
      other -> other
    end
  end

  defp update_in_structure(data, [], string_value, _ctx) do
    parse_field_value(data, string_value)
  end

  # Value-level multi-struct union kind switch (replaces whole value).
  defp update_in_structure(data, [key], string_value, %{
         value_union: %{discriminant_key: key} = choice
       }) do
    with {:ok, arm_id} <- ChoiceSchema.parse_arm_id(string_value, choice) do
      if ChoiceSchema.active_arm_id(data, choice) == arm_id do
        {:ok, data}
      else
        {:ok, ChoiceSchema.apply_arm(data, choice, arm_id)}
      end
    end
  end

  # CHOICE discriminants (tagged type / synthetic value_kind / period_kind).
  # Unchanged kind preserves sibling field edits applied earlier in the same submit.
  defp update_in_structure(%mod{} = data, [key], string_value, _ctx) when is_atom(mod) do
    case try_apply_choice_discriminant(data, key, string_value) do
      {:ok, _updated} = ok ->
        ok

      :not_choice ->
        update_struct_leaf(data, key, string_value)

      {:error, _reason} = err ->
        err
    end
  end

  defp update_in_structure(data, [key], string_value, _ctx) do
    update_struct_leaf(data, key, string_value)
  end

  defp update_in_structure(data, [key | rest], string_value, ctx) when is_integer(key) do
    case get_child(data, key) do
      {:ok, child} ->
        item_ctx = collection_item_ctx(ctx)

        with {:ok, updated_child} <- update_in_structure(child, rest, string_value, item_ctx) do
          map_child(data, key, updated_child)
        end

      {:error, _data} = err ->
        err
    end
  end

  defp update_in_structure(data, [key | rest], string_value, ctx) do
    case get_child(data, key) do
      {:ok, child} ->
        with {:ok, updated_child} <- update_in_structure(child, rest, string_value, ctx) do
          map_child(data, key, updated_child)
        end

      {:error, _data} = err ->
        err
    end
  end

  defp try_apply_choice_discriminant(%mod{} = data, key, string_value) when is_atom(mod) do
    with {:ok, schema} <- ChoiceSchema.fetch(mod),
         {:ok, choice} <- ChoiceSchema.choice_for_discriminant(schema, key),
         {:ok, arm_id} <- ChoiceSchema.parse_arm_id(string_value, choice) do
      if ChoiceSchema.active_arm_id(data, choice) == arm_id do
        {:ok, data}
      else
        {:ok, ChoiceSchema.apply_arm(data, choice, arm_id)}
      end
    else
      :error -> :not_choice
      {:error, _reason} = err -> err
    end
  end

  defp update_struct_leaf(data, key, string_value) do
    enum_type =
      if is_struct(data) and is_atom(key) do
        StructFieldTypes.enum_type_for_field(data, key)
      end

    with {:ok, child} <- get_child(data, key),
         {:ok, parsed} <- parse_field_value(child, string_value, enum_type) do
      map_child(data, key, parsed)
    end
  end

  defp get_child(data, key) when is_list(data) and is_integer(key) do
    case Enum.at(data, key) do
      nil -> {:error, :invalid_path}
      child -> {:ok, child}
    end
  end

  defp get_child(%BACnetArray{} = array, key) when is_integer(key) and key >= 0 do
    case BACnetArray.get_item(array, key + 1) do
      {:ok, child} -> {:ok, child}
      :error -> {:error, :invalid_path}
    end
  end

  defp get_child(extras, key) when is_list(extras) and is_atom(key) do
    {:ok, Keyword.get(extras, key)}
  end

  defp get_child(%_data{} = struct, key), do: {:ok, Map.get(struct, key)}
  defp get_child(_data, _key), do: {:error, :invalid_path}

  defp map_child(list, key, value) when is_list(list) and is_integer(key) do
    {:ok, List.replace_at(list, key, value)}
  end

  defp map_child(%BACnetArray{} = array, key, value) when is_integer(key) and key >= 0 do
    case BACnetArray.set_item(array, key + 1, value) do
      {:ok, updated} -> {:ok, updated}
      {:error, _list} = err -> err
    end
  end

  defp map_child(extras, key, value) when is_list(extras) and is_atom(key) do
    {:ok, Keyword.put(extras, key, value)}
  end

  defp map_child(%_list{} = struct, key, value), do: {:ok, struct(struct, [{key, value}])}
  defp map_child(_list, _key, _value), do: {:error, :invalid_path}

  # Sort numeric collection indices in path order so slots are filled 0..n before nested fields.
  # CHOICE discriminants (Recipient/CalendarEntry/Timestamp type, value_kind, period_kind,
  # property-level `kind`) run last so branch rebuild wins over stale previous-branch fields.
  # Encoding/ObjectIdentifier `:type` is not a CHOICE discriminant and stays normal order.
  defp sorted_field_paths(fields, template, ctx) when is_map(fields) do
    Enum.sort_by(Map.keys(fields), &path_sort_key(&1, template, ctx))
  end

  defp path_sort_key(path, template, ctx) when is_binary(path) do
    segments = String.split(path, ".")

    segment_keys =
      Enum.map(segments, fn segment ->
        case Integer.parse(segment) do
          {index, ""} -> {0, index}
          _segment -> {1, segment}
        end
      end)

    discriminant_rank =
      case parse_path(path) do
        {:ok, path_segments} ->
          if choice_discriminant_path?(template, path_segments, ctx), do: 1, else: 0

        {:error, _reason} ->
          0
      end

    {discriminant_rank, segment_keys}
  end

  defp choice_discriminant_path?(_data, [key], %{value_union: %{discriminant_key: key}}) do
    true
  end

  defp choice_discriminant_path?(%mod{}, [key], _ctx) when is_atom(mod) do
    case ChoiceSchema.fetch(mod) do
      {:ok, schema} -> ChoiceSchema.discriminant_key?(schema, key)
      :error -> false
    end
  end

  defp choice_discriminant_path?(data, [key | rest], ctx) when is_integer(key) do
    case get_child(data, key) do
      {:ok, child} -> choice_discriminant_path?(child, rest, collection_item_ctx(ctx))
      {:error, _reason} -> false
    end
  end

  defp choice_discriminant_path?(data, [key | rest], ctx) do
    case get_child(data, key) do
      {:ok, child} -> choice_discriminant_path?(child, rest, ctx)
      {:error, _reason} -> false
    end
  end

  defp choice_discriminant_path?(_data, _segments, _ctx), do: false

  defp collection_index_from_path(path) when is_binary(path) do
    case String.split(path, ".", parts: 2) do
      [index | _rest] ->
        case Integer.parse(index) do
          {n, ""} when n >= 0 -> {:ok, n}
          _index -> :error
        end

      _path ->
        :error
    end
  end

  # Grow variable collections when form paths reference a new last index (size).
  defp ensure_path_collection_slots(data, []), do: {:ok, data}

  defp ensure_path_collection_slots(data, [key | rest]) when is_integer(key) do
    with {:ok, data} <- ensure_collection_index(data, key),
         {:ok, child} <- get_child(data, key),
         {:ok, updated_child} <- ensure_path_collection_slots(child, rest) do
      map_child(data, key, updated_child)
    end
  end

  defp ensure_path_collection_slots(data, [key | rest]) do
    case get_child(data, key) do
      {:ok, child} ->
        with {:ok, updated_child} <- ensure_path_collection_slots(child, rest) do
          map_child(data, key, updated_child)
        end

      {:error, _data} = err ->
        err
    end
  end

  defp ensure_collection_index(%BACnetArray{fixed_size: nil} = array, key)
       when is_integer(key) and key >= 0 do
    size = BACnetArray.size(array)

    cond do
      key < size ->
        {:ok, array}

      key == size ->
        with {:ok, item} <- default_collection_item(array, []) do
          BACnetArray.set_item(array, nil, item)
        end

      true ->
        {:error, :invalid_path}
    end
  end

  defp ensure_collection_index(list, key) when is_list(list) and is_integer(key) and key >= 0 do
    size = length(list)

    cond do
      key < size ->
        {:ok, list}

      key == size ->
        with {:ok, item} <- default_collection_item(list, []) do
          # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
          {:ok, list ++ [item]}
        end

      true ->
        {:error, :invalid_path}
    end
  end

  defp ensure_collection_index(data, _key), do: {:ok, data}

  defp blank_collection_item(%DeviceObjectPropertyRef{} = item) do
    case CollectionItemTemplate.blank_struct(DeviceObjectPropertyRef) do
      {:ok, blank} -> blank
      {:error, _reason} -> item
    end
  end

  defp blank_collection_item(%ObjectPropertyRef{} = item) do
    case CollectionItemTemplate.blank_struct(ObjectPropertyRef) do
      {:ok, blank} -> blank
      {:error, _reason} -> item
    end
  end

  defp blank_collection_item(%ObjectIdentifier{} = _item) do
    %ObjectIdentifier{type: :analog_input, instance: 0}
  end

  defp blank_collection_item(%Destination{} = _item),
    do: CollectionItemTemplate.blank_destination()

  defp blank_collection_item(%Recipient{} = item) do
    type = if item.type in [:device, :address], do: item.type, else: :address
    CollectionItemTemplate.blank_recipient(type)
  end

  defp blank_collection_item(%CalendarEntry{} = item) do
    type =
      if item.type in [:date, :date_range, :week_n_day], do: item.type, else: :date

    CollectionItemTemplate.blank_calendar_entry(type)
  end

  defp blank_collection_item(%NameValue{} = _item) do
    %NameValue{name: "", value: nil}
  end

  defp blank_collection_item(%DailySchedule{} = _item), do: %DailySchedule{schedule: []}

  defp blank_collection_item(%Encoding{} = encoding) do
    %{encoding | value: blank_encoding_value(encoding.type, encoding.value)}
  end

  defp blank_collection_item(%_mod{} = struct) do
    case CollectionItemTemplate.blank_struct(struct.__struct__) do
      {:ok, blank} ->
        blank

      {:error, _reason} ->
        struct
        |> Map.from_struct()
        |> Enum.map(fn {key, value} -> {key, blank_collection_item(value)} end)
        |> then(&struct(struct.__struct__, &1))
    end
  end

  defp blank_collection_item(list) when is_list(list), do: []
  defp blank_collection_item(value) when is_binary(value), do: ""
  defp blank_collection_item(value) when is_integer(value), do: 0
  defp blank_collection_item(value) when is_float(value), do: 0.0
  defp blank_collection_item(value) when is_boolean(value), do: false
  defp blank_collection_item(nil), do: nil
  defp blank_collection_item(value) when is_atom(value), do: value
  defp blank_collection_item(value), do: value

  defp blank_encoding_value(:boolean, _value), do: false
  defp blank_encoding_value(type, _value) when type in [:real, :double], do: 0.0

  defp blank_encoding_value(type, _value)
       when type in [:unsigned_integer, :signed_integer, :enumerated],
       do: 0

  defp blank_encoding_value(:null, _value), do: nil
  defp blank_encoding_value(:character_string, _value), do: ""
  defp blank_encoding_value(_type, value), do: blank_collection_item(value)

  defp default_item_from_property(opts) when is_list(opts) do
    CollectionItemTemplate.default_item(opts)
  end

  defp parse_field_value(current, string_value, enum_type \\ nil)

  defp parse_field_value(current, string_value, enum_type)
       when is_atom(enum_type) and enum_type != nil do
    case PropertyEnumeration.parse_value(string_value, enum_type) do
      {:ok, atom} ->
        {:ok, atom}

      {:error, :empty_value} ->
        if is_nil(current), do: {:ok, nil}, else: {:error, :empty_value}

      {:error, _current} ->
        {:error, :invalid_enum}
    end
  end

  defp parse_field_value({:ip_address, current_ip}, string_value, nil)
       when is_tuple(current_ip) do
    with {:ok, ip} <- parse_ip_address_string(string_value) do
      {:ok, {:ip_address, ip}}
    end
  end

  defp parse_field_value(current, string_value, nil)
       when is_tuple(current) and tuple_size(current) > 0 do
    if PropertyFormatter.bitstring_value?(current) do
      PropertyFormatter.parse_bitstring(string_value, tuple_size(current))
    else
      if tuple_size(current) in [4, 8] do
        parse_ip_address_string(string_value)
      else
        parse_field_value_fallback(current, string_value)
      end
    end
  end

  # BACnet MAC / octet-string addresses (e.g. RecipientAddress.address)
  defp parse_field_value(current, string_value, nil) when is_binary(current) do
    if mac_octet_string?(current) do
      parse_mac_address_string(string_value)
    else
      # Allow empty character strings while drafting (e.g. blank NameValue name).
      # Wire validation still happens on write via bacstack encode/valid?.
      {:ok, String.trim(string_value)}
    end
  end

  defp parse_field_value(:broadcast, string_value, nil) do
    parse_mac_address_string(string_value)
  end

  defp parse_field_value(current, string_value, nil),
    do: parse_field_value_fallback(current, string_value)

  defp parse_field_value_fallback(current, string_value) do
    trimmed = String.trim(string_value)

    cond do
      trimmed == "" and is_nil(current) ->
        {:ok, nil}

      trimmed == "" ->
        {:error, :empty_value}

      # BACnetDate/Time components are integer | pattern atoms. When the current
      # value is `:unspecified` (or another pattern atom), numeric input like "0"
      # must become integer 0 — not an atom path (hour 0 is midnight, not unspecified).
      date_time_component_value?(current) ->
        parse_date_time_component(trimmed)

      is_boolean(current) ->
        parse_boolean(trimmed)

      is_integer(current) ->
        parse_integer(trimmed)

      is_float(current) ->
        parse_float(trimmed)

      is_atom(current) and not is_nil(current) ->
        decode_atom_field(trimmed)

      true ->
        {:ok, trimmed}
    end
  end

  # Integers and BACnet date/time pattern atoms used by BACnetDate / BACnetTime.
  defp date_time_component_value?(value) when is_integer(value), do: true

  defp date_time_component_value?(value) when value in [:unspecified, :even, :odd, :last],
    do: true

  defp date_time_component_value?(_value), do: false

  defp parse_date_time_component(trimmed) when is_binary(trimmed) do
    case Integer.parse(trimmed) do
      {int, ""} ->
        {:ok, int}

      _not_integer ->
        case decode_existing_atom(trimmed) do
          {:ok, atom} when atom in [:unspecified, :even, :odd, :last] ->
            {:ok, atom}

          {:ok, _atom} ->
            {:error, :invalid_atom}

          {:error, _reason} ->
            {:error, :invalid_number}
        end
    end
  end

  defp parse_boolean(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _value -> {:error, :invalid_boolean}
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _value -> {:error, :invalid_number}
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _value -> {:error, :invalid_number}
    end
  end

  defp parse_ip_address_string(string_value) when is_binary(string_value) do
    trimmed = String.trim(string_value)

    if trimmed == "" do
      {:error, :empty_value}
    else
      case :inet.parse_address(String.to_charlist(trimmed)) do
        {:ok, ip} -> {:ok, ip}
        {:error, _reason} -> parse_ip_tuple_inspect(trimmed)
      end
    end
  end

  # Accept legacy inspect form from older form drafts: "{192, 168, 1, 81}"
  defp parse_ip_tuple_inspect("{" <> rest) do
    with true <- String.ends_with?(rest, "}"),
         inner = String.trim_trailing(rest, "}"),
         parts when length(parts) in [4, 8] <- String.split(inner, ","),
         {:ok, ints} <- parse_ip_tuple_parts(parts) do
      ip = List.to_tuple(ints)

      case :inet.ntoa(ip) do
        {:error, _reason} -> {:error, :invalid_ip}
        _charlist -> {:ok, ip}
      end
    else
      _other -> {:error, :invalid_ip}
    end
  end

  defp parse_ip_tuple_inspect(_value), do: {:error, :invalid_ip}

  defp parse_ip_tuple_parts(parts) do
    case Enum.reduce_while(parts, [], fn part, acc ->
           case Integer.parse(String.trim(part)) do
             {int, ""} -> {:cont, [int | acc]}
             _other -> {:halt, :error}
           end
         end) do
      :error -> {:error, :invalid_ip}
      ints -> {:ok, Enum.reverse(ints)}
    end
  end

  # BACnet/IP six-byte MAC as "IPv4:port", hex octet strings, or "broadcast".
  defp parse_mac_address_string(string_value) when is_binary(string_value) do
    trimmed = String.trim(string_value)

    cond do
      trimmed == "" ->
        {:error, :empty_value}

      trimmed == "broadcast" ->
        {:ok, :broadcast}

      true ->
        case parse_ip_port_mac(trimmed) do
          {:ok, _mac} = ok -> ok
          :error -> parse_hex_mac(trimmed)
        end
    end
  end

  defp parse_ip_port_mac(string) when is_binary(string) do
    case String.split(string, ":", parts: 2) do
      [ip_str, port_str] ->
        with {:ok, {a, b, c, d}} <- parse_ip_address_string(ip_str),
             {port, ""} <- Integer.parse(port_str),
             true <- port in 0..65_535 do
          {:ok, <<a, b, c, d, Bitwise.bsr(port, 8), Bitwise.band(port, 0xFF)>>}
        else
          _ip_port -> :error
        end

      _ip_port ->
        :error
    end
  end

  defp parse_hex_mac(string) when is_binary(string) do
    hex =
      string
      |> String.replace(":", "")
      |> String.replace(" ", "")
      |> String.replace("-", "")

    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} when byte_size(binary) > 0 -> {:ok, binary}
      _hex -> {:error, :invalid_mac}
    end
  end

  defp value_to_string(nil), do: ""
  defp value_to_string(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_to_string(value) when is_integer(value), do: Integer.to_string(value)

  defp value_to_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 10)

  # Opaque BACnet octet / MAC binaries are not character text; format for forms / JSON.
  defp value_to_string(value) when is_binary(value) do
    if mac_octet_string?(value) do
      PropertyFormatter.format_mac_address(value)
    else
      value
    end
  end

  defp value_to_string({:ip_address, ip}) when is_tuple(ip), do: value_to_string(ip)

  defp value_to_string(value) when is_tuple(value) and tuple_size(value) > 0 do
    cond do
      PropertyFormatter.bitstring_value?(value) ->
        PropertyFormatter.format_edit_value(value, nil, nil)

      tuple_size(value) in [4, 8] ->
        case :inet.ntoa(value) do
          {:error, _reason} -> inspect(value, limit: 200)
          charlist when is_list(charlist) -> List.to_string(charlist)
        end

      true ->
        inspect(value, limit: 200)
    end
  end

  defp value_to_string(value), do: inspect(value, limit: 200)

  # Raw BACnet data-link / opaque octet addresses vs character text property values.
  # Use printable_text? so ASCII-range MACs with control bytes are still treated as binary.
  defp mac_octet_string?(value) when is_binary(value), do: Text.opaque_binary?(value)

  defp path_string([]), do: @root_field_path

  defp path_string(path_rev) do
    path_rev
    |> Enum.reverse()
    |> Enum.map_join(".", &segment_to_string/1)
  end

  defp segment_to_string(index) when is_integer(index), do: Integer.to_string(index)
  defp segment_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp segment_to_string(other), do: to_string(other)

  defp parse_path(@root_field_path), do: {:ok, []}

  defp parse_path(path) do
    case Enum.reduce_while(String.split(path, "."), {:ok, []}, fn segment, {:ok, acc} ->
           case parse_path_segment(segment) do
             {:ok, part} -> {:cont, {:ok, [part | acc]}}
             {:error, _path} = err -> {:halt, err}
           end
         end) do
      {:ok, segments} -> {:ok, Enum.reverse(segments)}
      err -> err
    end
  end

  defp unused_field_key?(key) when is_binary(key), do: String.starts_with?(key, "_unused_")
  defp unused_field_key?(_key), do: false

  defp parse_path_segment(segment) do
    case Integer.parse(segment) do
      {index, ""} ->
        {:ok, index}

      _segment ->
        {:ok, String.to_existing_atom(segment)}
    end
  rescue
    ArgumentError -> {:error, :invalid_path}
  end

  defp field_label_at(path_rev, suffix) do
    labels =
      path_rev
      |> Enum.reverse()
      |> Enum.map(&segment_label/1)
      |> Enum.reject(&(&1 == ""))

    base = Enum.join(labels, " · ")

    cond do
      base == "" and is_binary(suffix) -> suffix
      base == "" -> "Value"
      is_binary(suffix) -> base <> " · " <> suffix
      true -> base
    end
  end

  defp segment_label(index) when is_integer(index), do: "[#{index + 1}]"

  defp segment_label(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp encode(%Encoding{type: type, value: value, encoding: encoding, extras: extras}) do
    %{
      "encoding" => Atom.to_string(encoding),
      "type" => if(type, do: Atom.to_string(type), else: nil),
      "extras" => encode_encoding_extras(extras),
      "value" => encode(value)
    }
  end

  defp encode(%ObjectIdentifier{type: type, instance: instance}) do
    %{"type" => Atom.to_string(type), "instance" => instance}
  end

  defp encode(%PriorityArray{} = array) do
    array
    |> PriorityArray.to_list()
    |> Enum.map(fn
      {priority, value} -> %{"priority" => priority, "value" => encode(value)}
      value -> encode(value)
    end)
  end

  defp encode(%BACnetArray{} = array),
    do: array |> bacnet_array_elements() |> Enum.map(&encode/1)

  defp encode(%_value{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), encode(value)} end)
    |> Map.new()
  end

  defp encode({tag, value}) when is_atom(tag),
    do: %{"_tag" => Atom.to_string(tag), "value" => encode(value)}

  # Boolean bitstrings before IPv4/IPv6 (4-tuples of booleans must not become IP strings)
  defp encode(value) when is_tuple(value) and tuple_size(value) > 0 do
    cond do
      PropertyFormatter.bitstring_value?(value) ->
        Enum.map(Tuple.to_list(value), &encode/1)

      tuple_size(value) in [4, 8] ->
        case :inet.ntoa(value) do
          charlist when is_list(charlist) -> List.to_string(charlist)
          {:error, _reason} -> Enum.map(Tuple.to_list(value), &encode/1)
        end

      true ->
        Enum.map(Tuple.to_list(value), &encode/1)
    end
  end

  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(nil), do: nil
  defp encode(value) when is_boolean(value), do: value
  defp encode(value) when is_atom(value), do: Atom.to_string(value)

  # Jason rejects invalid UTF-8 binaries; format opaque BACnet MAC / octet strings.
  defp encode(value) when is_binary(value) do
    if mac_octet_string?(value) do
      PropertyFormatter.format_mac_address(value)
    else
      value
    end
  end

  defp encode(value), do: value

  defp decode(value, %Encoding{} = template) when is_map(value),
    do: decode_encoding_map(value, template)

  defp decode(value, %Encoding{type: type, value: template_value} = template) do
    with {:ok, decoded} <- decode(value, template_value) do
      rebuild_encoding(type, decoded, template)
    end
  end

  defp decode(value, %ObjectIdentifier{}), do: decode_object_identifier(value)
  defp decode(value, %PriorityArray{} = template), do: decode_priority_array(value, template)

  defp decode(value, %BACnetArray{} = template), do: decode_bacnet_array(value, template)

  defp decode(value, %BACnetDate{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetTime{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetDateTime{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %BACnetTimestamp{} = template), do: decode_struct_fields(value, template)
  defp decode(value, %Recipient{} = template), do: decode_recipient(value, template)
  defp decode(value, %_json{} = template), do: decode_struct_fields(value, template)

  defp decode(value, template) when is_list(template), do: decode_list(value, template)
  defp decode(value, _template) when is_integer(value), do: {:ok, value}
  defp decode(value, _template) when is_float(value) or is_boolean(value), do: {:ok, value}

  defp decode(value, template)
       when is_binary(value) and is_tuple(template) and tuple_size(template) > 0 do
    if PropertyFormatter.bitstring_value?(template) do
      PropertyFormatter.parse_bitstring(value, tuple_size(template))
    else
      if tuple_size(template) in [4, 8] do
        parse_ip_address_string(value)
      else
        {:error, :invalid_json_value}
      end
    end
  end

  defp decode(value, template) when is_binary(value) and is_binary(template) do
    if mac_octet_string?(template) do
      parse_mac_address_string(value)
    else
      {:ok, value}
    end
  end

  # RecipientAddress.address may be :broadcast or a MAC binary.
  defp decode(value, :broadcast) when is_binary(value), do: parse_mac_address_string(value)

  defp decode(value, template) when is_binary(value) and is_atom(template),
    do: decode_atom_field(value)

  defp decode(value, _template) when is_binary(value), do: {:ok, value}
  defp decode(value, nil) when value in [nil, "nil"], do: {:ok, nil}
  defp decode(nil, _template), do: {:ok, nil}

  defp decode(%{"_tag" => tag, "value" => inner}, template) when is_binary(tag) do
    with {:ok, tag_atom} <- decode_existing_atom(tag),
         {:ok, decoded} <- decode(inner, template_value_template(template, tag_atom)) do
      {:ok, {tag_atom, decoded}}
    end
  end

  defp decode(list, template)
       when is_list(list) and is_tuple(template) and tuple_size(template) > 0 do
    cond do
      PropertyFormatter.bitstring_value?(template) ->
        decode_bitstring_list(list, tuple_size(template))

      tuple_size(template) in [4, 8] ->
        decode_ip_tuple_list(list, template)

      true ->
        {:error, :invalid_json_value}
    end
  end

  defp decode(_value, _template), do: {:error, :invalid_json_value}

  defp decode_bitstring_list(list, expected_size)
       when is_list(list) and is_integer(expected_size) do
    with true <- length(list) == expected_size,
         {:ok, bits} <- decode_bitstring_items(list) do
      {:ok, List.to_tuple(bits)}
    else
      false -> {:error, {:bitstring_size_mismatch, expected_size, length(list)}}
      {:error, _reason} = err -> err
    end
  end

  defp decode_bitstring_items(list) do
    case Enum.reduce_while(list, [], fn item, acc ->
           case decode_bitstring_item(item) do
             {:ok, bit} -> {:cont, [bit | acc]}
             :error -> {:halt, :error}
           end
         end) do
      :error -> {:error, :invalid_bitstring}
      bits -> {:ok, Enum.reverse(bits)}
    end
  end

  defp decode_bitstring_item(true), do: {:ok, true}
  defp decode_bitstring_item(false), do: {:ok, false}
  defp decode_bitstring_item(1), do: {:ok, true}
  defp decode_bitstring_item(0), do: {:ok, false}
  defp decode_bitstring_item("true"), do: {:ok, true}
  defp decode_bitstring_item("false"), do: {:ok, false}
  defp decode_bitstring_item("1"), do: {:ok, true}
  defp decode_bitstring_item("0"), do: {:ok, false}
  defp decode_bitstring_item(_item), do: :error

  defp decode_ip_tuple_list(list, template)
       when is_list(list) and is_tuple(template) and tuple_size(template) in [4, 8] do
    with true <- length(list) == tuple_size(template),
         true <- Enum.all?(list, &is_integer/1) do
      ip = List.to_tuple(list)

      case :inet.ntoa(ip) do
        {:error, _reason} -> {:error, :invalid_ip}
        _charlist -> {:ok, ip}
      end
    else
      _other -> {:error, :invalid_ip}
    end
  end

  defp decode_struct_fields(map, %_map{} = template) when is_map(map) do
    fields = Map.from_struct(template)

    with :ok <- reject_unknown_json_fields(map, fields) do
      decode_known_struct_fields(map, fields, template)
    end
  end

  defp decode_struct_fields(_value, _template), do: {:error, :invalid_struct_json}

  defp bacnet_array_elements(%BACnetArray{size: 0}), do: []

  defp bacnet_array_elements(%BACnetArray{} = array) do
    Enum.map(1..BACnetArray.size(array), fn index ->
      case BACnetArray.get_item(array, index) do
        {:ok, item} -> item
        :error -> BACnetArray.get_default(array)
      end
    end)
  end

  defp bacnet_array_item_template(%BACnetArray{} = array, json_items) do
    case bacnet_array_elements(array) do
      [item | _array] when is_struct(item) ->
        item

      _array ->
        case BACnetArray.get_default(array) do
          default when is_struct(default) -> default
          _array -> infer_array_item_template(json_items)
        end
    end
  end

  defp infer_array_item_template([item | _item]) when is_map(item) do
    keys = MapSet.new(Map.keys(item))

    cond do
      MapSet.subset?(
        MapSet.new(["device_identifier", "object_identifier", "property_identifier"]),
        keys
      ) ->
        %DeviceObjectPropertyRef{
          object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
          property_identifier: :present_value,
          property_array_index: nil,
          device_identifier: nil
        }

      MapSet.subset?(MapSet.new(["object_identifier", "property_identifier"]), keys) ->
        %ObjectPropertyRef{
          object_identifier: %ObjectIdentifier{type: :analog_input, instance: 0},
          property_identifier: :present_value,
          property_array_index: nil
        }

      true ->
        nil
    end
  end

  defp infer_array_item_template(_item), do: nil

  defp decode_bacnet_array(list, %BACnetArray{fixed_size: fixed_size} = template)
       when is_list(list) and is_integer(fixed_size) do
    actual = length(list)

    if actual != fixed_size do
      {:error, {:fixed_bacnet_array_size, fixed_size, actual}}
    else
      decode_bacnet_array_items(list, template)
    end
  end

  defp decode_bacnet_array(list, %BACnetArray{} = template) when is_list(list) do
    decode_bacnet_array_items(list, template)
  end

  defp decode_bacnet_array(_value, _template), do: {:error, :invalid_list_json}

  defp decode_bacnet_array_items(list, %BACnetArray{} = template) do
    item_templates = bacnet_array_elements(template)
    default_item_template = bacnet_array_item_template(template, list)

    with {:ok, decoded_items} <- decode_array_items(list, item_templates, default_item_template) do
      rebuild_bacnet_array(decoded_items, template, default_item_template)
    end
  end

  defp decode_array_items(list, item_templates, default_item_template) do
    case Enum.reduce_while(Enum.with_index(list), {:ok, []}, fn {item, index}, {:ok, acc} ->
           item_template = Enum.at(item_templates, index, default_item_template)

           case decode(item, item_template) do
             {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
             {:error, _list} = err -> {:halt, err}
           end
         end) do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      err -> err
    end
  end

  # Variable arrays must not use a real element as the Erlang :array default.
  # `:array.sparse_to_list/1` (used by `BACnetArray.to_list/1` and thus write
  # casting via `reduce_while`) omits entries equal to the default. If the
  # default is the first existing item (or a blank template struct), any JSON
  # entry that matches it is dropped — typically leaving only later items on
  # the wire (e.g. schedule list_of_object_property_references).
  defp rebuild_bacnet_array(items, %BACnetArray{fixed_size: nil}, _item_template) do
    {:ok, BACnetArray.from_list(items, false, :undefined)}
  end

  defp rebuild_bacnet_array(
         items,
         %BACnetArray{fixed_size: fixed_size} = template,
         _item_template
       )
       when is_integer(fixed_size) do
    default = BACnetArray.get_default(template)
    base = BACnetArray.new(fixed_size, default)

    Enum.reduce_while(Enum.with_index(items, 1), {:ok, base}, fn {item, index}, {:ok, array} ->
      case BACnetArray.set_item(array, index, item) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _items} = err -> {:halt, err}
      end
    end)
  end

  defp decode_recipient(map, %Recipient{} = fallback) when is_map(map) do
    template =
      case Map.get(map, "type") do
        "device" ->
          %Recipient{
            type: :device,
            address: nil,
            device: recipient_device_template(fallback)
          }

        "address" ->
          %Recipient{
            type: :address,
            device: nil,
            address: recipient_address_template(fallback)
          }

        _map ->
          fallback
      end

    decode_struct_fields(map, template)
  end

  defp decode_recipient(_value, _template), do: {:error, :invalid_struct_json}

  defp recipient_device_template(%Recipient{device: %ObjectIdentifier{} = device}), do: device

  defp recipient_device_template(_recipient_device_template_arg1),
    do: %ObjectIdentifier{type: :device, instance: 0}

  defp recipient_address_template(%Recipient{address: %RecipientAddress{} = address}), do: address

  defp recipient_address_template(_recipient_address_template_arg1),
    do: %RecipientAddress{network: 0, address: :broadcast}

  defp decode_known_struct_fields(map, fields, %_map{} = template) do
    case Enum.reduce_while(fields, {:ok, %{}}, fn {key, field_template}, {:ok, acc} ->
           string_key = Atom.to_string(key)

           case Map.fetch(map, string_key) do
             :error ->
               {:cont, {:ok, Map.put(acc, key, field_template)}}

             {:ok, raw} ->
               case decode(raw, field_template) do
                 {:ok, decoded} -> {:cont, {:ok, Map.put(acc, key, decoded)}}
                 {:error, _map} = err -> {:halt, err}
               end
           end
         end) do
      {:ok, attrs} -> {:ok, struct(template.__struct__, attrs)}
      err -> err
    end
  end

  defp reject_unknown_json_fields(map, fields) when is_map(map) do
    known_keys = fields |> Map.keys() |> Enum.map(&Atom.to_string/1) |> MapSet.new()

    case Enum.reject(Map.keys(map), &MapSet.member?(known_keys, &1)) do
      [] -> :ok
      unknown -> {:error, {:unknown_json_fields, Enum.sort(unknown)}}
    end
  end

  defp decode_object_identifier(%{"type" => type, "instance" => instance}) when is_binary(type) do
    with {:ok, type_atom} <- PropertyEnumeration.parse_value(type, :object_type) do
      {:ok, %ObjectIdentifier{type: type_atom, instance: instance}}
    end
  end

  defp decode_object_identifier(_type), do: {:error, :invalid_object_identifier}

  defp decode_list(list, template) when is_list(list) and is_list(template) do
    default_item_template = List.first(template) || recipient_list_item_template(template)

    case Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
           item_template = list_item_template(item, default_item_template, template)

           case decode(item, item_template) do
             {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
             {:error, _list} = err -> {:halt, err}
           end
         end) do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      err -> err
    end
  end

  defp decode_list(list, _template) when is_list(list), do: {:ok, list}
  defp decode_list(_list, _template), do: {:error, :invalid_list_json}

  defp list_item_template(%{"type" => type}, default, list) when is_binary(type) do
    if recipient_list?(list) do
      recipient_template_for_type(type, default)
    else
      default
    end
  end

  defp list_item_template(_item, default, _list), do: default

  defp recipient_template_for_type("device", %Recipient{} = fallback) do
    %Recipient{
      type: :device,
      address: nil,
      device: recipient_device_template(fallback)
    }
  end

  defp recipient_template_for_type("address", %Recipient{} = fallback) do
    %Recipient{
      type: :address,
      device: nil,
      address: recipient_address_template(fallback)
    }
  end

  defp recipient_template_for_type(_type, default), do: default

  defp recipient_list?([%Recipient{} | _rest]), do: true
  defp recipient_list?(_value), do: false

  defp recipient_list_item_template([
         %Recipient{} = recipient | _recipient_list_item_template_arg1
       ]),
       do: recipient

  defp recipient_list_item_template(_recipient_list_item_template_arg1), do: nil

  defp decode_priority_array(list, %PriorityArray{} = template) when is_list(list) do
    slots =
      Enum.reduce_while(1..16, {:ok, %{}}, fn priority, {:ok, acc} ->
        field = priority_field_atom(priority)
        current = Map.get(template, field)

        encoded_item =
          Enum.find(list, fn
            %{"priority" => ^priority} = item -> item
            _list -> nil
          end)

        case encoded_item do
          %{"value" => raw} ->
            case decode(raw, current) do
              {:ok, decoded} -> {:cont, {:ok, Map.put(acc, field, decoded)}}
              err -> {:halt, err}
            end

          _list ->
            {:cont, {:ok, Map.put(acc, field, current)}}
        end
      end)

    case slots do
      {:ok, attrs} -> {:ok, struct(PriorityArray, attrs)}
      err -> err
    end
  end

  defp decode_priority_array(value, template),
    do: decode_list(value, PriorityArray.to_list(template))

  defp decode_atom_field(value) do
    case decode_existing_atom(value) do
      {:ok, atom} -> {:ok, atom}
      {:error, _value} -> {:ok, value}
    end
  end

  defp decode_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_atom}
  end

  defp template_value_template(_template, :real), do: 0.0
  defp template_value_template(_template, :enumerated), do: :active
  defp template_value_template(_template, :boolean), do: false
  defp template_value_template(_template, :unsigned_integer), do: 0
  defp template_value_template(_template, :signed_integer), do: 0
  defp template_value_template(_template, :character_string), do: ""

  # HostNPort and similar CHOICE tags: unwrap the payload template for the inner value
  defp template_value_template({tag, inner}, tag) when is_atom(tag), do: inner
  defp template_value_template(template, _tag), do: template

  defp finalize_apply_result({:ok, %Encoding{} = value}), do: finalize_encoding(value)
  defp finalize_apply_result(result), do: result

  defp decode_encoding_map(map, %Encoding{} = template) when is_map(map) do
    with :ok <- reject_unknown_encoding_json_fields(map),
         {:ok, encoding_kind} <-
           decode_encoding_kind_field(Map.get(map, "encoding"), template.encoding),
         {:ok, type} <- decode_encoding_type_field(Map.get(map, "type"), template.type),
         {:ok, extras} <- decode_encoding_extras(Map.get(map, "extras"), template.extras),
         value_template <-
           encoding_value_template(type, template.type, template.value),
         {:ok, value} <- decode(Map.get(map, "value"), value_template) do
      finalize_encoding(%{
        template
        | encoding: encoding_kind,
          type: type,
          extras: extras,
          value: value
      })
    end
  end

  defp reject_unknown_encoding_json_fields(map) do
    known = MapSet.new(["type", "value", "encoding", "extras"])

    case Enum.reject(Map.keys(map), &MapSet.member?(known, &1)) do
      [] -> :ok
      unknown -> {:error, {:unknown_json_fields, Enum.sort(unknown)}}
    end
  end

  defp decode_encoding_type_field(nil, template_type), do: {:ok, template_type}

  defp decode_encoding_type_field("", _template_type), do: {:ok, nil}

  defp decode_encoding_type_field(type, _template_type) when is_binary(type) do
    decode_encoding_type(type)
  end

  defp decode_encoding_kind_field(nil, template_kind), do: {:ok, template_kind}

  defp decode_encoding_kind_field(kind, _template_kind) when is_binary(kind) do
    decode_encoding_kind(kind)
  end

  defp decode_encoding_kind(string_value) when is_binary(string_value) do
    case decode_existing_atom(string_value) do
      {:ok, kind} when kind in [:primitive, :tagged, :constructed] -> {:ok, kind}
      {:ok, _nil} -> {:error, :invalid_encoding_kind}
      {:error, _nil} = err -> err
    end
  end

  defp decode_encoding_extras(nil, template_extras), do: {:ok, template_extras}

  defp decode_encoding_extras(map, template_extras) when is_map(map) do
    case Map.fetch(map, "tag_number") do
      :error ->
        {:ok, template_extras}

      {:ok, raw} ->
        with {:ok, tag_number} <- decode_optional_integer(raw) do
          {:ok, put_tag_number_extra(template_extras, tag_number)}
        end
    end
  end

  defp decode_encoding_extras(_value, template_extras), do: {:ok, template_extras}

  defp decode_optional_integer(nil), do: {:ok, nil}
  defp decode_optional_integer(value) when is_integer(value), do: {:ok, value}

  defp decode_optional_integer(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      case Integer.parse(trimmed) do
        {int, ""} -> {:ok, int}
        _nil -> {:error, :invalid_number}
      end
    end
  end

  defp strip_tag_number_for_primitive(:primitive, extras), do: Keyword.delete(extras, :tag_number)
  defp strip_tag_number_for_primitive(_encoding, extras), do: extras

  defp apply_tag_number_change(extras, string_value) do
    case decode_optional_integer(string_value) do
      {:ok, nil} -> {:ok, Keyword.delete(extras, :tag_number)}
      {:ok, tag} -> {:ok, Keyword.put(extras, :tag_number, tag)}
      {:error, _extras} = err -> err
    end
  end

  defp put_tag_number_extra(extras, nil), do: Keyword.delete(extras, :tag_number)
  defp put_tag_number_extra(extras, tag), do: Keyword.put(extras, :tag_number, tag)

  defp encode_encoding_extras(extras) when is_list(extras) do
    extras
    |> Keyword.take([:tag_number])
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  defp decode_encoding_type(string_value) when is_binary(string_value) do
    case decode_existing_atom(string_value) do
      {:ok, type} ->
        if type in PropertyFormatter.encoding_primitive_types(),
          do: {:ok, type},
          else: {:error, :invalid_encoding_type}

      {:error, _nil} = err ->
        err
    end
  end

  defp encoding_value_template(type, type, value), do: value

  defp encoding_value_template(type, _template_type, _value),
    do: template_value_template(nil, type)

  defp rebuild_encoding(nil, value, %Encoding{} = template) do
    finalize_encoding(%{template | value: value})
  end

  defp rebuild_encoding(type, value, %Encoding{} = template) when is_atom(type) do
    finalize_encoding(%{template | type: type, value: value})
  end

  defp finalize_encoding(%Encoding{} = encoding) do
    safe_finalize_encoding(encoding)
  rescue
    e in KeyError ->
      if e.key == :tag_number,
        do: {:error, :missing_tag_number},
        else: {:error, :invalid_encoding}
  end

  defp safe_finalize_encoding(%Encoding{} = encoding) do
    case Encoding.to_encoding(encoding) do
      {:ok, raw} ->
        case Encoding.create(raw, extras_to_create_opts(encoding.extras)) do
          {:ok, %Encoding{} = created} ->
            {:ok, preserve_encoding_metadata(created, encoding)}

          {:error, _encoding} = err ->
            err
        end

      {:error, _encoding} ->
        {:error, :invalid_encoding}
    end
  end

  defp extras_to_create_opts(extras) when is_list(extras),
    do: Keyword.take(extras, [:context, :encoder])

  defp preserve_encoding_metadata(%Encoding{} = created, %Encoding{} = template) do
    extras =
      if template.extras == [] do
        created.extras
      else
        template.extras
      end

    %{created | extras: extras}
  end

  defp parse_encoding_value(:boolean, _current, string_value) do
    parse_boolean(String.trim(string_value))
  end

  defp parse_encoding_value(type, _current, string_value)
       when type in [:real, :double] do
    parse_float(String.trim(string_value))
  end

  defp parse_encoding_value(type, _current, string_value)
       when type in [:unsigned_integer, :signed_integer, :enumerated] do
    parse_integer(String.trim(string_value))
  end

  defp parse_encoding_value(:null, _current, string_value) do
    if String.trim(string_value) in ["", "null"],
      do: {:ok, nil},
      else: {:error, :invalid_encoding_value}
  end

  defp parse_encoding_value(_type, current, string_value) do
    parse_field_value(current, string_value)
  end

  defp priority_field_atom(priority) when priority in 1..16,
    do: String.to_existing_atom("priority_#{priority}")
end
