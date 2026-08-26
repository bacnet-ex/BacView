defmodule BacViewWeb.ReadPropertyLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [start_async: 3]

  alias BACnet.Protocol.ObjectIdentifier

  alias BacView.BACnet.Address
  alias BacView.BACnet.Protocol.BacnetUri
  alias BacView.BACnet.Protocol.ErrorMessage
  alias BacView.BACnet.Protocol.PropertyDisplay
  alias BacView.BACnet.SinglePropertyRead
  alias BacView.Settings

  @form_as :read_property

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket), do: assign(socket, :read_property, nil)

  @spec open(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def open(socket) do
    assign(socket, :read_property, new_state())
  end

  @spec close(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close(socket), do: assign(socket, :read_property, nil)

  @spec change(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def change(socket, params) do
    case socket.assigns.read_property do
      nil ->
        socket

      state ->
        form_params = Map.get(params, "read_property", %{})
        current = form_values(state.form)
        values = merge_values(current, form_params)
        this_device_id = socket.assigns[:device_id]
        {values, uri_error} = apply_uri_and_sync(values, current["uri"], this_device_id)

        assign(socket, :read_property, %{
          state
          | transport: Settings.transport(),
            form: to_form(values, as: @form_as),
            uri_error: uri_error
        })
    end
  end

  @spec execute(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def execute(socket, params) do
    case socket.assigns.read_property do
      %{busy: true} ->
        socket

      nil ->
        socket

      state ->
        form_params = Map.get(params, "read_property", %{})
        current = form_values(state.form)
        values = merge_values(current, form_params)
        this_device_id = socket.assigns[:device_id]
        {values, uri_error} = apply_uri_and_sync(values, current["uri"], this_device_id)
        transport = Settings.transport()

        socket
        |> assign(:read_property, %{
          state
          | transport: transport,
            form: to_form(values, as: @form_as),
            uri_error: uri_error,
            busy: true,
            error: nil,
            result: nil
        })
        |> start_async(:read_property, fn ->
          SinglePropertyRead.from_form(values, transport: transport)
        end)
    end
  end

  @spec apply_async(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def apply_async(socket, result)

  def apply_async(socket, {:ok, {:ok, result}}) do
    update_open(socket, fn state ->
      display = PropertyDisplay.build(result.value, object: object_map(result.object))

      %{
        state
        | busy: false,
          error: nil,
          result: Map.put(result, :display, display)
      }
    end)
  end

  def apply_async(socket, {:ok, {:error, reason}}) do
    update_open(socket, fn state ->
      %{state | busy: false, result: nil, error: ErrorMessage.for_action(:read_property, reason)}
    end)
  end

  def apply_async(socket, {:exit, reason}) do
    update_open(socket, fn state ->
      %{state | busy: false, result: nil, error: ErrorMessage.for_action(:read_property, reason)}
    end)
  end

  defp update_open(socket, fun) do
    case socket.assigns.read_property do
      nil -> socket
      state -> assign(socket, :read_property, fun.(state))
    end
  end

  defp new_state() do
    %{
      transport: Settings.transport(),
      form: to_form(empty_values(), as: @form_as),
      uri_error: nil,
      error: nil,
      result: nil,
      busy: false
    }
  end

  defp empty_values() do
    %{
      "uri" => "",
      "locator" => "device_id",
      "device_id" => "",
      "address" => "",
      "object_type" => "",
      "instance" => "",
      "property" => "",
      "array_index" => ""
    }
  end

  defp form_values(%Phoenix.HTML.Form{} = form) do
    Map.merge(empty_values(), stringify_map(form.params || %{}))
  end

  defp merge_values(current, incoming) when is_map(incoming) do
    Map.merge(current, stringify_map(incoming))
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value_to_string(value)} end)
  end

  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp value_to_string(nil), do: ""
  defp value_to_string(value), do: to_string(value)

  # URI is a paste helper: unpack only when the URI text itself changes.
  # Afterwards the structured fields (including locator) are the source of truth.
  defp apply_uri_and_sync(values, prev_uri, this_device_id) do
    uri = String.trim(values["uri"] || "")
    prev = String.trim(prev_uri || "")

    if uri != prev do
      maybe_autofill(values, this_device_id)
    else
      values = maybe_rewrite_uri(values)
      {values, uri_status(values["uri"], this_device_id)}
    end
  end

  defp maybe_autofill(values, this_device_id) do
    uri = String.trim(values["uri"] || "")

    if uri == "" do
      {values, nil}
    else
      case BacnetUri.parse(uri) do
        {:ok, parsed} ->
          {fill_from_uri(values, parsed, this_device_id), uri_status(uri, this_device_id)}

        {:error, _reason} ->
          # Incomplete input ("bacnet:", "bacnet://123") should not flash an error
          # on every keystroke; only flag URIs that already include an object.
          error = if String.contains?(uri, ","), do: :invalid_bacnet_uri, else: nil
          {values, error}
      end
    end
  end

  defp fill_from_uri(values, parsed, this_device_id) do
    device_id =
      case BacnetUri.device_instance(parsed, this_device_id) do
        {:ok, instance} -> Integer.to_string(instance)
        {:error, _reason} -> values["device_id"]
      end

    property =
      case parsed.property_identifier do
        nil -> ""
        property -> identifier_to_form(property)
      end

    array_index =
      case parsed.property_array_index do
        nil -> ""
        index -> Integer.to_string(index)
      end

    values
    |> Map.put("device_id", device_id)
    |> Map.put("object_type", identifier_to_form(parsed.object_identifier.type))
    |> Map.put("instance", Integer.to_string(parsed.object_identifier.instance))
    |> Map.put("property", property)
    |> Map.put("array_index", array_index)
  end

  defp maybe_rewrite_uri(values) do
    uri = String.trim(values["uri"] || "")

    if uri != "" and match?({:ok, _parsed}, BacnetUri.parse(uri)) do
      case encode_uri_from_fields(values) do
        {:ok, encoded} -> Map.put(values, "uri", encoded)
        :skip -> values
      end
    else
      values
    end
  end

  defp encode_uri_from_fields(values) do
    device_raw = String.trim(values["device_id"] || "")
    type_str = String.trim(values["object_type"] || "")
    instance_str = String.trim(values["instance"] || "")
    prop_str = String.trim(values["property"] || "")
    index_str = String.trim(values["array_index"] || "")

    if device_raw == "" or type_str == "" or instance_str == "" do
      :skip
    else
      encode_uri_string(device_raw, type_str, instance_str, prop_str, index_str)
    end
  end

  defp encode_uri_string(device_raw, type_str, instance_str, prop_str, index_str) do
    if invalid_uri_segment?(type_str) or invalid_uri_segment?(instance_str) or
         invalid_uri_segment?(prop_str) do
      :skip
    else
      uri = build_uri_string(device_raw, type_str, instance_str, prop_str, index_str)

      case BacnetUri.parse(uri) do
        {:ok, parsed} ->
          case BacnetUri.encode(parsed) do
            {:ok, encoded} -> {:ok, encoded}
            {:error, _reason} -> :skip
          end

        {:error, _reason} ->
          :skip
      end
    end
  end

  defp build_uri_string(device_raw, type_str, instance_str, prop_str, index_str) do
    base = "bacnet://" <> device_raw <> "/" <> type_str <> "," <> instance_str

    with_prop =
      cond do
        prop_str != "" -> base <> "/" <> prop_str
        index_str != "" -> base <> "/present-value"
        true -> base
      end

    if index_str == "" do
      with_prop
    else
      with_prop <> "/" <> index_str
    end
  end

  defp invalid_uri_segment?(value), do: String.contains?(value, "/")

  defp uri_status(uri, this_device_id) do
    trimmed = String.trim(uri || "")

    if trimmed == "" do
      nil
    else
      case BacnetUri.parse(trimmed) do
        {:ok, parsed} ->
          case BacnetUri.device_instance(parsed, this_device_id) do
            {:ok, _instance} -> nil
            {:error, :this_device_unknown} -> :this_device_unknown
            {:error, _reason} -> nil
          end

        {:error, _reason} ->
          if String.contains?(trimmed, ","), do: :invalid_bacnet_uri, else: nil
      end
    end
  end

  defp identifier_to_form(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp identifier_to_form(value) when is_integer(value), do: Integer.to_string(value)

  defp object_map(%ObjectIdentifier{type: type, instance: instance}) do
    %{type: type, instance: instance}
  end

  @spec destination_label(term()) :: String.t()
  def destination_label(destination), do: Address.format_destination(destination)
end
