defmodule BacViewWeb.PropertyPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:object, :map, default: nil)
  attr(:properties, :list, default: [])
  attr(:loading, :boolean, default: false)
  attr(:subscribed_keys, :any, default: MapSet.new())

  def property_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-[var(--bac-bg-elevated)]">
      <div class="bac-panel-header">
        <div class="min-w-0">
          <p class="bac-section-title">{t(@locale, @locale_version, "Eigenschaften")}</p>
          <p :if={@object} class="bac-mono text-sm mt-1 truncate">
            {@object.type}:{@object.instance}
            <span :if={@object.name} class="font-sans text-[var(--bac-text-muted)] ml-1">
              {@object.name}
            </span>
          </p>
          <p :if={is_nil(@object)} class="text-sm bac-text-muted mt-1">
            {t(@locale, @locale_version, "Wählen Sie ein Objekt aus der Liste.")}
          </p>
        </div>
        <div :if={@object} class="flex gap-2 shrink-0">
          <button
            :if={!subscribed?(@subscribed_keys, @object, :present_value)}
            type="button"
            phx-click="subscribe_cov"
            phx-value-type={@object.type}
            phx-value-instance={@object.instance}
            phx-value-property="present_value"
            class="bac-btn bac-btn-primary bac-btn-xs"
          >
            {t(@locale, @locale_version, "COV")}
          </button>
          <button
            :if={subscribed?(@subscribed_keys, @object, :present_value)}
            type="button"
            phx-click="unsubscribe_cov"
            phx-value-type={@object.type}
            phx-value-instance={@object.instance}
            phx-value-property="present_value"
            class="bac-btn bac-btn-ghost bac-btn-xs"
          >
            {t(@locale, @locale_version, "Kündigen")}
          </button>
        </div>
      </div>

      <div class="flex-1 overflow-auto p-4">
        <div :if={@loading} class="bac-loading">
          <.icon name="hero-arrow-path" class="size-4 animate-spin" />
          {t(@locale, @locale_version, "Eigenschaften werden geladen…")}
        </div>

        <div :if={@object && !@loading && @properties != []} class="bac-table-wrap">
          <table class="bac-table">
            <thead>
              <tr>
                <th>{t(@locale, @locale_version, "Name")}</th>
                <th>{t(@locale, @locale_version, "Wert")}</th>
                <th>{t(@locale, @locale_version, "Typ")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={prop <- @properties} id={"prop-#{prop.property}"}>
                <td class="bac-mono">{prop.property_name}</td>
                <td class="bac-mono break-all text-[var(--bac-text)]">{prop.value_formatted}</td>
                <td class="bac-text-faint">{prop.type}</td>
                <td>
                  <button
                    :if={
                      cov_subscribable?(prop.property) &&
                        !subscribed?(@subscribed_keys, @object, prop.property)
                    }
                    type="button"
                    phx-click="subscribe_cov"
                    phx-value-type={@object.type}
                    phx-value-instance={@object.instance}
                    phx-value-property={prop.property}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    COV
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@object && !@loading && @properties == []} class="bac-hero py-12">
          <p class="text-sm bac-text-muted">{t(@locale, @locale_version, "Keine Eigenschaften verfügbar.")}</p>
        </div>
      </div>
    </div>
    """
  end

  defp subscribed?(keys, object, property) when is_map(object) do
    MapSet.member?(keys, {object.type, object.instance, normalize_property(property)})
  end

  defp subscribed?(_keys, _object2, _object), do: false

  defp cov_subscribable?(property) do
    property in [:present_value, :status_flags, :event_state] or
      (is_atom(property) and property not in [:object_identifier, :object_name, :object_type])
  end

  defp normalize_property("present_value"), do: :present_value
  defp normalize_property(prop) when is_atom(prop), do: prop
  defp normalize_property(prop) when is_binary(prop), do: String.to_existing_atom(prop)
end
