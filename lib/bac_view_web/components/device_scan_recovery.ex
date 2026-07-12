defmodule BacViewWeb.DeviceScanRecovery do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:scan_errors, :list, default: [])
  attr(:scan_retrying, :map, default: %{})

  def recovery_panel(assigns) do
    scan_errors = normalize_scan_errors(assigns.scan_errors)

    assigns =
      assigns
      |> assign(:scan_errors, scan_errors)
      |> assign(:scan_retrying, Map.get(assigns, :scan_retrying, %{}))

    ~H"""
    <details
      :if={@scan_errors != []}
      id="device-scan-recovery-panel"
      class="bac-collapsible mx-5 mt-3 rounded-lg border border-[var(--bac-amber)]/30 bg-[var(--bac-amber)]/8 px-4 py-3"
      open
    >
      <summary class="bac-collapsible-summary text-sm font-medium text-[var(--bac-amber)]">
        <.icon name="hero-chevron-right" class="bac-collapsible-icon size-4 shrink-0" />
        <span>
          {t(@locale, @locale_version, "%{count} Objekte konnten nicht gelesen werden",
            count: length(@scan_errors)
          )}
        </span>
      </summary>
      <p class="bac-collapsible-content text-xs bac-text-muted mt-2">
        {t(
          @locale,
          @locale_version,
          "Einige Objekte haben ungültige BACnet-Werte. Sie können sie mit reduzierter Validierung erneut lesen."
        )}
      </p>
      <ul class="bac-collapsible-content mt-3 space-y-3">
        <li
          :for={{entry, index} <- Enum.with_index(@scan_errors, 1)}
          id={"device-scan-recovery-#{index}"}
          class="rounded-lg border border-[var(--bac-border)]/60 bg-[var(--bac-surface)]/60 px-3 py-2.5"
        >
          <div class="flex flex-wrap items-start gap-x-2 gap-y-1 min-w-0">
            <span class="bac-mono text-sm text-[var(--bac-text)]">{entry.object}</span>
            <span class="text-xs text-[var(--bac-amber)]">{entry.message}</span>
          </div>
          <div class="mt-2 flex flex-wrap gap-2">
            <button
              :if={:value in entry.retry_modes}
              type="button"
              id={"device-scan-recovery-value-#{index}"}
              phx-click="retry_scan_object"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-skip-mode="value"
              disabled={retrying?(@scan_retrying, entry.key)}
              class={[
                "bac-btn bac-btn-sm",
                retrying?(@scan_retrying, entry.key) && "opacity-60 cursor-wait"
              ]}
            >
              <.icon
                :if={retrying?(@scan_retrying, entry.key)}
                name="hero-arrow-path"
                class="size-3.5 animate-spin"
              />
              {t(@locale, @locale_version, "Wertvalidierung überspringen")}
            </button>
            <button
              :if={true in entry.retry_modes}
              type="button"
              id={"device-scan-recovery-all-#{index}"}
              phx-click="retry_scan_object"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-skip-mode="all"
              disabled={retrying?(@scan_retrying, entry.key)}
              class={[
                "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
                retrying?(@scan_retrying, entry.key) && "opacity-60 cursor-wait"
              ]}
            >
              {t(@locale, @locale_version, "Alle Validierung überspringen")}
            </button>
          </div>
          <p :if={true in entry.retry_modes} class="mt-1.5 text-xs bac-text-faint">
            {t(
              @locale,
              @locale_version,
              "Alle Validierung überspringen kann fehlerhafte Datentypen akzeptieren und sollte nur bei Bedarf verwendet werden."
            )}
          </p>
        </li>
      </ul>
    </details>
    """
  end

  defp normalize_scan_errors(scan_errors) when is_list(scan_errors) do
    Enum.flat_map(scan_errors, fn
      %{
        object: object,
        object_id: %BACnet.Protocol.ObjectIdentifier{type: type, instance: instance}
      } = entry ->
        [
          %{
            object: object,
            message: Map.get(entry, :message, ""),
            retry_modes: Map.get(entry, :retry_modes, []),
            type: Atom.to_string(type),
            instance: Integer.to_string(instance),
            key: "#{type}:#{instance}"
          }
        ]

      _entry ->
        []
    end)
  end

  defp normalize_scan_errors(_scan_errors), do: []

  defp retrying?(retrying, key) when is_map(retrying), do: Map.get(retrying, key, false)
  defp retrying?(_retrying, _key), do: false
end
