defmodule BacView.BACnet.Protocol.ObjectTypesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Protocol.ObjectTypes

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
end
