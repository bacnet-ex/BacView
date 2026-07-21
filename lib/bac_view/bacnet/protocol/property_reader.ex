defmodule BacView.BACnet.Protocol.PropertyReader do
  @moduledoc """
  Reads object properties for the UI via RPM or individual ReadProperty streams.

  When `read_object` with `read_level: :all` succeeds, property rows are built
  from the decoded struct (no follow-up ReadPropertyMultiple / ReadProperty pass).

  The individual path (device `property_list` or schema fallback) reads properties
  one-by-one, casts a remote object from successful reads when possible, and
  falls back to a raw value map when casting fails.

  For debug output, set env `:bacview, :debug_log_property_reader` to `true`.
  """

  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.BACnetArray
  alias BACnet.Protocol.Constants
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.ObjectsUtility
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.Protocol.PropertyEnumeration
  alias BacView.BACnet.Protocol.PropertyFormatter
  alias BacView.BACnet.Protocol.UnknownProperty
  alias BacView.BACnet.Segmentation
  alias BacView.Text

  import BACnet.Protocol.ObjectsUtility, only: [is_object: 1]

  require Constants
  require Logger

  @read_opts [allow_unknown_properties: :no_unpack, ignore_unsupported_object_types: true]

  @input_object_types [:analog_input, :binary_input, :multi_state_input]

  @trend_log_types [:trend_log, :trend_log_multiple]

  # Large or scan-irrelevant Device properties - skip during individual property reads
  # (object_list alone can be thousands of entries and blocks the UI for minutes).
  @device_heavy_properties [
    :property_list,
    :object_list,
    :structured_object_list,
    :device_address_binding,
    :active_cov_subscriptions,
    :slave_address_binding,
    :manual_slave_address_binding,
    :restart_notification_recipients,
    :time_synchronization_recipients,
    :utc_time_synchronization_recipients,
    :configuration_files
  ]

  # Historical healthy default; override via config :bacview, :property_read_concurrency
  # (lower for devices overwhelmed by parallel ReadProperty - was temporarily 1).
  @default_property_read_concurrency 8

  @type read_result :: %{
          properties: [map()],
          unknown_properties: [map()]
        }

  @spec read_all(module(), term(), ObjectIdentifier.t(), keyword()) ::
          {:ok, read_result()} | {:error, term()}
  def read_all(client, destination, %ObjectIdentifier{} = object, opts \\ []) do
    read_opts = build_read_opts(opts)

    debug_log(object, "read_all_start", fn ->
      %{
        remote_device_id: Keyword.get(read_opts, :remote_device_id),
        skip_mode: Keyword.get(read_opts, :object_opts)
      }
    end)

    case fetch_bacnet_object(client, destination, object, read_opts) do
      {:ok, bacnet_object, :rpm} ->
        with {:ok, properties} <- property_list(bacnet_object) do
          readable = readable_properties(properties, object)
          results = ObjectsUtility.to_map(bacnet_object)
          result = build_read_result(readable, results, bacnet_object)

          debug_log(object, "read_all_done", fn ->
            %{
              path: :rpm,
              properties_list: length(properties),
              readable: length(readable),
              result_keys: map_size(results),
              displayed: length(result.properties),
              unknown: length(result.unknown_properties)
            }
          end)

          {:ok, result}
        end

      {:ok, properties, :individual} ->
        readable = readable_properties(properties, object)

        debug_log(object, "read_all_individual", fn ->
          %{candidate_count: length(readable)}
        end)

        results =
          read_properties_individually(client, destination, object, readable, read_opts)

        {:ok,
         build_individual_read_result(
           client,
           destination,
           object,
           readable,
           results,
           read_opts
         )}

      {:error, _client} = err ->
        debug_log(object, "read_all_failed", fn -> %{error: err} end)
        err
    end
  end

  defp build_read_opts(opts) when is_list(opts) do
    base =
      Keyword.merge(@read_opts, Keyword.take(opts, [:object_opts, :remote_device_id, :device_id]))

    case Keyword.get(opts, :on_property_progress) do
      fun when is_function(fun, 1) -> Keyword.put(base, :on_property_progress, fun)
      _no_progress -> base
    end
  end

  defp client_opts(read_opts) when is_list(read_opts),
    do: Keyword.drop(read_opts, [:on_property_progress, :log_errors])

  @doc """
  Non-RPM property load: resolve property identifiers (full list / indexed / schema),
  skip heavy properties, then ReadProperty each into a raw value map.

  Used by scan/fallback paths that need a map for hierarchy/`summarize_object`,
  not UI property rows.

  Optional `on_property_progress` in `opts` is called as `fun.(%{stage, done, total})`
  during individual ReadProperty streams (not for pure RPM success).
  """
  @spec read_properties_map(module(), term(), ObjectIdentifier.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def read_properties_map(client, destination, %ObjectIdentifier{} = object, opts \\ []) do
    read_opts = build_read_opts(opts)

    with {:ok, properties} <- list_property_identifiers(client, destination, object, read_opts) do
      readable = skip_heavy_properties(properties, object)
      {:ok, read_properties_individually(client, destination, object, readable, read_opts)}
    end
  end

  @doc false
  @spec read_result_from_object(ObjectIdentifier.t(), term()) :: read_result()
  def read_result_from_object(%ObjectIdentifier{} = object_id, obj) do
    bacnet_object = if is_object(obj), do: obj, else: nil

    results =
      cond do
        is_object(obj) -> ObjectsUtility.to_map(obj)
        is_map(obj) -> obj
        true -> %{}
      end

    raw_properties =
      cond do
        is_object(obj) ->
          obj |> ObjectsUtility.get_properties() |> normalize_properties()

        is_map(obj) ->
          normalize_properties(Map.keys(obj))

        true ->
          []
      end

    properties = readable_properties(raw_properties, object_id)

    rows = format_property_rows(properties, results, bacnet_object)
    unknown = format_unknown_properties(bacnet_object)

    %{
      properties: rows,
      unknown_properties: unknown
    }
  end

  @doc false
  @spec skip_heavy_properties([term()], ObjectIdentifier.t()) :: [term()]
  def skip_heavy_properties(properties, object_id) when is_list(properties) do
    skip = heavy_properties_for(object_id)
    Enum.reject(properties, &(&1 in skip))
  end

  @doc """
  Max concurrency for individual property ReadProperty streams.

  Configured via `config :bacview, :property_read_concurrency, n` (default 8).
  Set lower (e.g. 1) if old devices are overwhelmed by parallel reads.

  When `opts` includes `:device_id` or `:remote_device_id`, a per-device
  `:max_concurrency` from discovery (shared request destination, e.g. gateway)
  overrides the global default when set.
  """
  @spec property_read_concurrency(keyword()) :: pos_integer()
  def property_read_concurrency(opts \\ []) do
    case device_max_concurrency(opts) do
      n when is_integer(n) and n > 0 -> n
      _no_device_limit -> default_property_read_concurrency()
    end
  end

  @doc false
  @spec device_max_concurrency(keyword() | integer() | nil) :: pos_integer() | nil
  def device_max_concurrency(nil), do: nil

  def device_max_concurrency(device_id) when is_integer(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, %{max_concurrency: n}} when is_integer(n) and n > 0 -> n
      _device -> nil
    end
  end

  def device_max_concurrency(opts) when is_list(opts) do
    opts
    |> device_id_from_opts()
    |> device_max_concurrency()
  end

  @doc false
  @spec scan_concurrency(integer()) :: pos_integer()
  def scan_concurrency(device_id) when is_integer(device_id) do
    case device_max_concurrency(device_id) do
      n when is_integer(n) and n > 0 -> n
      _no_device_limit -> min(32, System.schedulers_online())
    end
  end

  defp default_property_read_concurrency() do
    case Application.get_env(
           :bacview,
           :property_read_concurrency,
           @default_property_read_concurrency
         ) do
      n when is_integer(n) and n > 0 -> n
      _invalid -> @default_property_read_concurrency
    end
  end

  defp device_id_from_opts(opts) when is_list(opts) do
    Keyword.get(opts, :device_id) || Keyword.get(opts, :remote_device_id)
  end

  @doc false
  @spec heavy_properties_for(ObjectIdentifier.t()) :: [atom()]
  def heavy_properties_for(%ObjectIdentifier{type: :device}), do: @device_heavy_properties

  def heavy_properties_for(%ObjectIdentifier{type: type})
      when type in @trend_log_types,
      do: [:property_list, :log_buffer]

  def heavy_properties_for(_object_id), do: [:property_list]

  defp readable_properties(properties, object_id),
    do: skip_heavy_properties(properties, object_id)

  @doc false
  @spec format_property_rows([term()], map(), term()) :: [map()]
  def format_property_rows(properties, results, bacnet_object \\ nil)
      when is_list(properties) and is_map(results) do
    format_results(properties, results, bacnet_object)
  end

  @doc false
  @spec schema_properties(ObjectIdentifier.t()) :: {:ok, [term()]} | {:error, term()}
  def schema_properties(%ObjectIdentifier{type: type}) do
    case ObjectsUtility.get_object_type_mappings()[type] do
      mod when is_atom(mod) ->
        Code.ensure_loaded(mod)

        if function_exported?(mod, :get_all_properties, 0) do
          {:ok, normalize_properties(mod.get_all_properties())}
        else
          {:error, :unsupported_object_type}
        end

      _unsupported ->
        {:error, :unsupported_object_type}
    end
  end

  @doc false
  @spec array_property?(ObjectIdentifier.t(), term()) :: boolean()
  def array_property?(%ObjectIdentifier{type: type}, property) do
    case ObjectsUtility.get_object_type_mappings()[type] do
      mod when is_atom(mod) ->
        if function_exported?(mod, :get_properties_type_map, 0) do
          type_map = mod.get_properties_type_map()
          match?({:array, _}, type_map[property] || type_map[normalize_property(property)])
        else
          false
        end

      _unsupported ->
        false
    end
  end

  @doc false
  @spec read_property_value(module(), term(), ObjectIdentifier.t(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def read_property_value(client, destination, %ObjectIdentifier{} = object, property, read_opts) do
    client_opts = client_opts(read_opts)

    case client.read_property(destination, object, property, client_opts) do
      {:ok, value} ->
        {:ok, sanitize_read_value(value)}

      {:error, {:invalid_property_value, {^property, raw}}} ->
        {:ok, sanitize_loose_property_value(raw)}

      {:error, reason} = err ->
        if is_nil(Keyword.get(client_opts, :array_index)) and array_property?(object, property) and
             Segmentation.fallback_error?(err) do
          maybe_log_read_error(
            read_opts,
            :read_property,
            destination,
            object,
            property,
            reason,
            level: :debug
          )

          read_property_array_indexed(client, destination, object, property, client_opts)
        else
          maybe_log_read_error(read_opts, :read_property, destination, object, property, reason)
          err
        end
    end
  end

  defp sanitize_loose_property_value(%Encoding{value: value}),
    do: sanitize_loose_property_value(value)

  defp sanitize_loose_property_value(value) when is_binary(value), do: Text.sanitize_utf8(value)
  defp sanitize_loose_property_value(value), do: value

  defp sanitize_read_value(value) when is_binary(value) do
    if String.valid?(value), do: value, else: Text.sanitize_utf8(value)
  end

  defp sanitize_read_value(%Encoding{value: inner} = encoding),
    do: %{encoding | value: sanitize_read_value(inner)}

  defp sanitize_read_value(value), do: value

  defp fetch_bacnet_object(client, destination, object, read_opts) do
    opts = Keyword.merge(client_opts(read_opts), read_level: :all)

    case client.read_object(destination, object, opts) do
      {:ok, obj} when is_object(obj) ->
        debug_log(object, "fetch_bacnet_object", fn ->
          %{
            path: :rpm,
            properties_list: length(ObjectsUtility.get_properties(obj))
          }
        end)

        {:ok, obj, :rpm}

      {:error, reason} = error ->
        if Segmentation.rpm_fallback_error?(error) do
          debug_log(object, "fetch_bacnet_object", fn ->
            %{
              path: :individual_fallback,
              rpm_error: reason
            }
          end)

          maybe_log_read_error(
            read_opts,
            :read_object,
            destination,
            object,
            nil,
            reason,
            level: :debug
          )

          # Devices without RPM/segmentation: resolve property_list or schema, then
          # individual ReadProperty, then cast from successful reads.
          case list_property_identifiers(client, destination, object, read_opts) do
            {:ok, properties} -> {:ok, properties, :individual}
            {:error, _reason} = err -> err
          end
        else
          debug_log(object, "fetch_bacnet_object", fn ->
            %{
              path: :error,
              rpm_error: reason
            }
          end)

          maybe_log_read_error(read_opts, :read_object, destination, object, nil, reason)
          error
        end

      other ->
        debug_log(object, "fetch_bacnet_object", fn ->
          %{
            path: :object_unavailable,
            response: inspect(other, limit: 50)
          }
        end)

        {:error, :object_unavailable}
    end
  end

  defp maybe_log_read_error(
         read_opts,
         operation,
         destination,
         object,
         property,
         reason,
         opts \\ []
       ) do
    if Keyword.get(read_opts, :log_errors, true) do
      Client.log_read_error(operation, destination, object, property, reason, opts)
    else
      :ok
    end
  end

  defp list_property_identifiers(client, destination, object, read_opts) do
    case read_property_list(client, destination, object, read_opts) do
      {:ok, property_list} ->
        normalized = normalize_properties(property_list)

        debug_log(object, "property_identifiers", fn ->
          %{
            source: :property_list,
            count: length(normalized)
          }
        end)

        {:ok, normalized}

      {:error, reason} ->
        debug_log(object, "property_identifiers", fn ->
          %{
            source: :schema_fallback,
            property_list_error: reason
          }
        end)

        schema_properties(object)
    end
  end

  defp debug_log(%ObjectIdentifier{} = object, event, fun)
       when is_binary(event) and is_function(fun, 0) do
    if Application.get_env(:bacview, :debug_log_property_reader, false) do
      Logger.debug(fn ->
        "[PropertyReader #{object.type}:#{object.instance}] #{event} " <>
          inspect(fun.(), printable_limit: 500)
      end)
    end
  end

  defp read_object_name(client, destination, object, read_opts) do
    case read_property_value(client, destination, object, :object_name, read_opts) do
      {:ok, name} when is_binary(name) ->
        {:ok, name}

      {:ok, %Encoding{value: name}} when is_binary(name) ->
        {:ok, name}

      _read_object_name ->
        {:ok, default_object_name(object)}
    end
  end

  defp default_object_name(%ObjectIdentifier{type: type, instance: instance}),
    do: "#{type}:#{instance}"

  defp build_individual_read_result(
         client,
         destination,
         %ObjectIdentifier{} = object,
         readable,
         results,
         read_opts
       )
       when is_list(readable) and is_map(results) and is_list(read_opts) do
    results = ensure_object_name_for_cast(client, destination, object, results, read_opts)
    successful = Enum.filter(readable, &Map.has_key?(results, &1))

    debug_log(object, "individual_reads_done", fn ->
      %{
        attempted: length(readable),
        read_ok: length(successful),
        read_failed: length(readable) - length(successful)
      }
    end)

    # UI rows = successfully read properties. Cast enriches types/writable only.
    {bacnet_object, display_results, path} =
      case cast_object(object, results, read_opts) do
        {:ok, obj} ->
          debug_log(object, "individual_cast_ok", fn -> %{path: :struct} end)
          typed = ObjectsUtility.to_map(obj)

          display =
            Map.new(successful, fn prop ->
              {prop, Map.get(typed, prop, Map.get(results, prop))}
            end)

          {obj, display, :individual_cast}

        {:error, reason} ->
          debug_log(object, "individual_cast_failed", fn ->
            %{path: :map_fallback, reason: reason}
          end)

          {nil, Map.take(results, successful), :individual_map_fallback}
      end

    result = build_read_result(successful, display_results, bacnet_object)

    debug_log(object, "read_all_done", fn ->
      %{
        path: path,
        displayed: length(result.properties),
        unknown: length(result.unknown_properties)
      }
    end)

    result
  end

  defp ensure_object_name_for_cast(client, destination, object, results, read_opts) do
    if Map.has_key?(results, :object_name) do
      results
    else
      {:ok, name} = read_object_name(client, destination, object, read_opts)
      Map.put(results, :object_name, name)
    end
  end

  defp cast_object(%ObjectIdentifier{} = object, results, read_opts)
       when is_map(results) and is_list(read_opts) do
    ObjectsUtility.cast_properties_to_object(object, results, cast_opts_from_read_opts(read_opts))
  end

  defp cast_opts_from_read_opts(read_opts) when is_list(read_opts) do
    opts =
      read_opts
      |> Keyword.take([:allow_unknown_properties, :remote_device_id, :device_id])
      |> Keyword.put_new(:allow_unknown_properties, :no_unpack)

    case Keyword.get(read_opts, :object_opts) do
      object_opts when is_list(object_opts) -> Keyword.put(opts, :object_opts, object_opts)
      _no_object_opts -> opts
    end
  end

  defp read_property_list(client, destination, object, read_opts) do
    case read_property_value(client, destination, object, :property_list, read_opts) do
      {:ok, property_list} ->
        {:ok, unwrap_property_list(property_list)}

      {:error, _reason} = err ->
        if Segmentation.array_fallback_error?(err) do
          read_property_list_indexed(client, destination, object, read_opts)
        else
          err
        end
    end
  end

  defp read_property_list_indexed(client, destination, object, read_opts) do
    indexed_opts = Keyword.merge(read_opts, array_index: 0)

    case read_property_value(client, destination, object, :property_list, indexed_opts) do
      {:ok, 0} ->
        {:ok, []}

      {:ok, count} when is_integer(count) and count > 0 ->
        props =
          1..count
          |> Task.async_stream(
            fn idx ->
              case read_property_value(
                     client,
                     destination,
                     object,
                     :property_list,
                     Keyword.merge(read_opts, array_index: idx)
                   ) do
                {:ok, prop} -> unwrap_property_identifier(prop)
                {:error, _reason} -> nil
              end
            end,
            max_concurrency: property_read_concurrency(read_opts),
            timeout: :infinity,
            ordered: false
          )
          |> Enum.reduce([], fn
            {:ok, prop}, acc when not is_nil(prop) -> [prop | acc]
            _read_property_list_index, acc -> acc
          end)
          |> Enum.reverse()

        {:ok, props}

      {:error, _reason} = err ->
        err

      _read_property_list_indexed ->
        {:error, :property_list_not_readable}
    end
  end

  defp unwrap_property_list(%BACnetArray{} = array), do: BACnetArray.to_list(array)
  defp unwrap_property_list(list) when is_list(list), do: list
  defp unwrap_property_list(%Encoding{value: value}), do: unwrap_property_list(value)
  defp unwrap_property_list(value), do: [value]

  defp unwrap_property_identifier(%Encoding{value: value}), do: unwrap_property_identifier(value)
  defp unwrap_property_identifier(value), do: value

  defp property_list(bacnet_object) do
    properties =
      bacnet_object
      |> ObjectsUtility.get_properties()
      |> normalize_properties()

    {:ok, properties}
  end

  @doc false
  def normalize_properties(list) when is_list(list) do
    list
    |> Enum.map(&normalize_property/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&valid_property?/1)
    |> Enum.uniq()
  end

  def normalize_properties(_list), do: []

  defp normalize_property(:engineering_units), do: :units
  defp normalize_property(prop) when is_atom(prop), do: prop
  defp normalize_property(prop) when is_integer(prop), do: prop
  defp normalize_property(%{value: val}), do: normalize_property(val)
  defp normalize_property(%ObjectIdentifier{}), do: nil
  defp normalize_property(_engineering_units), do: nil

  defp valid_property?(prop) when is_atom(prop) do
    case Constants.by_name(:property_identifier, prop) do
      {:ok, _prop} -> true
      :error -> false
    end
  end

  defp valid_property?(prop) when is_integer(prop) and prop >= 0, do: true
  defp valid_property?(_prop), do: false

  defp read_properties_individually(_client, _destination, _object, [], _read_opts), do: %{}

  defp read_properties_individually(client, destination, object, properties, read_opts) do
    total = length(properties)
    on_progress = Keyword.get(read_opts, :on_property_progress)
    # Bulk individual reads often hit expected misses (unknown_property, etc.).
    # Log once at debug here; suppress per-call warnings inside read_property_value/5.
    quiet_opts = Keyword.put(read_opts, :log_errors, false)
    report_property_progress(on_progress, 0, total)

    properties
    |> Task.async_stream(
      fn prop ->
        case read_property_value(client, destination, object, prop, quiet_opts) do
          {:ok, value} ->
            {prop, value}

          {:error, reason} ->
            Logger.debug(
              Client.read_error_message(:read_property, destination, object, prop, reason)
            )

            nil
        end
      end,
      max_concurrency: property_read_concurrency(read_opts),
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce({%{}, 0}, fn
      {:ok, {prop, value}}, {acc, done} ->
        done = done + 1
        report_property_progress(on_progress, done, total)
        {Map.put(acc, prop, value), done}

      _other, {acc, done} ->
        done = done + 1
        report_property_progress(on_progress, done, total)
        {acc, done}
    end)
    |> elem(0)
  end

  defp report_property_progress(fun, done, total)
       when is_function(fun, 1) and is_integer(done) and is_integer(total) and total > 0 do
    if done == 0 or done == total or rem(done, property_progress_interval(total)) == 0 do
      fun.(%{stage: :reading_properties, done: done, total: total})
    end

    :ok
  end

  defp report_property_progress(_fun, _done, _total), do: :ok

  defp property_progress_interval(total) when total <= 40, do: 1
  defp property_progress_interval(total), do: max(1, div(total, 20))

  defp build_read_result(properties, results, bacnet_object)
       when is_list(properties) and is_map(results) do
    %{
      properties: format_results(properties, results, bacnet_object),
      unknown_properties: format_unknown_properties(bacnet_object)
    }
  end

  @doc false
  @spec format_unknown_properties(term()) :: [map()]
  def format_unknown_properties(bacnet_object) when is_object(bacnet_object) do
    bacnet_object
    |> Map.get(:_unknown_properties, %{})
    |> Enum.map(fn {property, value} ->
      presented = UnknownProperty.present(value)
      display = PropertyDisplay.build(presented.display_value)

      Text.sanitize_property_row(%{
        property: property,
        property_name: property_name(property),
        value: value,
        value_display: display,
        value_formatted: presented.formatted,
        type: presented.type,
        string_value?: presented.string_value?,
        hex_toggle?: presented.hex_toggle?,
        raw_binary: presented.raw_binary
      })
    end)
    |> Enum.sort_by(& &1.property_name)
  end

  def format_unknown_properties(_bacnet_object), do: []

  defp format_results(properties, results, bacnet_object)
       when is_list(properties) and is_map(results) do
    type_map = properties_type_map(bacnet_object)

    properties
    |> Enum.map(fn property ->
      value = Map.get(results, property)
      bac_type = Map.get(type_map, property)
      binary_meta = binary_presentation(value, bac_type)
      display = property_display(value, binary_meta)

      %{
        property: property,
        property_name: property_name(property),
        value: value,
        value_display: display,
        value_formatted: Map.get(binary_meta, :formatted, display.formatted),
        bac_type: bac_type,
        type: property_type(value, display, bac_type),
        writable: writable_property?(bacnet_object, property, results),
        updated_at: DateTime.utc_now(),
        string_value?: Map.get(binary_meta, :string_value?, false),
        hex_toggle?: Map.get(binary_meta, :hex_toggle?, false),
        raw_binary: Map.get(binary_meta, :raw_binary)
      }
      |> PropertyEnumeration.enrich_property(bac_type)
      |> Text.sanitize_property_row()
    end)
    |> Enum.sort_by(& &1.property_name)
  end

  defp property_display(_value, %{string_value?: true, formatted: formatted}) do
    %{kind: :scalar, formatted: formatted, fields: [], items: []}
  end

  defp property_display(value, _binary_meta), do: PropertyDisplay.build(value)

  # Binary / character presentation for known properties (hex toggle support).
  # Octet strings default to hex display; character strings to sanitized text.
  # Non-printable values get `hex_toggle?: true` so the UI can switch views.
  defp binary_presentation(value, bac_type) when is_binary(value) do
    octet? = bac_type == :octet_string
    printable? = Text.printable_text?(value)

    formatted =
      if octet? do
        PropertyFormatter.format_binary_hex(value)
      else
        Text.sanitize_utf8(value)
      end

    %{
      string_value?: true,
      hex_toggle?: not printable?,
      raw_binary: value,
      formatted: formatted
    }
  end

  defp binary_presentation(%Encoding{type: :character_string, value: inner}, _bac_type)
       when is_binary(inner) do
    binary_presentation(inner, :character_string)
  end

  defp binary_presentation(%Encoding{type: :octet_string, value: inner}, _bac_type)
       when is_binary(inner) do
    binary_presentation(inner, :octet_string)
  end

  defp binary_presentation(_value, _bac_type), do: %{}

  defp properties_type_map(bacnet_object) when is_object(bacnet_object) do
    mod = bacnet_object.__struct__

    if function_exported?(mod, :get_properties_type_map, 0) do
      mod.get_properties_type_map()
    else
      %{}
    end
  end

  defp properties_type_map(_bacnet_object), do: %{}

  defp property_type(_value, _display, {:constant, _type}), do: "ENUMERATED"

  defp property_type(nil, _display, :boolean), do: "BOOLEAN"
  defp property_type(nil, _display, :real), do: "REAL"
  defp property_type(nil, _display, :double), do: "REAL"
  defp property_type(nil, _display, :bitstring), do: "BITSTRING"

  # bacstack object schemas use `:string` for character strings (`String.t()`)
  # and `:octet_string` for raw binaries. ApplicationTags use `:character_string`.
  defp property_type(_value, _display, bac_type)
       when bac_type in [:string, :character_string],
       do: "CHARACTER STRING"

  defp property_type(_value, _display, :octet_string), do: "OCTET STRING"

  defp property_type(nil, _display, _bac_type), do: "-"

  defp property_type(_value, %{kind: :array}, _bac_type), do: "ARRAY"
  defp property_type(_value, %{kind: :list}, _bac_type), do: "LIST"

  defp property_type(_value, %{kind: kind}, _bac_type)
       when kind in [:struct, :priority_array],
       do: "STRUCT"

  defp property_type(value, _display, :bitstring) do
    if PropertyFormatter.bitstring_value?(value),
      do: "BITSTRING",
      else: PropertyFormatter.property_type(value)
  end

  defp property_type(value, _display, bac_type) do
    case PropertyFormatter.integer_bac_type_label(bac_type) do
      nil -> PropertyFormatter.property_type(value)
      label -> label
    end
  end

  defp property_name(property) when is_atom(property),
    do: property |> Atom.to_string() |> String.replace("_", " ")

  defp property_name(property) when is_integer(property) do
    case Constants.by_value(:property_identifier, property) do
      {:ok, name} -> String.replace(Atom.to_string(name), "_", " ")
      :error -> "property #{property}"
    end
  end

  defp property_name(property), do: inspect(property)

  @doc false
  @spec input_object_type?(atom()) :: boolean()
  def input_object_type?(type) when is_atom(type), do: type in @input_object_types
  def input_object_type?(_type), do: false

  @doc false
  @spec sync_input_present_value_writable([map()], map() | nil) :: [map()]
  def sync_input_present_value_writable(properties, object) when is_list(properties) do
    if input_object_summary?(object) do
      enabled = out_of_service_enabled_in_properties?(properties)

      Enum.map(properties, fn
        %{property: :present_value} = prop -> Map.put(prop, :writable, enabled)
        prop -> prop
      end)
    else
      properties
    end
  end

  def sync_input_present_value_writable(properties, _properties), do: properties

  defp writable_property?(_object, property, _results)
       when property in [:object_identifier, :object_name, :object_type, :property_list],
       do: false

  defp writable_property?(object, property, results) when is_object(object) do
    case property do
      :present_value -> present_value_writable?(object, results)
      _object -> ObjectsUtility.property_writable?(object, property)
    end
  end

  defp writable_property?(_object, property, _results)
       when property in [:out_of_service, :description, :relinquish_default],
       do: true

  defp writable_property?(_object, _property, _results), do: false

  defp present_value_writable?(object, results) do
    if input_object_type?(ObjectsUtility.get_object_type(object)) do
      out_of_service_enabled?(object, results)
    else
      ObjectsUtility.property_writable?(object, :present_value)
    end
  end

  defp out_of_service_enabled?(object, results) do
    case Map.get(results, :out_of_service) do
      true -> true
      false -> false
      _object -> Map.get(object, :out_of_service) == true
    end
  end

  defp input_object_summary?(%{type: type}), do: input_object_type?(type)
  defp input_object_summary?(_input_object_summary), do: false

  defp out_of_service_enabled_in_properties?(properties) do
    case Enum.find(properties, &(&1.property == :out_of_service)) do
      %{value: true} -> true
      _properties -> false
    end
  end

  defp read_property_array_indexed(client, destination, object, property, read_opts) do
    indexed_opts = Keyword.merge(read_opts, array_index: 0)

    case client.read_property(destination, object, property, indexed_opts) do
      {:ok, 0} ->
        {:ok, []}

      {:ok, count} when is_integer(count) and count > 0 ->
        elements =
          1..count
          |> Task.async_stream(
            fn idx ->
              case client.read_property(
                     destination,
                     object,
                     property,
                     Keyword.merge(read_opts, array_index: idx)
                   ) do
                {:ok, value} -> value
                {:error, _reason} -> nil
              end
            end,
            max_concurrency: property_read_concurrency(read_opts),
            timeout: :infinity,
            ordered: true
          )
          |> Enum.reduce([], fn
            {:ok, value}, acc when not is_nil(value) -> [value | acc]
            _other, acc -> acc
          end)
          |> Enum.reverse()

        {:ok, elements}

      {:error, _reason} = err ->
        err

      _other ->
        {:error, :property_array_not_readable}
    end
  end
end
