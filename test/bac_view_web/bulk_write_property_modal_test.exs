defmodule BacViewWeb.BulkWritePropertyModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BacViewWeb.BulkWritePropertyModal

  test "explains an empty property list and still lists the objects" do
    html =
      render_component(&BulkWritePropertyModal.modal/1,
        modal: %{
          properties: [],
          property: nil,
          value: "",
          priority: 8,
          busy: false,
          objects: [],
          rows: [
            %{
              type: :device,
              instance: 1,
              name: "Gerät",
              type_label: "Gerät",
              status: :ready,
              message: nil
            }
          ]
        },
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="bulk-write-no-properties"/
    assert html =~ "keine gemeinsame schreibbare Eigenschaft"
    assert html =~ ~s/id="bulk-write-row-device-1"/
    assert html =~ ~s/data-status="ready"/
    refute html =~ ~s/id="bulk-write-property-form"/
  end

  test "renders a write error next to the object" do
    html =
      render_component(&BulkWritePropertyModal.modal/1,
        modal: %{
          properties: [%{id: :description, label: "description"}],
          property: :description,
          value: "Halle",
          priority: 8,
          busy: false,
          objects: [],
          rows: [
            %{
              type: :analog_input,
              instance: 3,
              name: "Raum",
              type_label: "Analogwert-Eingang",
              status: :error,
              message: "Schreiben fehlgeschlagen: timeout"
            }
          ]
        },
        locale: "de",
        locale_version: 0
      )

    assert html =~ ~s/id="bulk-write-results"/
    assert html =~ ~s/data-status="error"/
    assert html =~ "Schreiben fehlgeschlagen: timeout"
    assert html =~ "0 geschrieben, 1 fehlgeschlagen."
  end
end
