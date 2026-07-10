defmodule BacViewWeb.ShortcutsTest do
  use BacViewWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.Shortcuts

  defmodule RefreshLive do
    use BacViewWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      {:ok, Phoenix.Component.assign(socket, :show_shortcuts, false)}
    end

    @impl true
    def handle_info(:refresh_properties, socket) do
      {:noreply, Phoenix.Component.assign(socket, :refreshed, true)}
    end

    @impl true
    def handle_event("global_keydown", %{"key" => key}, socket) do
      Shortcuts.handle(key, socket, refresh: :refresh_object)
    end

    @impl true
    def render(assigns) do
      ~H"""
      <button id="press-r" phx-click="global_keydown" phx-value-key="r">r</button>
      <span id="refreshed">{to_string(Map.get(assigns, :refreshed, false))}</span>
      """
    end
  end

  test "r triggers object property refresh on object view" do
    {:ok, view, _html} = live_isolated(build_conn(), RefreshLive, [])

    view |> element("#press-r") |> render_click()

    assert has_element?(view, "#refreshed", "true")
  end

  test "uppercase R also triggers refresh" do
    {:ok, view, _html} = live_isolated(build_conn(), RefreshLive, [])

    render_click(view, "global_keydown", %{"key" => "R"})

    assert has_element?(view, "#refreshed", "true")
  end
end
