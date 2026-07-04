defmodule BacViewWeb.StatusFlagsIcons do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BACnet.Protocol.StatusFlags

  @filter_flags [:in_alarm, :fault, :overridden, :out_of_service, :none]
  @display_flags [:in_alarm, :fault, :overridden, :out_of_service]

  attr(:flags, :any, default: nil)
  attr(:counts, :map, default: %{})
  attr(:mode, :atom, default: :active, values: [:active, :all, :stats, :counts])

  def status_flags_icons(assigns) do
    assigns =
      assigns
      |> assign(:active, active_flags(assigns.flags))
      |> assign(:resolved_flags, resolve_flags(assigns.flags))
      |> assign(:display_flags, @display_flags)

    ~H"""
    <%= if @mode == :counts do %>
      <span
        :if={status_flag_count_entries(@counts) == []}
        class="bac-text-faint text-xs whitespace-nowrap"
      >
        —
      </span>
      <span
        :if={status_flag_count_entries(@counts) != []}
        class="inline-flex flex-wrap items-center justify-end gap-2"
        aria-label={count_summary_aria_label(@counts, @locale, @locale_version)}
      >
        <span
          :for={{flag, count} <- status_flag_count_entries(@counts)}
          class={["inline-flex items-center gap-1 text-xs font-medium whitespace-nowrap", flag_class(flag)]}
          title={count_summary_title(flag, count, @locale, @locale_version)}
        >
          <.icon name={flag_icon(flag)} class="size-3.5" />
          {count}
        </span>
      </span>
    <% else %>
    <%= if @mode == :stats do %>
      <div
        class="flex flex-wrap items-center justify-center gap-2 shrink-0"
        role="group"
        aria-label={all_flags_aria_label(@resolved_flags, @locale, @locale_version)}
      >
        <div
          :for={flag <- @display_flags}
          class={[
            "bac-stat bac-stat-flag flex flex-col items-center text-center",
            stat_flag_box_class(@resolved_flags, flag)
          ]}
          title={all_flag_title(@resolved_flags, flag, @locale, @locale_version)}
        >
          <p class="bac-stat-label w-full">{flag_label(flag, @locale, @locale_version)}</p>
          <div class={["bac-stat-flag-icon", flag_icon_class(@resolved_flags, flag)]}>
            <.icon name={flag_icon(flag)} class="size-8" />
          </div>
        </div>
      </div>
    <% else %>
      <%= if @mode == :all do %>
        <span
          class="inline-flex items-center gap-1.5"
          aria-label={all_flags_aria_label(@resolved_flags, @locale, @locale_version)}
        >
          <span
            :for={flag <- @display_flags}
            class={["inline-flex", flag_icon_class(@resolved_flags, flag)]}
            title={all_flag_title(@resolved_flags, flag, @locale, @locale_version)}
          >
            <.icon name={flag_icon(flag)} class="size-4" />
          </span>
        </span>
      <% else %>
      <span
        :if={@active != []}
        class="inline-flex items-center gap-1.5"
        aria-label={aria_label(@active, @locale, @locale_version)}
      >
        <span
          :for={flag <- @active}
          class={["inline-flex", flag_class(flag)]}
          title={flag_title(flag, @locale, @locale_version)}
        >
          <.icon name={flag_icon(flag)} class="size-4" />
        </span>
      </span>
      <span :if={@active == []} class="bac-text-faint">—</span>
      <% end %>
    <% end %>
    <% end %>
    """
  end

  @doc false
  @spec filter_flags() :: [atom()]
  def filter_flags(), do: @filter_flags

  @doc false
  @spec active_flags(term()) :: [atom()]
  def active_flags(%StatusFlags{} = flags) do
    Enum.filter([:in_alarm, :fault, :overridden, :out_of_service], &Map.fetch!(flags, &1))
  end

  def active_flags(_flags), do: []

  @doc false
  @spec resolve_flags(term()) :: StatusFlags.t()
  def resolve_flags(%StatusFlags{} = flags), do: flags

  def resolve_flags(_flags),
    do: %StatusFlags{in_alarm: false, fault: false, overridden: false, out_of_service: false}

  @doc false
  @spec flag_active?(StatusFlags.t(), atom()) :: boolean()
  def flag_active?(%StatusFlags{} = flags, flag) when flag in @display_flags,
    do: Map.fetch!(flags, flag)

  @doc false
  @spec flag_icon_class(StatusFlags.t(), atom()) :: String.t()
  def flag_icon_class(flags, flag) do
    if flag_active?(flags, flag),
      do: flag_class(flag),
      else: "text-[var(--bac-text-faint)] opacity-40"
  end

  @doc false
  @spec stat_flag_box_class(StatusFlags.t(), atom()) :: String.t()
  def stat_flag_box_class(flags, flag) do
    if flag_active?(flags, flag), do: "bac-stat-flag-active", else: ""
  end

  @doc false
  @spec icon_name(atom()) :: String.t()
  def icon_name(:in_alarm), do: "hero-bell-alert"
  def icon_name(:fault), do: "hero-exclamation-triangle"
  def icon_name(:overridden), do: "hero-hand-raised"
  def icon_name(:out_of_service), do: "hero-pause-circle"
  def icon_name(:none), do: "hero-check-circle"
  def icon_name(_in_alarm), do: "hero-question-mark-circle"

  defp flag_icon(flag), do: icon_name(flag)

  @doc false
  @spec flag_class(atom()) :: String.t()
  def flag_class(:in_alarm), do: "text-[var(--bac-orange)]"
  def flag_class(:fault), do: "text-[var(--bac-rose)]"
  def flag_class(:overridden), do: "text-[var(--bac-violet)]"
  def flag_class(:out_of_service), do: "text-[var(--bac-amber)]"
  def flag_class(:none), do: "text-[var(--bac-emerald)]"
  def flag_class(_orange), do: "bac-text-faint"

  @doc false
  @spec flag_label(atom(), String.t(), integer()) :: String.t()
  def flag_label(:in_alarm, locale, lv), do: t(locale, lv, "In Alarm")
  def flag_label(:fault, locale, lv), do: t(locale, lv, "Störung")
  def flag_label(:overridden, locale, lv), do: t(locale, lv, "Übersteuert")
  def flag_label(:out_of_service, locale, lv), do: t(locale, lv, "Ausser Betrieb")
  def flag_label(:none, locale, lv), do: t(locale, lv, "Normal")
  def flag_label(flag, _locale, _lv), do: Atom.to_string(flag)

  defp flag_title(flag, locale, lv), do: flag_label(flag, locale, lv)

  defp aria_label(flags, locale, lv) do
    Enum.map_join(flags, ", ", &flag_title(&1, locale, lv))
  end

  defp all_flag_title(flags, flag, locale, lv) do
    state =
      if flag_active?(flags, flag),
        do: t(locale, lv, "aktiv"),
        else: t(locale, lv, "inaktiv")

    "#{flag_title(flag, locale, lv)} (#{state})"
  end

  defp all_flags_aria_label(%StatusFlags{} = flags, locale, lv) do
    Enum.map_join(@display_flags, ", ", &all_flag_title(flags, &1, locale, lv))
  end

  defp status_flag_count_entries(counts) when is_map(counts) do
    @display_flags
    |> Enum.map(fn flag -> {flag, Map.get(counts, flag, 0)} end)
    |> Enum.reject(fn {_flag, count} -> count == 0 end)
  end

  defp status_flag_count_entries(_counts), do: []

  defp count_summary_title(flag, count, locale, lv) do
    t(locale, lv, "%{count} %{label}", count: count, label: flag_label(flag, locale, lv))
  end

  defp count_summary_aria_label(counts, locale, lv) do
    counts
    |> status_flag_count_entries()
    |> Enum.map_join(", ", fn {flag, count} -> count_summary_title(flag, count, locale, lv) end)
  end
end
