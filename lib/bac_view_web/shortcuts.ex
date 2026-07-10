defmodule BacViewWeb.Shortcuts do
  @moduledoc false

  import Phoenix.LiveView, only: [push_event: 3]

  @digit_codes ~w(Digit1 Digit2 Digit3 Digit4)

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

  defp handle_key(key, _params, socket, opts) do
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
          assign_shortcuts(socket, false)

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
end
