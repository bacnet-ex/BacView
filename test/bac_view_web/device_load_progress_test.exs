defmodule BacViewWeb.DeviceLoadProgressTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.DeviceLoadProgress

  test "renders collapsible error log during object scan" do
    html =
      render_component(&DeviceLoadProgress.status_banner/1,
        progress: %{
          stage: :scanning_objects,
          done: 2,
          total: 3,
          errors: 1,
          skipped: 0,
          error_log: [
            %{object: "analog_input:1", message: "Das Objekt ist dem Gerät nicht bekannt."}
          ]
        },
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="device-scan-error-log"/
    assert html =~ "Fehlerprotokoll (1)"
    assert html =~ "analog_input:1"
    assert html =~ "Das Objekt ist dem Gerät nicht bekannt."
    refute html =~ "%{count} Fehler"
  end

  test "does not render error log when there are no errors" do
    html =
      render_component(&DeviceLoadProgress.status_banner/1,
        progress: %{
          stage: :scanning_objects,
          done: 3,
          total: 3,
          errors: 0,
          skipped: 0,
          error_log: []
        },
        locale: "de",
        locale_version: 0
      )

    refute html =~ ~s/id="device-scan-error-log"/
  end
end
