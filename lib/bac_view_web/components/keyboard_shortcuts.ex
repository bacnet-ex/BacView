defmodule BacViewWeb.KeyboardShortcuts do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:show, :boolean, default: false)
  attr(:context, :atom, default: :dashboard, values: [:dashboard, :device, :object])

  def keyboard_shortcuts(assigns) do
    ~H"""
    <div :if={@show} id="keyboard-shortcuts-modal" class="bac-modal-backdrop">
      <button
        type="button"
        class="bac-modal-overlay"
        phx-click="toggle_shortcuts"
        aria-label={t(@locale, @locale_version, "Schliessen")}
      />
      <div class="bac-modal" role="dialog" aria-modal="true">
        <div class="bac-modal-body space-y-4">
          <div class="flex items-center gap-3">
            <div class="bac-logo-mark">
              <.icon name="hero-command-line" class="size-4" />
            </div>
            <h2 class="text-lg font-semibold">{t(@locale, @locale_version, "Tastaturkürzel")}</h2>
          </div>

          <ul class="text-sm space-y-2.5">
            <.shortcut_row keys="?" desc={t(@locale, @locale_version, "Diese Hilfe ein-/ausblenden")} />
            <.shortcut_row keys="/" desc={t(@locale, @locale_version, "Suche fokussieren")} />
            <.shortcut_row keys="r" desc={refresh_label(@context, @locale, @locale_version)} />
            <.shortcut_row
              :if={@context == :device}
              keys="1 – 4"
              desc={t(@locale, @locale_version, "Tabs wechseln (Hierarchie, Objekte, …)")}
            />
            <.shortcut_row
              :if={@context == :device}
              keys="Shift + 1 – 3"
              desc={t(@locale, @locale_version, "Untertabs im Alarm-Tab wechseln")}
            />
            <.shortcut_row
              :if={@context in [:device, :object]}
              keys="0"
              desc={go_up_label(@context, @locale, @locale_version)}
            />
            <.shortcut_row keys="Esc" desc={t(@locale, @locale_version, "Hilfe schliessen")} />
          </ul>

          <.device_list_shortcuts
            :if={@context == :device}
            locale={@locale}
            locale_version={@locale_version}
          />

          <div class="flex justify-end pt-2">
            <button type="button" phx-click="toggle_shortcuts" class="bac-btn bac-btn-primary bac-btn-sm">
              {t(@locale, @locale_version, "Schliessen")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp device_list_shortcuts(assigns) do
    ~H"""
    <div class="space-y-3 border-t border-[var(--bac-border)] pt-4">
      <h3 class="text-xs font-semibold uppercase tracking-wide bac-text-faint">
        {t(@locale, @locale_version, "Listen-Aktionen")}
      </h3>

      <.shortcut_group
        title={t(@locale, @locale_version, "Objektliste")}
        rows={[
          %{
            keys: "c",
            desc: t(@locale, @locale_version, "COV abonnieren (Auswahl)")
          },
          %{
            keys: "Shift + c",
            desc: t(@locale, @locale_version, "Alle PV abonnieren")
          },
          %{
            keys: "u",
            desc: t(@locale, @locale_version, "COV kündigen (Auswahl)")
          },
          %{
            keys: "Shift + u",
            desc: t(@locale, @locale_version, "Alle kündigen")
          }
        ]}
      />

      <.shortcut_group
        title={t(@locale, @locale_version, "Abonnements")}
        rows={[
          %{
            keys: "c",
            desc: t(@locale, @locale_version, "Erneut abonnieren (Auswahl)")
          },
          %{
            keys: "Shift + c",
            desc: t(@locale, @locale_version, "Alle PV abonnieren")
          },
          %{
            keys: "u",
            desc: t(@locale, @locale_version, "Ausgewählte kündigen")
          },
          %{
            keys: "Shift + u",
            desc: t(@locale, @locale_version, "Alle kündigen")
          }
        ]}
      />

      <.shortcut_group
        title={t(@locale, @locale_version, "Aktive Alarme")}
        rows={[
          %{
            keys: "c",
            desc: t(@locale, @locale_version, "Empfängerliste eintragen")
          },
          %{
            keys: "u",
            desc: t(@locale, @locale_version, "Empfängerliste entfernen")
          }
        ]}
      />

      <.shortcut_group
        title={t(@locale, @locale_version, "Ereignisinformation")}
        rows={[
          %{
            keys: "e",
            desc: t(@locale, @locale_version, "Ereignisse abrufen")
          }
        ]}
      />
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:rows, :list, required: true)

  defp shortcut_group(assigns) do
    ~H"""
    <div class="space-y-2">
      <p class="text-xs font-medium text-[var(--bac-text)]">{@title}</p>
      <ul class="space-y-2">
        <.shortcut_row :for={row <- @rows} keys={row.keys} desc={row.desc} />
      </ul>
    </div>
    """
  end

  attr(:keys, :string, required: true)
  attr(:desc, :string, required: true)

  defp shortcut_row(assigns) do
    ~H"""
    <li class="flex items-center justify-between gap-4">
      <span class="bac-text-muted">{@desc}</span>
      <kbd class="bac-kbd">{@keys}</kbd>
    </li>
    """
  end

  defp refresh_label(:dashboard, locale, locale_version),
    do: t(locale, locale_version, "Netzwerk scannen")

  defp refresh_label(:device, locale, locale_version),
    do: t(locale, locale_version, "Gerät aktualisieren")

  defp refresh_label(:object, locale, locale_version),
    do: t(locale, locale_version, "Objekt vom Gerät neu lesen")

  defp go_up_label(:device, locale, locale_version),
    do: t(locale, locale_version, "Zur Startseite")

  defp go_up_label(:object, locale, locale_version),
    do: t(locale, locale_version, "Zurück zur Objektliste")
end
