defmodule BacViewWeb.LocaleTest do
  use ExUnit.Case, async: true

  use Gettext, backend: BacViewWeb.Gettext

  setup do
    on_exit(fn -> Gettext.put_locale(BacViewWeb.Gettext, "de") end)
    :ok
  end

  test "German locale shows German strings for German msgids" do
    Gettext.put_locale(BacViewWeb.Gettext, "de")

    assert gettext("Alle Objekte anzeigen") == "Alle Objekte anzeigen"
    assert gettext("Hierarchie") == "Hierarchie"
  end

  test "English locale translates German msgids" do
    Gettext.put_locale(BacViewWeb.Gettext, "en")

    assert gettext("Alle Objekte anzeigen") == "Show all objects"
    assert gettext("Hierarchie") == "Hierarchy"
  end

  test "GettextLC.translate! respects explicit locale" do
    assert BacViewWeb.GettextLC.translate!("Netzwerk", %{}, "en", 1) == "Network"
    assert BacViewWeb.GettextLC.translate!("Netzwerk", %{}, "de", 0) == "Netzwerk"
  end
end
