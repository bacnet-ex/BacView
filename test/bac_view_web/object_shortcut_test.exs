defmodule BacViewWeb.ObjectShortcutTest do
  use BacViewWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule ObjectRefreshLive do
    use BacViewWeb, :live_view

    alias BacViewWeb.ObjectDetail

    @impl true
    def mount(_params, _session, socket) do
      object = %{
        type: :analog_input,
        instance: 1,
        name: "AI-1",
        present_value: 21.0,
        present_value_formatted: "21.0",
        writable: false,
        commandable: false,
        units: nil,
        updated_at: nil
      }

      {:ok,
       socket
       |> Phoenix.Component.assign(:show_shortcuts, false)
       |> Phoenix.Component.assign(:device, %{id: 42})
       |> Phoenix.Component.assign(:object, object)
       |> Phoenix.Component.assign(:properties, [])
       |> Phoenix.Component.assign(:loading, false)
       |> Phoenix.Component.assign(:properties_loading, false)}
    end

    @impl true
    def handle_event("global_keydown", params, socket) do
      key = Map.get(params, "key", "")

      cond do
        BacViewWeb.Shortcuts.refresh_key?(key) ->
          {:noreply, Phoenix.Component.assign(socket, :properties_loading, true)}

        true ->
          BacViewWeb.Shortcuts.handle(params, socket)
      end
    end

    @impl true
    def render(assigns) do
      ~H"""
      <ObjectDetail.object_detail
        device={@device}
        object={@object}
        properties={@properties}
        loading={@loading}
        properties_loading={@properties_loading}
        locale="de"
        locale_version={0}
      />
      """
    end
  end

  test "r shortcut shows immediate refresh feedback on object view" do
    {:ok, view, _html} = live_isolated(build_conn(), ObjectRefreshLive, [])

    html =
      render_click(view, "global_keydown", %{"key" => "r", "code" => "KeyR", "shift" => false})

    assert html =~ ~s(id="object-refresh-banner")
    assert has_element?(view, "#refresh-properties-btn[disabled]")
    assert has_element?(view, "#refresh-properties-btn .animate-spin")
  end
end
