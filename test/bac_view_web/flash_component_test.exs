defmodule BacViewWeb.FlashComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defmodule SampleFlash do
    use BacViewWeb, :html

    def reconnect_error(assigns) do
      ~H"""
      <.flash
        id="connection-error"
        kind={:error}
        locale="en"
        locale_version={1}
        title="Unable to connect to server"
      >
        <span class="inline-flex items-center gap-1">
          Attempting to reconnect
        </span>
      </.flash>
      """
    end
  end

  test "connection flash uses header grid layout" do
    html = render_component(&SampleFlash.reconnect_error/1, %{})

    assert html =~ "bac-alert-titled"
    assert html =~ ~s(<div class="bac-alert-header">)
    assert html =~ ~s(<p class="bac-alert-title">Unable to connect to server</p>)
    assert html =~ ~s(<div class="bac-alert-body">)
    assert html =~ ~s(<div class="bac-alert-message">)
    assert html =~ ~s(<button type="button" class="bac-alert-close")
    assert html =~ "Attempting to reconnect"
    refute html =~ "Something went wrong!"
    refute html =~ "We can't find the internet"
  end
end
