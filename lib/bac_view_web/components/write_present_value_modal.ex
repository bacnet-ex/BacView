defmodule BacViewWeb.WritePresentValueModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyFormatter

  attr(:object, :map, required: true)
  attr(:write_priority, :integer, default: 8)
  attr(:writing, :boolean, default: false)

  def modal(assigns) do
    boolean_options = boolean_options(assigns.object)

    state_options =
      if MultistateState.multistate_object?(assigns.object) do
        MultistateState.state_options(assigns.object)
      else
        []
      end

    assigns =
      assigns
      |> assign(:boolean_options, boolean_options)
      |> assign(:boolean_dropdown?, boolean_options != [])
      |> assign(:state_options, state_options)
      |> assign(:state_dropdown?, state_options != [])

    ~H"""
    <div id="write-present-value-modal" class="bac-modal-backdrop" phx-hook="FocusFirstInput">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="close_write_modal"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal bac-modal-lg" role="dialog" aria-modal="true">
        <div class="bac-modal-body space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs bac-text-faint uppercase tracking-wide">
                {t(@locale, @locale_version, "Present Value schreiben")}
              </p>
              <h2 class="font-semibold text-base truncate mt-0.5">
                {@object.name || "#{@object.type}:#{@object.instance}"}
              </h2>
              <p class="bac-mono text-xs bac-text-faint mt-0.5">
                {@object.type}:{@object.instance}
              </p>
            </div>
            <button
              type="button"
              phx-click="close_write_modal"
              class="bac-btn bac-btn-ghost bac-btn-icon shrink-0"
              aria-label={t(@locale, @locale_version, "Schliessen")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div class="bac-stat py-3">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Aktueller Wert")}</p>
              <p
                class="bac-stat-value bac-mono text-base break-all"
                title={@object.present_value_formatted}
              >
                {@object.present_value_formatted}
              </p>
            </div>
            <div :if={commandable?(@object)} class="bac-stat py-3">
              <p class="bac-stat-label">{t(@locale, @locale_version, "Aktive Priorität")}</p>
              <p class="bac-stat-value text-base">
                <%= if active_priority(@object) do %>
                  <span class="bac-mono">{active_priority(@object)}</span>
                  <span
                    :if={active_priority_value_formatted(@object)}
                    class="block text-xs bac-text-faint bac-mono mt-0.5 font-normal"
                  >
                    {active_priority_value_formatted(@object)}
                  </span>
                <% else %>
                  <span class="bac-text-faint">-</span>
                <% end %>
              </p>
            </div>
          </div>

          <.form for={%{}} as={:write} id="write-present-value-form" phx-submit="write_present_value">
            <div :if={commandable?(@object)} class="space-y-1.5 mb-4">
              <label for="modal-write-priority" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Schreib-Priorität")}
              </label>
              <select
                id="modal-write-priority"
                name="priority"
                phx-change="set_write_priority"
                class="bac-input bac-input-sm w-full"
              >
                <option :for={p <- 1..16} value={p} selected={p == @write_priority}>
                  {p}
                </option>
              </select>
            </div>

            <div class="space-y-1.5 mb-4">
              <label for="modal-write-value" class="text-xs bac-text-faint">
                {t(@locale, @locale_version, "Neuer Wert")}
              </label>
              <select
                :if={@boolean_dropdown?}
                id="modal-write-value"
                name="value"
                data-autofocus
                class="bac-input bac-input-sm w-full"
              >
                <option
                  :for={opt <- @boolean_options}
                  value={to_string(opt.value)}
                  selected={selected_boolean_option?(@object, opt.value)}
                >
                  {opt.label}
                </option>
              </select>
              <select
                :if={!@boolean_dropdown? && @state_dropdown?}
                id="modal-write-value"
                name="value"
                data-autofocus
                class="bac-input bac-input-sm w-full"
              >
                <option
                  :for={opt <- @state_options}
                  value={opt.value}
                  selected={selected_state_option?(@object, opt)}
                >
                  {opt.label}
                </option>
              </select>
              <div :if={!@boolean_dropdown? && !@state_dropdown?} class="space-y-1">
                <input
                  id="modal-write-value"
                  type="text"
                  name="value"
                  value={input_value(@object)}
                  placeholder={write_value_placeholder(@object, @locale, @locale_version)}
                  class="bac-input bac-input-sm bac-mono w-full"
                  autocomplete="off"
                  data-autofocus
                />
                <p :if={bitstring_present_value?(@object)} class="text-xs bac-text-faint">
                  {t(
                    @locale,
                    @locale_version,
                    "Bitstring: Bits als 0/1 (z. B. 10110), optional mit Leerzeichen. Länge muss %{count} betragen.",
                    count: bitstring_size(@object)
                  )}
                </p>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2 pt-2">
              <button
                :if={commandable?(@object)}
                type="button"
                phx-click="reset_present_value"
                disabled={@writing}
                class="bac-btn bac-btn-ghost bac-btn-sm mr-auto"
              >
                {t(@locale, @locale_version, "Null (Priorität zurücksetzen)")}
              </button>
              <button type="button" phx-click="close_write_modal" class="bac-btn bac-btn-ghost bac-btn-sm">
                {t(@locale, @locale_version, "Abbrechen")}
              </button>
              <button
                type="submit"
                disabled={@writing}
                class="bac-btn bac-btn-primary bac-btn-sm"
              >
                <.icon :if={@writing} name="hero-arrow-path" class="size-4 animate-spin" />
                {t(@locale, @locale_version, "Schreiben")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp commandable?(object) when is_map(object), do: Map.get(object, :commandable, false)
  defp commandable?(_object), do: false

  defp active_priority(object) when is_map(object), do: Map.get(object, :active_priority)
  defp active_priority(_object), do: nil

  defp active_priority_value_formatted(object) when is_map(object),
    do: Map.get(object, :active_priority_value_formatted)

  defp active_priority_value_formatted(_object), do: nil

  defp boolean_options(object) when is_map(object) do
    cond do
      BinaryPV.binary_object?(object) ->
        BinaryPV.state_options(object)

      is_boolean(Map.get(object, :present_value)) ->
        [
          %{value: true, label: "true"},
          %{value: false, label: "false"}
        ]

      true ->
        []
    end
  end

  defp boolean_options(_object), do: []

  defp selected_boolean_option?(object, option_value) when is_map(object) do
    BinaryPV.normalize_value(Map.get(object, :present_value)) == option_value
  end

  defp selected_boolean_option?(_object, _option_value), do: false

  defp selected_state_option?(%{present_value: value}, %{value: option_value}) do
    normalize_state_value(value) == option_value
  end

  defp selected_state_option?(_object, _option), do: false

  defp normalize_state_value(value) when is_integer(value), do: value

  defp normalize_state_value(value) when is_float(value), do: trunc(value)
  defp normalize_state_value(_value), do: nil

  defp input_value(object) when is_map(object) do
    PropertyFormatter.format_edit_value(
      Map.get(object, :present_value),
      object,
      %{property: :present_value}
    )
  end

  defp write_value_placeholder(object, locale, locale_version) do
    if bitstring_present_value?(object) do
      t(locale, locale_version, "Bits als 0/1 …")
    else
      t(locale, locale_version, "Neuer Wert")
    end
  end

  defp bitstring_present_value?(object) when is_map(object) do
    PropertyFormatter.bitstring_value?(Map.get(object, :present_value))
  end

  defp bitstring_present_value?(_object), do: false

  defp bitstring_size(object) when is_map(object) do
    case Map.get(object, :present_value) do
      value when is_tuple(value) -> tuple_size(value)
      {:bitstring, value} when is_tuple(value) -> tuple_size(value)
      _other -> 0
    end
  end

  defp bitstring_size(_object), do: 0
end
