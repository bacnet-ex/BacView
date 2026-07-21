defmodule BacViewWeb.DeviceSkippedObjects do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:skipped_objects, :list, default: [])

  def skipped_panel(assigns) do
    skipped = normalize_skipped(assigns.skipped_objects)
    count = length(skipped)

    assigns =
      assigns
      |> assign(:skipped_objects, skipped)
      |> assign(:count, count)

    ~H"""
    <details
      :if={@count > 0}
      id="device-skipped-objects"
      class="bac-collapsible mx-5 mt-3 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-bg-elevated)]/60 px-4 py-3"
    >
      <summary class="bac-collapsible-summary text-sm font-medium text-[var(--bac-text)]">
        <.icon name="hero-chevron-right" class="bac-collapsible-icon size-4 shrink-0" />
        <span>
          {t(
            @locale,
            @locale_version,
            "%{count} unbekannte/proprietäre Objekttypen übersprungen",
            count: @count
          )}
        </span>
      </summary>
      <p class="bac-collapsible-content text-xs bac-text-muted mt-2">
        {t(
          @locale,
          @locale_version,
          "Diese Objekttypen sind dem Scanner nicht bekannt und wurden nicht gelesen."
        )}
      </p>
      <ul class="bac-collapsible-content mt-2 space-y-1 text-xs max-h-48 overflow-y-auto">
        <li
          :for={{entry, index} <- Enum.with_index(@skipped_objects, 1)}
          id={"device-skipped-object-#{index}"}
          class="bac-mono text-[var(--bac-text)]"
        >
          {entry.label}
        </li>
      </ul>
    </details>
    """
  end

  defp normalize_skipped(list) when is_list(list) do
    Enum.flat_map(list, fn
      %{label: label} = entry when is_binary(label) ->
        [entry]

      %{object_id: object_id} = entry ->
        [Map.put(entry, :label, format_oid(object_id))]

      %BACnet.Protocol.ObjectIdentifier{} = oid ->
        [%{label: format_oid(oid), object_id: oid, reason: :unsupported_object_type}]

      _other ->
        []
    end)
  end

  defp normalize_skipped(_list), do: []

  defp format_oid(%BACnet.Protocol.ObjectIdentifier{type: type, instance: instance}),
    do: "#{type}:#{instance}"

  defp format_oid(other), do: inspect(other)
end
