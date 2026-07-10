defmodule BacView.BACnet.Protocol.ObjectTypesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.ObjectTypes
  alias BACnet.Protocol.Constants.Object, as: ObjectConstants

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "label includes localized names and BACnet type atom" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")
    assert ObjectTypes.label(:analog_input) == "Analog Input (analog_input)"

    Gettext.put_locale(BacViewWeb.Gettext, "de")
    assert ObjectTypes.label(:analog_input) == "Analogwert-Eingang (Analog Input)"
  end

  test "short_label returns compact localized name" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")
    assert ObjectTypes.short_label(:analog_input) == "Analog Input"

    Gettext.put_locale(BacViewWeb.Gettext, "de")
    assert ObjectTypes.short_label(:analog_input) == "Analogwert-Eingang"
  end

  test "calendar and schedule have localized short labels" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")
    assert ObjectTypes.short_label(:calendar) == "Calendar"
    assert ObjectTypes.short_label(:schedule) == "Schedule"

    Gettext.put_locale(BacViewWeb.Gettext, "de")
    assert ObjectTypes.short_label(:calendar) == "Kalender"
    assert ObjectTypes.short_label(:schedule) == "Zeitplan"
  end

  test "all standard BACnet object types have localized short labels" do
    for value <- 0..0x3B,
        {:ok, type} <- [ObjectConstants.by_value(:object_type, value)] do
      assert ObjectTypes.short_label(type) != Atom.to_string(type),
             "expected localized label for #{type}, got raw atom name"
    end
  end

  test "unknown object types fall back to a humanized label" do
    assert ObjectTypes.short_label(:vendor_specific_widget) == "Vendor Specific Widget"

    assert ObjectTypes.label(:vendor_specific_widget) ==
             "Vendor Specific Widget (vendor_specific_widget)"
  end
end
