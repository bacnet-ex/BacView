defmodule BacViewWeb.Shortcuts do
  @moduledoc false

  import Phoenix.LiveView, only: [push_event: 3]

  @digit_codes ~w(Digit1 Digit2 Digit3 Digit4)

  # Assigns that indicate a modal is open. Popups (alarm/COV badges) are not included —
  # only full modals with `.bac-modal-backdrop` that steal typing intent.
  # Order is ESC close priority (first open match wins).
  @blocking_modal_closes [
    {:write_property_modal, "close_write_property_modal"},
    {:write_modal, "close_write_modal"},
    {:reset_priority_modal, "close_reset_priority_modal"},
    {:trend_chart_modal_open, "close_trend_chart_modal"},
    {:cov_chart_modal_open, "close_cov_chart_modal"},
    {:ede_export_modal_open, "close_ede_export_modal"},
    {:device_service_modal, "close_device_service_modal"},
    {:log_viewer_open, "close_log_viewer"},
    {:show_shortcuts, :close_shortcuts}
  ]

  @blocking_modal_assigns Enum.map(@blocking_modal_closes, &elem(&1, 0))

  @spec handle(String.t() | map(), Phoenix.LiveView.Socket.t(), keyword()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle(key, socket, opts \\ [])

  def handle(%{} = params, socket, opts) do
    key = Map.get(params, "key", "")
    handle_key(key, params, socket, opts)
  end

  def handle(key, socket, opts) when is_binary(key) do
    handle_key(key, %{"key" => key, "code" => "", "shift" => false}, socket, opts)
  end

  @doc """
  True when a modal is open and the key is not Escape.

  LiveViews should early-return from `global_keydown` when this is true so digit
  tab switches and action shortcuts do not fire while the user is interacting
  with (or about to type into) a modal.
  """
  @spec ignore_global_shortcut?(map() | String.t(), map()) :: boolean()
  def ignore_global_shortcut?(params_or_key, assigns) do
    blocking_modal_open?(assigns) and not escape_key?(params_or_key)
  end

  @spec blocking_modal_open?(map()) :: boolean()
  def blocking_modal_open?(assigns) when is_map(assigns) do
    Enum.any?(@blocking_modal_assigns, fn key ->
      modal_assign_open?(Map.get(assigns, key))
    end)
  end

  @spec escape_key?(map() | String.t()) :: boolean()
  def escape_key?(%{"key" => "Escape"}), do: true
  def escape_key?("Escape"), do: true
  def escape_key?(_escape_key), do: false

  @doc """
  What Escape should do given current assigns.

  * `{:event, name}` — LiveView should `handle_event(name, %{}, socket)`
  * `:close_shortcuts` — close the shortcuts help overlay
  * `:none` — no blocking modal open
  """
  @spec escape_close_action(map()) :: {:event, String.t()} | :close_shortcuts | :none
  def escape_close_action(assigns) when is_map(assigns) do
    Enum.find_value(@blocking_modal_closes, :none, fn {key, action} ->
      if modal_assign_open?(Map.get(assigns, key)) do
        case action do
          event when is_binary(event) -> {:event, event}
          :close_shortcuts -> :close_shortcuts
        end
      end
    end)
  end

  @doc """
  Close shortcuts help overlay.
  """
  @spec close_shortcuts_help(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close_shortcuts_help(socket), do: assign_shortcuts(socket, false)

  @doc """
  Close the topmost blocking modal on Escape.

  `dispatch` is called with `(event_name, socket)` for LiveView close events
  (e.g. `"close_write_property_modal"`) so existing handlers run unchanged.
  """
  @spec apply_escape_close(Phoenix.LiveView.Socket.t(), (String.t(),
                                                         Phoenix.LiveView.Socket.t() ->
                                                           {:noreply, Phoenix.LiveView.Socket.t()})) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def apply_escape_close(socket, dispatch) when is_function(dispatch, 2) do
    case escape_close_action(socket.assigns) do
      {:event, event} -> dispatch.(event, socket)
      :close_shortcuts -> {:noreply, close_shortcuts_help(socket)}
      :none -> {:noreply, socket}
    end
  end

  defp modal_assign_open?(nil), do: false
  defp modal_assign_open?(false), do: false
  defp modal_assign_open?(_open), do: true

  defp handle_key(key, params, socket, opts) do
    if ignore_global_shortcut?(params, socket.assigns) do
      {:noreply, socket}
    else
      apply_global_shortcut(key, socket, opts)
    end
  end

  defp apply_global_shortcut(key, socket, opts) do
    refresh = Keyword.get(opts, :refresh)
    tabs = Keyword.get(opts, :tabs, %{})

    socket =
      cond do
        key == "?" ->
          toggle_shortcuts(socket)

        key == "/" ->
          push_event(socket, "focus_search", %{})

        refresh_key?(key) and not is_nil(refresh) ->
          apply_refresh(socket, refresh)

        key == "Escape" ->
          close_shortcuts_help(socket)

        Map.has_key?(tabs, key) ->
          Phoenix.Component.assign(socket, :tab, Map.fetch!(tabs, key))

        true ->
          socket
      end

    {:noreply, socket}
  end

  @spec digit_index(String.t()) :: pos_integer() | nil
  def digit_index("Digit" <> digit) when digit in ~w(1 2 3 4), do: String.to_integer(digit)
  def digit_index(_digit), do: nil

  @spec digit_code?(String.t()) :: boolean()
  def digit_code?(code), do: code in @digit_codes

  @spec shift_pressed?(map()) :: boolean()
  def shift_pressed?(%{"shift" => true}), do: true
  def shift_pressed?(_shift_pressed), do: false

  @spec go_up_pressed?(map()) :: boolean()
  def go_up_pressed?(%{"shift" => true}), do: false
  def go_up_pressed?(%{"code" => "Digit0"}), do: true
  def go_up_pressed?(%{"key" => "0"}), do: true
  def go_up_pressed?(_go_up_pressed), do: false

  @spec toggle_shortcuts(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def toggle_shortcuts(socket) do
    assign_shortcuts(socket, not socket.assigns.show_shortcuts)
  end

  defp assign_shortcuts(socket, value) do
    Phoenix.Component.assign(socket, :show_shortcuts, value)
  end

  defp apply_refresh(socket, :scan_network) do
    send(self(), :shortcut_scan)
    socket
  end

  defp apply_refresh(socket, :refresh_device) do
    send(self(), :shortcut_refresh_device)
    socket
  end

  defp apply_refresh(socket, :refresh_object) do
    send(self(), :refresh_properties)
    socket
  end

  defp apply_refresh(socket, _socket), do: socket

  @spec refresh_key?(String.t()) :: boolean()
  def refresh_key?(key) when key in ["r", "R"], do: true
  def refresh_key?(_key), do: false

  @spec letter_key_pressed?(map(), String.t()) :: boolean()
  def letter_key_pressed?(%{"code" => "Key" <> code_letter}, letter) do
    String.upcase(letter) == code_letter
  end

  def letter_key_pressed?(%{"key" => key}, letter) do
    key in [letter, String.upcase(letter)]
  end

  def letter_key_pressed?(_params, _letter), do: false

  @device_shortcuts [
    :subscribe_all_pv,
    :unsubscribe_all_cov,
    :subscribe_selected_cov,
    :unsubscribe_selected_cov,
    :resubscribe_selected_subscriptions,
    :unsubscribe_selected_subscriptions,
    :subscribe_notification_classes,
    :unsubscribe_notification_classes,
    :refresh_alarms
  ]

  @spec device_action(map(), map()) :: {:event, String.t()} | :none
  def device_action(params, assigns) do
    Enum.find_value(@device_shortcuts, :none, fn shortcut ->
      case device_shortcut(shortcut, params, assigns) do
        {:event, _event} = result -> result
        :none -> nil
      end
    end)
  end

  defp device_shortcut(:subscribe_all_pv, params, assigns) do
    if shift_pressed?(params) && letter_key_pressed?(params, "c") &&
         subscribe_all_pv_tab?(assigns) &&
         not assigns.loading && not assigns.bulk_subscribing do
      {:event, "subscribe_all_pv"}
    else
      :none
    end
  end

  defp device_shortcut(:unsubscribe_all_cov, params, assigns) do
    if shift_pressed?(params) && letter_key_pressed?(params, "u") &&
         subscribe_all_pv_tab?(assigns) &&
         not assigns.loading && active_subscriptions?(assigns) do
      {:event, "unsubscribe_all_cov"}
    else
      :none
    end
  end

  defp device_shortcut(:subscribe_selected_cov, params, assigns) do
    if letter_key_pressed?(params, "c") && not shift_pressed?(params) && objects_tab?(assigns) &&
         not assigns.loading && selected_objects?(assigns) do
      {:event, "subscribe_selected_cov"}
    else
      :none
    end
  end

  defp device_shortcut(:unsubscribe_selected_cov, params, assigns) do
    if letter_key_pressed?(params, "u") && not shift_pressed?(params) && objects_tab?(assigns) &&
         not assigns.loading && selected_objects?(assigns) do
      {:event, "unsubscribe_selected_cov"}
    else
      :none
    end
  end

  defp device_shortcut(:resubscribe_selected_subscriptions, params, assigns) do
    if letter_key_pressed?(params, "c") && not shift_pressed?(params) &&
         cov_subscriptions_list?(assigns) && not assigns.loading &&
         selected_subscriptions?(assigns) do
      {:event, "resubscribe_selected_subscriptions"}
    else
      :none
    end
  end

  defp device_shortcut(:unsubscribe_selected_subscriptions, params, assigns) do
    if letter_key_pressed?(params, "u") && not shift_pressed?(params) &&
         cov_subscriptions_list?(assigns) && not assigns.loading &&
         selected_subscriptions?(assigns) do
      {:event, "unsubscribe_selected_subscriptions"}
    else
      :none
    end
  end

  defp device_shortcut(:subscribe_notification_classes, params, assigns) do
    if letter_key_pressed?(params, "c") && not shift_pressed?(params) &&
         active_alarms_list?(assigns) && nc_subscribe_enabled?(assigns) do
      {:event, "subscribe_notification_classes"}
    else
      :none
    end
  end

  defp device_shortcut(:unsubscribe_notification_classes, params, assigns) do
    if letter_key_pressed?(params, "u") && active_alarms_list?(assigns) &&
         nc_unsubscribe_enabled?(assigns) do
      {:event, "unsubscribe_notification_classes"}
    else
      :none
    end
  end

  defp device_shortcut(:refresh_alarms, params, assigns) do
    if letter_key_pressed?(params, "e") && event_information_tab?(assigns) &&
         not assigns.alarms_refreshing do
      {:event, "refresh_alarms"}
    else
      :none
    end
  end

  defp objects_tab?(assigns), do: assigns.tab == "objects"

  defp subscribe_all_pv_tab?(assigns) do
    objects_tab?(assigns) or assigns.tab == "subscriptions"
  end

  defp cov_subscriptions_list?(assigns) do
    assigns.tab == "subscriptions" && assigns.cov_view == "subscriptions"
  end

  defp active_alarms_list?(assigns) do
    assigns.tab == "alarms" && assigns.alarm_view == "active_alarms"
  end

  defp event_information_tab?(assigns) do
    assigns.tab == "alarms" && assigns.alarm_view == "event_information"
  end

  defp selected_objects?(assigns) do
    MapSet.size(assigns.selected_object_keys) > 0
  end

  defp selected_subscriptions?(assigns) do
    MapSet.size(assigns.selected_subscription_keys) > 0
  end

  defp active_subscriptions?(assigns) do
    assigns.subscriptions != []
  end

  defp nc_subscribe_enabled?(assigns) do
    not assigns.nc_subscribing &&
      (assigns.nc_total == 0 or assigns.nc_enrolled_count < assigns.nc_total)
  end

  defp nc_unsubscribe_enabled?(assigns) do
    not assigns.nc_subscribing && assigns.nc_enrolled_count > 0
  end
end
