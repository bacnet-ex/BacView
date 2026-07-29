defmodule BacViewWeb.DeviceScanRecovery do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:scan_errors, :list, default: [])
  attr(:scan_retrying, :map, default: %{})
  attr(:scan_recovery_open, :boolean, default: false)

  def recovery_panel(assigns) do
    scan_errors = normalize_scan_errors(assigns.scan_errors)

    scan_retrying = Map.get(assigns, :scan_retrying, %{})

    value_bulk? = bulk_retry_available?(scan_errors, :value)
    ignore_invalid_bulk? = bulk_retry_available?(scan_errors, :ignore_invalid)
    all_bulk? = bulk_retry_available?(scan_errors, true)
    maximal_bulk? = bulk_retry_available?(scan_errors, :skip_all_and_ignore_invalid)

    assigns =
      assigns
      |> assign(:scan_errors, scan_errors)
      |> assign(:scan_retrying, scan_retrying)
      |> assign(:scan_recovery_open, Map.get(assigns, :scan_recovery_open, false))
      |> assign(:value_bulk_available?, value_bulk?)
      |> assign(:ignore_invalid_bulk_available?, ignore_invalid_bulk?)
      |> assign(:all_bulk_available?, all_bulk?)
      |> assign(:maximal_bulk_available?, maximal_bulk?)
      |> assign(
        :any_retry_available?,
        value_bulk? or ignore_invalid_bulk? or all_bulk? or maximal_bulk?
      )
      |> assign(:any_retrying?, scan_retry_in_progress?(scan_retrying))

    ~H"""
    <details
      :if={@scan_errors != []}
      id="device-scan-recovery-panel"
      open={@scan_recovery_open}
      class="bac-collapsible mx-5 mt-3 rounded-lg border border-[var(--bac-amber)]/30 bg-[var(--bac-amber)]/8 px-4 py-3"
    >
      <summary
        phx-click="toggle_scan_recovery_panel"
        class="bac-collapsible-summary text-sm font-medium text-[var(--bac-amber)]"
      >
        <.icon name="hero-chevron-right" class="bac-collapsible-icon size-4 shrink-0" />
        <span>
          {t(@locale, @locale_version, "%{count} Objekte konnten nicht gelesen werden",
            count: length(@scan_errors)
          )}
        </span>
      </summary>
      <p :if={@any_retry_available?} class="bac-collapsible-content text-xs bac-text-muted mt-2">
        {t(
          @locale,
          @locale_version,
          "Einige Objekte haben ungültige BACnet-Werte. Sie können sie mit reduzierter Validierung erneut lesen."
        )}
      </p>
      <p :if={!@any_retry_available?} class="bac-collapsible-content text-xs bac-text-muted mt-2">
        {t(
          @locale,
          @locale_version,
          "Diese Objekte konnten nicht gelesen werden. Die Fehler sind unten aufgelistet."
        )}
      </p>
      <div
        :if={@any_retrying?}
        id="device-scan-recovery-status"
        role="status"
        aria-live="polite"
        class="bac-collapsible-content mt-3 flex items-center gap-2 rounded-md border border-[var(--bac-accent)]/25 bg-[var(--bac-accent)]/8 px-3 py-2 text-xs text-[var(--bac-text)]"
      >
        <.icon name="hero-arrow-path" class="size-3.5 shrink-0 animate-spin text-[var(--bac-accent)]" />
        <span>
          {t(
            @locale,
            @locale_version,
            "Objekte werden mit reduzierter Validierung nachgelesen…"
          )}
        </span>
      </div>
      <div
        :if={
          @value_bulk_available? or @ignore_invalid_bulk_available? or @all_bulk_available? or
            @maximal_bulk_available?
        }
        class="bac-collapsible-content mt-3 flex flex-wrap gap-2"
      >
        <button
          :if={@value_bulk_available?}
          type="button"
          id="device-scan-recovery-bulk-value"
          phx-click="retry_all_scan_objects"
          phx-value-skip-mode="value"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@any_retrying?}
          class={[
            "bac-btn bac-btn-sm",
            @any_retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon
            :if={@any_retrying?}
            name="hero-arrow-path"
            class="size-3.5 animate-spin"
          />
          {t(@locale, @locale_version, "Alle: Wertvalidierung überspringen")}
        </button>
        <button
          :if={@ignore_invalid_bulk_available?}
          type="button"
          id="device-scan-recovery-bulk-ignore-invalid"
          phx-click="retry_all_scan_objects"
          phx-value-skip-mode="ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@any_retrying?}
          class={[
            "bac-btn bac-btn-sm",
            @any_retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon
            :if={@any_retrying?}
            name="hero-arrow-path"
            class="size-3.5 animate-spin"
          />
          {t(@locale, @locale_version, "Alle: Ungültige Eigenschaften auslassen")}
        </button>
        <button
          :if={@all_bulk_available?}
          type="button"
          id="device-scan-recovery-bulk-all"
          phx-click="retry_all_scan_objects"
          phx-value-skip-mode="all"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@any_retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @any_retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon
            :if={@any_retrying?}
            name="hero-arrow-path"
            class="size-3.5 animate-spin"
          />
          {t(@locale, @locale_version, "Alle: Validierung überspringen")}
        </button>
        <button
          :if={@maximal_bulk_available?}
          type="button"
          id="device-scan-recovery-bulk-maximal"
          phx-click="retry_all_scan_objects"
          phx-value-skip-mode="skip-all-and-ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@any_retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @any_retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon
            :if={@any_retrying?}
            name="hero-arrow-path"
            class="size-3.5 animate-spin"
          />
          {t(@locale, @locale_version, "Alle: Maximal nachlesen")}
        </button>
      </div>
      <ul class="bac-collapsible-content mt-3 space-y-3">
        <li
          :for={{entry, index} <- Enum.with_index(@scan_errors, 1)}
          id={"device-scan-recovery-#{index}"}
          class="rounded-lg border border-[var(--bac-border)]/60 bg-[var(--bac-surface)]/60 px-3 py-2.5"
        >
          <div class="flex flex-wrap items-start gap-x-2 gap-y-1 min-w-0">
            <span class="bac-mono text-sm text-[var(--bac-text)]">{entry.object}</span>
            <span class="text-xs text-[var(--bac-amber)]">
              {error_entry_text(entry, @locale, @locale_version)}
            </span>
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
              phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
              disabled={@any_retrying?}
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
              :if={:ignore_invalid in entry.retry_modes}
              type="button"
              id={"device-scan-recovery-ignore-invalid-#{index}"}
              phx-click="retry_scan_object"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-skip-mode="ignore-invalid"
              phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
              disabled={@any_retrying?}
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
              {t(@locale, @locale_version, "Ungültige Eigenschaften auslassen")}
            </button>
            <button
              :if={true in entry.retry_modes}
              type="button"
              id={"device-scan-recovery-all-#{index}"}
              phx-click="retry_scan_object"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-skip-mode="all"
              phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
              disabled={@any_retrying?}
              class={[
                "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
                retrying?(@scan_retrying, entry.key) && "opacity-60 cursor-wait"
              ]}
            >
              <.icon
                :if={retrying?(@scan_retrying, entry.key)}
                name="hero-arrow-path"
                class="size-3.5 animate-spin"
              />
              {t(@locale, @locale_version, "Alle Validierung überspringen")}
            </button>
            <button
              :if={:skip_all_and_ignore_invalid in entry.retry_modes}
              type="button"
              id={"device-scan-recovery-maximal-#{index}"}
              phx-click="retry_scan_object"
              phx-value-type={entry.type}
              phx-value-instance={entry.instance}
              phx-value-skip-mode="skip-all-and-ignore-invalid"
              phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
              disabled={@any_retrying?}
              class={[
                "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
                retrying?(@scan_retrying, entry.key) && "opacity-60 cursor-wait"
              ]}
            >
              <.icon
                :if={retrying?(@scan_retrying, entry.key)}
                name="hero-arrow-path"
                class="size-3.5 animate-spin"
              />
              {t(@locale, @locale_version, "Maximal nachlesen")}
            </button>
          </div>
          <p :if={:ignore_invalid in entry.retry_modes} class="mt-1.5 text-xs bac-text-faint">
            {t(
              @locale,
              @locale_version,
              "Ungültige Eigenschaften auslassen entfernt Eigenschaften, die nicht dekodiert werden können; die übrigen bleiben lesbar."
            )}
          </p>
          <p :if={true in entry.retry_modes} class="mt-1.5 text-xs bac-text-faint">
            {t(
              @locale,
              @locale_version,
              "Alle Validierung überspringen kann fehlerhafte Datentypen akzeptieren und sollte nur bei Bedarf verwendet werden."
            )}
          </p>
          <p
            :if={:skip_all_and_ignore_invalid in entry.retry_modes}
            class="mt-1.5 text-xs bac-text-faint"
          >
            {t(
              @locale,
              @locale_version,
              "Maximal nachlesen kombiniert das Auslassen ungültiger Eigenschaften mit dem Überspringen der Validierung."
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
            reason: Map.get(entry, :reason),
            message: Map.get(entry, :message),
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

  defp bulk_retry_available?(scan_errors, skip_mode) do
    Enum.any?(scan_errors, fn entry -> skip_mode in entry.retry_modes end)
  end

  defp scan_retry_in_progress?(retrying) when is_map(retrying) do
    Enum.any?(retrying, fn {_key, in_progress?} -> in_progress? end)
  end

  defp scan_retry_in_progress?(_retrying), do: false

  defp retrying?(retrying, key) when is_map(retrying), do: Map.get(retrying, key, false)
  defp retrying?(_retrying, _key), do: false

  defp error_entry_text(entry, locale, locale_version) do
    case Map.get(entry, :reason) do
      reason when not is_nil(reason) ->
        BacViewWeb.ErrorMessageText.format(reason, locale, locale_version)

      _reason ->
        Map.get(entry, :message, "")
    end
  end

  # Full device load failed on the device object — user must choose a recovery mode
  # (or stop). Strict re-load without a mode stays available via the normal reload control.
  attr(:recovery, :map, default: nil)
  attr(:retrying?, :boolean, default: false)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def device_load_recovery_panel(assigns) do
    recovery = Map.get(assigns, :recovery)
    retry_modes = if is_map(recovery), do: Map.get(recovery, :retry_modes, []), else: []

    assigns =
      assigns
      |> assign(:recovery, recovery)
      |> assign(:retry_modes, retry_modes)
      |> assign(:retrying?, Map.get(assigns, :retrying?, false))
      |> assign(:has_modes?, retry_modes != [])

    ~H"""
    <div
      :if={@recovery && @has_modes?}
      id="device-load-recovery-panel"
      class="mx-5 mt-3 rounded-lg border border-[var(--bac-amber)]/30 bg-[var(--bac-amber)]/8 px-4 py-3"
      role="region"
      aria-label={t(@locale, @locale_version, "Geräteladen mit reduzierter Validierung")}
    >
      <p class="text-sm font-medium text-[var(--bac-amber)]">
        {t(@locale, @locale_version, "Geräteobjekt konnte nicht gelesen werden")}
      </p>
      <p class="mt-1 text-xs bac-text-muted">
        {error_entry_text(@recovery, @locale, @locale_version)}
      </p>
      <p class="mt-2 text-xs bac-text-muted">
        {t(
          @locale,
          @locale_version,
          "Sie können das Gerät mit reduzierter Validierung erneut laden oder abbrechen."
        )}
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          :if={:value in @retry_modes}
          type="button"
          id="device-load-recovery-value"
          phx-click="retry_device_load"
          phx-value-skip-mode="value"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={["bac-btn bac-btn-sm", @retrying? && "opacity-60 cursor-wait"]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Wertvalidierung überspringen")}
        </button>
        <button
          :if={:ignore_invalid in @retry_modes}
          type="button"
          id="device-load-recovery-ignore-invalid"
          phx-click="retry_device_load"
          phx-value-skip-mode="ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={["bac-btn bac-btn-sm", @retrying? && "opacity-60 cursor-wait"]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Ungültige Eigenschaften auslassen")}
        </button>
        <button
          :if={true in @retry_modes}
          type="button"
          id="device-load-recovery-all"
          phx-click="retry_device_load"
          phx-value-skip-mode="all"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Alle Validierung überspringen")}
        </button>
        <button
          :if={:skip_all_and_ignore_invalid in @retry_modes}
          type="button"
          id="device-load-recovery-maximal"
          phx-click="retry_device_load"
          phx-value-skip-mode="skip-all-and-ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Maximal nachlesen")}
        </button>
      </div>
      <p :if={:ignore_invalid in @retry_modes} class="mt-2 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Ungültige Eigenschaften auslassen entfernt Eigenschaften, die nicht dekodiert werden können; die übrigen bleiben lesbar."
        )}
      </p>
      <p :if={true in @retry_modes} class="mt-1.5 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Alle Validierung überspringen kann fehlerhafte Datentypen akzeptieren und sollte nur bei Bedarf verwendet werden."
        )}
      </p>
      <p :if={:skip_all_and_ignore_invalid in @retry_modes} class="mt-1.5 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Maximal nachlesen kombiniert das Auslassen ungültiger Eigenschaften mit dem Überspringen der Validierung."
        )}
      </p>
    </div>
    """
  end

  attr(:recovery, :map, default: nil)
  attr(:retrying?, :boolean, default: false)
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def property_load_recovery_panel(assigns) do
    recovery = Map.get(assigns, :recovery)
    retry_modes = if is_map(recovery), do: Map.get(recovery, :retry_modes, []), else: []

    assigns =
      assigns
      |> assign(:recovery, recovery)
      |> assign(:retry_modes, retry_modes)
      |> assign(:retrying?, Map.get(assigns, :retrying?, false))
      |> assign(:has_modes?, retry_modes != [])

    ~H"""
    <div
      :if={@recovery && @has_modes?}
      id="property-load-recovery-panel"
      class="mx-0 mt-3 rounded-lg border border-[var(--bac-amber)]/30 bg-[var(--bac-amber)]/8 px-4 py-3"
      role="region"
      aria-label={t(@locale, @locale_version, "Eigenschaften mit reduzierter Validierung lesen")}
    >
      <p class="text-sm font-medium text-[var(--bac-amber)]">
        {t(@locale, @locale_version, "Eigenschaften konnten nicht gelesen werden")}
      </p>
      <p class="mt-1 text-xs bac-text-muted">
        {error_entry_text(@recovery, @locale, @locale_version)}
      </p>
      <p class="mt-2 text-xs bac-text-muted">
        {t(
          @locale,
          @locale_version,
          "Sie können die Eigenschaften mit reduzierter Validierung erneut lesen oder abbrechen."
        )}
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          :if={:value in @retry_modes}
          type="button"
          id="property-load-recovery-value"
          phx-click="retry_property_load"
          phx-value-skip-mode="value"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={["bac-btn bac-btn-sm", @retrying? && "opacity-60 cursor-wait"]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Wertvalidierung überspringen")}
        </button>
        <button
          :if={:ignore_invalid in @retry_modes}
          type="button"
          id="property-load-recovery-ignore-invalid"
          phx-click="retry_property_load"
          phx-value-skip-mode="ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={["bac-btn bac-btn-sm", @retrying? && "opacity-60 cursor-wait"]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Ungültige Eigenschaften auslassen")}
        </button>
        <button
          :if={true in @retry_modes}
          type="button"
          id="property-load-recovery-all"
          phx-click="retry_property_load"
          phx-value-skip-mode="all"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Alle Validierung überspringen")}
        </button>
        <button
          :if={:skip_all_and_ignore_invalid in @retry_modes}
          type="button"
          id="property-load-recovery-maximal"
          phx-click="retry_property_load"
          phx-value-skip-mode="skip-all-and-ignore-invalid"
          phx-disable-with={t(@locale, @locale_version, "Wird nachgelesen…")}
          disabled={@retrying?}
          class={[
            "bac-btn bac-btn-sm border-[var(--bac-amber)]/40 text-[var(--bac-amber)] hover:bg-[var(--bac-amber)]/10",
            @retrying? && "opacity-60 cursor-wait"
          ]}
        >
          <.icon :if={@retrying?} name="hero-arrow-path" class="size-3.5 animate-spin" />
          {t(@locale, @locale_version, "Maximal nachlesen")}
        </button>
      </div>
      <p :if={:ignore_invalid in @retry_modes} class="mt-2 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Ungültige Eigenschaften auslassen entfernt Eigenschaften, die nicht dekodiert werden können; die übrigen bleiben lesbar."
        )}
      </p>
      <p :if={true in @retry_modes} class="mt-1.5 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Alle Validierung überspringen kann fehlerhafte Datentypen akzeptieren und sollte nur bei Bedarf verwendet werden."
        )}
      </p>
      <p :if={:skip_all_and_ignore_invalid in @retry_modes} class="mt-1.5 text-xs bac-text-faint">
        {t(
          @locale,
          @locale_version,
          "Maximal nachlesen kombiniert das Auslassen ungültiger Eigenschaften mit dem Überspringen der Validierung."
        )}
      </p>
    </div>
    """
  end
end
