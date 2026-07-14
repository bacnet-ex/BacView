defmodule BacViewWeb.SubscriptionsPanel do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.CovNotificationChart
  alias BacViewWeb.CovNotificationTable
  alias BacViewWeb.DeviceUrl
  alias BacViewWeb.SortHeader
  alias BacViewWeb.SubscriptionTable

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:cov_view, :string, required: true)
  attr(:cov_view_paths, :map, required: true)
  attr(:subscriptions, :list, required: true)
  attr(:objects, :list, default: [])
  attr(:cov_notifications, :list, required: true)
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:search, :string, default: "")
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:notifications_sort_by, :string, default: nil)
  attr(:notifications_sort_dir, :atom, default: :desc)

  def subscriptions_panel(assigns) do
    ~H"""
    <div class="space-y-5 min-w-0 w-full">
      <div class="bac-tabs">
        <.link
          patch={@cov_view_paths["subscriptions"]}
          class={["bac-tab", @cov_view == "subscriptions" && "bac-tab-active"]}
          id="cov-subtab-subscriptions"
        >
          <.icon name="hero-signal" class="size-4" />
          {t(@locale, @locale_version, "Abonnements")}
          <span :if={length(@subscriptions) > 0} class="bac-badge bac-badge-sm bac-badge-success">
            {length(@subscriptions)}
          </span>
        </.link>
        <.link
          patch={@cov_view_paths["notifications"]}
          class={["bac-tab", @cov_view == "notifications" && "bac-tab-active"]}
          id="cov-subtab-notifications"
        >
          <.icon name="hero-inbox-arrow-down" class="size-4" />
          {t(@locale, @locale_version, "Meldungen")}
          <span
            :if={length(@cov_notifications) > 0}
            class="bac-badge bac-badge-sm bac-badge-ghost"
          >
            {length(@cov_notifications)}
          </span>
        </.link>
      </div>

      <.subscriptions_list_panel
        :if={@cov_view == "subscriptions"}
        device_id={@device_id}
        list_opts={@list_opts}
        subscriptions={@subscriptions}
        objects={@objects}
        selected_keys={@selected_keys}
        search={@search}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        locale={@locale}
        locale_version={@locale_version}
      />

      <.cov_notifications_panel
        :if={@cov_view == "notifications"}
        device_id={@device_id}
        list_opts={@list_opts}
        notifications={@cov_notifications}
        sort_by={@notifications_sort_by}
        sort_dir={@notifications_sort_dir}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:subscriptions, :list, required: true)
  attr(:objects, :list, default: [])
  attr(:selected_keys, :any, default: MapSet.new())
  attr(:search, :string, default: "")
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp subscriptions_list_panel(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_subscriptions,
        SubscriptionTable.list_subscriptions(
          assigns.subscriptions,
          assigns.objects,
          assigns.search,
          assigns.sort_by,
          assigns.sort_dir
        )
      )

    ~H"""
    <div class="space-y-4 min-w-0 w-full" id="cov-panel-subscriptions">
      <input
        :if={@subscriptions != []}
        id="subscription-search"
        type="search"
        name="search"
        value={@search}
        placeholder={
          t(@locale, @locale_version, "Abonnements suchen… (-Begriff zum Ausschliessen)")
        }
        phx-keyup="search_subscriptions"
        phx-debounce="200"
        class="bac-input bac-input-sm max-w-md"
      />

      <div :if={@subscriptions != []} class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          id="unsubscribe-all-cov"
          phx-click="unsubscribe_all_cov"
          class="bac-btn bac-btn-ghost bac-btn-sm text-[var(--bac-rose)]"
        >
          <.icon name="hero-signal-slash" class="size-4" />
          {t(@locale, @locale_version, "Alle kündigen")}
        </button>
      </div>

      <p :if={@subscriptions == []} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Keine aktiven COV-Abonnements.")}
      </p>

      <p
        :if={@subscriptions != [] and @sorted_subscriptions == []}
        class="text-sm bac-text-muted py-12 text-center"
      >
        {t(@locale, @locale_version, "Keine Treffer")}
      </p>

      <div :if={@sorted_subscriptions != []} class="bac-table-wrap">
        <table class="bac-table" id="cov-subscriptions-table">
          <colgroup>
            <col class="w-8" />
            <col class="w-[12%]" />
            <col class="w-[16%]" />
            <col class="w-[10%]" />
            <col class="w-[12%]" />
            <col class="w-[18%]" />
            <col class="w-[10%]" />
            <col class="w-[10%]" />
          </colgroup>
          <thead>
            <tr>
              <th class="w-8 px-2">
                <input
                  id="subscription-select-all"
                  type="checkbox"
                  checked={all_selected?(@selected_keys, @sorted_subscriptions)}
                  phx-click="toggle_select_all_subscriptions"
                  class="bac-checkbox shrink-0"
                  aria-label={t(@locale, @locale_version, "Alle Abonnements auswählen")}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="object"
                  label={t(@locale, @locale_version, "Objekt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="description"
                  label={t(@locale, @locale_version, "Beschreibung")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="property"
                  label={t(@locale, @locale_version, "Eigenschaft")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="last_cov"
                  label={t(@locale, @locale_version, "Letzte COV")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="value"
                  label={t(@locale, @locale_version, "Wert")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_subscriptions"
                  id_prefix="subscription-sort"
                  column="remaining"
                  label={t(@locale, @locale_version, "Verbleibend")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={sub <- @sorted_subscriptions}
              id={"sub-#{sub.device_id}-#{sub.object_id.type}-#{sub.object_id.instance}-#{sub.property}"}
              class={selected?(@selected_keys, sub) && "bac-row-selected"}
            >
              <td
                phx-click="toggle_subscription_selection"
                phx-value-type={sub.object_id.type}
                phx-value-instance={sub.object_id.instance}
                phx-value-property={sub.property}
                class="w-8 px-2 cursor-pointer"
              >
                <input
                  type="checkbox"
                  checked={selected?(@selected_keys, sub)}
                  class="bac-checkbox shrink-0 pointer-events-none"
                  aria-label={t(@locale, @locale_version, "Abonnement auswählen")}
                />
              </td>
              <td
                class="bac-row-clickable min-w-0"
                phx-click={JS.navigate(object_path(@device_id, sub.object_id, @list_opts))}
              >
                <span class="bac-mono">{sub.object_id.type}:{sub.object_id.instance}</span>
                <p
                  :if={sub.object_name}
                  class="text-xs text-[var(--bac-text-muted)] truncate mt-0.5"
                  title={sub.object_name}
                >
                  {sub.object_name}
                </p>
              </td>
              <td
                class="text-[var(--bac-text-muted)] max-w-xs truncate bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, sub.object_id, @list_opts))}
                title={sub.description}
              >
                {sub.description || "—"}
              </td>
              <td class="bac-mono">{sub.property}</td>
              <td class="bac-text-faint">{format_time(sub.last_cov_at)}</td>
              <td class="bac-mono text-[var(--bac-emerald)]">{sub.last_value_formatted || "—"}</td>
              <td class="bac-text-faint">{remaining_label(sub, @locale, @locale_version)}</td>
              <td>
                <div class="flex flex-wrap items-center gap-1">
                  <button
                    :if={CovNotificationChart.trendable_subscription?(@device_id, sub)}
                    type="button"
                    id={"cov-chart-open-#{sub.object_id.type}-#{sub.object_id.instance}-#{sub.property}"}
                    phx-click="open_cov_chart_modal"
                    phx-value-type={sub.object_id.type}
                    phx-value-instance={sub.object_id.instance}
                    phx-value-property={sub.property}
                    class="bac-btn bac-btn-ghost bac-btn-xs"
                  >
                    <.icon name="hero-chart-bar" class="size-3.5" />
                    {t(@locale, @locale_version, "Diagramm")}
                  </button>
                  <button
                    type="button"
                    phx-click="unsubscribe_cov"
                    phx-value-type={sub.object_id.type}
                    phx-value-instance={sub.object_id.instance}
                    phx-value-property={sub.property}
                    class="bac-btn bac-btn-ghost bac-btn-xs text-[var(--bac-rose)]"
                  >
                    {t(@locale, @locale_version, "Kündigen")}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:list_opts, :list, default: [])
  attr(:notifications, :list, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :desc)
  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, required: true)

  defp cov_notifications_panel(assigns) do
    assigns =
      assign(
        assigns,
        :sorted_notifications,
        CovNotificationTable.sorted_notifications(
          assigns.notifications,
          assigns.sort_by,
          assigns.sort_dir
        )
      )

    ~H"""
    <div class="space-y-4 min-w-0 w-full" id="cov-panel-notifications">
      <p :if={@notifications == []} class="text-sm bac-text-muted py-12 text-center">
        {t(@locale, @locale_version, "Noch keine COV-Meldungen empfangen.")}
      </p>

      <div :if={@notifications != []} class="bac-table-wrap">
        <table class="bac-table" id="cov-notifications-table">
          <colgroup>
            <col class="w-[16%]" />
            <col class="w-[18%]" />
            <col class="w-[14%]" />
            <col class="w-[28%]" />
            <col class="w-[12%]" />
            <col class="w-[12%]" />
          </colgroup>
          <thead>
            <tr>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="received"
                  label={t(@locale, @locale_version, "Empfangen")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="object"
                  label={t(@locale, @locale_version, "Objekt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="property"
                  label={t(@locale, @locale_version, "Eigenschaft")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="value"
                  label={t(@locale, @locale_version, "Wert")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="confirmed"
                  label={t(@locale, @locale_version, "Bestätigt")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
              <th>
                <SortHeader.sort_header
                  event="sort_cov_notifications"
                  id_prefix="cov-notification-sort"
                  column="time_remaining"
                  label={t(@locale, @locale_version, "Verbleibend")}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={entry <- @sorted_notifications}
              id={"cov-notification-#{entry.log_id}"}
            >
              <td class="bac-text-faint whitespace-nowrap">
                {format_datetime(entry.received_at)}
              </td>
              <td
                class="bac-mono bac-row-clickable"
                phx-click={JS.navigate(object_path(@device_id, entry.object_id, @list_opts))}
              >
                {entry.object_id.type}:{entry.object_id.instance}
              </td>
              <td class="bac-mono">{entry.property}</td>
              <td class="bac-mono text-[var(--bac-emerald)]">{entry.formatted || "—"}</td>
              <td class="bac-text-faint">
                {confirmed_label(entry.confirmed, @locale, @locale_version)}
              </td>
              <td class="bac-text-faint">{time_remaining_label(entry.time_remaining)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp selected?(keys, sub),
    do: MapSet.member?(keys, {sub.object_id.type, sub.object_id.instance, sub.property})

  defp all_selected?(keys, subscriptions) when is_list(subscriptions) do
    subscriptions != [] and Enum.all?(subscriptions, &selected?(keys, &1))
  end

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt),
    do: BacView.Timezone.format(dt, "%H:%M:%S")

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt),
    do: BacView.Timezone.format(dt, "%Y-%m-%d %H:%M:%S")

  defp confirmed_label(true, locale, lv), do: t(locale, lv, "Ja")
  defp confirmed_label(false, locale, lv), do: t(locale, lv, "Nein")
  defp confirmed_label(_true, locale, lv), do: t(locale, lv, "—")

  defp time_remaining_label(nil), do: "—"
  defp time_remaining_label(sec) when is_integer(sec), do: "#{sec}s"

  defp remaining_label(%{lifetime: 0}, locale, locale_version),
    do: t(locale, locale_version, "Unbegrenzt")

  defp remaining_label(%{expires_at: nil}, _locale, _locale_version), do: "—"

  defp remaining_label(%{expires_at: expires_at}, locale, locale_version) do
    sec = max(0, DateTime.diff(expires_at, DateTime.utc_now(), :second))
    t(locale, locale_version, "%{sec}s", sec: sec)
  end

  defp object_path(device_id, %{type: type, instance: instance}, list_opts) do
    url_opts =
      list_opts
      |> Keyword.delete(:device_id)
      |> Keyword.put(:tab, "subscriptions")

    DeviceUrl.object_path(device_id, type, instance, url_opts)
  end
end
