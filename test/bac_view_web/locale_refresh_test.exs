defmodule BacViewWeb.LocaleRefreshTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.{ObjectTypes, PropertyEnumeration}
  alias BacViewWeb.LocaleRefresh

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "refresh_object updates type_label for current locale" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")

    object = %{type: :analog_input, type_label: "Analogwert-Eingang (analog_input)"}
    refreshed = LocaleRefresh.refresh_object(object)

    assert refreshed.type_label == ObjectTypes.short_label(:analog_input)
    assert refreshed.type_label == "Analog Input"
  end

  test "relocalize_property refreshes enum labels and options" do
    Gettext.put_locale(BacViewWeb.Gettext, "de")

    prop = %{
      property: :reliability,
      value: :no_fault_detected,
      bac_type: {:constant, :reliability},
      value_display: %{kind: :scalar, formatted: "old"},
      value_formatted: "old",
      type: "ENUMERATED"
    }

    prop = PropertyEnumeration.enrich_property(prop, {:constant, :reliability})

    Gettext.put_locale(BacViewWeb.Gettext, "en")

    refreshed = PropertyEnumeration.relocalize_property(prop)

    assert refreshed.value_formatted == "no fault detected"
    assert Enum.any?(refreshed.enum_options, &(&1.label =~ "(0)"))
  end
end
