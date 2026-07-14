defmodule BacViewWeb.ErrorMessageTextTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.ErrorMessageText

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "formats scan validation errors in english" do
    assert ErrorMessageText.format(
             {:value_failed_property_validation, :present_value},
             "en",
             1
           ) =~ "BACnet specification"

    refute ErrorMessageText.format(
             {:value_failed_property_validation, :present_value},
             "en",
             1
           ) =~ "Spezifikation"
  end
end