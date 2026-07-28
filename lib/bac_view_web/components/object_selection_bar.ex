defmodule BacViewWeb.ObjectSelectionBar do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  attr(:count, :integer, required: true)
  attr(:write_priority, :integer, default: 8)
  attr(:bulk_resetting, :boolean, default: false)

  def selection_bar(assigns) do
    ~H"""
    <div
      id="object-selection-bar"
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 mb-4 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-surface)]"
    >
      <span class="text-sm font-medium text-[var(--bac-text)]">
        {t(@locale, @locale_version, "%{count} ausgewählt", count: @count)}
      </span>
      <div class="flex flex-wrap items-center gap-2 ml-auto">
        <button
          type="button"
          phx-click="subscribe_selected_cov"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-primary bac-btn-sm"
        >
          <.icon name="hero-signal" class="size-4" />
          {t(@locale, @locale_version, "COV abonnieren")}
        </button>
        <button
          type="button"
          phx-click="unsubscribe_selected_cov"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "COV kündigen")}
        </button>
        <div class="bac-btn-split">
          <button
            type="button"
            id="reset-selected-priority"
            phx-click="open_reset_priority_confirm"
            disabled={@bulk_resetting}
            class="bac-btn bac-btn-ghost bac-btn-sm bac-btn-split-start"
            title={
              t(
                @locale,
                @locale_version,
                "Priorität %{priority} bei ausgewählten commandable Objekten zurücksetzen (NULL)",
                priority: @write_priority
              )
            }
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" />
            {t(@locale, @locale_version, "Priorität %{priority} zurücksetzen",
              priority: @write_priority
            )}
          </button>
          <details
            id="reset-selected-priority-menu"
            phx-hook="DetailsOutsideClose"
            class={[
              "bac-btn-split-details",
              @bulk_resetting && "pointer-events-none opacity-45"
            ]}
          >
            <summary
              class="bac-btn bac-btn-ghost bac-btn-sm bac-btn-split-end bac-btn-split-toggle"
              title={t(@locale, @locale_version, "Andere Priorität wählen und zurücksetzen")}
              aria-label={t(@locale, @locale_version, "Andere Priorität wählen und zurücksetzen")}
            >
              <.icon name="hero-chevron-down" class="size-3.5 opacity-70" />
            </summary>
            <div class="bac-btn-split-menu" role="menu">
              <button
                type="button"
                id="reset-selected-priority-other"
                role="menuitem"
                phx-click="open_reset_priority_choose"
                disabled={@bulk_resetting}
                class="bac-btn-split-menu-item"
                title={t(@locale, @locale_version, "Andere Priorität wählen und zurücksetzen")}
              >
                {t(@locale, @locale_version, "Andere Priorität…")}
              </button>
            </div>
          </details>
        </div>
        <button
          type="button"
          phx-click="clear_selection"
          disabled={@bulk_resetting}
          class="bac-btn bac-btn-ghost bac-btn-sm"
        >
          {t(@locale, @locale_version, "Auswahl aufheben")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Keys suitable for present_value COV (un)subscribe from a multi-object selection.

  Returns `{keys, skipped}` where `skipped` is how many selectable selected objects
  have no `present_value` (they are dropped silently before the network call).
  """
  @spec cov_present_value_keys(MapSet.t(), MapSet.t(), [map()]) ::
          {[{atom() | integer(), non_neg_integer()}], non_neg_integer()}
  def cov_present_value_keys(selected_keys, selectable_keys, objects)
      when is_list(objects) do
    candidates = MapSet.intersection(selected_keys, selectable_keys)

    with_pv =
      objects
      |> Enum.filter(fn obj ->
        MapSet.member?(candidates, {obj.type, obj.instance}) and
          not is_nil(Map.get(obj, :present_value))
      end)
      |> Enum.map(fn obj -> {obj.type, obj.instance} end)
      |> MapSet.new()

    skipped = MapSet.size(candidates) - MapSet.size(with_pv)
    {MapSet.to_list(with_pv), skipped}
  end
end
