defmodule BacViewWeb.WritePresentValueModal do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.BinaryPV
  alias BacView.BACnet.Protocol.MultistateState
  alias BacView.BACnet.Protocol.PropertyFormatter

  @analog_types [
    :analog_input,
    :analog_output,
    :analog_value,
    :large_analog_value
  ]

  @max_slider_span 9999
  @tick_intervals 10

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

    slider = slider_config(assigns.object)

    assigns =
      assigns
      |> assign(:boolean_options, boolean_options)
      |> assign(:boolean_dropdown?, boolean_options != [])
      |> assign(:state_options, state_options)
      |> assign(:state_dropdown?, state_options != [])
      |> assign(:slider, slider)
      |> assign(:slider?, is_map(slider))

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
              <div :if={!@boolean_dropdown? && !@state_dropdown?} class="space-y-2">
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
                <div
                  :if={@slider?}
                  id="modal-write-value-slider-wrap"
                  class="space-y-2"
                  phx-hook="SyncRangeInput"
                  phx-update="ignore"
                  data-target="modal-write-value"
                >
                  <input
                    type="range"
                    id="modal-write-value-slider"
                    class="bac-range w-full"
                    min={@slider.min}
                    max={@slider.max}
                    step="1"
                    value={@slider.value}
                    aria-valuemin={@slider.min}
                    aria-valuemax={@slider.max}
                    aria-valuenow={@slider.value}
                  />
                  <div class="flex flex-wrap justify-between gap-1">
                    <button
                      :for={tick <- @slider.ticks}
                      type="button"
                      data-tick={tick}
                      class="bac-btn bac-btn-ghost bac-btn-xs bac-mono min-w-[2.25rem] px-1.5"
                    >
                      {tick}
                    </button>
                  </div>
                  <div class="flex justify-between text-xs bac-text-faint bac-mono">
                    <span>{@slider.min}</span>
                    <span>{@slider.max}</span>
                  </div>
                </div>
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

  @doc """
  Builds integer range-slider config for analog objects with min/max present value.

  Returns `%{min, max, value, ticks}` or `nil` when the object is not eligible.
  """
  @spec slider_config(map() | nil) ::
          %{min: integer(), max: integer(), value: integer(), ticks: [integer()]} | nil
  def slider_config(object) when is_map(object) do
    with true <- analog_object?(object),
         {:ok, min_i} <- integer_bound(Map.get(object, :min_present_value)),
         {:ok, max_i} <- integer_bound(Map.get(object, :max_present_value)),
         true <- min_i < max_i,
         true <- max_i - min_i <= @max_slider_span do
      value = clamp_integer(present_value_integer(object), min_i, max_i)

      %{
        min: min_i,
        max: max_i,
        value: value,
        ticks: tick_values(min_i, max_i)
      }
    else
      _ineligible -> nil
    end
  end

  def slider_config(_object), do: nil

  defp commandable?(object) when is_map(object), do: Map.get(object, :commandable, false)
  defp commandable?(_object), do: false

  defp active_priority(object) when is_map(object), do: Map.get(object, :active_priority)

  defp active_priority_value_formatted(object) when is_map(object),
    do: Map.get(object, :active_priority_value_formatted)

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
      {:bitstring, value} when is_tuple(value) -> tuple_size(value)
      value when is_tuple(value) -> tuple_size(value)
      _other -> 0
    end
  end

  defp analog_object?(%{type: type}) when type in @analog_types, do: true
  defp analog_object?(_object), do: false

  defp integer_bound(value) when is_integer(value), do: {:ok, value}
  defp integer_bound(value) when is_float(value), do: {:ok, trunc(value)}
  defp integer_bound(_value), do: :error

  defp present_value_integer(object) when is_map(object) do
    case Map.get(object, :present_value) do
      value when is_integer(value) -> value
      value when is_float(value) -> trunc(value)
      _other -> nil
    end
  end

  defp clamp_integer(nil, min_i, _max_i), do: min_i
  defp clamp_integer(value, min_i, _max_i) when value < min_i, do: min_i
  defp clamp_integer(value, _min_i, max_i) when value > max_i, do: max_i
  defp clamp_integer(value, _min_i, _max_i), do: value

  defp tick_values(min_i, max_i) do
    span = max_i - min_i

    if span <= @tick_intervals do
      Enum.to_list(min_i..max_i)
    else
      0..@tick_intervals
      |> Enum.map(fn i -> min_i + round(i * span / @tick_intervals) end)
      |> Enum.uniq()
    end
  end
end
